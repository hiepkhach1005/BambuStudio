// Standalone host test: clang++ -std=c++17 -I src/slic3r/GUI tests/touch_input/touch_input_test.cpp src/slic3r/GUI/TouchInput.cpp
#include "TouchInput.hpp"
#include <cassert>
#include <cstdio>
using namespace Slic3r::GUI;
using K = TouchAction::Kind;
using T = TouchEvent;
static T ev(T::Type t, int id, double x, double y, int64_t ms) { T e; e.type = t; e.id = id; e.x = x; e.y = y; e.t_ms = ms; return e; }
static int count(const std::vector<TouchAction>& v, K k) { int n = 0; for (auto& a : v) n += a.kind == k; return n; }
static void add(std::vector<TouchAction>& all, const std::vector<TouchAction>& v) { all.insert(all.end(), v.begin(), v.end()); }

int main()
{
    { // tap: hover first, then down+up on release (inside press delay)
        TouchGesture g; std::vector<TouchAction> a;
        auto d = g.on_event(ev(T::Down, 1, 100, 100, 0));
        assert(d.size() == 1 && d[0].kind == K::Hover);
        add(a, g.on_event(ev(T::Up, 1, 100, 100, 40)));
        assert(a.size() == 2 && a[0].kind == K::LeftDown && a[1].kind == K::LeftUp);
        assert(!g.active()); puts("tap ok");
    }
    { // press delay commits LeftDown; drag follows; normal up
        TouchGesture g; g.on_event(ev(T::Down, 1, 0, 0, 0));
        auto t = g.on_tick(100); assert(count(t, K::LeftDown) == 1);
        auto m = g.on_event(ev(T::Update, 1, 50, 0, 120)); assert(count(m, K::LeftMove) == 1);
        auto u = g.on_event(ev(T::Up, 1, 50, 0, 140)); assert(count(u, K::LeftUp) == 1);
        assert(!g.active()); puts("drag ok");
    }
    { // slop exceeded before delay: LeftDown at start point then move
        TouchGesture g; g.on_event(ev(T::Down, 1, 10, 10, 0));
        auto m = g.on_event(ev(T::Update, 1, 40, 10, 20));
        assert(m.size() == 2 && m[0].kind == K::LeftDown && m[0].x == 10 && m[1].kind == K::LeftMove);
        puts("slop ok");
    }
    { // early second finger: nothing was sent, no click anywhere
        TouchGesture g; std::vector<TouchAction> a;
        add(a, g.on_event(ev(T::Down, 1, 100, 100, 0)));
        add(a, g.on_event(ev(T::Down, 2, 200, 100, 30)));
        add(a, g.on_tick(200));
        add(a, g.on_event(ev(T::Up, 1, 100, 100, 300)));
        add(a, g.on_event(ev(T::Up, 2, 200, 100, 310)));
        assert(count(a, K::LeftDown) == 0 && count(a, K::LeftUp) == 0 && count(a, K::LeftCancel) == 0);
        assert(!g.active()); puts("early 2nd finger ok");
    }
    { // second finger after LeftDown sent: LeftCancel (not LeftUp), then no click afterwards
        TouchGesture g; std::vector<TouchAction> a;
        g.on_event(ev(T::Down, 1, 100, 100, 0)); g.on_tick(100);
        add(a, g.on_event(ev(T::Down, 2, 200, 100, 150)));
        assert(count(a, K::LeftCancel) == 1);
        add(a, g.on_event(ev(T::Up, 2, 200, 100, 200)));
        add(a, g.on_event(ev(T::Up, 1, 100, 100, 210)));
        assert(count(a, K::LeftUp) == 0); assert(!g.active()); puts("late 2nd finger ok");
    }
    { // pinch + pan about centroid
        TouchGesture g; g.on_event(ev(T::Down, 1, 100, 100, 0)); g.on_event(ev(T::Down, 2, 200, 100, 10));
        auto r = g.on_event(ev(T::Update, 2, 300, 100, 20));
        assert(count(r, K::Zoom) == 1 && count(r, K::Pan) == 1);
        for (auto& x : r) {
            if (x.kind == K::Zoom) assert(x.factor == 2.0 && x.x == 200 && x.y == 100);
            if (x.kind == K::Pan) assert(x.dx == 50 && x.dy == 0);
        }
        auto r2 = g.on_event(ev(T::Update, 1, 100, 150, 30)); // pure pan component + shrink
        assert(count(r2, K::Pan) == 1);
        g.on_event(ev(T::Up, 1, 100, 150, 40));
        auto r3 = g.on_event(ev(T::Update, 2, 310, 100, 50)); // remaining finger must not act
        assert(r3.empty());
        g.on_event(ev(T::Up, 2, 310, 100, 60)); assert(!g.active()); puts("pinch ok");
    }
    { // long press within slop
        TouchGesture g; std::vector<TouchAction> a;
        g.on_event(ev(T::Down, 1, 100, 100, 0)); add(a, g.on_tick(100));
        add(a, g.on_event(ev(T::Update, 1, 104, 100, 200)));
        add(a, g.on_tick(499)); assert(count(a, K::LongPress) == 0);
        add(a, g.on_tick(500)); assert(count(a, K::LongPress) == 1);
        add(a, g.on_event(ev(T::Up, 1, 104, 100, 600)));
        assert(count(a, K::LeftUp) == 0); assert(!g.active()); puts("long press ok");
    }
    { // moved beyond slop and back: no long press
        TouchGesture g; std::vector<TouchAction> a;
        g.on_event(ev(T::Down, 1, 100, 100, 0)); g.on_tick(100);
        g.on_event(ev(T::Update, 1, 150, 100, 150)); g.on_event(ev(T::Update, 1, 100, 100, 160));
        add(a, g.on_tick(700)); assert(count(a, K::LongPress) == 0); puts("no long press after move ok");
    }
    { // capture lost cancels left without click
        TouchGesture g; std::vector<TouchAction> a;
        g.on_event(ev(T::Down, 1, 100, 100, 0)); g.on_tick(100);
        add(a, g.on_event(ev(T::Cancel, 1, 100, 100, 150)));
        assert(count(a, K::LeftCancel) == 1 && count(a, K::LeftUp) == 0 && !g.active()); puts("cancel ok");
    }
    puts("ALL PASSED");
}
