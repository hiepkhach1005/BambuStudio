#ifndef slic3r_GUI_TouchDetect_hpp_
#define slic3r_GUI_TouchDetect_hpp_

#include <cmath>
#include <string>

namespace Slic3r { namespace GUI {

// Screen the main window will open on. Pure data, filled by GUI_App on Windows.
struct TouchScreenInfo
{
    bool has_touch  = false; // a finger digitizer is mapped to this screen
    int  width_mm   = 0;     // physical size, 0 when the driver does not report it
    int  height_mm  = 0;
    bool slate_mode = false; // Windows reports tablet posture (keyboard detached or folded)

    double diagonal_inch() const
    {
        if (width_mm <= 0 || height_mm <= 0) return 0.0;
        return std::sqrt(double(width_mm) * width_mm + double(height_mm) * height_mm) / 25.4;
    }
};

// setting: "1"/"true" always on, "0"/"false" always off, anything else means automatic.
inline bool touch_mode_decide(const std::string &setting, const TouchScreenInfo &s)
{
    if (setting == "1" || setting == "true") return true;
    if (setting == "0" || setting == "false") return false;
    if (!s.has_touch) return false;
    const double d = s.diagonal_inch();
    if (d >= 4.0 && d <= 11.0) return true; // handhelds and small tablets
    // Larger touch screens usually have a mouse: only when used as a tablet. Desktop touch monitors
    // may also report slate posture, hence the upper limit. Unknown size: same rule.
    return s.slate_mode && d <= 16.0;
}

// Multiplier for the 3D toolbar icons: small screens need the larger one.
inline float touch_toolbar_factor_for(const TouchScreenInfo &s)
{
    return s.diagonal_inch() > 11.0 ? 1.25f : 1.4f;
}

}} // namespace Slic3r::GUI

#endif
