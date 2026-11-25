#include "Engine.hpp"
#include <atomic>
#include <mutex>
#include <set>
#include <pthread.h>
#include <boost/filesystem.hpp>
#include <boost/algorithm/string.hpp>
#include "nlohmann/json.hpp"
#include "libslic3r/Utils.hpp"
#include "libslic3r/PresetBundle.hpp"
#include "libslic3r/Model.hpp"
#include "libslic3r/ModelArrange.hpp"
#include "libslic3r/Print.hpp"
#include "libslic3r/Orient.hpp"
#include "libslic3r/CutUtils.hpp"
#include "libslic3r/AABBMesh.hpp"
#include "libslic3r/TriangleSelector.hpp"
#include "libslic3r/QuadricEdgeCollapse.hpp"
#include "libslic3r/Format/bbs_3mf.hpp"
#include "libslic3r/Format/STEP.hpp"
#include "libslic3r/Format/STL.hpp"
#include "libslic3r/GCode/GCodeProcessor.hpp"

using namespace Slic3r;
using json   = nlohmann::json;
namespace fs = boost::filesystem;

namespace {
std::string dump(const json &j) { return j.dump(-1, ' ', false, json::error_handler_t::replace); }
Vec3d       vec(const json &j) { return Vec3d(j.at(0), j.at(1), j.at(2)); }
json        arr(const Vec3d &v) { return json::array({v.x(), v.y(), v.z()}); }

struct Plate
{
    std::string                           name;
    std::shared_ptr<Print>                print;
    std::shared_ptr<GCodeProcessorResult> result;
    std::string                           gcode;
    bool                                  valid = false;
};

struct Snapshot
{
    std::shared_ptr<Model>   model;
    std::vector<std::string> plates;
    int                      current;
};
}

struct Engine::Impl
{
    std::string  resources, data_dir, temp_dir;
    PresetBundle bundle;
    Model        model;
    std::vector<Plate> plates;
    int          current = 0;
    std::vector<Snapshot> undo, redo;
    std::string  project_path;
    bool         modified = false;

    std::map<const TriangleMesh *, std::pair<std::weak_ptr<const TriangleMesh>, long long>> mesh_ids;
    std::map<long long, std::shared_ptr<const TriangleMesh>>                                live;
    long long next_mesh = 1;

    std::mutex  status_mtx;
    json        status{{"state", "idle"}};
    std::atomic<bool> slicing{false}, cancelled{false};
    std::shared_ptr<Print> running;
    pthread_t   slice_thread{};
    bool        joinable = false;

    // --- beds and plates ---
    BoundingBoxf bed() const
    {
        BoundingBoxf b;
        if (auto *o = bundle.printers.get_edited_preset().config.option<ConfigOptionPoints>("printable_area"))
            for (const Vec2d &pt : o->values) b.merge(pt);
        if (!b.defined) { b.merge(Vec2d(0, 0)); b.merge(Vec2d(256, 256)); }
        return b;
    }
    double bed_height() const
    {
        auto *o = bundle.printers.get_edited_preset().config.option<ConfigOptionFloat>("printable_height");
        return o ? o->value : 256.;
    }
    Vec3d origin(int i, int count = -1) const
    {
        if (count < 0) count = (int) plates.size();
        const int    cols = std::max(1, (int) std::ceil(std::sqrt((double) count)));
        const Vec2d  s    = bed().size();
        return Vec3d((i % cols) * s.x() * 1.2, -(i / cols) * s.y() * 1.2, 0.);
    }
    BoundingBoxf plate_box(int i) const
    {
        BoundingBoxf b = bed();
        const Vec3d  o = origin(i);
        b.translate(o.x(), o.y());
        return b;
    }
    int plate_of(const ModelObject &o, size_t inst) const
    {
        const BoundingBoxf3 bb = o.instance_bounding_box(inst);
        const Vec2d         c(bb.center().x(), bb.center().y());
        for (int i = 0; i < (int) plates.size(); ++i)
            if (plate_box(i).contains(c)) return i;
        return -1;
    }
    // Moves objects along when the plate grid changes its column count.
    void regrid(int old_count, int new_count)
    {
        if (old_count == new_count) return;
        for (ModelObject *o : model.objects)
            for (size_t k = 0; k < o->instances.size(); ++k) {
                const int i = plate_of(*o, k);
                if (i < 0 || i >= new_count) continue;
                const Vec3d d = origin(i, new_count) - origin(i, old_count);
                if (d.norm() > 1e-6) { o->instances[k]->set_offset(o->instances[k]->get_offset() + d); }
            }
        for (ModelObject *o : model.objects) o->invalidate_bounding_box();
    }
    void set_plate_count(int n)
    {
        n = std::clamp(n, 1, 36);
        regrid((int) plates.size(), n);
        plates.resize(n);
        current = std::clamp(current, 0, n - 1);
    }
    void dirty(int plate = -1)
    {
        modified = true;
        for (int i = 0; i < (int) plates.size(); ++i)
            if (plate < 0 || plate == i) plates[i].valid = false;
    }

    // --- undo ---
    Snapshot snap() const
    {
        Snapshot s;
        s.model = std::make_shared<Model>(model);
        for (const Plate &pl : plates) s.plates.push_back(pl.name);
        s.current = current;
        return s;
    }
    void restore(const Snapshot &s)
    {
        model = *s.model;
        plates.clear();
        for (const std::string &n : s.plates) { Plate pl; pl.name = n; plates.push_back(pl); }
        current = s.current;
        dirty();
    }
    void checkpoint()
    {
        undo.push_back(snap());
        if (undo.size() > 30) undo.erase(undo.begin());
        redo.clear();
        dirty();
    }

    // --- meshes ---
    long long mesh_id(const std::shared_ptr<const TriangleMesh> &m)
    {
        auto it = mesh_ids.find(m.get());
        if (it == mesh_ids.end() || it->second.first.lock() != m) {
            mesh_ids[m.get()] = {m, next_mesh++};
            it = mesh_ids.find(m.get());
        }
        live[it->second.second] = m;
        return it->second.second;
    }

    // --- presets ---
    PresetCollection &collection(const std::string &type)
    {
        if (type == "printer") return bundle.printers;
        if (type == "filament") return bundle.filaments;
        return bundle.prints;
    }
    void after_preset_change()
    {
        bundle.update_compatible(PresetSelectCompatibleType::Always);
        if (bundle.filament_presets.empty()) bundle.filament_presets.push_back(bundle.filaments.get_selected_preset_name());
        sync_filament_count(bundle.filament_presets.size());
        dirty();
    }
    void sync_filament_count(size_t n)
    {
        n = std::clamp<size_t>(n, 1, 16);
        bundle.set_num_filaments((unsigned) n);
        auto *c = bundle.project_config.option<ConfigOptionStrings>("filament_colour", true);
        static const char *defaults[] = {"#00AE42", "#F4EE2A", "#0078BF", "#C12E1F", "#FFFFFF", "#000000", "#FF6A13", "#8E9089"};
        while (c->values.size() < n) c->values.push_back(defaults[c->values.size() % 8]);
        c->values.resize(n);
        for (size_t i = 0; i < n; ++i) if (c->values[i].empty()) c->values[i] = defaults[i % 8];
    }
    void load_presets()
    {
        bundle.load_vendor_configs_from_json(resources + "/profiles", "BBL", PresetBundle::LoadSystem, ForwardCompatibilitySubstitutionRule::EnableSilent);
        try {
            PresetsConfigSubstitutions subst;
            const std::string user = data_dir + "/user/default";
            fs::create_directories(user);
            for (const char *d : {"machine", "process", "filament"}) fs::create_directories(user + "/" + d);
            bundle.prints.load_presets(user, "process", subst, ForwardCompatibilitySubstitutionRule::EnableSilent);
            bundle.filaments.load_presets(user, "filament", subst, ForwardCompatibilitySubstitutionRule::EnableSilent);
            bundle.printers.load_presets(user, "machine", subst, ForwardCompatibilitySubstitutionRule::EnableSilent);
            bundle.prints.update_user_presets_directory(user, "process");
            bundle.filaments.update_user_presets_directory(user, "filament");
            bundle.printers.update_user_presets_directory(user, "machine");
        } catch (const std::exception &) {}
        std::string printer = "Bambu Lab P1S 0.4 nozzle", process, filament;
        try {
            std::ifstream f(data_dir + "/last.json");
            json j = json::parse(f);
            printer = j.value("printer", printer); process = j.value("process", ""); filament = j.value("filament", "");
        } catch (const std::exception &) {}
        if (!bundle.printers.find_preset(printer)) printer = "Bambu Lab P1S 0.4 nozzle";
        bundle.printers.select_preset_by_name(printer, true);
        select_defaults();
        if (!process.empty() && bundle.prints.find_preset(process)) bundle.prints.select_preset_by_name(process, true);
        if (!filament.empty() && bundle.filaments.find_preset(filament)) { bundle.filaments.select_preset_by_name(filament, true); bundle.filament_presets = {filament}; }
        after_preset_change();
    }
    void select_defaults()
    {
        const DynamicPrintConfig &c = bundle.printers.get_edited_preset().config;
        if (auto *o = c.option<ConfigOptionString>("default_print_profile"); o && bundle.prints.find_preset(o->value))
            bundle.prints.select_preset_by_name(o->value, true);
        if (auto *o = c.option<ConfigOptionStrings>("default_filament_profile"); o && !o->values.empty() && bundle.filaments.find_preset(o->values[0])) {
            bundle.filaments.select_preset_by_name(o->values[0], true);
            if (bundle.filament_presets.empty()) bundle.filament_presets = {o->values[0]};
            for (std::string &f : bundle.filament_presets) f = o->values[0];
        }
    }
    void remember()
    {
        std::ofstream f(data_dir + "/last.json");
        f << dump({{"printer", bundle.printers.get_selected_preset_name()}, {"process", bundle.prints.get_selected_preset_name()},
                   {"filament", bundle.filament_presets.empty() ? "" : bundle.filament_presets.front()}});
    }

    json preset_list(PresetCollection &c, bool only_compatible)
    {
        json a = json::array();
        for (const Preset &pr : c.get_presets()) {
            if (pr.is_default || (only_compatible && !pr.is_compatible)) continue;
            a.push_back({{"name", pr.name}, {"system", pr.is_system}, {"alias", pr.alias.empty() ? pr.name : pr.alias}});
        }
        return a;
    }

    // --- options ---
    static void write_value(json &o, const std::string &key, const ConfigOption *opt)
    {
        o["value"] = opt ? opt->serialize() : std::string();
    }
    json options(const DynamicPrintConfig &cfg, const std::set<std::string> &dirty_keys)
    {
        json out = json::object();
        for (const std::string &key : cfg.keys()) {
            const ConfigOptionDef *def = print_config_def.get(key);
            const ConfigOption    *opt = cfg.option(key);
            if (def == nullptr || opt == nullptr) continue;
            json o{{"label", def->label}, {"tooltip", def->tooltip}, {"unit", def->sidetext}, {"mode", (int) def->mode}, {"multiline", def->multiline}, {"readonly", def->readonly}};
            switch (def->type) {
            case coBool: case coBools: o["type"] = "bool"; break;
            case coEnum: case coEnums: o["type"] = "enum"; o["values"] = def->enum_values; o["labels"] = def->enum_labels; break;
            case coInt: case coInts: o["type"] = "int"; break;
            case coFloat: case coFloats: o["type"] = "float"; break;
            case coPercent: case coPercents: o["type"] = "percent"; break;
            case coFloatOrPercent: case coFloatsOrPercents: o["type"] = "floatOrPercent"; break;
            default: o["type"] = "string";
            }
            if ((def->type == coString || def->type == coStrings) && !def->enum_values.empty()) { o["values"] = def->enum_values; o["labels"] = def->enum_labels; }
            if (def->min > -1e6) o["min"] = (double) def->min;
            if (def->max < 1e6) o["max"] = (double) def->max;
            if (dirty_keys.count(key)) o["dirty"] = true;
            write_value(o, key, opt);
            out[key] = std::move(o);
        }
        return out;
    }
    static void check_range(const std::string &key, const ConfigOption *opt)
    {
        const ConfigOptionDef *def = print_config_def.get(key);
        auto check = [&](double v) { if (v < def->min || v > def->max) throw std::runtime_error("value out of range"); };
        if (auto *f = dynamic_cast<const ConfigOptionFloat *>(opt)) check(f->value);
        else if (auto *i = dynamic_cast<const ConfigOptionInt *>(opt)) check(i->value);
    }
    void set_option(DynamicPrintConfig &cfg, const std::string &key, const std::string &value)
    {
        const ConfigOption *old = cfg.option(key);
        std::unique_ptr<ConfigOption> backup(old ? old->clone() : nullptr);
        try {
            cfg.set_deserialize_strict(key, value);
            check_range(key, cfg.option(key));
        } catch (...) {
            if (backup) cfg.set_key_value(key, backup.release());
            else cfg.erase(key);
            throw;
        }
    }
    DynamicPrintConfig full_config() const
    {
        DynamicPrintConfig c = bundle.full_config();
        return c;
    }

    // --- objects ---
    ModelObject *object(const json &a)
    {
        const int i = a.at("o");
        if (i < 0 || i >= (int) model.objects.size()) throw std::runtime_error("object not found");
        return model.objects[i];
    }
    ModelInstance *instance(const json &a)
    {
        ModelObject *o = object(a);
        const int    i = a.value("i", 0);
        if (i < 0 || i >= (int) o->instances.size()) throw std::runtime_error("instance not found");
        return o->instances[i];
    }
    ModelVolume *volume(const json &a)
    {
        ModelObject *o = object(a);
        const int    v = a.value("v", 0);
        if (v < 0 || v >= (int) o->volumes.size()) throw std::runtime_error("part not found");
        return o->volumes[v];
    }
    void place_new(const std::vector<ModelObject *> &objs)
    {
        const BoundingBoxf b = plate_box(current);
        for (ModelObject *o : objs) {
            o->center_around_origin();
            if (o->instances.empty()) o->add_instance();
            o->instances.front()->set_offset(Vec3d(b.center().x(), b.center().y(), o->instances.front()->get_offset(Z)));
            o->invalidate_bounding_box();
            o->ensure_on_bed();
        }
        if (!objs.empty() && (objs.size() > 1 || model.objects.size() > objs.size())) arrange(false);
    }
    void arrange(bool all)
    {
        ModelInstancePtrs ptrs;
        const Vec3d       org = origin(current);
        arrangement::ArrangePolygons items;
        std::vector<ModelInstance *> insts;
        for (ModelObject *o : model.objects)
            for (size_t k = 0; k < o->instances.size(); ++k) {
                const int pl = plate_of(*o, k);
                if (!all && pl >= 0 && pl != current) continue;
                ModelInstance *inst = o->instances[k];
                Geometry::Transformation t = inst->get_transformation();
                t.set_offset(Vec3d(0, 0, t.get_offset(Z)));
                arrangement::ArrangePolygon ap;
                Polygon hull = o->convex_hull_2d(t.get_matrix());
                if (hull.points.size() < 3) continue;
                ap.poly.contour = hull;
                ap.translation  = Vec2crd(scaled<coord_t>(inst->get_offset(X)), scaled<coord_t>(inst->get_offset(Y)));
                ap.height       = o->instance_bounding_box(k).max.z();
                ap.name         = o->name;
                ap.bed_idx      = 0;
                const int ext   = std::max(1, o->config.extruder());
                ap.extrude_id_filament_types[ext] = "";
                ap.print_temp = 220; ap.first_print_temp = 220; ap.bed_temp = 55; ap.first_bed_temp = 55; ap.vitrify_temp = 100;
                items.push_back(ap);
                insts.push_back(inst);
            }
        if (items.empty()) return;
        arrangement::ArrangeParams params;
        const DynamicPrintConfig   cfg = full_config();
        params.printable_height  = (float) bed_height();
        params.min_obj_distance  = scaled<coord_t>(6.);
        arrangement::update_arrange_params(params, cfg, items);
        arrangement::update_selected_items_inflation(items, cfg, params);
        Points bedpts = arrangement::get_shrink_bedpts(cfg, params);
        arrangement::arrange(items, {}, bedpts, params);
        int max_bed = 0;
        for (auto &ap : items) max_bed = std::max(max_bed, ap.bed_idx);
        if (all && max_bed + 1 > (int) plates.size()) plates.resize(std::min(36, max_bed + 1));
        for (size_t n = 0; n < items.size(); ++n) {
            auto &ap = items[n];
            if (ap.bed_idx < 0) continue;
            int pl = all ? ap.bed_idx : current + ap.bed_idx;
            if (pl >= (int) plates.size()) set_plate_count(pl + 1);
            const Vec3d po = origin(pl);
            ModelInstance *inst = insts[n];
            if (ap.rotation != 0.) inst->set_rotation(inst->get_rotation() + Vec3d(0, 0, ap.rotation));
            inst->set_offset(Vec3d(unscaled(ap.translation.x()) + po.x(), unscaled(ap.translation.y()) + po.y(), inst->get_offset(Z)));
        }
        for (ModelObject *o : model.objects) o->invalidate_bounding_box();
    }

    json state();
    json open(const json &a);
    void save(const std::string &path, int plate_gcode);
    void start_slice(int plate);
    void run_slice(int plate, std::shared_ptr<Print> print, std::string out);
    json dispatch(const std::string &cmd, const json &a);
    json paint(const json &a);
    json ray(const json &a);
    void set_status(json s) { std::lock_guard<std::mutex> l(status_mtx); status = std::move(s); }
    void join() { if (joinable) { pthread_join(slice_thread, nullptr); joinable = false; } }
    static FacetsAnnotation &facets(ModelVolume *v, int kind)
    {
        return kind == 0 ? v->supported_facets : kind == 1 ? v->seam_facets : v->mmu_segmentation_facets;
    }
};

json Engine::Impl::state()
{
    live.clear();
    json s;
    json objs = json::array();
    for (int oi = 0; oi < (int) model.objects.size(); ++oi) {
        ModelObject *o = model.objects[oi];
        json jo{{"index", oi}, {"id", (long long) o->id().id}, {"name", o->name}, {"extruder", std::max(1, o->config.extruder())}, {"facets", (long long) o->facets_count()}};
        json vs = json::array();
        for (int vi = 0; vi < (int) o->volumes.size(); ++vi) {
            ModelVolume *v = o->volumes[vi];
            json         m = json::array();
            const Matrix4f mat = v->get_matrix().matrix().cast<float>();
            for (int k = 0; k < 16; ++k) m.push_back(mat.data()[k]);
            vs.push_back({{"index", vi}, {"name", v->name}, {"mesh", mesh_id(v->get_mesh_shared_ptr())}, {"type", (int) v->type()}, {"matrix", m}, {"extruder", std::max(1, v->extruder_id())},
                          {"supportPaint", !v->supported_facets.empty()}, {"seamPaint", !v->seam_facets.empty()}, {"colorPaint", !v->mmu_segmentation_facets.empty()},
                          {"paintStamp", (long long) (v->supported_facets.timestamp() + v->seam_facets.timestamp() + v->mmu_segmentation_facets.timestamp())}});
        }
        jo["volumes"] = vs;
        json is = json::array();
        for (int ii = 0; ii < (int) o->instances.size(); ++ii) {
            ModelInstance *inst = o->instances[ii];
            const Matrix4f mat  = inst->get_matrix().matrix().cast<float>();
            json           m    = json::array();
            for (int k = 0; k < 16; ++k) m.push_back(mat.data()[k]);
            const BoundingBoxf3 bb = o->instance_bounding_box(ii);
            is.push_back({{"index", ii}, {"matrix", m}, {"printable", inst->printable}, {"plate", plate_of(*o, ii)}, {"offset", arr(inst->get_offset())},
                          {"rotation", arr(inst->get_rotation() * (180. / PI))}, {"scale", arr(inst->get_scaling_factor())}, {"min", arr(bb.min)}, {"max", arr(bb.max)}});
        }
        jo["instances"] = is;
        json oc = json::object();
        for (const std::string &k : o->config.keys()) if (k != "extruder") oc[k] = o->config.get().opt_serialize(k);
        jo["config"] = oc;
        objs.push_back(jo);
    }
    s["objects"] = objs;
    json pls = json::array();
    for (int i = 0; i < (int) plates.size(); ++i) {
        const Vec3d o = origin(i);
        pls.push_back({{"index", i}, {"name", plates[i].name}, {"origin", {o.x(), o.y()}}, {"sliced", plates[i].valid}});
    }
    s["plates"]  = pls;
    s["current"] = current;
    const BoundingBoxf b = bed();
    s["bed"] = {b.min.x(), b.min.y(), b.max.x(), b.max.y(), bed_height()};
    json excl = json::array();
    if (auto *o = bundle.printers.get_edited_preset().config.option<ConfigOptionPoints>("bed_exclude_area"))
        for (const Vec2d &pt : o->values) excl.push_back({pt.x(), pt.y()});
    s["exclude"] = excl;
    s["printer"] = {{"name", bundle.printers.get_selected_preset_name()}, {"dirty", bundle.printers.current_is_dirty()}};
    s["process"] = {{"name", bundle.prints.get_selected_preset_name()}, {"dirty", bundle.prints.current_is_dirty()}};
    json fil = json::array();
    auto *colors = bundle.project_config.option<ConfigOptionStrings>("filament_colour");
    for (size_t i = 0; i < bundle.filament_presets.size(); ++i) {
        std::string type;
        if (const Preset *pr = bundle.filaments.find_preset(bundle.filament_presets[i]))
            if (auto *t = pr->config.option<ConfigOptionStrings>("filament_type"); t && !t->values.empty()) type = t->values[0];
        fil.push_back({{"name", bundle.filament_presets[i]}, {"type", type}, {"color", colors && i < colors->values.size() ? colors->values[i] : "#00AE42"}});
    }
    s["filaments"] = fil;
    s["bedType"]   = bundle.project_config.opt_serialize("curr_bed_type");
    s["canUndo"]   = !undo.empty();
    s["canRedo"]   = !redo.empty();
    s["modified"]  = modified;
    s["path"]      = project_path;
    return s;
}

json Engine::Impl::open(const json &a)
{
    const std::string path = a.at("path");
    const bool        is3mf = boost::iends_with(path, ".3mf");
    if (!is3mf || a.value("geometry", false)) {
        Model m;
        if (boost::iends_with(path, ".step") || boost::iends_with(path, ".stp")) {
            bool cancel = false;
            if (!load_step(path.c_str(), &m, cancel)) throw std::runtime_error("cannot read STEP file");
            m.add_default_instances();
        } else if (is3mf) {
            DynamicPrintConfig c; ConfigSubstitutionContext sc(ForwardCompatibilitySubstitutionRule::EnableSilent);
            m = Model::read_from_file(path, &c, &sc, LoadStrategy::LoadModel | LoadStrategy::AddDefaultInstances);
        } else
            m = Model::read_from_file(path, nullptr, nullptr, LoadStrategy::AddDefaultInstances);
        if (m.objects.empty()) throw std::runtime_error("the file contains no model");
        checkpoint();
        std::vector<ModelObject *> added;
        for (ModelObject *o : m.objects) {
            ModelObject *n = model.add_object(*o);
            if (n->name.empty()) n->name = fs::path(path).stem().string();
            n->sort_volumes(true);
            added.push_back(n);
        }
        place_new(added);
        return state();
    }
    DynamicPrintConfig        loaded;
    ConfigSubstitutionContext subst(ForwardCompatibilitySubstitutionRule::Enable);
    PlateDataPtrs             pd;
    std::vector<Preset *>     project_presets;
    bool   is_bbl = false;
    Semver version;
    Model  m = Model::read_from_file(path, &loaded, &subst, LoadStrategy::LoadModel | LoadStrategy::LoadConfig | LoadStrategy::AddDefaultInstances, &pd, &project_presets, &is_bbl, &version);
    if (m.objects.empty()) { release_PlateData_list(pd); throw std::runtime_error("the file contains no model"); }
    std::string warn;
    if (!loaded.empty()) {
        try {
            if (!project_presets.empty()) bundle.load_project_embedded_presets(project_presets, ForwardCompatibilitySubstitutionRule::EnableSilent);
            // Plain printer name: fill keys the (older) file does not know from the stock preset of this printer.
            Preset::normalize(loaded);
            bundle.load_config_model(fs::path(path).filename().string(), loaded, version);
            bundle.update_compatible(PresetSelectCompatibleType::Never);
            sync_filament_count(bundle.filament_presets.size());
        } catch (const std::exception &e) { warn = e.what(); }
    }
    undo.clear(); redo.clear();
    model = std::move(m);
    plates.clear();
    plates.resize(std::max<size_t>(1, pd.size()));
    for (size_t i = 0; i < pd.size(); ++i) plates[i].name = pd[i]->plate_name;
    current = 0;
    if (!is_bbl) place_new(model.objects);
    else for (ModelObject *o : model.objects) o->invalidate_bounding_box();
    release_PlateData_list(pd);
    dirty();
    modified     = false;
    project_path = path;
    json s = state();
    if (!warn.empty()) s["warning"] = warn;
    return s;
}

void Engine::Impl::save(const std::string &path, int plate_gcode)
{
    PlateDataPtrs pd;
    for (int i = 0; i < (int) plates.size(); ++i) {
        auto *d        = new PlateData();
        d->plate_index = i;
        d->plate_name  = plates[i].name;
        for (int o = 0; o < (int) model.objects.size(); ++o)
            for (int k = 0; k < (int) model.objects[o]->instances.size(); ++k)
                if (plate_of(*model.objects[o], k) == i) d->objects_and_instances.emplace_back(o, k);
        if (plate_gcode >= 0 && i == plate_gcode && plates[i].valid) {
            d->gcode_file      = plates[i].gcode;
            d->is_sliced_valid = true;
            GCodeProcessorResult *r = plates[i].result.get();
            d->gcode_prediction = std::to_string((int) r->print_statistics.modes[0].time);
            d->gcode_weight     = std::to_string(plates[i].print->print_statistics().total_weight);
            d->printer_model_id = bundle.printers.get_edited_preset().get_printer_type(&bundle);
            d->nozzle_diameters = plates[i].print->config().nozzle_diameter.serialize();
            d->is_support_used  = plates[i].print->is_support_used();
            d->parse_filament_info(r);
        }
        pd.push_back(d);
    }
    DynamicPrintConfig cfg = full_config();
    StoreParams sp;
    const std::string tmp = path + ".tmp";
    sp.path             = tmp.c_str();
    sp.model            = &model;
    sp.plate_data_list  = pd;
    sp.project_presets  = bundle.get_current_project_embedded_presets();
    sp.config           = &cfg;
    sp.export_plate_idx = plate_gcode;
    sp.strategy         = SaveStrategy::Zip64 | SaveStrategy::Silence;
    if (plate_gcode >= 0) sp.strategy = sp.strategy | SaveStrategy::WithGcode | SaveStrategy::SkipModel | SaveStrategy::WithSliceInfo | SaveStrategy::SkipAuxiliary;
    else sp.strategy = sp.strategy | SaveStrategy::SplitModel | SaveStrategy::ShareMesh;
    const bool ok = store_bbs_3mf(sp);
    for (auto *d : pd) delete d;
    if (!ok) { boost::system::error_code ec; fs::remove(tmp, ec); throw std::runtime_error("cannot write the 3mf file"); }
    fs::rename(tmp, path);
    if (plate_gcode < 0) { modified = false; project_path = path; }
}

void Engine::Impl::run_slice(int plate, std::shared_ptr<Print> print, std::string out)
{
    json done;
    try {
        print->process();
        auto result = std::make_shared<GCodeProcessorResult>();
        const std::string path = print->export_gcode(out, result.get(), nullptr);
        const auto &m = result->print_statistics.modes[0];
        json roles = json::array();
        for (auto &r : m.roles_times) roles.push_back({(int) r.first, r.second});
        json fil = json::array();
        for (auto &f : print->print_statistics().filament_stats) fil.push_back({(int) f.first, f.second});
        json warns = json::array();
        for (auto &w : result->warnings) warns.push_back(w.msg);
        done = {{"state", "done"}, {"plate", plate}, {"time", m.time}, {"prepare", m.prepare_time}, {"weight", print->print_statistics().total_weight}, {"length", print->print_statistics().total_used_filament},
                {"cost", print->print_statistics().total_cost}, {"layers", print->objects().empty() ? 0 : (int) print->objects().front()->layer_count()}, {"roles", roles}, {"filaments", fil},
                {"toolchanges", print->print_statistics().total_toolchanges}, {"warnings", warns}, {"conflict", print->get_conflict_string()}, {"gcode", path}};
        std::lock_guard<std::mutex> l(status_mtx);
        if (plate < (int) plates.size() && plates[plate].print == print) {
            plates[plate].result = result;
            plates[plate].gcode  = path;
        }
    } catch (const CanceledException &) {
        done = {{"state", "cancelled"}, {"plate", plate}};
    } catch (const std::exception &e) {
        done = {{"state", "error"}, {"plate", plate}, {"message", e.what()}};
    }
    if (cancelled) done = {{"state", "cancelled"}, {"plate", plate}};
    print->finalize();
    set_status(done);
    slicing = false;
}

void Engine::Impl::start_slice(int plate)
{
    if (slicing) throw std::runtime_error("already slicing");
    join();
    if (plate < 0 || plate >= (int) plates.size()) throw std::runtime_error("plate not found");
    int count = 0;
    for (ModelObject *o : model.objects)
        for (size_t k = 0; k < o->instances.size(); ++k) {
            const bool on = plate_of(*o, k) == plate;
            BoundingBoxf3 bb = o->instance_bounding_box(k);
            BoundingBoxf  pb = plate_box(plate);
            const bool    inside = on && pb.contains(Vec2d(bb.min.x(), bb.min.y())) && pb.contains(Vec2d(bb.max.x(), bb.max.y())) && bb.max.z() <= bed_height() + EPSILON;
            o->instances[k]->print_volume_state = inside ? ModelInstancePVS_Inside : on ? ModelInstancePVS_Partly_Outside : ModelInstancePVS_Fully_Outside;
            if (on && o->instances[k]->printable) {
                if (!inside) throw std::runtime_error("\"" + o->name + "\" is outside the plate or too tall");
                ++count;
            }
        }
    if (!count) throw std::runtime_error("the plate is empty");
    auto print = std::make_shared<Print>();
    print->set_plate_index(plate);
    print->set_plate_origin(origin(plate));
    DynamicPrintConfig cfg = full_config();
    print->apply(model, cfg);
    std::vector<StringObjectException> warnings;
    const auto err = print->validate(&warnings);
    if (!err.string.empty()) throw std::runtime_error(err.string);
    print->set_status_callback([this, plate](const PrintBase::SlicingStatus &st) {
        if (st.percent >= 0) set_status({{"state", "slicing"}, {"plate", plate}, {"percent", st.percent}, {"text", st.text}});
    });
    plates[plate].print = print;
    plates[plate].valid = true; // cleared again by dirty(), or by slice_result when it did not finish
    plates[plate].result.reset();
    cancelled = false;
    slicing   = true;
    running   = print;
    set_status({{"state", "slicing"}, {"plate", plate}, {"percent", 0}, {"text", ""}});
    struct Job { Impl *self; int plate; std::shared_ptr<Print> print; std::string out; };
    auto *job = new Job{this, plate, print, temp_dir + "/plate_" + std::to_string(plate + 1) + ".gcode"};
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 64 << 20);
    const int rc = pthread_create(&slice_thread, &attr, [](void *q) -> void * {
        std::unique_ptr<Job> j(static_cast<Job *>(q));
        pthread_setname_np("slicing");
        j->self->run_slice(j->plate, j->print, j->out);
        return nullptr;
    }, job);
    pthread_attr_destroy(&attr);
    if (rc != 0) { delete job; slicing = false; throw std::runtime_error("cannot start the slicing thread"); }
    joinable = true;
}

// World-space ray against one volume. {o,i,v,origin,dir} -> {hit,point(volume space),facet,normal(world)}
json Engine::Impl::ray(const json &a)
{
    ModelVolume   *v  = volume(a);
    ModelInstance *in = instance(a);
    const Transform3d t   = in->get_matrix() * v->get_matrix();
    const Transform3d inv = t.inverse();
    const Vec3d src = inv * vec(a.at("origin"));
    const Vec3d dir = (inv.linear() * vec(a.at("dir"))).normalized();
    static std::map<const TriangleMesh *, std::pair<std::weak_ptr<const TriangleMesh>, std::shared_ptr<AABBMesh>>> cache;
    auto  sp = v->get_mesh_shared_ptr();
    auto &e  = cache[sp.get()];
    if (e.first.lock() != sp) {
        for (auto it = cache.begin(); it != cache.end();) if (it->first != sp.get() && it->second.first.expired()) it = cache.erase(it); else ++it;
        cache[sp.get()] = {sp, std::make_shared<AABBMesh>(sp->its)};
    }
    auto hit = cache[sp.get()].second->query_ray_hit(src, dir);
    if (!hit.is_hit()) return {{"hit", false}};
    const Vec3d n = (t.linear().inverse().transpose() * hit.normal()).normalized();
    return {{"hit", true}, {"point", arr(hit.position())}, {"world", arr(t * hit.position())}, {"facet", hit.face()}, {"normal", arr(n)}};
}

// {.. ray args, kind, state, radius, tool: "circle"|"sphere"|"fill"|"triangle", angle}
json Engine::Impl::paint(const json &a)
{
    json h = ray(a);
    if (!h.value("hit", false)) return {{"hit", false}};
    ModelVolume   *v  = volume(a);
    ModelInstance *in = instance(a);
    const int kind  = a.at("kind");
    const auto st   = (EnforcerBlockerType) a.at("state").get<int>();
    FacetsAnnotation &fa = facets(v, kind);
    TriangleSelector  sel(v->mesh());
    if (!fa.empty()) sel.deserialize(fa.get_data());
    Transform3d t = in->get_matrix() * v->get_matrix();
    const Vec3f hit = vec(h["point"]).cast<float>();
    const Vec3f cam = (t.inverse() * vec(a.at("origin"))).cast<float>();
    Transform3d nt = t; nt.translation().setZero();
    const int   facet = h["facet"];
    const std::string tool = a.value("tool", "circle");
    if (tool == "fill") {
        sel.seed_fill_select_triangles(hit, facet, nt, TriangleSelector::ClippingPlane(), a.value("angle", 30.f), 0.f, true);
        sel.seed_fill_apply_on_triangles(st);
    } else if (tool == "triangle") {
        sel.bucket_fill_select_triangles(hit, facet, TriangleSelector::ClippingPlane(), 30.f, false, true);
        sel.seed_fill_apply_on_triangles(st);
    } else {
        auto cur = TriangleSelector::SinglePointCursor::cursor_factory(hit, cam, a.value("radius", 2.f), tool == "sphere" ? TriangleSelector::CursorType::SPHERE : TriangleSelector::CursorType::CIRCLE, t, TriangleSelector::ClippingPlane());
        sel.select_patch(facet, std::move(cur), st, nt, true, 0.f);
    }
    fa.set(sel);
    dirty();
    return {{"hit", true}};
}

json Engine::Impl::dispatch(const std::string &cmd, const json &a)
{
    if (cmd == "state") return state();
    if (cmd == "presets") {
        const std::string t = a.at("type");
        return {{"items", preset_list(collection(t), t != "printer")}, {"selected", collection(t).get_selected_preset_name()}};
    }
    if (cmd == "select_preset") {
        const std::string t = a.at("type"), n = a.at("name");
        if (!collection(t).find_preset(n)) throw std::runtime_error("preset not found");
        collection(t).select_preset_by_name(n, true);
        if (t == "printer") {
            const size_t count = std::max<size_t>(1, bundle.filament_presets.size());
            // keep the process/filaments when they still fit, else take the printer's defaults
            bundle.update_compatible(PresetSelectCompatibleType::Never);
            const bool ok = bundle.prints.get_edited_preset().is_compatible;
            bool fok = true;
            for (auto &f : bundle.filament_presets) { const Preset *pr = bundle.filaments.find_preset(f); fok = fok && pr && pr->is_compatible; }
            if (!ok || !fok) select_defaults();
            bundle.filament_presets.resize(count, bundle.filament_presets.empty() ? "" : bundle.filament_presets.front());
        }
        after_preset_change();
        remember();
        return state();
    }
    if (cmd == "set_filament") {
        const int i = a.at("index");
        if (i < 0 || i >= (int) bundle.filament_presets.size()) throw std::runtime_error("filament not found");
        if (a.contains("name")) {
            const std::string n = a["name"];
            if (!bundle.filaments.find_preset(n)) throw std::runtime_error("preset not found");
            bundle.set_filament_preset(i, n);
            if (i == 0) bundle.filaments.select_preset_by_name(n, true);
        }
        if (a.contains("color")) bundle.project_config.option<ConfigOptionStrings>("filament_colour", true)->values.at(i) = a["color"].get<std::string>();
        dirty(); remember();
        return state();
    }
    if (cmd == "add_filament") { sync_filament_count(bundle.filament_presets.size() + 1); bundle.update_multi_material_filament_presets(); dirty(); return state(); }
    if (cmd == "remove_filament") {
        const int i = a.at("index");
        const int n = (int) bundle.filament_presets.size();
        if (n <= 1 || i < 0 || i >= n) throw std::runtime_error("the last filament cannot be removed");
        checkpoint();
        auto *c = bundle.project_config.option<ConfigOptionStrings>("filament_colour", true);
        if (i < (int) c->values.size()) c->values.erase(c->values.begin() + i);
        bundle.filament_presets.erase(bundle.filament_presets.begin() + i);
        sync_filament_count(n - 1);
        bundle.update_multi_material_filament_presets();
        for (ModelObject *o : model.objects) {
            auto fix = [&](ModelConfigObject &cfg) { const int e = cfg.extruder(); if (e > i + 1) cfg.set("extruder", e - 1); else if (e == i + 1) cfg.set("extruder", 1); };
            if (o->config.has("extruder")) fix(o->config);
            for (ModelVolume *v : o->volumes) if (v->config.has("extruder")) fix(v->config);
        }
        return state();
    }
    if (cmd == "bed_type") { bundle.project_config.set_deserialize_strict("curr_bed_type", a.at("value").get<std::string>()); dirty(); return state(); }
    if (cmd == "bed_types") {
        const ConfigOptionDef *d = print_config_def.get("curr_bed_type");
        return {{"values", d->enum_values}, {"labels", d->enum_labels}};
    }
    if (cmd == "options") {
        const std::string t = a.at("type");
        if (t == "object") return options(object(a)->config.get(), {});
        auto dk = collection(t).current_dirty_options();
        std::set<std::string> ds;
        for (std::string k : dk) ds.insert(k.substr(0, k.find('#')));
        return options(collection(t).get_edited_preset().config, ds);
    }
    if (cmd == "set_option") {
        const std::string t = a.at("type"), key = a.at("key"), val = a.at("value");
        if (t == "object") { checkpoint(); DynamicPrintConfig tmp; set_option(tmp, key, val); object(a)->config.apply(tmp, true); }
        else { set_option(collection(t).get_edited_preset().config, key, val); collection(t).update_dirty(); if (t == "printer") bundle.update_compatible(PresetSelectCompatibleType::Never); }
        dirty();
        return state();
    }
    if (cmd == "clear_object_option") { checkpoint(); object(a)->config.erase(a.at("key").get<std::string>()); return state(); }
    if (cmd == "reset_option") {
        const std::string t = a.at("type"), key = a.at("key");
        const ConfigOption *o = collection(t).get_selected_preset().config.option(key);
        if (o) collection(t).get_edited_preset().config.set_key_value(key, o->clone());
        collection(t).update_dirty(); dirty();
        return state();
    }
    if (cmd == "discard_preset") { collection(a.at("type")).discard_current_changes(); after_preset_change(); return state(); }
    if (cmd == "save_preset") {
        const std::string t = a.at("type"), n = a.at("name");
        if (n.empty() || n.find_first_of("<>[]:/\\|?*\"") != std::string::npos) throw std::runtime_error("the name contains invalid characters");
        if (const Preset *pr = collection(t).find_preset(n); pr && (pr->is_system || pr->is_default)) throw std::runtime_error("a system preset cannot be overwritten");
        collection(t).save_current_preset(n);
        if (t == "filament" && !bundle.filament_presets.empty()) bundle.filament_presets.front() = n;
        after_preset_change(); remember();
        return state();
    }
    if (cmd == "delete_preset") {
        if (collection(a.at("type")).get_selected_preset().is_system) throw std::runtime_error("a system preset cannot be deleted");
        collection(a.at("type")).delete_current_preset(); after_preset_change(); return state();
    }
    if (cmd == "open") return open(a);
    if (cmd == "new") { model.clear_objects(); plates.assign(1, Plate()); current = 0; undo.clear(); redo.clear(); project_path.clear(); modified = false; return state(); }
    if (cmd == "save") { save(a.at("path"), -1); return state(); }
    if (cmd == "export_gcode3mf") {
        const int pl = a.value("plate", current);
        if (!plates.at(pl).valid || !plates[pl].result) throw std::runtime_error("slice the plate first");
        save(a.at("path"), pl); return json::object();
    }
    if (cmd == "export_gcode") {
        const int pl = a.value("plate", current);
        if (!plates.at(pl).valid || !plates[pl].result) throw std::runtime_error("slice the plate first");
        fs::copy_file(plates[pl].gcode, a.at("path").get<std::string>(), fs::copy_options::overwrite_existing); return json::object();
    }
    if (cmd == "export_stl") {
        TriangleMesh m = a.contains("o") ? object(a)->mesh() : model.mesh();
        if (!store_stl(a.at("path").get<std::string>().c_str(), &m, true)) throw std::runtime_error("cannot write STL");
        return json::object();
    }
    if (cmd == "undo" || cmd == "redo") {
        auto &from = cmd == "undo" ? undo : redo;
        auto &to   = cmd == "undo" ? redo : undo;
        if (from.empty()) return state();
        to.push_back(snap());
        Snapshot s = from.back(); from.pop_back();
        restore(s);
        return state();
    }
    if (cmd == "plate_select") { current = std::clamp<int>(a.at("plate"), 0, (int) plates.size() - 1); return state(); }
    if (cmd == "plate_add") { checkpoint(); set_plate_count((int) plates.size() + 1); current = (int) plates.size() - 1; return state(); }
    if (cmd == "plate_rename") { plates.at(a.at("plate").get<int>()).name = a.at("name"); modified = true; return state(); }
    if (cmd == "plate_remove") {
        const int i = a.at("plate");
        if (plates.size() <= 1 || i < 0 || i >= (int) plates.size()) throw std::runtime_error("the last plate cannot be removed");
        checkpoint();
        for (size_t o = model.objects.size(); o-- > 0;) {
            ModelObject *ob = model.objects[o];
            for (size_t k = ob->instances.size(); k-- > 0;) {
                const int pl = plate_of(*ob, k);
                if (pl == i) ob->delete_instance(k);
                else if (pl > i) ob->instances[k]->set_offset(ob->instances[k]->get_offset() + origin(pl - 1) - origin(pl));
            }
            ob->invalidate_bounding_box();
            if (ob->instances.empty()) model.delete_object(o);
        }
        const int n = (int) plates.size();
        plates.erase(plates.begin() + i);
        plates.resize(n);
        set_plate_count(n - 1);
        dirty();
        return state();
    }
    if (cmd == "arrange") { checkpoint(); arrange(a.value("all", false)); return state(); }
    if (cmd == "delete") {
        checkpoint();
        std::set<std::pair<int, int>> ids;
        for (auto &x : a.at("ids")) ids.insert({x.at(0), x.at(1)});
        for (auto it = ids.rbegin(); it != ids.rend(); ++it) {
            if (it->first >= (int) model.objects.size()) continue;
            ModelObject *o = model.objects[it->first];
            if (it->second < (int) o->instances.size() && o->instances.size() > 1) o->delete_instance(it->second);
            else if (it->second < (int) o->instances.size()) model.delete_object(it->first);
        }
        return state();
    }
    if (cmd == "delete_volume") {
        checkpoint();
        ModelObject *o = object(a);
        if (o->volumes.size() <= 1) throw std::runtime_error("the last part cannot be deleted");
        volume(a); o->delete_volume(a.at("v").get<int>()); o->invalidate_bounding_box();
        return state();
    }
    if (cmd == "clone") {
        checkpoint();
        ModelObject *o = object(a);
        const int    n = std::clamp<int>(a.value("n", 1), 1, 100);
        for (int k = 0; k < n; ++k) {
            ModelInstance *src = o->instances.at(a.value("i", 0));
            ModelObject   *c   = model.add_object(*o);
            while (c->instances.size() > 1) c->delete_last_instance();
            c->instances.front()->set_transformation(src->get_transformation());
            c->instances.front()->set_offset(src->get_offset() + Vec3d(10. * (k + 1), 0, 0));
            c->invalidate_bounding_box();
        }
        if (a.value("arrange", true)) arrange(false);
        return state();
    }
    if (cmd == "rename") { object(a)->name = a.at("name"); modified = true; return state(); }
    if (cmd == "printable") { checkpoint(); instance(a)->printable = a.at("value"); return state(); }
    if (cmd == "extruder") {
        checkpoint();
        const int e = a.at("value");
        if (a.contains("v")) volume(a)->config.set("extruder", e);
        else { object(a)->config.set("extruder", e); for (ModelVolume *v : object(a)->volumes) v->config.erase("extruder"); }
        return state();
    }
    if (cmd == "volume_type") { checkpoint(); volume(a)->set_type((ModelVolumeType) a.at("value").get<int>()); object(a)->invalidate_bounding_box(); return state(); }
    if (cmd == "transform") {
        ModelInstance *in = instance(a);
        if (a.value("checkpoint", true)) checkpoint();
        in = instance(a); // checkpoint() copies the model; pointers stay valid, refreshed for clarity
        if (a.contains("offset")) in->set_offset(vec(a["offset"]));
        if (a.contains("rotation")) in->set_rotation(vec(a["rotation"]) * (PI / 180.));
        if (a.contains("rotateWorld")) { // axis + degrees about the world axis
            const Vec3d  ax = vec(a["rotateWorld"]).normalized();
            Geometry::Transformation t = in->get_transformation();
            const Vec3d off = t.get_offset();
            Transform3d m = t.get_matrix(); m.translation().setZero();
            m = Transform3d(Eigen::AngleAxisd(a.at("degrees").get<double>() * PI / 180., ax)) * m;
            m.translation() = off;
            in->set_transformation(Geometry::Transformation(m));
        }
        if (a.contains("scale")) {
            const Vec3d s = vec(a["scale"]);
            if (s.minCoeff() <= 0.0001 || s.maxCoeff() > 10000.) throw std::runtime_error("invalid scale");
            in->set_scaling_factor(s);
        }
        if (a.contains("mirror")) { const Axis ax = (Axis) a["mirror"].get<int>(); in->set_mirror(ax, -in->get_mirror(ax)); }
        ModelObject *o = object(a);
        o->invalidate_bounding_box();
        if (a.value("drop", true)) {
            const double z = o->instance_bounding_box(a.value("i", 0)).min.z();
            in->set_offset(Z, in->get_offset(Z) - z);
            o->invalidate_bounding_box();
        }
        dirty();
        return state();
    }
    if (cmd == "center") {
        checkpoint();
        ModelInstance *in = instance(a);
        const Vec2d c = plate_box(current).center();
        const BoundingBoxf3 bb = object(a)->instance_bounding_box(a.value("i", 0));
        in->set_offset(in->get_offset() + Vec3d(c.x() - bb.center().x(), c.y() - bb.center().y(), 0));
        object(a)->invalidate_bounding_box();
        return state();
    }
    if (cmd == "lay_flat") { // normal in world space becomes -Z
        checkpoint();
        ModelInstance *in = instance(a);
        const Vec3d n = vec(a.at("normal")).normalized();
        Geometry::Transformation t = in->get_transformation();
        const Vec3d off = t.get_offset();
        Transform3d m = t.get_matrix(); m.translation().setZero();
        m = Transform3d(Eigen::Quaterniond().setFromTwoVectors(n, -Vec3d::UnitZ())) * m;
        m.translation() = off;
        in->set_transformation(Geometry::Transformation(m));
        ModelObject *o = object(a);
        o->invalidate_bounding_box();
        in->set_offset(Z, in->get_offset(Z) - o->instance_bounding_box(a.value("i", 0)).min.z());
        o->invalidate_bounding_box();
        return state();
    }
    if (cmd == "auto_orient") {
        checkpoint();
        ModelObject *o = object(a);
        orientation::orient(o);
        o->invalidate_bounding_box();
        o->ensure_on_bed();
        return state();
    }
    if (cmd == "split_objects") {
        checkpoint();
        ModelObject    *o = object(a);
        ModelObjectPtrs out;
        o->split(&out);
        if (out.size() <= 1) { for (auto *n : out) model.delete_object(n); undo.pop_back(); throw std::runtime_error("the object has only one part"); }
        for (ModelObject *n : out) { n->invalidate_bounding_box(); n->ensure_on_bed(); }
        model.delete_object(o);
        return state();
    }
    if (cmd == "split_parts") {
        checkpoint();
        if (volume(a)->split((unsigned) bundle.filament_presets.size()) <= 1) throw std::runtime_error("the part cannot be split");
        object(a)->invalidate_bounding_box();
        return state();
    }
    if (cmd == "merge") {
        checkpoint();
        std::set<int> ids;
        for (auto &x : a.at("ids")) ids.insert(x.get<int>());
        if (ids.size() < 2) throw std::runtime_error("select at least two objects");
        ModelObject *n = model.add_object();
        n->name = "Assembly";
        for (int id : ids) {
            ModelObject *o = model.objects.at(id);
            for (ModelVolume *v : o->volumes) {
                ModelVolume *nv = n->add_volume(*v);
                nv->set_transformation(Geometry::Transformation(o->instances.front()->get_matrix() * v->get_matrix()));
                if (!nv->config.has("extruder")) nv->config.set("extruder", std::max(1, o->config.extruder()));
            }
        }
        n->add_instance();
        for (auto it = ids.rbegin(); it != ids.rend(); ++it) model.delete_object(*it);
        n->invalidate_bounding_box();
        const Vec3d c = n->instance_bounding_box(0).center();
        n->center_around_origin();
        n->instances.front()->set_offset(c);
        n->invalidate_bounding_box(); n->ensure_on_bed();
        return state();
    }
    if (cmd == "simplify") {
        checkpoint();
        ModelVolume *v = volume(a);
        indexed_triangle_set its = v->mesh().its;
        const double r = std::clamp<double>(a.at("ratio"), 0.01, 1.);
        its_quadric_edge_collapse(its, (uint32_t) std::max(4., its.indices.size() * r));
        v->set_mesh(std::move(its));
        v->calculate_convex_hull(); v->set_new_unique_id();
        v->supported_facets.reset(); v->seam_facets.reset(); v->mmu_segmentation_facets.reset();
        object(a)->invalidate_bounding_box();
        return state();
    }
    if (cmd == "add_shape") {
        checkpoint();
        const std::string t = a.at("shape");
        const double s = a.value("size", 20.);
        TriangleMesh m = t == "cylinder" ? make_cylinder(s / 2, s) : t == "sphere" ? make_sphere(s / 2, PI / 60) : t == "cone" ? make_cone(s / 2, s) : make_cube(s, s, s);
        if (a.contains("o")) { // part inside an object: 1 negative, 2 modifier, 3 blocker, 4 enforcer
            ModelObject *o = object(a);
            ModelVolume *v = o->add_volume(std::move(m), (ModelVolumeType) a.value("type", 0));
            v->name = t;
            v->set_offset(Vec3d::Zero());
            o->invalidate_bounding_box();
        } else {
            ModelObject *o = model.add_object(t.c_str(), "", std::move(m));
            o->volumes.front()->name = t;
            place_new({o});
        }
        return state();
    }
    if (cmd == "volume_transform") {
        checkpoint();
        ModelVolume *v = volume(a);
        if (a.contains("offset")) v->set_offset(vec(a["offset"]));
        if (a.contains("scale")) v->set_scaling_factor(vec(a["scale"]));
        object(a)->invalidate_bounding_box();
        return state();
    }
    if (cmd == "cut") { // plane point + normal in world space
        checkpoint();
        ModelObject   *o  = object(a);
        ModelInstance *in = instance(a);
        const int      ii = a.value("i", 0);
        const Vec3d n = vec(a.at("normal")).normalized();
        Transform3d cm = Transform3d::Identity();
        cm.linear() = Eigen::Quaterniond().setFromTwoVectors(Vec3d::UnitZ(), n).toRotationMatrix();
        cm.translation() = vec(a.at("point")) - in->get_offset();
        ModelObjectCutAttributes at = ModelObjectCutAttribute::InvalidateCutInfo;
        if (a.value("upper", true)) at = at | ModelObjectCutAttribute::KeepUpper;
        if (a.value("lower", true)) at = at | ModelObjectCutAttribute::KeepLower;
        if (a.value("parts", false)) at = at | ModelObjectCutAttribute::CutToParts;
        else at = at | ModelObjectCutAttribute::PlaceOnCutUpper;
        Cut cut(o, ii, cm, at);
        std::vector<ModelObject *> added;
        for (const ModelObject *r : cut.perform_with_plane()) added.push_back(model.add_object(*r));
        if (added.empty()) { undo.pop_back(); throw std::runtime_error("the plane does not cut the object"); }
        model.delete_object(o);
        for (ModelObject *r : added) { r->invalidate_bounding_box(); r->ensure_on_bed(); }
        if (added.size() > 1 && !a.value("parts", false)) arrange(false);
        return state();
    }
    if (cmd == "ray") return ray(a);
    if (cmd == "paint_begin") { checkpoint(); return json::object(); }
    if (cmd == "paint") return paint(a);
    if (cmd == "paint_clear") { checkpoint(); for (ModelVolume *v : object(a)->volumes) facets(v, a.at("kind")).reset(); return state(); }
    if (cmd == "paint_overhang") { // automatic support enforcers below the threshold angle
        checkpoint();
        const double th = std::cos((90. - a.value("angle", 45.)) * PI / 180.);
        ModelInstance *in = instance(a);
        for (ModelVolume *v : object(a)->volumes) {
            if (!v->is_model_part()) continue;
            TriangleSelector sel(v->mesh());
            if (!v->supported_facets.empty()) sel.deserialize(v->supported_facets.get_data());
            const Transform3d t = in->get_matrix() * v->get_matrix();
            const Matrix3d nm = t.linear().inverse().transpose();
            const auto &its = v->mesh().its;
            for (int f = 0; f < (int) its.indices.size(); ++f) {
                const Vec3d n = (nm * its_face_normal(its, f).cast<double>()).normalized();
                const Vec3d c = t * ((its.vertices[its.indices[f][0]] + its.vertices[its.indices[f][1]] + its.vertices[its.indices[f][2]]) / 3.f).cast<double>();
                if (n.z() < -th && c.z() > 0.3) sel.set_facet(f, EnforcerBlockerType::ENFORCER);
            }
            v->supported_facets.set(sel);
        }
        return state();
    }
    if (cmd == "slice") { start_slice(a.value("plate", current)); return state(); }
    if (cmd == "slice_result") { // called once the status turned final
        join();
        for (Plate &pl : plates) if (!pl.result) pl.valid = false;
        running.reset();
        return state();
    }
    throw std::runtime_error("unknown command " + cmd);
}

Engine::Engine(const std::string &resources, const std::string &data, const std::string &temp) : p(new Impl)
{
    p->resources = resources; p->data_dir = data; p->temp_dir = temp;
    fs::create_directories(data); fs::create_directories(temp);
    set_resources_dir(resources); set_var_dir(resources + "/images"); set_data_dir(data); set_temporary_dir(temp);
    p->plates.resize(1);
    p->load_presets();
    p->modified = false;
}
Engine::~Engine() { cancel(); p->join(); }

std::string Engine::call(const std::string &cmd, const std::string &args)
{
    try {
        json a = args.empty() ? json::object() : json::parse(args);
        return dump(p->dispatch(cmd, a));
    } catch (const std::exception &e) {
        return dump({{"error", e.what()}});
    }
}

static void push(std::vector<float> &out, const indexed_triangle_set &its, float state = -1.f)
{
    for (size_t f = 0; f < its.indices.size(); ++f) {
        const Vec3f n = its_face_normal(its, (int) f);
        for (int k = 0; k < 3; ++k) {
            const Vec3f &v = its.vertices[its.indices[f][k]];
            out.insert(out.end(), {v.x(), v.y(), v.z(), n.x(), n.y(), n.z()});
            if (state >= 0) out.push_back(state);
        }
    }
}
std::vector<float> Engine::mesh(long long key)
{
    std::vector<float> out;
    auto it = p->live.find(key);
    if (it != p->live.end()) { out.reserve(it->second->its.indices.size() * 18); push(out, it->second->its); }
    return out;
}
std::vector<float> Engine::painted(int o, int v, int kind)
{
    std::vector<float> out;
    if (o < 0 || o >= (int) p->model.objects.size() || v < 0 || v >= (int) p->model.objects[o]->volumes.size()) return out;
    ModelVolume *vol = p->model.objects[o]->volumes[v];
    FacetsAnnotation &fa = Impl::facets(vol, kind);
    if (fa.empty()) return out;
    std::vector<indexed_triangle_set> sets;
    TriangleSelector sel(vol->mesh());
    sel.deserialize(fa.get_data());
    sel.get_facets(sets);
    for (size_t s = 1; s < sets.size(); ++s) push(out, sets[s], (float) s);
    return out;
}
std::vector<float> Engine::preview(int plate)
{
    std::vector<float> out;
    if (plate < 0 || plate >= (int) p->plates.size()) return out;
    std::shared_ptr<GCodeProcessorResult> r;
    { std::lock_guard<std::mutex> l(p->status_mtx); r = p->plates[plate].result; }
    if (!r || r->moves.empty()) return out;
    const Vec3f org = p->origin(plate).cast<float>();
    float layer = 0, z = -1e9f;
    Vec3f prev = r->moves.front().position;
    size_t n = 0;
    for (auto &m : r->moves) if (m.type == GCodeProcessorResult::MoveVertex().type) {} else ++n;
    out.reserve(n * 12);
    for (const auto &m : r->moves) {
        const bool ext = m.type == EMoveType::Extrude, trav = m.type == EMoveType::Travel;
        if (ext || trav) {
            if (ext && m.extrusion_role != erCustom && m.position.z() > z + 1e-3f) { if (z > -1e8f) layer += 1; z = m.position.z(); }
            auto seg = [&](const Vec3f &a, const Vec3f &b) {
                out.insert(out.end(), {a.x() + org.x(), a.y() + org.y(), a.z(), b.x() + org.x(), b.y() + org.y(), b.z(), ext ? m.width : 0.f, ext ? m.height : 0.f,
                                       ext ? (float) m.extrusion_role : 100.f, (float) m.extruder_id, layer, m.feedrate});
            };
            Vec3f a = prev;
            if (m.is_arc_move_with_interpolation_points())
                for (const Vec3f &q : m.interpolation_points) { seg(a, q); a = q; }
            seg(a, m.position);
        }
        prev = m.position;
    }
    return out;
}
std::string Engine::slice_status() { std::lock_guard<std::mutex> l(p->status_mtx); return dump(p->status); }
void        Engine::cancel()
{
    if (p->slicing) { p->cancelled = true; if (auto r = p->running) r->cancel(); }
}
