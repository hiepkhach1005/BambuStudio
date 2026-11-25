#define TOUCH_SCROLL_LOGIC_ONLY
#include "../../src/slic3r/GUI/Widgets/TouchScroll.hpp"
#include <cstdio>
using namespace Slic3r::GUI; using A = TouchScrollLogic::Action;
static int fails = 0;
#define CHECK(c) do { if (!(c)) { std::printf("FAIL line %d: %s\n", __LINE__, #c); ++fails; } } while (0)
int main()
{
    { TouchScrollLogic l; l.on_down(0, 0, true);                         // tap with jitter
      CHECK(l.on_move(3, 4) == A::Pass); CHECK(l.on_up() == A::Pass); }
    { TouchScrollLogic l; l.on_down(0, 0, true);                         // vertical drag
      CHECK(l.on_move(2, 8) == A::Pass); CHECK(l.on_move(3, 25) == A::BeginScroll); CHECK(l.dy() == 25);
      CHECK(l.on_move(3, 40) == A::Scroll); CHECK(l.dy() == 40); CHECK(l.on_up() == A::Swallow); CHECK(!l.scrolling()); }
    { TouchScrollLogic l; l.on_down(0, 0, true);                         // horizontal passes through for the whole gesture
      CHECK(l.on_move(30, 5) == A::Pass); CHECK(l.on_move(31, 80) == A::Pass); CHECK(l.on_up() == A::Pass); }
    { TouchScrollLogic l; l.on_down(0, 0, false);                        // excluded/outside area
      CHECK(l.on_move(0, 100) == A::Pass); CHECK(l.on_up() == A::Pass); }
    { TouchScrollLogic l; l.on_down(0, 0, true); l.on_move(0, 50); l.cancel(); CHECK(l.on_move(0, 90) == A::Pass); }
    std::puts(fails ? "FAILED" : "ALL PASSED"); return fails;
}
