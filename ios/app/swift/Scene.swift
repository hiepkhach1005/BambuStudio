import SwiftUI
import MetalKit
import simd

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;
struct U { float4x4 mvp; float4x4 model; float4 color; float4 eye; float4 opt; };
struct VO { float4 pos [[position]]; float3 n; float4 c; };
struct PV { packed_float3 p; packed_float3 n; };
vertex VO mesh_v(uint i [[vertex_id]], const device PV *v [[buffer(0)]], constant U &u [[buffer(1)]]) {
  VO o; o.pos = u.mvp * u.model * float4(float3(v[i].p), 1);
  float3x3 m(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);
  float3x3 nm(cross(m[1], m[2]), cross(m[2], m[0]), cross(m[0], m[1]));
  if (dot(m[0], nm[0]) < 0) nm = -1.0 * nm;
  o.n = normalize(nm * float3(v[i].n)); o.c = u.color;
  float4 w = u.model * float4(float3(v[i].p), 1); if (w.z < -0.01) o.c.rgb = mix(o.c.rgb, float3(1,0,0), 0.6);
  return o; }
struct PP { packed_float3 p; packed_float3 n; float s; };
vertex VO paint_v(uint i [[vertex_id]], const device PP *v [[buffer(0)]], constant U &u [[buffer(1)]], constant float4 *pal [[buffer(2)]]) {
  VO o; o.pos = u.mvp * u.model * float4(float3(v[i].p), 1); o.pos.z -= 0.00005 * o.pos.w;
  float3x3 m(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz); o.n = normalize(m * float3(v[i].n));
  o.c = pal[clamp(int(v[i].s), 0, 16)]; return o; }
vertex VO line_v(uint i [[vertex_id]], const device packed_float3 *v [[buffer(0)]], constant U &u [[buffer(1)]]) {
  VO o; o.pos = u.mvp * u.model * float4(float3(v[i]), 1); o.n = float3(0,0,1); o.c = u.color; return o; }
struct Seg { packed_float3 a; packed_float3 b; float w, h, role, ext, layer, speed; };
vertex VO seg_v(uint vid [[vertex_id]], uint iid [[instance_id]], const device Seg *s [[buffer(0)]], constant U &u [[buffer(1)]], constant float4 *pal [[buffer(2)]]) {
  Seg g = s[iid]; bool travel = g.role > 99; VO o;
  if (travel && u.opt.x < 0.5) { o.pos = float4(2,2,2,1); o.n = float3(0,0,1); o.c = float4(0); return o; }
  float3 a = float3(g.a), b = float3(g.b); float w = travel ? 0.1 : g.w, h = travel ? 0.1 : g.h;
  float3 d = b - a; float l = length(d); float3 x = l > 1e-6 ? d / l : float3(1,0,0);
  float3 up = abs(x.z) > 0.9 ? float3(0,1,0) : float3(0,0,1); float3 y = normalize(cross(up, x)); float3 z = cross(x, y);
  const float3 nn[6] = { float3(1,0,0), float3(-1,0,0), float3(0,1,0), float3(0,-1,0), float3(0,0,1), float3(0,0,-1) };
  const float2 q[6] = { float2(-1,-1), float2(1,-1), float2(1,1), float2(-1,-1), float2(1,1), float2(-1,1) };
  uint f = vid / 6; float2 c = q[vid % 6]; float3 n = nn[f]; float3 p;
  if (f < 2) p = float3(n.x, c.x, c.y); else if (f < 4) p = float3(c.x, n.y, c.y); else p = float3(c.x, c.y, n.z);
  float3 ctr = (a + b) * 0.5 - float3(0, 0, travel ? 0 : h * 0.5);
  float3 wp = ctr + x * p.x * (l * 0.5 + (travel ? 0 : w * 0.25)) + y * p.y * w * 0.5 + z * p.z * h * 0.5;
  o.pos = u.mvp * float4(wp, 1); o.n = normalize(x * n.x + y * n.y + z * n.z);
  if (travel) o.c = float4(0.3, 0.45, 0.65, 1);
  else if (u.opt.y < 0.5) o.c = pal[clamp(int(g.role), 0, 31)];
  else if (u.opt.y < 1.5) o.c = pal[32 + clamp(int(g.ext), 0, 15)];
  else { float t = u.opt.y < 2.5 ? clamp(g.speed / max(u.opt.z, 1.0), 0.0, 1.0) : u.opt.y < 3.5 ? clamp(g.h / 0.4, 0.0, 1.0) : clamp(g.w / 0.8, 0.0, 1.0);
    o.c = float4(clamp(float3(1.5 - abs(4 * t - 3), 1.5 - abs(4 * t - 2), 1.5 - abs(4 * t - 1)), 0.05, 1.0), 1); }
  return o; }
fragment float4 lit_f(VO i [[stage_in]], bool front [[front_facing]]) {
  float3 n = normalize(i.n); float l = 0.42 + 0.45 * max(0.0, dot(n, normalize(float3(-0.4,-0.6,0.9)))) + 0.2 * max(0.0, dot(n, normalize(float3(0.7,0.4,0.3))));
  return float4(i.c.rgb * l, i.c.a); }
fragment float4 flat_f(VO i [[stage_in]]) { return i.c; }
"""

struct Uniforms { var mvp: simd_float4x4, model: simd_float4x4, color: SIMD4<Float>, eye: SIMD4<Float>, opt: SIMD4<Float> }

func mat(_ a: [Float]) -> simd_float4x4 {
    simd_float4x4(SIMD4(a[0], a[1], a[2], a[3]), SIMD4(a[4], a[5], a[6], a[7]), SIMD4(a[8], a[9], a[10], a[11]), SIMD4(a[12], a[13], a[14], a[15]))
}
func translation(_ v: SIMD3<Float>) -> simd_float4x4 { var m = matrix_identity_float4x4; m.columns.3 = SIMD4(v, 1); return m }

struct CameraS {
    var target = SIMD3<Float>(128, 128, 0), yaw: Float = -.pi / 2, pitch: Float = 0.75, dist: Float = 520
    var eye: SIMD3<Float> { target + dist * SIMD3(cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), sin(pitch)) }
    var right: SIMD3<Float> { SIMD3(-sin(yaw), cos(yaw), 0) }
    var fwd: SIMD3<Float> { simd_normalize(target - eye) }
    var up: SIMD3<Float> { simd_cross(right, fwd) }
    static let fov: Float = 40 * .pi / 180
    func vp(_ aspect: Float) -> simd_float4x4 {
        let r = right, u = up, f = fwd, e = eye
        let view = simd_float4x4(SIMD4(r.x, u.x, -f.x, 0), SIMD4(r.y, u.y, -f.y, 0), SIMD4(r.z, u.z, -f.z, 0), SIMD4(-simd_dot(r, e), -simd_dot(u, e), simd_dot(f, e), 1))
        let near = max(0.5, dist * 0.01), far = dist + 4000, ys = 1 / tan(CameraS.fov / 2)
        let proj = simd_float4x4(SIMD4(ys / aspect, 0, 0, 0), SIMD4(0, ys, 0, 0), SIMD4(0, 0, far / (near - far), -1), SIMD4(0, 0, near * far / (near - far), 0))
        return proj * view
    }
    func ray(_ p: CGPoint, _ size: CGSize) -> (SIMD3<Float>, SIMD3<Float>) {
        let x = Float(p.x / size.width) * 2 - 1, y = 1 - Float(p.y / size.height) * 2
        let t = tan(CameraS.fov / 2), a = Float(size.width / max(size.height, 1))
        return (eye, simd_normalize(fwd + right * (x * t * a) + up * (y * t)))
    }
}

struct Hit { let sel: Sel, volume: Int, world: SIMD3<Float>, normal: SIMD3<Float>, t: Float }

@MainActor final class SceneController: NSObject, MTKViewDelegate, UIGestureRecognizerDelegate {
    let store: Store
    var cam = CameraS()
    weak var view: MTKView?
    private var device: MTLDevice!, queue: MTLCommandQueue!
    private var meshP, paintP, lineP, segP: MTLRenderPipelineState!
    private var meshT, lineFlatT: MTLRenderPipelineState!
    private var depthOn, depthOff: MTLDepthStencilState!
    private var buffers: [Int64: (MTLBuffer, Int)] = [:], paintBuf: [String: (Data, MTLBuffer)] = [:]
    private var segBuf: MTLBuffer?, segData: Data?, layerStart: [Int] = [], maxSpeed: Float = 200
    private var lastFit = -1
    var dragDelta: [Sel: SIMD3<Float>] = [:]
    private var dragging: Hit?, dragStart = SIMD3<Float>(), painting = false, paintBusy = false

    init(_ s: Store) { store = s }
    func setup(_ v: MTKView) {
        view = v
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else { return }
        device = d; queue = q
        v.device = d; v.delegate = self; v.colorPixelFormat = .bgra8Unorm; v.depthStencilPixelFormat = .depth32Float; v.sampleCount = 4
        v.enableSetNeedsDisplay = true; v.isPaused = true; v.isMultipleTouchEnabled = true
        do {
            let lib = try d.makeLibrary(source: shaderSource, options: nil)
            func pipe(_ a: String, _ b: String, blend: Bool = false) throws -> MTLRenderPipelineState {
                let p = MTLRenderPipelineDescriptor()
                p.vertexFunction = lib.makeFunction(name: a); p.fragmentFunction = lib.makeFunction(name: b)
                p.colorAttachments[0].pixelFormat = .bgra8Unorm; p.depthAttachmentPixelFormat = .depth32Float; p.rasterSampleCount = 4
                if blend { let c = p.colorAttachments[0]!; c.isBlendingEnabled = true; c.sourceRGBBlendFactor = .sourceAlpha; c.destinationRGBBlendFactor = .oneMinusSourceAlpha }
                return try d.makeRenderPipelineState(descriptor: p)
            }
            meshP = try pipe("mesh_v", "lit_f"); meshT = try pipe("mesh_v", "lit_f", blend: true); paintP = try pipe("paint_v", "lit_f")
            lineP = try pipe("line_v", "flat_f"); lineFlatT = try pipe("line_v", "flat_f", blend: true); segP = try pipe("seg_v", "lit_f")
        } catch { store.error = "\(error)"; return }
        func depth(_ w: Bool) -> MTLDepthStencilState { let x = MTLDepthStencilDescriptor(); x.depthCompareFunction = .lessEqual; x.isDepthWriteEnabled = w; return d.makeDepthStencilState(descriptor: x)! }
        depthOn = depth(true); depthOff = depth(false)
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap)); v.addGestureRecognizer(tap)
        let dbl = UITapGestureRecognizer(target: self, action: #selector(onDouble)); dbl.numberOfTapsRequired = 2; v.addGestureRecognizer(dbl); tap.require(toFail: dbl)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan)); pan.maximumNumberOfTouches = 1; pan.delegate = self; v.addGestureRecognizer(pan)
        let two = UIPanGestureRecognizer(target: self, action: #selector(onTwo)); two.minimumNumberOfTouches = 2; two.delegate = self; v.addGestureRecognizer(two)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch)); pinch.delegate = self; v.addGestureRecognizer(pinch)
        let long = UILongPressGestureRecognizer(target: self, action: #selector(onLong)); v.addGestureRecognizer(long)
    }
    func redraw() { view?.setNeedsDisplay() }
    nonisolated func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool {
        MainActor.assumeIsolated {
            let twoA = (a as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 2, twoB = (b as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 2
            return (twoA && b is UIPinchGestureRecognizer) || (twoB && a is UIPinchGestureRecognizer)
        }
    }

    // MARK: camera
    func fit() {
        guard let s = store.state else { return }
        let p = s.plates[min(s.current, s.plates.count - 1)].origin
        cam.target = SIMD3(Float((s.bed[0] + s.bed[2]) / 2 + p[0]), Float((s.bed[1] + s.bed[3]) / 2 + p[1]), 10)
        cam.dist = Float(max(s.bed[2] - s.bed[0], s.bed[3] - s.bed[1])) * 1.75
        cam.yaw = -.pi / 2; cam.pitch = 0.75
        redraw()
    }
    func look(yaw: Float, pitch: Float) { cam.yaw = yaw; cam.pitch = pitch; redraw() }

    // MARK: picking
    func pick(_ pt: CGPoint) -> Hit? {
        guard let v = view, let s = store.state else { return nil }
        let (o, d) = cam.ray(pt, v.bounds.size)
        var best: Hit?
        for ob in s.objects { for ins in ob.instances {
            let lo = SIMD3<Float>(Float(ins.min[0]), Float(ins.min[1]), Float(ins.min[2])) - 1, hi = SIMD3<Float>(Float(ins.max[0]), Float(ins.max[1]), Float(ins.max[2])) + 1
            let t1 = (lo - o) / d, t2 = (hi - o) / d
            let n = simd_reduce_max(simd_min(t1, t2)), f = simd_reduce_min(simd_max(t1, t2))
            if ob.volumes.allSatisfy({ $0.type == 0 }) && !(f >= max(n, 0)) { continue }
            for vol in ob.volumes {
                guard let data = store.meshes[vol.mesh] else { continue }
                let m = mat(ins.matrix) * mat(vol.matrix), inv = m.inverse
                let lo4 = inv * SIMD4(o, 1), ld4 = inv * SIMD4(d, 0)
                let lo3 = SIMD3(lo4.x, lo4.y, lo4.z), ld = SIMD3(ld4.x, ld4.y, ld4.z)
                data.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
                    let fl = b.bindMemory(to: Float.self); let tris = fl.count / 18
                    for k in 0..<tris {
                        let q = k * 18
                        let a = SIMD3(fl[q], fl[q+1], fl[q+2]), e1 = SIMD3(fl[q+6], fl[q+7], fl[q+8]) - a, e2 = SIMD3(fl[q+12], fl[q+13], fl[q+14]) - a
                        let pv = simd_cross(ld, e2), det = simd_dot(e1, pv)
                        if abs(det) < 1e-12 { continue }
                        let tv = lo3 - a, u = simd_dot(tv, pv) / det
                        if u < 0 || u > 1 { continue }
                        let qv = simd_cross(tv, e1), w = simd_dot(ld, qv) / det
                        if w < 0 || u + w > 1 { continue }
                        let t = simd_dot(e2, qv) / det
                        if t > 0 && t < (best?.t ?? .infinity) {
                            let nl = SIMD4(simd_normalize(simd_cross(e1, e2)), 0)
                            let nw = inv.transpose * nl
                            best = Hit(sel: Sel(o: ob.index, i: ins.index), volume: vol.index, world: o + d * t, normal: simd_normalize(SIMD3(nw.x, nw.y, nw.z)), t: t)
                        }
                    }
                }
            }
        } }
        return best
    }
    private func onPlane(_ pt: CGPoint, z: Float) -> SIMD3<Float>? {
        guard let v = view else { return nil }
        let (o, d) = cam.ray(pt, v.bounds.size)
        guard abs(d.z) > 1e-4 else { return nil }
        let t = (z - o.z) / d.z
        return t > 0 ? o + d * t : nil
    }

    // MARK: gestures
    @objc func onTap(_ g: UITapGestureRecognizer) {
        guard store.tab == 0, let s = store.state else { return }
        let pt = g.location(in: view)
        if let h = pick(pt) {
            if store.tool == .layflat { store.run("lay_flat", ["o": h.sel.o, "i": h.sel.i, "normal": [Double(h.normal.x), Double(h.normal.y), Double(h.normal.z)]]); store.tool = .none; return }
            if store.tool.paintKind != nil { paint(h, pt, first: true); return }
            store.selection = [h.sel]
            let p = s.objects[h.sel.o].instances[h.sel.i].plate
            if p >= 0 && p != s.current { store.run("plate_select", ["plate": p]) }
        } else if store.tool.paintKind == nil {
            store.selection = []
            if let w = onPlane(pt, z: 0) {
                for p in s.plates where p.index != s.current {
                    let x = Double(w.x) - p.origin[0], y = Double(w.y) - p.origin[1]
                    if x >= s.bed[0] && x <= s.bed[2] && y >= s.bed[1] && y <= s.bed[3] { store.run("plate_select", ["plate": p.index]) { self.fit() } }
                }
            }
        }
        store.sceneStamp += 1
    }
    @objc func onDouble(_ g: UITapGestureRecognizer) {
        if let h = pick(g.location(in: view)) { cam.target = h.world; cam.dist = min(cam.dist, 180); redraw() } else { fit() }
    }
    @objc func onLong(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, store.tab == 0, store.tool.paintKind == nil, let h = pick(g.location(in: view)) else { return }
        if store.selection.contains(h.sel) { store.selection.remove(h.sel) } else { store.selection.insert(h.sel) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        store.sceneStamp += 1
    }
    @objc func onPan(_ g: UIPanGestureRecognizer) {
        let pt = g.location(in: view)
        switch g.state {
        case .began:
            let tr = g.translation(in: view), st = CGPoint(x: pt.x - tr.x, y: pt.y - tr.y)
            guard store.tab == 0 else { return }
            let h = pick(st)
            if store.tool.paintKind != nil { if let h { painting = true; paint(h, pt, first: true) } }
            else if let h, store.selection.contains(h.sel), !store.busy, let w = onPlane(st, z: h.world.z) { dragging = h; dragStart = w }
        case .changed:
            if painting { if let h = pick(pt) { paint(h, pt, first: false) } }
            else if let h = dragging { if let w = onPlane(pt, z: h.world.z) { for s in store.selection { dragDelta[s] = w - dragStart }; redraw() } }
            else {
                let d = g.translation(in: view); g.setTranslation(.zero, in: view)
                cam.yaw -= Float(d.x) * 0.006; cam.pitch = min(1.56, max(-1.2, cam.pitch + Float(d.y) * 0.006)); redraw()
            }
        default:
            if painting { painting = false; store.run("state") }
            else if dragging != nil {
                dragging = nil
                let moves = dragDelta
                guard g.state == .ended, let s = store.state else { dragDelta = [:]; redraw(); return }
                var first = true, left = moves.count
                for (sel, d) in moves where sel.o < s.objects.count && sel.i < s.objects[sel.o].instances.count {
                    let o = s.objects[sel.o].instances[sel.i].offset
                    store.transform(sel, ["offset": [o[0] + Double(d.x), o[1] + Double(d.y), o[2]], "checkpoint": first, "drop": false]) { left -= 1; if left <= 0 { self.dragDelta = [:]; self.redraw() } }
                    first = false
                }
            }
        }
    }
    @objc func onTwo(_ g: UIPanGestureRecognizer) {
        guard let v = view else { return }
        let d = g.translation(in: v); g.setTranslation(.zero, in: v)
        let k = 2 * cam.dist * tan(CameraS.fov / 2) / Float(max(v.bounds.height, 1))
        cam.target += cam.right * (-Float(d.x) * k) + cam.up * (Float(d.y) * k); redraw()
    }
    @objc func onPinch(_ g: UIPinchGestureRecognizer) {
        cam.dist = min(4000, max(8, cam.dist / Float(max(0.2, g.scale)))); g.scale = 1; redraw()
    }
    private func paint(_ h: Hit, _ pt: CGPoint, first: Bool) {
        guard let kind = store.tool.paintKind, let v = view, let s = store.state, !paintBusy else { return }
        let (o, d) = cam.ray(pt, v.bounds.size)
        let go = {
            self.paintBusy = true
            self.store.raw("paint", ["o": h.sel.o, "i": h.sel.i, "v": h.volume, "kind": kind, "state": self.store.paintState, "radius": self.store.paintRadius, "tool": self.store.paintTool,
                                     "origin": [Double(o.x), Double(o.y), Double(o.z)], "dir": [Double(d.x), Double(d.y), Double(d.z)]]) { r in
                self.paintBusy = false
                if let e = Store.err(r) { self.store.error = e; return }
                let key = "\(s.objects[h.sel.o].id)/\(h.volume)/\(kind)"
                self.store.loadPaint(h.sel.o, h.volume, kind, key)
                if !self.painting { self.store.run("state") }
            }
        }
        if first { store.raw("paint_begin") { _ in go() } } else { go() }
    }

    // MARK: drawing
    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { MainActor.assumeIsolated { redraw() } }
    nonisolated func draw(in view: MTKView) { MainActor.assumeIsolated { render(view) } }
    private func meshBuffer(_ id: Int64) -> (MTLBuffer, Int)? {
        if let b = buffers[id] { return b }
        guard let d = store.meshes[id], !d.isEmpty, let b = d.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: d.count) }) else { return nil }
        buffers[id] = (b, d.count / 24); return buffers[id]
    }
    private func render(_ view: MTKView) {
        guard segP != nil, let s = store.state, let desc = view.currentRenderPassDescriptor, let dr = view.currentDrawable, let cb = queue.makeCommandBuffer() else { return }
        if store.fitRequest != lastFit { lastFit = store.fitRequest; fit() }
        let dark = view.traitCollection.userInterfaceStyle == .dark
        desc.colorAttachments[0].clearColor = dark ? MTLClearColor(red: 0.16, green: 0.17, blue: 0.18, alpha: 1) : MTLClearColor(red: 0.9, green: 0.91, blue: 0.92, alpha: 1)
        guard let e = cb.makeRenderCommandEncoder(descriptor: desc) else { return }
        let size = view.bounds.size
        var u = Uniforms(mvp: cam.vp(Float(size.width / max(size.height, 1))), model: matrix_identity_float4x4, color: .one, eye: SIMD4(cam.eye, 1), opt: .zero)
        func setU() { e.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1) }
        func verts(_ p: [Float], _ type: MTLPrimitiveType) {
            guard !p.isEmpty else { return }
            if p.count * 4 <= 4096 { e.setVertexBytes(p, length: p.count * 4, index: 0) } else if let b = device.makeBuffer(bytes: p, length: p.count * 4) { e.setVertexBuffer(b, offset: 0, index: 0) } else { return }
            setU(); e.drawPrimitives(type: type, vertexStart: 0, vertexCount: p.count / 3)
        }
        // plates
        e.setDepthStencilState(depthOn)
        let b = s.bed.map(Float.init)
        for p in s.plates {
            let ox = Float(p.origin[0]), oy = Float(p.origin[1]), cur = p.index == s.current
            let x0 = b[0] + ox, y0 = b[1] + oy, x1 = b[2] + ox, y1 = b[3] + oy
            u.model = matrix_identity_float4x4
            e.setRenderPipelineState(lineFlatT)
            u.color = dark ? SIMD4(0.27, 0.28, 0.29, cur ? 0.9 : 0.5) : SIMD4(0.72, 0.73, 0.75, cur ? 0.9 : 0.5)
            verts([x0, y0, -0.05, x1, y0, -0.05, x1, y1, -0.05, x0, y0, -0.05, x1, y1, -0.05, x0, y1, -0.05], .triangle)
            if s.exclude.count >= 3 {
                var ex: [Float] = []
                for k in 1..<(s.exclude.count - 1) { for q in [s.exclude[0], s.exclude[k], s.exclude[k+1]] { ex += [Float(q[0]) + ox, Float(q[1]) + oy, -0.02] } }
                u.color = SIMD4(0.8, 0.3, 0.2, 0.35); verts(ex, .triangle)
            }
            var grid: [Float] = []
            var x = x0; while x <= x1 + 0.01 { grid += [x, y0, 0, x, y1, 0]; x += 10 }
            var y = y0; while y <= y1 + 0.01 { grid += [x0, y, 0, x1, y, 0]; y += 10 }
            u.color = SIMD4(0.5, 0.5, 0.52, cur ? 0.5 : 0.25); verts(grid, .line)
            u.color = cur ? SIMD4(0, 0.68, 0.26, 1) : SIMD4(0.5, 0.5, 0.5, 0.6)
            verts([x0, y0, 0, x1, y0, 0, x1, y1, 0, x0, y1, 0, x0, y0, 0], .lineStrip)
        }
        if store.tab == 1 { drawPreview(e, &u, s) } else { drawObjects(e, &u, s, verts, setU) }
        e.endEncoding(); cb.present(dr); cb.commit()
    }
    private func drawObjects(_ e: MTLRenderCommandEncoder, _ u: inout Uniforms, _ s: StateS, _ verts: ([Float], MTLPrimitiveType) -> Void, _ unused: () -> Void) {
        var used: Set<Int64> = []
        let kind = store.tool.paintKind
        for pass in 0..<2 {
            for ob in s.objects { for ins in ob.instances {
                let sel = Sel(o: ob.index, i: ins.index)
                let im = translation(dragDelta[sel] ?? .zero) * mat(ins.matrix)
                for vol in ob.volumes {
                    let special = vol.type != 0
                    if special != (pass == 1) { continue }
                    guard let (buf, n) = meshBuffer(vol.mesh) else { continue }
                    used.insert(vol.mesh)
                    let ext = vol.extruder > 1 ? vol.extruder : ob.extruder
                    var c = color(s.filaments.indices.contains(ext - 1) ? s.filaments[ext - 1].color : "#00AE42")
                    if ins.plate < 0 || !ins.printable { c = SIMD4(0.55, 0.55, 0.55, 1) }
                    if special { c = [SIMD4<Float>(0.5, 0.5, 0.5, 0.4), SIMD4(0.2, 0.2, 0.9, 0.4), SIMD4(0.9, 0.2, 0.2, 0.4), SIMD4(0.2, 0.2, 1, 0.4), SIMD4(0.2, 0.9, 0.2, 0.4)][min(4, max(0, vol.type))] }
                    if store.selection.contains(sel) && kind == nil { c = SIMD4(simd_mix(SIMD3(c.x, c.y, c.z), SIMD3(repeating: 1), SIMD3(repeating: 0.35)), c.w) }
                    u.model = im * mat(vol.matrix); u.color = c
                    e.setRenderPipelineState(special ? meshT : meshP); e.setDepthStencilState(special ? depthOff : depthOn)
                    e.setVertexBuffer(buf, offset: 0, index: 0)
                    e.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                    e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: n)
                    let k = kind ?? 2
                    let key = "\(ob.id)/\(vol.index)/\(k)"
                    if let d = store.paints[key], !d.isEmpty {
                        if paintBuf[key]?.0 != d, let nb = d.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: d.count) }) { paintBuf[key] = (d, nb) }
                        if let pb = paintBuf[key] {
                            var pal = [SIMD4<Float>](repeating: SIMD4(0.5, 0.5, 0.5, 1), count: 17)
                            if k == 2 { for (j, f) in s.filaments.enumerated() where j < 16 { pal[j + 1] = color(f.color) } } else { pal[1] = SIMD4(0.1, 0.4, 1, 1); pal[2] = SIMD4(1, 0.25, 0.25, 1) }
                            e.setRenderPipelineState(paintP); e.setVertexBuffer(pb.1, offset: 0, index: 0)
                            e.setVertexBytes(pal, length: 17 * 16, index: 2)
                            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: d.count / 28)
                        }
                    }
                }
            } }
        }
        for k in Array(buffers.keys) where !used.contains(k) && store.meshes[k] == nil { buffers[k] = nil }
        for k in Array(paintBuf.keys) where store.paints[k] == nil { paintBuf[k] = nil }
        u.model = matrix_identity_float4x4
        e.setDepthStencilState(depthOff)
        for sel in store.selection where sel.o < s.objects.count && sel.i < s.objects[sel.o].instances.count {
            let ins = s.objects[sel.o].instances[sel.i], d = dragDelta[sel] ?? .zero
            let a = SIMD3<Float>(Float(ins.min[0]), Float(ins.min[1]), Float(ins.min[2])) + d, c = SIMD3<Float>(Float(ins.max[0]), Float(ins.max[1]), Float(ins.max[2])) + d
            func p(_ i: Int) -> [Float] { [i & 1 == 0 ? a.x : c.x, i & 2 == 0 ? a.y : c.y, i & 4 == 0 ? a.z : c.z] }
            var l: [Float] = []
            for (i, j) in [(0,1),(2,3),(4,5),(6,7),(0,2),(1,3),(4,6),(5,7),(0,4),(1,5),(2,6),(3,7)] { l += p(i) + p(j) }
            e.setRenderPipelineState(lineP)
            line(e, &u, l, .line, SIMD4(1, 1, 1, 1))
            if store.tool == .cut {
                let (pt, n) = cutPlane(ins)
                let x = simd_normalize(simd_cross(abs(n.z) > 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3(0, 0, 1), n)), y = simd_cross(n, x)
                let r = simd_length(c - a) * 0.6
                let q = [pt - x * r - y * r, pt + x * r - y * r, pt + x * r + y * r, pt - x * r + y * r]
                let v = [q[0], q[1], q[2], q[0], q[2], q[3]].flatMap { [$0.x, $0.y, $0.z] }
                e.setRenderPipelineState(lineFlatT)
                line(e, &u, v, .triangle, SIMD4(0.2, 0.7, 1, 0.35))
            }
        }
    }
    private func line(_ e: MTLRenderCommandEncoder, _ u: inout Uniforms, _ v: [Float], _ t: MTLPrimitiveType, _ c: SIMD4<Float>) {
        u.color = c
        e.setVertexBytes(v, length: v.count * 4, index: 0)
        e.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        e.drawPrimitives(type: t, vertexStart: 0, vertexCount: v.count / 3)
    }
    func cutPlane(_ ins: InstanceS) -> (SIMD3<Float>, SIMD3<Float>) {
        let rx = Float(store.cutTilt.x) * .pi / 180, ry = Float(store.cutTilt.y) * .pi / 180
        let q = simd_quatf(angle: ry, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: rx, axis: SIMD3(1, 0, 0))
        return (SIMD3(Float(ins.min[0] + ins.max[0]) / 2, Float(ins.min[1] + ins.max[1]) / 2, Float(store.cutZ)), q.act(SIMD3(0, 0, 1)))
    }
    private func drawPreview(_ e: MTLRenderCommandEncoder, _ u: inout Uniforms, _ s: StateS) {
        guard let d = store.previewData, !d.isEmpty, store.previewPlate == s.current, s.plates[s.current].sliced else { segBuf = nil; segData = nil; return }
        if segData != d || segBuf == nil {
            segData = d
            segBuf = d.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: d.count) }
            layerStart = []; maxSpeed = 1
            d.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
                let f = b.bindMemory(to: Float.self)
                for i in 0..<(f.count / 12) {
                    let l = Int(f[i * 12 + 10])
                    while layerStart.count <= l { layerStart.append(i) }
                    if f[i * 12 + 8] < 99 { maxSpeed = max(maxSpeed, f[i * 12 + 11]) }
                }
                layerStart.append(f.count / 12)
            }
        }
        guard let buf = segBuf, layerStart.count > 1 else { return }
        let n = layerStart.count - 1
        let lo = min(max(0, Int(store.layerLow)), n - 1), hi = min(max(lo, Int(store.layerHigh)), n - 1)
        let a = layerStart[lo], z = layerStart[hi + 1]
        guard z > a else { return }
        var pal = [SIMD4<Float>](repeating: .one, count: 48)
        for (i, c) in roleColors.enumerated() { pal[i] = color(c) }
        for (i, f) in s.filaments.enumerated() where i < 16 { pal[32 + i] = color(f.color) }
        u.model = matrix_identity_float4x4; u.opt = SIMD4(store.showTravel ? 1 : 0, Float(store.colorBy), maxSpeed, 0)
        e.setRenderPipelineState(segP); e.setDepthStencilState(depthOn)
        e.setVertexBuffer(buf, offset: a * 48, index: 0)
        e.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        e.setVertexBytes(pal, length: 48 * 16, index: 2)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: z - a)
    }
}

struct SceneView: UIViewRepresentable {
    let ctl: SceneController
    let stamp: Int
    func makeUIView(context: Context) -> MTKView { let v = MTKView(); ctl.setup(v); return v }
    func updateUIView(_ v: MTKView, context: Context) { v.setNeedsDisplay() }
}
