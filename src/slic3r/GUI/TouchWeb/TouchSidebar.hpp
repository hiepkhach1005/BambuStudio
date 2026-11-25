#ifndef slic3r_GUI_TouchSidebar_hpp_
#define slic3r_GUI_TouchSidebar_hpp_

// Hosts the React touch sidebar (TouchWeb/sidebar, protocol in sidebar/PROTOCOL.md)
// inside a wxAui pane. Created only when GUI_App::is_touch_mode() is true. Not compiled/tested yet.

#include <functional>
#include <string>

#include <wx/event.h>
#include <wx/panel.h>
#include <wx/timer.h>
#include <wx/webview.h>
#include <wx/weakref.h>
#include <nlohmann/json.hpp>

namespace Slic3r { namespace GUI {

class TouchSidebar : public wxEvtHandler
{
public:
    static constexpr int kClosedWidthDip = 60;
    static constexpr int kOpenWidthDip   = 360;
    static constexpr int kMaxWidthDip    = 600;
    static constexpr int kPaneLayer      = 1; // own aui layer, left of the native sidebar

    struct Callbacks {
        std::function<void()> width_changed;    // pane width must be re-applied
        std::function<void()> native_toggled;   // native sidebar visibility must be re-evaluated
        std::function<void()> failed;           // page did not load, native sidebar takes over
    };

    TouchSidebar(wxWindow *parent, const Callbacks &callbacks);
    ~TouchSidebar() override;

    // Page + WebView2 are loaded, the page answered 'init' and no failure happened.
    wxWindow *window() const { return m_panel; }
    // Start loading the page and the ready timeout. Call once the pane is added.
    void start();

    bool failed() const { return m_failed; }
    // True while the native sidebar must stay hidden.
    bool hides_native() const { return m_started && !m_failed && !m_native_open; }
    int  width_dip() const { return m_width_dip; }

    void on_sys_color_changed();

    // Removes the touch pane (and its dock size) from a wxAuiManager perspective string.
    static wxString strip_from_perspective(const wxString &perspective);

private:
    void on_script_message(wxWebViewEvent &e);
    void on_navigating(wxWebViewEvent &e);
    void on_loaded(wxWebViewEvent &e);
    void on_load_error(wxWebViewEvent &e);
    void on_poll(wxTimerEvent &);
    void on_ready_timeout(wxTimerEvent &);

    void handle_raw(const std::string &raw);
    void dispatch(const nlohmann::json &msg);
    void handle_command(const nlohmann::json &payload);
    // Validates a command without side effects. Returns an empty function and fills err when invalid.
    // modal is set for commands that may open a modal dialog (ack is then sent before running).
    std::function<bool(std::string &)> prepare(const std::string &cmd, const nlohmann::json &args, std::string &err, bool &modal);

    nlohmann::json build_state();
    // Builds a snapshot, bumps the revision when it changed. Returns true when it changed.
    bool refresh_state();
    void push_state();
    bool try_send_init();
    void send(const char *action, nlohmann::json payload);
    void send_ack(const std::string &id);
    void send_error(const std::string &id, int code, const std::string &message);
    void send_theme();
    void fail(const char *reason);
    bool is_local_page(const wxString &url) const;
    wxString page_url() const;

    wxWeakRef<wxPanel>   m_panel;
    wxWeakRef<wxWebView> m_web;
    Callbacks            m_cb;
    wxTimer              m_poll;
    wxTimer              m_ready_timer;
    bool                 m_started{false};
    bool                 m_failed{false};
    bool                 m_ready{false};     // page sent 'init'
    bool                 m_pending_init{false};
    bool                 m_native_open{false};
    bool                 m_busy{false};      // a command is executing (possibly inside a modal dialog)
    int                  m_width_dip{kClosedWidthDip};
    long long            m_revision{0};
    unsigned long long   m_seq{0};
    std::string          m_last_state_dump;  // state without revision, for change detection
    nlohmann::json       m_last_state;
};

}} // namespace Slic3r::GUI

#endif
