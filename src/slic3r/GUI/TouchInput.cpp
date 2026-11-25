#include "TouchInput.hpp"
#include <cmath>

namespace Slic3r { namespace GUI {

TouchGesture::Pt* TouchGesture::find(int id)
{
    for (int i = 0; i < m_n; ++i) if (m_pts[i].id == id) return &m_pts[i];
    return nullptr;
}
void TouchGesture::erase(int id)
{
    for (int i = 0; i < m_n; ++i)
        if (m_pts[i].id == id) { m_pts[i] = m_pts[--m_n]; return; }
}
void TouchGesture::centroid(double& cx, double& cy, double& dist) const
{
    const Pt* a = nullptr; const Pt* b = nullptr;
    for (int i = 0; i < m_n; ++i) {
        if (m_pts[i].id == m_id0) a = &m_pts[i];
        if (m_pts[i].id == m_id1) b = &m_pts[i];
    }
    if (!a || !b) { cx = cy = dist = 0; return; }
    cx = (a->x + b->x) * 0.5; cy = (a->y + b->y) * 0.5;
    dist = std::hypot(a->x - b->x, a->y - b->y);
}

std::vector<TouchAction> TouchGesture::on_event(const TouchEvent& ev)
{
    std::vector<TouchAction> out;
    auto push = [&](TouchAction::Kind k, double x, double y) { TouchAction a; a.kind = k; a.x = x; a.y = y; out.push_back(a); };

    if (ev.type == TouchEvent::Down) {
        if (find(ev.id) || m_n >= 16) return out;
        m_pts[m_n++] = {ev.id, ev.x, ev.y};
        if (m_state == Idle) {
            m_state = Pending; m_sx = ev.x; m_sy = ev.y; m_t0 = ev.t_ms; m_left_sent = false; m_moved = false; m_id0 = ev.id;
            push(TouchAction::Hover, ev.x, ev.y);
        } else if (m_state == Pending || m_state == OneFinger) {
            if (m_left_sent) {
                const Pt* p0 = find(m_id0);
                push(TouchAction::LeftCancel, p0 ? p0->x : m_sx, p0 ? p0->y : m_sy);
            }
            m_left_sent = false;
            m_id1 = ev.id; m_state = TwoFinger;
            centroid(m_cx, m_cy, m_dist);
        }
        // TwoFinger / Suppressed: extra fingers ignored
        return out;
    }

    Pt* p = find(ev.id);
    if (!p) return out;

    if (ev.type == TouchEvent::Update) {
        p->x = ev.x; p->y = ev.y;
        if (m_state == Pending && ev.id == m_id0) {
            if (std::hypot(ev.x - m_sx, ev.y - m_sy) > m_cfg.slop_px) {
                m_moved = true;
                push(TouchAction::LeftDown, m_sx, m_sy); m_left_sent = true; m_state = OneFinger;
                push(TouchAction::LeftMove, ev.x, ev.y);
            }
        } else if (m_state == OneFinger && ev.id == m_id0) {
            if (std::hypot(ev.x - m_sx, ev.y - m_sy) > m_cfg.slop_px) m_moved = true;
            push(TouchAction::LeftMove, ev.x, ev.y);
        } else if (m_state == TwoFinger && (ev.id == m_id0 || ev.id == m_id1)) {
            double cx, cy, d; centroid(cx, cy, d);
            TouchAction pan; pan.kind = TouchAction::Pan; pan.x = cx; pan.y = cy; pan.dx = cx - m_cx; pan.dy = cy - m_cy;
            if (pan.dx != 0 || pan.dy != 0) out.push_back(pan);
            if (m_dist > 1e-3 && d > 1e-3 && d != m_dist) {
                TouchAction z; z.kind = TouchAction::Zoom; z.x = cx; z.y = cy; z.factor = d / m_dist; out.push_back(z);
            }
            m_cx = cx; m_cy = cy; m_dist = d;
        }
        return out;
    }

    // Up or Cancel
    const double ux = p->x, uy = p->y;
    const bool was_first = ev.id == m_id0;
    erase(ev.id);
    if (m_state == Pending && was_first) {
        if (ev.type == TouchEvent::Up) { push(TouchAction::LeftDown, m_sx, m_sy); push(TouchAction::LeftUp, ev.x, ev.y); }
        m_state = Idle;
    } else if (m_state == OneFinger && was_first) {
        push(ev.type == TouchEvent::Up ? TouchAction::LeftUp : TouchAction::LeftCancel, ux, uy);
        m_state = Idle; m_left_sent = false;
    } else if (m_state == TwoFinger) {
        m_state = m_n ? Suppressed : Idle;
    }
    if (ev.type == TouchEvent::Cancel && m_state != Idle) {
        // a cancelled stream (capture lost) is unreliable: drop everything
        if (m_state == OneFinger && m_left_sent) push(TouchAction::LeftCancel, ux, uy);
        reset();
    }
    if (m_n == 0) m_state = Idle;
    else if (m_state == Idle) m_state = Suppressed;
    return out;
}

std::vector<TouchAction> TouchGesture::abort()
{
    std::vector<TouchAction> out;
    if (m_state == OneFinger && m_left_sent) {
        const Pt* p = find(m_id0);
        TouchAction a; a.kind = TouchAction::LeftCancel; a.x = p ? p->x : m_sx; a.y = p ? p->y : m_sy;
        out.push_back(a);
    }
    reset();
    return out;
}

std::vector<TouchAction> TouchGesture::on_tick(int64_t t)
{
    std::vector<TouchAction> out;
    TouchAction a;
    if (m_state == Pending && t - m_t0 >= m_cfg.press_delay_ms) {
        a.kind = TouchAction::LeftDown; a.x = m_sx; a.y = m_sy; out.push_back(a);
        m_left_sent = true; m_state = OneFinger;
    }
    if (m_state == OneFinger && m_long_press && m_left_sent && t - m_t0 >= m_cfg.long_press_ms) {
        Pt* p = find(m_id0);
        if (p && !m_moved && std::hypot(p->x - m_sx, p->y - m_sy) <= m_cfg.slop_px) {
            a = TouchAction(); a.kind = TouchAction::LongPress; a.x = p->x; a.y = p->y; out.push_back(a);
            m_left_sent = false; m_state = Suppressed;
        }
    }
    return out;
}

}} // namespace
