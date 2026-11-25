#include "TouchSidebar.hpp"

#include <algorithm>
#include <chrono>
#include <cctype>
#include <climits>
#include <cmath>
#include <cstdio>
#include <set>
#include <utility>

#include <boost/algorithm/string.hpp>
#include <boost/any.hpp>
#include <boost/log/trivial.hpp>

#include <wx/sizer.h>
#include <wx/tokenzr.h>
#include <wx/uri.h>

#include "libslic3r/Model.hpp"
#include "libslic3r/PresetBundle.hpp"
#include "libslic3r/PrintConfig.hpp"
#include "libslic3r/Utils.hpp"
#include "slic3r/GUI/BackgroundSlicingProcess.hpp"
#include "slic3r/GUI/Event.hpp"
#include "slic3r/GUI/GLToolbar.hpp"
#include "slic3r/GUI/GUI.hpp"
#include "slic3r/GUI/GUI_App.hpp"
#include "slic3r/GUI/GUI_ObjectList.hpp"
#include "slic3r/GUI/PartPlate.hpp"
#include "slic3r/GUI/Plater.hpp"
#include "slic3r/GUI/PresetComboBoxes.hpp"
#include "slic3r/GUI/Tab.hpp"
#include "slic3r/GUI/Widgets/WebView.hpp"

namespace Slic3r { namespace GUI {

using json = nlohmann::json;

namespace {

constexpr const char *kModule     = "touch_sidebar";
constexpr const char *kVersion    = "1.0";
constexpr int         kReadyMs    = 5000;
constexpr int         kPollMs     = 300;
constexpr int         kIdPoll     = 1;
constexpr int         kIdReady    = 2;

// Quality option keys the page may read and write (PROTOCOL.md).
const char *const kQualityKeys[] = {"layer_height",   "wall_loops",           "top_shell_layers",
                                    "bottom_shell_layers", "sparse_infill_density", "sparse_infill_pattern",
                                    "enable_support", "brim_type",            "brim_width"};

const std::set<std::string> &command_whitelist()
{
    static const std::set<std::string> s{"select_printer_preset", "select_nozzle", "select_plate_type", "filament_add",
                                         "filament_remove",       "filament_edit", "filament_set_preset",
                                         "filament_set_color",    "select_process_preset", "set_option",
                                         "open_advanced",         "object_select", "object_set_visible",
                                         "object_delete",         "object_action", "slice", "print", "export", "cancel"};
    return s;
}

std::string dump_json(const json &j) { return j.dump(-1, ' ', false, json::error_handler_t::replace); }

long long now_ms()
{
    return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
}

bool ts_get_string(const json &o, const char *key, std::string &out, size_t max_len)
{
    if (!o.is_object()) return false;
    auto it = o.find(key);
    if (it == o.end() || !it->is_string()) return false;
    out = it->get<std::string>();
    return !out.empty() && out.size() <= max_len;
}

bool ts_get_int(const json &o, const char *key, int lo, int hi, int &out)
{
    if (!o.is_object()) return false;
    auto it = o.find(key);
    if (it == o.end() || !it->is_number_integer()) return false;
    const long long v = it->get<long long>();
    if (v < lo || v > hi) return false;
    out = (int) v;
    return true;
}

bool valid_color(const std::string &c)
{
    if (c.size() != 7 || c[0] != '#') return false;
    return std::all_of(c.begin() + 1, c.end(), [](unsigned char ch) { return std::isxdigit(ch) != 0; });
}

// "obj:N" -> 1, "vol:N:M" -> 2, anything else -> 0 (plate ids included).
int parse_object_id(const std::string &s, int &o, int &v)
{
    int len = 0;
    o = v = -1;
    if (std::sscanf(s.c_str(), "obj:%d%n", &o, &len) == 1 && len == (int) s.size() && o >= 0) return 1;
    len = 0;
    if (std::sscanf(s.c_str(), "vol:%d:%d%n", &o, &v, &len) == 2 && len == (int) s.size() && o >= 0 && v >= 0) return 2;
    return 0;
}

std::string normalize_url(const wxString &url)
{
    wxString u = wxURI::Unescape(url);
    u.Replace("\\", "/");
    u.MakeLower();
    const size_t q = u.find_first_of("?#");
    if (q != wxString::npos) u = u.Left(q);
    std::string s = u.ToUTF8().data();
    if (boost::starts_with(s, "file:")) {
        s.erase(0, 5);
        s.erase(0, s.find_first_not_of('/'));
    }
    return s;
}

std::string format_diameter(double v)
{
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%g", v);
    return buf;
}

// Select a preset through the sidebar combo, i.e. through the same event path as a user click.
bool select_in_combo(PlaterPresetComboBox *combo, Preset::Type type, const std::string &name, std::string &err)
{
    if (combo == nullptr) {
        err = "sidebar combo is not available";
        return false;
    }
    PresetBundle *pb = wxGetApp().preset_bundle;
    for (unsigned i = 0; i < combo->GetCount(); ++i) {
        const size_t marker = reinterpret_cast<size_t>(combo->GetClientData(i));
        if (marker >= (size_t) 0xffffff01u) continue; // label / physical printer items
        const std::string item = pb->get_preset_name_by_alias(type, Preset::remove_suffix_modified(combo->GetString(i).ToUTF8().data()));
        if (item == name) {
            combo->SelectAndNotify((int) i);
            return true;
        }
    }
    err = "preset is not offered by the sidebar list";
    return false;
}

bool make_option_value(const std::string &key, const json &v, boost::any &out, std::string &err)
{
    bool allowed = false;
    for (const char *k : kQualityKeys) allowed = allowed || key == k;
    if (!allowed) {
        err = "option is not allowed";
        return false;
    }
    const ConfigOptionDef *def = print_config_def.get(key);
    if (def == nullptr) {
        err = "unknown option";
        return false;
    }
    switch (def->type) {
    case coFloat:
    case coPercent: {
        if (!v.is_number()) { err = "number expected"; return false; }
        const double d = v.get<double>();
        if (!std::isfinite(d) || d < def->min || d > def->max) { err = "value out of range"; return false; }
        out = d;
        return true;
    }
    case coInt: {
        if (!v.is_number_integer()) { err = "integer expected"; return false; }
        const long long x = v.get<long long>();
        if (x < (long long) INT_MIN || x > (long long) INT_MAX || (double) x < def->min || (double) x > def->max) { err = "value out of range"; return false; }
        out = (int) x;
        return true;
    }
    case coBool:
        if (!v.is_boolean()) { err = "boolean expected"; return false; }
        out = v.get<bool>();
        return true;
    case coEnum: {
        if (!v.is_string() || def->enum_keys_map == nullptr) { err = "enum string expected"; return false; }
        auto it = def->enum_keys_map->find(v.get<std::string>());
        if (it == def->enum_keys_map->end()) { err = "unknown enum value"; return false; }
        out = it->second;
        return true;
    }
    default: err = "option type is not supported"; return false;
    }
}

} // namespace

// ---------------------------------------------------------------------------------------------

TouchSidebar::TouchSidebar(wxWindow *parent, const Callbacks &callbacks) : m_cb(callbacks), m_poll(this, kIdPoll), m_ready_timer(this, kIdReady)
{
    m_panel = new wxPanel(parent, wxID_ANY);
    m_panel->SetMinSize(wxSize(m_panel->FromDIP(kClosedWidthDip), -1));
    auto *sizer = new wxBoxSizer(wxVERTICAL);
    m_panel->SetSizer(sizer);

    wxWebView *web = WebView::CreateWebView(m_panel, wxEmptyString, "TouchSidebar");
    m_web          = web;
    if (web != nullptr) {
        sizer->Add(web, 1, wxEXPAND);
        // Same contract as DeviceWebBridge::InitBridge, injected before page scripts run.
        web->AddUserScript(wxString::FromUTF8("window.__cppPush = function(pkt){ try { document.dispatchEvent(new CustomEvent('cpp:' + pkt.event, { detail: pkt })); } catch(e) { console.error(e); } };"),
                           wxWEBVIEW_INJECT_AT_DOCUMENT_START);
        web->Bind(wxEVT_WEBVIEW_SCRIPT_MESSAGE_RECEIVED, &TouchSidebar::on_script_message, this);
        web->Bind(wxEVT_WEBVIEW_NAVIGATING, &TouchSidebar::on_navigating, this);
        web->Bind(wxEVT_WEBVIEW_LOADED, &TouchSidebar::on_loaded, this);
        web->Bind(wxEVT_WEBVIEW_ERROR, &TouchSidebar::on_load_error, this);
    }
    Bind(wxEVT_TIMER, &TouchSidebar::on_poll, this, kIdPoll);
    Bind(wxEVT_TIMER, &TouchSidebar::on_ready_timeout, this, kIdReady);
}

TouchSidebar::~TouchSidebar()
{
    m_poll.Stop();
    m_ready_timer.Stop();
    if (m_web) {
        m_web->Unbind(wxEVT_WEBVIEW_SCRIPT_MESSAGE_RECEIVED, &TouchSidebar::on_script_message, this);
        m_web->Unbind(wxEVT_WEBVIEW_NAVIGATING, &TouchSidebar::on_navigating, this);
        m_web->Unbind(wxEVT_WEBVIEW_LOADED, &TouchSidebar::on_loaded, this);
        m_web->Unbind(wxEVT_WEBVIEW_ERROR, &TouchSidebar::on_load_error, this);
    }
}

wxString TouchSidebar::page_url() const
{
    std::string lang = wxGetApp().app_config ? wxGetApp().app_config->get("language") : std::string();
    lang             = lang.substr(0, lang.find('_'));
    boost::to_lower(lang);
    if (lang.empty()) lang = "en";
    return wxString::Format("file://%s/web/touch_sidebar/index.html?lang=%s", from_u8(resources_dir()), wxString::FromUTF8(lang));
}

bool TouchSidebar::is_local_page(const wxString &url) const
{
    return !url.empty() && normalize_url(url) == normalize_url(page_url());
}

void TouchSidebar::start()
{
    if (m_started) return;
    m_started = true;
    if (!m_web) {
        fail("webview could not be created");
        return;
    }
    if (WebView::CreationFault(m_web).has_value()) {
        fail("webview backend unavailable");
        return;
    }
    const wxString url = page_url();
    if (!WebView::ValidateLocalTarget(m_web, url)) {
        fail("touch sidebar page is missing (web/touch_sidebar)");
        return;
    }
    m_ready_timer.Start(kReadyMs, wxTIMER_ONE_SHOT);
    WebView::LoadUrl(m_web, url);
}

void TouchSidebar::fail(const char *reason)
{
    if (m_failed) return;
    m_failed = true;
    BOOST_LOG_TRIVIAL(warning) << "TouchSidebar: falling back to the native sidebar: " << reason;
    m_poll.Stop();
    m_ready_timer.Stop();
    if (m_panel) m_panel->Hide();
    if (m_cb.failed) CallAfter([this]() { m_cb.failed(); });
}

void TouchSidebar::on_ready_timeout(wxTimerEvent &)
{
    if (!m_ready) fail("page did not answer init in time");
}

void TouchSidebar::on_load_error(wxWebViewEvent &e)
{
    if (!m_ready) fail("page load error");
    e.Skip();
}

void TouchSidebar::on_loaded(wxWebViewEvent &e)
{
    // The user script already defines it; this covers a backend that ignored AddUserScript.
    if (m_web && is_local_page(e.GetURL()))
        WebView::RunScript(m_web, wxString::FromUTF8("if (!window.__cppPush) { window.__cppPush = function(pkt){ document.dispatchEvent(new CustomEvent('cpp:' + pkt.event, { detail: pkt })); }; }"));
    e.Skip();
}

void TouchSidebar::on_navigating(wxWebViewEvent &e)
{
    const wxString url = e.GetURL();
    if (url.empty() || url == "about:blank" || is_local_page(url)) {
        e.Skip();
        return;
    }
    BOOST_LOG_TRIVIAL(warning) << "TouchSidebar: blocked navigation to " << url.ToUTF8().data();
    e.Veto(); // includes app:// message navigation: only postMessage is accepted
}

void TouchSidebar::on_script_message(wxWebViewEvent &e)
{
    if (!m_web || !is_local_page(m_web->GetCurrentURL())) {
        BOOST_LOG_TRIVIAL(warning) << "TouchSidebar: message from a foreign page ignored";
        return;
    }
    const std::string raw = e.GetString().ToUTF8().data();
    if (raw.size() > 256 * 1024) return;
    json msg = json::parse(raw, nullptr, false);
    if (msg.is_discarded() || !msg.is_object()) return;
    // Never act inside the webview callback.
    CallAfter([this, msg]() { dispatch(msg); });
}

void TouchSidebar::dispatch(const json &msg)
{
    if (m_failed || wxGetApp().is_closing()) return;
    auto head = msg.find("head");
    auto body = msg.find("body");
    if (head == msg.end() || body == msg.end() || !head->is_object() || !body->is_object()) return;
    auto ver = head->find("version");
    if (ver == head->end() || !ver->is_string() || ver->get<std::string>() != kVersion) return;
    std::string module, action;
    if (!ts_get_string(*body, "module", module, 64) || module != kModule || !ts_get_string(*body, "action", action, 64)) return;
    auto pl = body->find("payload");
    if (pl == body->end() || !pl->is_object()) return;

    if (action == "init") {
        m_ready        = true;
        m_pending_init = true;
        m_ready_timer.Stop();
        m_poll.Start(kPollMs);
        try_send_init();
    } else if (action == "resync") {
        refresh_state();
        if (m_last_state.is_null()) send_error("", 503, "state is not available yet");
        else send("snapshot", {{"state", m_last_state}});
    } else if (action == "layout") {
        int w = 0;
        if (!ts_get_int(*pl, "width", 1, 4096, w)) return;
        const int nw = std::max<int>(kClosedWidthDip, std::min<int>(kMaxWidthDip, w));
        if (nw != m_width_dip) {
            m_width_dip = nw;
            if (m_cb.width_changed) m_cb.width_changed();
        }
    } else if (action == "command") {
        handle_command(*pl);
    }
}

void TouchSidebar::send(const char *action, json payload)
{
    if (!m_web || m_failed) return;
    json j;
    j["event"] = "touch_sidebar";
    j["head"]  = {{"version", kVersion}, {"type", "report"}, {"seq", m_seq++}, {"ts", now_ms()}};
    j["body"]  = {{"module", kModule}, {"action", action}, {"payload", std::move(payload)}};
    try {
        WebView::RunScript(m_web, wxString::FromUTF8("window.__cppPush(" + dump_json(j) + ");"));
    } catch (const std::exception &ex) {
        BOOST_LOG_TRIVIAL(error) << "TouchSidebar: serialize failed: " << ex.what();
    }
}

void TouchSidebar::send_ack(const std::string &id)
{
    send("ack", {{"id", id}, {"revision", m_revision}});
}

void TouchSidebar::send_error(const std::string &id, int code, const std::string &message)
{
    json p = {{"code", code}, {"message", message}};
    if (!id.empty()) p["id"] = id;
    send("error", std::move(p));
}

void TouchSidebar::send_theme()
{
    send("theme", {{"theme", wxGetApp().dark_mode() ? "dark" : "light"}});
}

void TouchSidebar::on_sys_color_changed()
{
    if (m_ready) send_theme();
}

bool TouchSidebar::try_send_init()
{
    refresh_state();
    if (m_last_state.is_null()) return false; // application not fully built yet, retried by the poll timer
    std::string lang = wxGetApp().app_config->get("language");
    lang             = lang.substr(0, lang.find('_'));
    boost::to_lower(lang);
    send("init", {{"protocol", kVersion}, {"state", m_last_state}, {"theme", wxGetApp().dark_mode() ? "dark" : "light"}, {"lang", lang.empty() ? std::string("en") : lang}});
    m_pending_init = false;
    return true;
}

void TouchSidebar::on_poll(wxTimerEvent &)
{
    if (m_failed || !m_ready || wxGetApp().is_closing()) return;
    if (m_pending_init) {
        try_send_init();
        return;
    }
    push_state();
}

bool TouchSidebar::refresh_state()
{
    json s = build_state();
    if (s.is_null()) return false;
    const std::string dump = dump_json(s);
    if (dump == m_last_state_dump && !m_last_state.is_null()) return false;
    m_last_state_dump = dump;
    ++m_revision;
    s["revision"] = m_revision;
    m_last_state  = std::move(s);
    return true;
}

void TouchSidebar::push_state()
{
    if (refresh_state()) send("snapshot", {{"state", m_last_state}});
}

// ---------------------------------------------------------------------------------------------
// State

json TouchSidebar::build_state()
{
    GUI_App &app = wxGetApp();
    PresetBundle *pb = app.preset_bundle;
    Plater *plater   = app.plater();
    if (pb == nullptr || plater == nullptr || app.is_closing() || app.get_tab(Preset::TYPE_PRINT) == nullptr) return json();

    json s;
    // printer
    {
        json presets = json::array();
        const std::string sel = pb->printers.get_selected_preset_name();
        const bool dirty      = pb->printers.current_is_dirty();
        for (const Preset &p : pb->printers.get_presets()) {
            if (p.is_default || !p.is_visible) continue;
            presets.push_back({{"id", p.name}, {"name", p.name}, {"dirty", dirty && p.name == sel}});
        }
        json nozzles = json::array();
        std::string nozzle;
        if (const auto *nd = pb->printers.get_edited_preset().config.option<ConfigOptionFloats>("nozzle_diameter")) {
            if (!nd->values.empty()) {
                nozzle = format_diameter(nd->values.front());
                nozzles.push_back(nozzle);
            }
        }
        json plate_types = json::array();
        std::string plate;
        const ConfigOptionDef *bed_def = print_config_def.get("curr_bed_type");
        if (bed_def != nullptr) {
            auto bed_id = [bed_def](BedType t) -> int {
                const int i = (int) t - 1;
                return (i >= 0 && i < (int) bed_def->enum_values.size()) ? i : -1;
            };
            for (BedType t : plater->sidebar().get_cur_combox_bed_types()) {
                const int i = bed_id(t);
                if (i < 0) continue;
                const std::string label = i < (int) bed_def->enum_labels.size() ? bed_def->enum_labels[i] : bed_def->enum_values[i];
                plate_types.push_back({{"id", bed_def->enum_values[i]}, {"name", label}});
            }
            const int ci = bed_id(pb->project_config.opt_enum<BedType>("curr_bed_type"));
            if (ci >= 0) plate = bed_def->enum_values[ci];
        }
        s["printer"] = {{"presets", presets}, {"preset", sel}, {"nozzles", nozzles}, {"nozzle", nozzle}, {"plateTypes", plate_types}, {"plate", plate}};
    }
    // filament
    {
        json items = json::array();
        const auto &combos = plater->sidebar().combos_filament();
        const auto *colors = pb->project_config.option<ConfigOptionStrings>("filament_colour");
        const size_t n     = std::min(combos.size(), pb->filament_presets.size());
        auto display_id = [pb](const Preset &p) { return p.alias.empty() ? p.name : pb->get_preset_name_by_alias(Preset::TYPE_FILAMENT, p.alias); };
        for (size_t i = 0; i < n; ++i) {
            std::string type;
            std::string preset_id = pb->filament_presets[i];
            if (const Preset *p = pb->filaments.find_preset(pb->filament_presets[i])) {
                if (p->config.has("filament_type")) type = p->config.opt_string("filament_type", 0u);
                preset_id = display_id(*p);
            }
            const std::string color = (colors != nullptr && i < colors->values.size()) ? colors->values[i] : std::string("#808080");
            items.push_back({{"id", (int) i}, {"color", color}, {"type", type}, {"preset", preset_id}});
        }
        json presets = json::array();
        std::set<std::string> seen;
        for (const Preset &p : pb->filaments.get_presets()) {
            if (p.is_default || !p.is_visible || !p.is_compatible) continue;
            const std::string id = display_id(p);
            if (!seen.insert(id).second) continue;
            presets.push_back({{"id", id}, {"name", p.alias.empty() ? p.name : p.alias}});
        }
        s["filament"] = {{"items", items}, {"presets", presets}, {"max", (int) MAX_PHYSICAL_FILAMENT_COUNT}};
    }
    // quality
    {
        json presets = json::array();
        const std::string sel = pb->prints.get_selected_preset_name();
        const bool dirty      = pb->prints.current_is_dirty();
        for (const Preset &p : pb->prints.get_presets()) {
            if (p.is_default || !p.is_visible || !p.is_compatible) continue;
            presets.push_back({{"id", p.name}, {"name", p.name}, {"dirty", dirty && p.name == sel}});
        }
        json values = json::object();
        const DynamicPrintConfig &cfg = pb->prints.get_edited_preset().config;
        for (const char *key : kQualityKeys) {
            const ConfigOptionDef *def = print_config_def.get(key);
            if (def == nullptr || !cfg.has(key)) continue;
            switch (def->type) {
            case coFloat: values[key] = cfg.opt_float(key); break;
            case coInt: values[key] = cfg.opt_int(key); break;
            case coBool: values[key] = cfg.opt_bool(key); break;
            case coPercent: values[key] = cfg.option<ConfigOptionPercent>(key)->value; break;
            case coEnum: values[key] = cfg.opt_serialize(key); break;
            default: break;
            }
        }
        s["quality"] = {{"presets", presets}, {"preset", sel}, {"values", values}};
    }
    // objects
    {
        json plates = json::array();
        Model &model          = plater->model();
        PartPlateList &list   = plater->get_partplate_list();
        const int selected    = plater->sidebar().obj_list() ? plater->sidebar().obj_list()->get_selected_obj_idx() : -1;
        for (int k = 0; k < list.get_plate_count(); ++k) {
            PartPlate *plate = list.get_plate(k);
            if (plate == nullptr) continue;
            json children = json::array();
            for (int i = 0; i < (int) model.objects.size(); ++i) {
                const ModelObject *mo = model.objects[i];
                bool on_plate         = false;
                for (int j = 0; j < (int) mo->instances.size() && !on_plate; ++j) on_plate = plate->contain_instance(i, j);
                if (!on_plate) continue;
                json parts = json::array();
                if (mo->volumes.size() > 1) {
                    for (int v = 0; v < (int) mo->volumes.size(); ++v) {
                        const ModelVolume *mv = mo->volumes[v];
                        if (!mv->is_model_part()) continue;
                        parts.push_back({{"id", "vol:" + std::to_string(i) + ":" + std::to_string(v)}, {"kind", "part"}, {"name", mv->name}});
                    }
                }
                json node = {{"id", "obj:" + std::to_string(i)}, {"kind", "object"}, {"name", mo->name},
                             {"visible", mo->instances.empty() ? true : mo->instances.front()->printable}, {"selected", i == selected}};
                if (!parts.empty()) node["children"] = parts;
                children.push_back(std::move(node));
            }
            std::string pname = plate->get_plate_name();
            if (pname.empty()) pname = "Plate " + std::to_string(k + 1);
            plates.push_back({{"id", "plate:" + std::to_string(k)}, {"kind", "plate"}, {"name", pname}, {"selected", k == list.get_curr_plate_index()}, {"children", children}});
        }
        s["objects"] = plates;
    }
    // slice
    {
        PartPlate *cp = plater->get_partplate_list().get_curr_plate();
        const bool slicing = plater->is_background_process_slicing();
        const bool valid   = cp != nullptr && cp->is_slice_result_valid();
        double pct         = slicing && cp != nullptr ? (double) cp->get_slicing_percent() : (valid ? 100.0 : 0.0);
        pct                = std::max(0.0, std::min(100.0, pct));
        s["slice"] = {{"status", slicing ? "slicing" : (valid ? "ready" : "idle")}, {"progress", pct}, {"message", ""},
                      {"canPrint", cp != nullptr && cp->is_slice_result_ready_for_print()}};
    }
    return s;
}

// ---------------------------------------------------------------------------------------------
// Commands

void TouchSidebar::handle_command(const json &payload)
{
    std::string id, cmd;
    if (!ts_get_string(payload, "id", id, 64)) {
        send_error("", 400, "command without a valid id");
        return;
    }
    auto args_it = payload.find("args");
    const json args = (args_it != payload.end() && args_it->is_object()) ? *args_it : json::object();
    if (!ts_get_string(payload, "cmd", cmd, 64) || command_whitelist().count(cmd) == 0) {
        send_error(id, 400, "unknown command");
        return;
    }
    if (m_busy) {
        send_error(id, 409, "another command is still running");
        return;
    }
    std::string err;
    bool modal = false;
    auto action = prepare(cmd, args, err, modal);
    if (!action) {
        send_error(id, err.rfind("not supported", 0) == 0 ? 501 : 400, err);
        return;
    }
    if (modal) {
        // Ack before any dialog can block the loop; the result arrives as a snapshot or an unsolicited error.
        m_busy = true;
        send_ack(id);
        CallAfter([this, action]() {
            std::string e;
            const bool ok = action(e);
            m_busy        = false;
            if (!ok) send_error("", 500, e);
            push_state();
        });
        return;
    }
    m_busy = true;
    std::string e;
    const bool ok = action(e);
    m_busy        = false;
    push_state();
    if (ok) send_ack(id);
    else send_error(id, 500, e);
}

std::function<bool(std::string &)> TouchSidebar::prepare(const std::string &cmd, const json &args, std::string &err, bool &modal)
{
    GUI_App &app     = wxGetApp();
    PresetBundle *pb = app.preset_bundle;
    Plater *plater   = app.plater();
    modal            = false;
    if (pb == nullptr || plater == nullptr) {
        err = "application is not ready";
        return {};
    }
    using Fn = std::function<bool(std::string &)>;

    if (cmd == "select_printer_preset" || cmd == "select_process_preset") {
        std::string id;
        if (!ts_get_string(args, "id", id, 256)) { err = "id expected"; return {}; }
        const bool printer = cmd == "select_printer_preset";
        const Preset *p    = printer ? pb->printers.find_preset(id, false) : pb->prints.find_preset(id, false);
        if (p == nullptr || p->is_default || !p->is_visible || (!printer && !p->is_compatible)) { err = "preset not found"; return {}; }
        modal = true;
        if (printer)
            return [id](std::string &e) { return select_in_combo(wxGetApp().sidebar().printer_combox(), Preset::TYPE_PRINTER, id, e); };
        return [id](std::string &e) {
            Tab *tab = wxGetApp().get_tab(Preset::TYPE_PRINT);
            if (tab == nullptr) { e = "process tab is not available"; return false; }
            if (!tab->select_preset(id)) { e = "preset switch was cancelled"; return false; }
            wxGetApp().plater()->on_config_change(wxGetApp().preset_bundle->full_config());
            return true;
        };
    }
    if (cmd == "select_nozzle") {
        err = "not supported: nozzle selection has no verified native entry point for this printer";
        return {};
    }
    if (cmd == "select_plate_type") {
        std::string id;
        if (!ts_get_string(args, "id", id, 64)) { err = "id expected"; return {}; }
        const ConfigOptionDef *def = print_config_def.get("curr_bed_type");
        bool found = false;
        if (def != nullptr)
            for (BedType t : plater->sidebar().get_cur_combox_bed_types()) {
                const int i = (int) t - 1;
                found = found || (i >= 0 && i < (int) def->enum_values.size() && def->enum_values[i] == id);
            }
        if (!found) { err = "plate type is not available for this printer"; return {}; }
        return [id](std::string &e) {
            if (!wxGetApp().sidebar().set_bed_type(id)) { e = "plate type rejected"; return false; }
            return true;
        };
    }
    if (cmd == "filament_add") {
        if (plater->sidebar().combos_filament().size() >= MAX_PHYSICAL_FILAMENT_COUNT) { err = "filament limit reached"; return {}; }
        return [](std::string &e) {
            Sidebar &sb        = wxGetApp().sidebar();
            const size_t before = sb.combos_filament().size();
            sb.add_filament();
            if (sb.combos_filament().size() <= before) { e = "filament was not added"; return false; }
            return true;
        };
    }
    if (cmd == "filament_remove" || cmd == "filament_edit" || cmd == "filament_set_preset" || cmd == "filament_set_color") {
        const int count = (int) plater->sidebar().combos_filament().size();
        int index       = 0;
        if (count == 0 || !ts_get_int(args, "index", 0, count - 1, index)) { err = "index out of range"; return {}; }
        if (cmd == "filament_remove") {
            if (count <= 1) { err = "the last filament cannot be removed"; return {}; }
            modal = true;
            return [index](std::string &e) {
                Sidebar &sb = wxGetApp().sidebar();
                if (index >= (int) sb.combos_filament().size() || sb.combos_filament().size() <= 1) { e = "index out of range"; return false; }
                sb.delete_filament((size_t) index);
                return true;
            };
        }
        if (cmd == "filament_edit") {
            modal = true;
            return [index](std::string &e) {
                Sidebar &sb = wxGetApp().sidebar();
                if (index >= (int) sb.combos_filament().size()) { e = "index out of range"; return false; }
                return sb.combos_filament()[index]->switch_to_tab();
            };
        }
        if (cmd == "filament_set_preset") {
            std::string id;
            if (!ts_get_string(args, "id", id, 256)) { err = "id expected"; return {}; }
            const Preset *p = pb->filaments.find_preset(id, false);
            if (p == nullptr || p->is_default || !p->is_visible) { err = "preset not found"; return {}; }
            modal = true;
            return [index, id](std::string &e) {
                Sidebar &sb = wxGetApp().sidebar();
                if (index >= (int) sb.combos_filament().size()) { e = "index out of range"; return false; }
                return select_in_combo(sb.combos_filament()[index], Preset::TYPE_FILAMENT, id, e);
            };
        }
        std::string color;
        if (!ts_get_string(args, "color", color, 16) || !valid_color(color)) { err = "color must be #RRGGBB"; return {}; }
        boost::to_upper(color);
        return [index, color](std::string &e) {
            PresetBundle *bundle = wxGetApp().preset_bundle;
            Sidebar &sb          = wxGetApp().sidebar();
            Tab *printer_tab     = wxGetApp().get_tab(Preset::TYPE_PRINTER);
            const auto *cur      = bundle->project_config.option<ConfigOptionStrings>("filament_colour");
            if (printer_tab == nullptr || cur == nullptr || index >= (int) cur->values.size() || index >= (int) sb.combos_filament().size()) {
                e = "filament slot is not available";
                return false;
            }
            // Same sequence as PlaterPresetComboBox::change_extruder_color() after the colour dialog.
            auto *colors = static_cast<ConfigOptionStrings *>(cur->clone());
            colors->values[index] = color;
            DynamicPrintConfig cfg_new = bundle->project_config;
            cfg_new.set_key_value("filament_colour", colors);
            printer_tab->load_config(cfg_new);
            sb.combos_filament()[index]->update();
            wxGetApp().plater()->on_config_change(cfg_new);
            return true;
        };
    }
    if (cmd == "set_option") {
        std::string key;
        if (!ts_get_string(args, "key", key, 64) || args.find("value") == args.end()) { err = "key and value expected"; return {}; }
        boost::any value;
        if (!make_option_value(key, args.at("value"), value, err)) return {};
        if (app.get_tab(Preset::TYPE_PRINT) == nullptr) { err = "process tab is not available"; return {}; }
        modal = true; // dependency checks may ask questions (e.g. prime tower)
        return [key, value](std::string &e) {
            Tab *tab = wxGetApp().get_tab(Preset::TYPE_PRINT);
            DynamicPrintConfig *cfg = tab ? tab->get_config() : nullptr;
            if (cfg == nullptr || !cfg->has(key)) { e = "option is not available in this preset"; return false; }
            change_opt_value(*cfg, key, value);
            tab->update_dirty();
            tab->on_value_change(key, value);
            return true;
        };
    }
    if (cmd == "open_advanced") {
        return [this](std::string &) {
            m_native_open = !m_native_open;
            if (m_cb.native_toggled) m_cb.native_toggled();
            return true;
        };
    }
    if (cmd == "object_select" || cmd == "object_set_visible" || cmd == "object_delete") {
        std::string id;
        int o = -1, v = -1;
        if (!ts_get_string(args, "id", id, 64)) { err = "id expected"; return {}; }
        const int kind = parse_object_id(id, o, v);
        Model &model   = plater->model();
        if (kind == 0) { err = "not supported: plate items cannot be targeted"; return {}; }
        if (o >= (int) model.objects.size() || (kind == 2 && v >= (int) model.objects[o]->volumes.size())) { err = "object not found"; return {}; }
        if (cmd == "object_select") {
            return [o, v, kind](std::string &e) {
                Model &m = wxGetApp().plater()->model();
                if (o >= (int) m.objects.size() || (kind == 2 && v >= (int) m.objects[o]->volumes.size())) { e = "object not found"; return false; }
                ObjectVolumeID ov;
                ov.object = m.objects[o];
                ov.volume = kind == 2 ? m.objects[o]->volumes[v] : nullptr;
                wxGetApp().obj_list()->select_item(ov);
                return true;
            };
        }
        if (kind != 1) { err = "not supported: only whole objects can be hidden or deleted"; return {}; }
        if (cmd == "object_set_visible") {
            if (!args.contains("visible") || !args.at("visible").is_boolean()) { err = "visible must be boolean"; return {}; }
            const bool visible = args.at("visible").get<bool>();
            return [o, visible](std::string &e) {
                Model &m = wxGetApp().plater()->model();
                if (o >= (int) m.objects.size() || m.objects[o]->instances.empty()) { e = "object not found"; return false; }
                ObjectVolumeID ov;
                ov.object = m.objects[o];
                wxGetApp().obj_list()->select_item(ov);
                if (m.objects[o]->instances.front()->printable != visible) wxGetApp().obj_list()->toggle_printable_state();
                return true;
            };
        }
        modal = true;
        return [o](std::string &e) {
            Plater *pl = wxGetApp().plater();
            if (o >= (int) pl->model().objects.size()) { e = "object not found"; return false; }
            pl->remove((size_t) o);
            return true;
        };
    }
    if (cmd == "object_action") {
        std::string action;
        if (!ts_get_string(args, "action", action, 32)) { err = "action expected"; return {}; }
        if (action == "arrange") return [](std::string &) { wxGetApp().plater()->arrange(); return true; };
        if (action == "menu") { err = "not supported: native context menu cannot be opened from the sidebar"; return {}; }
        err = "unknown action";
        return {};
    }
    if (cmd == "slice") {
        modal = true;
        return [](std::string &) { wxPostEvent(wxGetApp().plater(), SimpleEvent(EVT_GLTOOLBAR_SLICE_PLATE)); return true; };
    }
    if (cmd == "print" || cmd == "export") {
        PartPlate *cp = plater->get_partplate_list().get_curr_plate();
        if (cp == nullptr || !(cmd == "print" ? cp->is_slice_result_ready_for_print() : cp->is_slice_result_ready_for_export())) {
            err = "the current plate has no sliced result";
            return {};
        }
        modal = true;
        if (cmd == "print") return [](std::string &) { wxPostEvent(wxGetApp().plater(), SimpleEvent(EVT_GLTOOLBAR_PRINT_PLATE)); return true; };
        return [](std::string &) { wxPostEvent(wxGetApp().plater(), SimpleEvent(EVT_GLTOOLBAR_EXPORT_GCODE)); return true; };
    }
    if (cmd == "cancel") {
        return [](std::string &) {
            BackgroundSlicingProcess &bp = wxGetApp().plater()->background_process();
            if (!bp.idle()) bp.stop();
            return true;
        };
    }
    err = "unknown command";
    return {};
}

// ---------------------------------------------------------------------------------------------

wxString TouchSidebar::strip_from_perspective(const wxString &perspective)
{
    // Layout: "layout2|name=...;...|name=...;...|dock_size(dir,layer,row)=size|"
    const wxString pane_prefix = "name=touch_sidebar;";
    const wxString dock_mid    = wxString::Format(",%d,", kPaneLayer);
    wxString out;
    wxStringTokenizer tk(perspective, "|", wxTOKEN_RET_EMPTY_ALL);
    bool first = true;
    while (tk.HasMoreTokens()) {
        const wxString part = tk.GetNextToken();
        const bool is_dock  = part.StartsWith("dock_size(");
        if (part.StartsWith(pane_prefix) || (is_dock && part.Find(dock_mid) != wxNOT_FOUND && part.Find(dock_mid) < part.Find(')')))
            continue;
        if (!first) out += "|";
        out += part;
        first = false;
    }
    return out;
}

}} // namespace Slic3r::GUI
