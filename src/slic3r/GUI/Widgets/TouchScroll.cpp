#include "TouchScroll.hpp"

#ifdef _WIN32
#include <algorithm>
#include <vector>
#include <wx/wx.h>
#include <wx/scrolwin.h>
#include <wx/slider.h>
#include <wx/textctrl.h>
#include <wx/spinctrl.h>
#include <wx/scrolbar.h>
#include <wx/combobox.h>
#include <wx/msw/private.h>
#include "../GUI_App.hpp"

namespace Slic3r { namespace GUI {
namespace {

std::vector<wxScrolledWindow*> s_areas;
HHOOK s_hook = nullptr;
TouchScrollLogic s_logic(10);
wxScrolledWindow* s_active = nullptr;
HWND s_child = nullptr;
UINT s_down_msg = 0;
WPARAM s_down_wp = 0;
LPARAM s_down_lp = 0;
int s_start_view_y = 0;

bool is_touch_message()
{
    // Touch-promoted mouse messages carry 0xFF515780; pen is 0xFF515700.
    return (GetMessageExtraInfo() & 0xFFFFFF80) == 0xFF515780;
}

wxScrolledWindow* find_area(HWND h)
{
    for (; h; h = (GetWindowLongPtr(h, GWL_STYLE) & WS_CHILD) ? GetParent(h) : nullptr)
        for (auto* a : s_areas)
            if (a->GetHWND() == (WXHWND) h) return a;
    return nullptr;
}

bool excluded_child(HWND h)
{
    wchar_t cls[64] = {0};
    GetClassNameW(h, cls, 63);
    static const wchar_t* names[] = {L"msctls_trackbar32", L"Edit", L"msctls_updown32", L"ScrollBar",
                                     L"ComboBox", L"RICHEDIT50W", L"SysListView32"};
    for (auto* n : names) if (_wcsicmp(cls, n) == 0) return true;
    wxWindow* w = wxGetWindowFromHWND((WXHWND) h);
    return w && (dynamic_cast<wxSlider*>(w) || dynamic_cast<wxTextCtrl*>(w) || dynamic_cast<wxSpinCtrl*>(w) ||
                 dynamic_cast<wxScrollBar*>(w) || dynamic_cast<wxComboBox*>(w));
}

// Deliver the withheld press. State is cleared first: handlers may re-enter the message loop.
void replay_press()
{
    HWND child = s_child;
    s_active = nullptr;
    s_child  = nullptr;
    if (child && IsWindow(child))
        SendMessageW(child, s_down_msg, s_down_wp, s_down_lp);
}

// The press is withheld until the gesture is known. A control therefore never sees a press (or a
// release) for a scroll, whatever it does on LEFT_DOWN / LEFT_UP.
void handle_touch(MSG *m)
{
    // Screen coordinates, so child-local origins do not matter.
    const int x = m->pt.x, y = m->pt.y;

    if (m->message == WM_LBUTTONDOWN || m->message == WM_LBUTTONDBLCLK) {
        s_active = nullptr;
        s_child  = nullptr;
        wxScrolledWindow *a = GUI_App::is_touch_mode() ? find_area(m->hwnd) : nullptr;
        if (!a || excluded_child(m->hwnd)) {
            s_logic.cancel();
            return;
        }
        s_logic = TouchScrollLogic(a->FromDIP(12));
        s_logic.on_down(x, y, true);
        s_active       = a;
        s_child        = m->hwnd;
        s_down_msg     = m->message;
        s_down_wp      = m->wParam;
        s_down_lp      = m->lParam;
        s_start_view_y = a->GetViewStart().y;
        m->message     = WM_NULL;
        return;
    }

    if (!s_active)
        return;

    if (m->message == WM_MOUSEMOVE) {
        if (!(m->wParam & MK_LBUTTON)) { // the release was lost
            s_logic.cancel();
            s_active = nullptr;
            s_child  = nullptr;
            return;
        }
        const TouchScrollLogic::Action act = s_logic.on_move(x, y);
        if (act == TouchScrollLogic::Action::BeginScroll || act == TouchScrollLogic::Action::Scroll) {
            int ppu_x = 0, ppu_y = 0;
            s_active->GetScrollPixelsPerUnit(&ppu_x, &ppu_y);
            if (ppu_y > 0) // wx clamps to the valid range, but -1 means "unchanged"
                s_active->Scroll(-1, std::max(0, s_start_view_y - s_logic.dy() / ppu_y));
            m->message = WM_NULL;
        } else if (s_logic.armed()) {
            m->message = WM_NULL; // undecided
        } else {
            replay_press(); // horizontal drag: belongs to the control
        }
        return;
    }

    // WM_LBUTTONUP
    if (s_logic.on_up() == TouchScrollLogic::Action::Swallow) {
        s_active   = nullptr;
        s_child    = nullptr;
        m->message = WM_NULL;
        return;
    }
    // A tap: press and release at the original point, even if the finger rolled onto a neighbour.
    m->hwnd   = s_child;
    m->lParam = s_down_lp;
    replay_press();
}

LRESULT CALLBACK hook_proc(int code, WPARAM wp, LPARAM lp)
{
    if (code == HC_ACTION && wp == PM_REMOVE) {
        MSG *m = reinterpret_cast<MSG *>(lp);
        if ((m->message == WM_LBUTTONDOWN || m->message == WM_LBUTTONDBLCLK || m->message == WM_MOUSEMOVE || m->message == WM_LBUTTONUP) && is_touch_message())
            handle_touch(m);
    }
    return CallNextHookEx(s_hook, code, wp, lp);
}

} // namespace

void install_touch_scroll(wxScrolledWindow* area)
{
    if (!area) return;
    s_areas.push_back(area);
    area->Bind(wxEVT_DESTROY, [area](wxWindowDestroyEvent& e) {
        e.Skip();
        if (e.GetEventObject() != area) // command event: also arrives from destroyed children
            return;
        s_areas.erase(std::remove(s_areas.begin(), s_areas.end(), area), s_areas.end());
        if (s_active == area) { s_active = nullptr; s_logic.cancel(); }
    });
    if (!s_hook) s_hook = SetWindowsHookExW(WH_GETMESSAGE, hook_proc, nullptr, GetCurrentThreadId());
}

}} // namespace
#else
#include <wx/scrolwin.h>
namespace Slic3r { namespace GUI { void install_touch_scroll(wxScrolledWindow*) {} }}
#endif
