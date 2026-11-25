#ifndef slic3r_GUI_TouchScroll_hpp_
#define slic3r_GUI_TouchScroll_hpp_

#include <cstdlib>

namespace Slic3r { namespace GUI {

// Pure decision logic (no wx / Win32), host-testable.
class TouchScrollLogic
{
public:
    enum class Action {
        Pass,          // let the message through untouched
        BeginScroll,   // start scrolling: scroll by dy(); swallow message
        Scroll,        // scroll by dy(); swallow message
        Swallow,       // swallow message (final up of a scroll gesture)
    };

    explicit TouchScrollLogic(int slop_px = 10) : m_slop(slop_px) {}

    // eligible: touch-origin press inside a registered area on a non-excluded child.
    void on_down(int x, int y, bool eligible)
    {
        m_x0 = x; m_y0 = y; m_dy = 0;
        m_state = eligible ? State::Armed : State::Idle;
    }
    Action on_move(int x, int y)
    {
        switch (m_state) {
        case State::Armed: {
            int dx = x - m_x0, dy = y - m_y0;
            if (std::abs(dy) > m_slop && std::abs(dy) > std::abs(dx)) {
                m_state = State::Scrolling; m_dy = dy; return Action::BeginScroll;
            }
            if (std::abs(dx) > m_slop && std::abs(dx) >= std::abs(dy)) m_state = State::Idle; // horizontal: pass through
            return Action::Pass;
        }
        case State::Scrolling: m_dy = y - m_y0; return Action::Scroll;
        default: return Action::Pass;
        }
    }
    Action on_up()
    {
        bool was = m_state == State::Scrolling;
        m_state = State::Idle;
        return was ? Action::Swallow : Action::Pass;
    }
    void cancel() { m_state = State::Idle; }
    bool armed() const { return m_state == State::Armed; }
    bool scrolling() const { return m_state == State::Scrolling; }
    int  dy() const { return m_dy; } // total finger travel since press, pixels (positive = down)

private:
    enum class State { Idle, Armed, Scrolling };
    State m_state{State::Idle};
    int m_slop, m_x0{0}, m_y0{0}, m_dy{0};
};

}} // namespace

#ifndef TOUCH_SCROLL_LOGIC_ONLY
class wxScrolledWindow;
namespace Slic3r { namespace GUI {
// Enables finger-drag scrolling for the given area on Windows in touch mode. No-op elsewhere.
void install_touch_scroll(wxScrolledWindow* area);
}}
#endif

#endif
