// Standalone host test: clang++ -std=c++17 -I src/slic3r/GUI tests/touch_detect/touch_detect_test.cpp
#include "TouchDetect.hpp"
#include <cstdio>
using namespace Slic3r::GUI;
static int fails = 0;
#define CHECK(x) do { if (!(x)) { ++fails; std::printf("FAIL line %d: %s\n", __LINE__, #x); } } while (0)
int main()
{
    const TouchScreenInfo ally{true, 155, 87, true}, ally_dock{false, 1220, 690, true}, desktop{false, 600, 340, false};
    const TouchScreenInfo laptop{true, 310, 174, false}, tablet13{true, 274, 183, true}, aio{true, 527, 296, true};
    const TouchScreenInfo unknown{true, 0, 0, false}, unknown_slate{true, 0, 0, true}, rotated{true, 87, 155, false};
    CHECK(touch_mode_decide("auto", ally));
    CHECK(touch_mode_decide("", ally));
    CHECK(touch_mode_decide("auto", rotated));
    CHECK(!touch_mode_decide("auto", ally_dock));
    CHECK(!touch_mode_decide("auto", desktop));
    CHECK(!touch_mode_decide("auto", laptop));
    CHECK(touch_mode_decide("auto", tablet13));
    CHECK(!touch_mode_decide("auto", aio));
    CHECK(!touch_mode_decide("auto", unknown));
    CHECK(touch_mode_decide("auto", unknown_slate));
    CHECK(touch_mode_decide("1", desktop) && touch_mode_decide("true", desktop));
    CHECK(!touch_mode_decide("0", ally) && !touch_mode_decide("false", ally));
    CHECK(touch_toolbar_factor_for(ally) == 1.4f && touch_toolbar_factor_for(tablet13) == 1.25f);
    if (!fails) std::puts("ok");
    return fails != 0;
}
