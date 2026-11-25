#ifndef slic3r_GUI_TouchInput_hpp_
#define slic3r_GUI_TouchInput_hpp_

// Platform-free touch gesture state machine for the 3D canvas.
// No wx / Win32 dependencies: the caller feeds pointer events and a clock (ms),
// and executes the returned actions.
#include <cstdint>
#include <vector>

namespace Slic3r { namespace GUI {

struct TouchEvent {
    enum Type { Down, Update, Up, Cancel };
    Type    type{Down};
    int     id{0};
    double  x{0}, y{0};   // client coordinates, physical pixels
    int64_t t_ms{0};
};

struct TouchAction {
    enum Kind {
        Hover,       // position update with no button (ImGui needs this before a press)
        LeftDown,    // x,y
        LeftMove,    // x,y, left button held (drag)
        LeftUp,      // x,y, normal release (may be a click)
        LeftCancel,  // x,y, release that must NOT be treated as a click
        LongPress,   // x,y: cancel left (no click) then right down/up -> context menu
        Pan,         // dx,dy centroid movement
        Zoom,        // factor (incremental), x,y centroid
    };
    Kind   kind{Hover};
    double x{0}, y{0}, dx{0}, dy{0}, factor{1};
};

struct TouchConfig {
    int    press_delay_ms{90};   // hold back LeftDown so an early 2nd finger cancels cleanly
    int    long_press_ms{500};
    double slop_px{10};
};

class TouchGesture {
public:
    explicit TouchGesture(TouchConfig cfg = {}) : m_cfg(cfg) {}
    std::vector<TouchAction> on_event(const TouchEvent& ev);
    // Call periodically while active() to run press-delay and long-press timers.
    std::vector<TouchAction> on_tick(int64_t t_ms);
    bool active() const { return m_state != Idle; }
    // Forget all contacts; returns a LeftCancel if the left button is held.
    std::vector<TouchAction> abort();
    void reset() { m_left_sent = false; m_state = Idle; m_n = 0; }
    // e.g. disabled while a painting gizmo is active (holding still must not abort a stroke)
    void set_long_press_enabled(bool v) { m_long_press = v; }

private:
    enum State { Idle, Pending, OneFinger, TwoFinger, Suppressed };
    struct Pt { int id; double x, y; };
    Pt* find(int id);
    void erase(int id);
    void centroid(double& cx, double& cy, double& dist) const;

    TouchConfig m_cfg;
    State   m_state{Idle};
    Pt      m_pts[16];
    int     m_n{0};
    double  m_sx{0}, m_sy{0};       // first-finger start
    int64_t m_t0{0};
    bool    m_left_sent{false};
    bool    m_moved{false};
    bool    m_long_press{true};
    double  m_cx{0}, m_cy{0}, m_dist{0};
    int     m_id0{-1}, m_id1{-1};
};

}} // namespace Slic3r::GUI
#endif
