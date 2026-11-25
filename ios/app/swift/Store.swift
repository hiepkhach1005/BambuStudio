import SwiftUI
import simd

// MARK: - Translations: the desktop app's own .mo catalogue
final class Translator {
    static let shared = Translator()
    private var map: [String: String] = [:]
    private init() {
        let lang = (Locale.preferredLanguages.first ?? "en").replacingOccurrences(of: "-", with: "_")
        let base = lang.split(separator: "_").first.map(String.init) ?? "en"
        for l in [lang, base] {
            let url = Bundle.main.bundleURL.appendingPathComponent("bbl_res/i18n/\(l)/BambuStudio.mo")
            if let d = try? Data(contentsOf: url), load(d) { break }
        }
    }
    private func load(_ d: Data) -> Bool {
        func u32(_ o: Int) -> Int { o + 4 <= d.count ? Int(d[o]) | Int(d[o+1]) << 8 | Int(d[o+2]) << 16 | Int(d[o+3]) << 24 : 0 }
        guard d.count > 28, u32(0) == 0x950412de else { return false }
        let n = u32(8), a = u32(12), b = u32(16)
        for i in 0..<n {
            let l1 = u32(a + i*8), o1 = u32(a + i*8 + 4), l2 = u32(b + i*8), o2 = u32(b + i*8 + 4)
            guard o1 + l1 <= d.count, o2 + l2 <= d.count else { return false }
            guard let k = String(data: d[o1..<(o1+l1)], encoding: .utf8), let v = String(data: d[o2..<(o2+l2)], encoding: .utf8) else { continue }
            let key = k.components(separatedBy: "\u{4}").last!.components(separatedBy: "\0")[0]
            let val = v.components(separatedBy: "\0")[0]
            if !val.isEmpty && map[key] == nil { map[key] = val }
        }
        return true
    }
    private lazy var lower: [String: String] = Dictionary(map.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
    private static let extraVi = ["add printer": "Thêm máy in", "arrange all": "Xếp tất cả", "auto": "Tự động", "object settings": "Thông số vật thể", "no objects": "Chưa có vật thể", "no printer": "Chưa có máy in", "access code": "Mã truy cập", "serial number": "Số sê-ri", "printer name": "Tên máy in", "unsaved changes will be lost.": "Các thay đổi chưa lưu sẽ bị mất.", "erase all painting": "Xóa hết nét tô", "printing plate": "Tấm in"]
    private let vi = Locale.preferredLanguages.first?.hasPrefix("vi") == true
    func t(_ s: String) -> String { if let v = map[s] { return v }; let l = s.lowercased(); return lower[l] ?? (vi ? Self.extraVi[l] : nil) ?? s }
}
func tr(_ s: String) -> String { Translator.shared.t(s) }

// MARK: - State mirrored from the engine
struct VolumeS: Decodable, Identifiable {
    let index: Int, name: String, mesh: Int64, type: Int, matrix: [Float], extruder: Int, paintStamp: Int64
    let supportPaint: Bool, seamPaint: Bool, colorPaint: Bool
    var id: Int { index }
    func painted(_ k: Int) -> Bool { k == 0 ? supportPaint : k == 1 ? seamPaint : colorPaint }
}
struct InstanceS: Decodable, Identifiable {
    let index: Int, matrix: [Float], printable: Bool, plate: Int, offset: [Double], rotation: [Double], scale: [Double], min: [Double], max: [Double]
    var id: Int { index }
}
struct ObjectS: Decodable, Identifiable {
    let index: Int, id: Int64, name: String, extruder: Int, facets: Int, volumes: [VolumeS], instances: [InstanceS], config: [String: String]
}
struct PlateS: Decodable, Identifiable { let index: Int, name: String, origin: [Double], sliced: Bool; var id: Int { index } }
struct PresetRef: Decodable { let name: String, dirty: Bool }
struct FilamentS: Decodable { let name: String, type: String, color: String }
struct StateS: Decodable {
    let objects: [ObjectS], plates: [PlateS], current: Int, bed: [Double], exclude: [[Double]], printer: PresetRef, process: PresetRef
    let filaments: [FilamentS], bedType: String, canUndo: Bool, canRedo: Bool, modified: Bool, path: String
    let warning: String?
}
struct PresetItem: Decodable, Identifiable { let name: String, system: Bool, alias: String; var id: String { name } }
struct OptionS: Decodable {
    let label: String, tooltip: String, unit: String, mode: Int, multiline: Bool, readonly: Bool, type: String
    var value: String
    let values: [String]?, labels: [String]?, min: Double?, max: Double?, dirty: Bool?
}
struct LayoutPage: Decodable, Identifiable { let title: String, groups: [LayoutGroup]; var id: String { title } }
struct LayoutGroup: Decodable, Identifiable { let title: String, options: [String]; var id: String { title + (options.first ?? "") } }
struct SliceStatus: Decodable {
    let state: String
    var plate: Int?, percent: Int?, text: String?, message: String?
    var time: Double?, prepare: Double?, weight: Double?, length: Double?, cost: Double?, layers: Int?
    var roles: [[Double]]?, filaments: [[Double]]?, toolchanges: Int?, warnings: [String]?, conflict: String?
}
struct Sel: Hashable { let o: Int, i: Int }

enum Tool: String { case none, move, rotate, scale, layflat, cut, support, seam, color
    var paintKind: Int? { switch self { case .support: 0; case .seam: 1; case .color: 2; default: nil } } }

@MainActor final class Store: ObservableObject {
    let engine: EngineBridge
    @Published var state: StateS?
    @Published var selection: Set<Sel> = []
    @Published var tool: Tool = .none { didSet { sceneStamp += 1 } }
    @Published var error: String?
    @Published var busy = true
    @Published var slice = SliceStatus(state: "idle")
    @Published var tab = 0 { didSet { sceneStamp += 1; if tab == 1 { loadPreview() } } }
    @Published var layout: [String: [LayoutPage]] = [:]
    @Published var layerLow = 0.0 { didSet { sceneStamp += 1 } }
    @Published var layerHigh = 0.0 { didSet { sceneStamp += 1 } }
    @Published var layerCount = 0
    @Published var showTravel = false { didSet { sceneStamp += 1 } }
    @Published var colorBy = 0 { didSet { loadPreview(force: true) } }
    @Published var cutZ = 0.0 { didSet { sceneStamp += 1 } }
    @Published var cutTilt = SIMD2<Double>(0, 0) { didSet { sceneStamp += 1 } }
    @Published var paintState = 1
    @Published var paintRadius = 2.0
    @Published var paintTool = "circle"
    @Published var sceneStamp = 0
    var meshes: [Int64: Data] = [:]
    var meshesLoading: Set<Int64> = []
    var paints: [String: Data] = [:]
    var paintStamps: [String: Int64] = [:]
    var previewData: Data?
    var previewPlate = -1
    var fitRequest = 0
    private var pollTimer: Timer?
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    init() {
        let res = Bundle.main.bundleURL.appendingPathComponent("bbl_res").path
        let sup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("studio").path
        engine = EngineBridge(resources: res, data: sup, temp: NSTemporaryDirectory() + "slice")
        if let d = try? Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("layout.json")),
           let l = try? JSONDecoder().decode([String: [LayoutPage]].self, from: d) { layout = l }
        run("state") { [weak self] in self?.fit() }
    }
    func raw(_ cmd: String, _ args: [String: Any] = [:], _ done: @escaping (Data) -> Void) {
        let a = (try? JSONSerialization.data(withJSONObject: args)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        engine.call(cmd, args: a) { r in done(Data(r.utf8)) }
    }
    static func err(_ d: Data) -> String? { (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["error"] as? String }
    /// Commands that answer with the whole document state.
    func run(_ cmd: String, _ args: [String: Any] = [:], then: (() -> Void)? = nil) {
        busy = true
        raw(cmd, args) { [weak self] d in
            guard let self else { return }
            self.busy = false
            if let e = Store.err(d) { self.error = tr(e); return }
            do { self.apply(try JSONDecoder().decode(StateS.self, from: d)) } catch { self.error = "\(error)"; return }
            then?()
        }
    }
    func query<T: Decodable>(_ type: T.Type, _ cmd: String, _ args: [String: Any] = [:], _ done: @escaping (T) -> Void) {
        raw(cmd, args) { [weak self] d in
            if let e = Store.err(d) { self?.error = tr(e) }
            else if let v = try? JSONDecoder().decode(T.self, from: d) { done(v) }
            else { self?.error = "unexpected reply: \(cmd)" }
        }
    }
    private func apply(_ s: StateS) {
        state = s
        if let w = s.warning { error = w }
        selection = selection.filter { x in x.o < s.objects.count && x.i < s.objects[x.o].instances.count }
        var used: Set<Int64> = [], usedPaint: Set<String> = []
        for o in s.objects { for v in o.volumes {
            used.insert(v.mesh)
            if meshes[v.mesh] == nil && !meshesLoading.contains(v.mesh) {
                meshesLoading.insert(v.mesh)
                engine.mesh(v.mesh) { d in
                    Task { @MainActor in self.meshesLoading.remove(v.mesh); if !d.isEmpty { self.meshes[v.mesh] = d }; self.sceneStamp += 1 }
                }
            }
            for k in 0..<3 {
                let key = "\(o.id)/\(v.index)/\(k)"
                if v.painted(k) {
                    usedPaint.insert(key)
                    if paintStamps[key] != v.paintStamp { paintStamps[key] = v.paintStamp; loadPaint(o.index, v.index, k, key) }
                }
            }
        } }
        meshes = meshes.filter { used.contains($0.key) }
        for k in Array(paints.keys) where !usedPaint.contains(k) { paints[k] = nil; paintStamps[k] = nil }
        sceneStamp += 1
    }
    func loadPaint(_ o: Int, _ v: Int, _ k: Int, _ key: String) {
        engine.paintedObject(Int32(o), volume: Int32(v), kind: Int32(k)) { d in Task { @MainActor in self.paints[key] = d; self.sceneStamp += 1 } }
    }
    func fit() { fitRequest += 1; sceneStamp += 1 }
    var single: (ObjectS, InstanceS, Sel)? {
        guard selection.count == 1, let s = selection.first, let st = state, s.o < st.objects.count, s.i < st.objects[s.o].instances.count else { return nil }
        return (st.objects[s.o], st.objects[s.o].instances[s.i], s)
    }
    func ids() -> [[Int]] { selection.map { [$0.o, $0.i] } }
    func transform(_ s: Sel, _ extra: [String: Any], then: (() -> Void)? = nil) { run("transform", ["o": s.o, "i": s.i].merging(extra) { $1 }, then: then) }

    // MARK: files
    func open(_ url: URL, geometry: Bool) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        // Work on a private copy: the engine reads on another thread and providers may evict the original.
        let dir = docs.appendingPathComponent("Imported")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dst = dir.appendingPathComponent(url.lastPathComponent)
        var cerr: NSError?
        var failure: String?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &cerr) { u in
            do {
                if u.standardizedFileURL == dst.standardizedFileURL { return }
                let tmp = dir.appendingPathComponent(UUID().uuidString)
                try FileManager.default.copyItem(at: u, to: tmp)
                if FileManager.default.fileExists(atPath: dst.path) { _ = try FileManager.default.replaceItemAt(dst, withItemAt: tmp) }
                else { try FileManager.default.moveItem(at: tmp, to: dst) }
            } catch { failure = error.localizedDescription }
        }
        if let e = failure ?? cerr?.localizedDescription { error = e; return }
        if !geometry && url.pathExtension.lowercased() == "3mf" { selection = [] }
        run("open", ["path": dst.path, "geometry": geometry]) { self.tab = 0; self.fit() }
    }
    func tempExport(_ name: String, _ cmd: String, _ args: [String: Any] = [:], _ done: @escaping (URL) -> Void) {
        let safe = name.replacingOccurrences(of: "/", with: "_")
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(safe)
        try? FileManager.default.removeItem(at: url)
        busy = true
        raw(cmd, args.merging(["path": url.path]) { $1 }) { d in
            self.busy = false
            if let e = Store.err(d) { self.error = tr(e) } else { done(url); if cmd == "save" { self.run("state") } }
        }
    }
    var baseName: String {
        guard let s = state else { return "project" }
        if !s.path.isEmpty { return (s.path as NSString).lastPathComponent.replacingOccurrences(of: ".3mf", with: "") }
        return s.objects.first?.name ?? "project"
    }

    // MARK: slicing
    func startSlice(then: (() -> Void)? = nil) {
        guard let s = state else { return }
        previewData = nil; previewPlate = -1
        run("slice", ["plate": s.current]) {
            self.slice = SliceStatus(state: "slicing", plate: s.current, percent: 0)
            UIApplication.shared.isIdleTimerDisabled = true
            self.pollTimer?.invalidate()
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in Task { @MainActor in self.poll(then) } }
        }
    }
    private func poll(_ then: (() -> Void)?) {
        guard pollTimer != nil, let st = try? JSONDecoder().decode(SliceStatus.self, from: Data(engine.sliceStatus().utf8)) else { return }
        slice = st
        if st.state == "slicing" { return }
        pollTimer?.invalidate(); pollTimer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        run("slice_result") {
            if st.state == "done" { if self.tab == 1 { self.loadPreview(force: true) } else { self.tab = 1 }; then?() }
        }
        if st.state == "error" { error = tr(st.message ?? "Slicing failed") }
    }
    func loadPreview(force: Bool = false) {
        guard let s = state, s.plates.indices.contains(s.current) else { return }
        let p = s.current
        guard s.plates[p].sliced else { previewData = nil; previewPlate = -1; layerCount = 0; sceneStamp += 1; return }
        if !force && previewPlate == p && previewData != nil { return }
        engine.previewPlate(Int32(p)) { d in Task { @MainActor in
            self.previewData = d; self.previewPlate = p
            let n = d.count / 48
            self.layerCount = n == 0 ? 0 : d.withUnsafeBytes { Int($0.load(fromByteOffset: (n - 1) * 48 + 40, as: Float.self)) + 1 }
            self.layerLow = 0; self.layerHigh = Double(max(0, self.layerCount - 1))
            self.sceneStamp += 1
        } }
    }
}

func color(_ hex: String) -> SIMD4<Float> {
    var v: UInt64 = 0
    let h = String(hex.dropFirst().prefix(6))
    guard Scanner(string: h).scanHexInt64(&v) else { return [0, 0.68, 0.26, 1] }
    return [Float((v >> 16) & 255) / 255, Float((v >> 8) & 255) / 255, Float(v & 255) / 255, 1]
}
extension Color { init(hex: String) { let c = color(hex); self.init(red: Double(c.x), green: Double(c.y), blue: Double(c.z)) } }
let roleNames = ["Undefined", "Inner wall", "Outer wall", "Overhang wall", "Sparse infill", "Internal solid infill", "Floating vertical shell", "Top surface", "Bottom surface", "Ironing", "Bridge", "Gap infill", "Skirt", "Brim", "Support", "Support interface", "Support transition", "Support ironing", "Prime tower", "Custom", "Flush", "Multiple"]
let roleColors = ["#E6B3B3", "#FFE64D", "#FF7D38", "#1F1FFF", "#B03029", "#9654CC", "#E26BD3", "#F04040", "#665CC7", "#FF8C69", "#4D80BA", "#FFFFFF", "#00876E", "#003B6E", "#00FF00", "#008000", "#004000", "#70B070", "#B3E3AB", "#5ED194", "#808080", "#808080"]
