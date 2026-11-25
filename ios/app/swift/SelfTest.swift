import SwiftUI

/// `--selftest` launch argument: drives every engine command on the device; results and screenshots go to Documents/selftest.
@MainActor final class SelfTest {
    let s: Store, dir: URL
    var log = ""
    init(_ s: Store) { self.s = s; dir = s.docs.appendingPathComponent("selftest"); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    func note(_ t: String) { log += t + "\n"; print(t); try? log.write(to: dir.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8) }
    func wait(_ x: Double) async { try? await Task.sleep(nanoseconds: UInt64(x * 1e9)) }
    func shot(_ n: String) async {
        await wait(0.8)
        guard let w = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first else { return note("no window") }
        let img = UIGraphicsImageRenderer(bounds: w.bounds).image { _ in w.drawHierarchy(in: w.bounds, afterScreenUpdates: true) }
        try? img.pngData()?.write(to: dir.appendingPathComponent(n + ".png"))
    }
    @discardableResult func cmd(_ c: String, _ a: [String: Any] = [:], label: String? = nil) async -> [String: Any] {
        let t = Date()
        let d: Data = await withCheckedContinuation { k in s.raw(c, a) { k.resume(returning: $0) } }
        let o = (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
        let e = o["error"] as? String
        let objs = (o["objects"] as? [[String: Any]]).map { x in " objects=\(x.count) vols=\(x.map { ($0["volumes"] as? [Any])?.count ?? 0 })" } ?? ""
        note("\(e == nil ? "OK  " : "FAIL") \(label ?? c) \(String(format: "%.2fs", -t.timeIntervalSinceNow))\(objs)\(e.map { " -> " + $0 } ?? "")")
        return o
    }
    func reload() async { await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in s.run("state") { k.resume() } } }
    func slice(_ label: String) async {
        s.startSlice()
        await wait(1)
        while s.slice.state == "slicing" { await wait(0.2) }
        await wait(1.5)
        note("SLICE \(label): \(s.slice.state) \(s.slice.message ?? "") layers=\(s.slice.layers ?? 0) weight=\(s.slice.weight ?? 0) time=\(s.slice.time ?? 0) filaments=\(s.slice.filaments ?? []) segs=\((s.previewData?.count ?? 0) / 48) warnings=\(s.slice.warnings ?? [])")
    }
    func run() async {
        for _ in 0..<150 where s.state == nil { await wait(0.2) }
        note("state loaded: \(s.state != nil) printer=\(s.state?.printer.name ?? "") process=\(s.state?.process.name ?? "") error=\(s.error ?? "")")
        s.tab = 0
        await shot("01-empty")
        for t in ["printer", "filament", "process"] {
            let r = await cmd("presets", ["type": t], label: "presets \(t)"); note("   count \((r["items"] as? [Any])?.count ?? 0)")
            await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
                s.raw("options", ["type": t]) { d in
                    do { let o = try JSONDecoder().decode([String: OptionS].self, from: d); let miss = (self.s.layout[t] ?? []).flatMap(\.groups).flatMap(\.options).filter { o[$0] == nil }; self.note("OK   options \(t) \(o.count), layout keys missing: \(miss)") } catch { self.note("FAIL options \(t) \(error)") }
                    k.resume()
                }
            }
        }
        await cmd("bed_types")
        await cmd("new")
        for x in ["cube", "cylinder", "sphere", "cone"] { await cmd("add_shape", ["shape": x], label: "add_shape \(x)") }
        await cmd("arrange")
        await reload(); s.selection = [Sel(o: 0, i: 0)]; s.tool = .move
        await shot("02-shapes")
        let c: [String: Any] = ["o": 0, "i": 0]
        func w(_ x: [String: Any]) -> [String: Any] { c.merging(x) { $1 } }
        await cmd("transform", w(["rotation": [0, 0, 30]]), label: "rotate")
        await cmd("transform", w(["rotateWorld": [1, 0, 0], "degrees": 45]), label: "rotateWorld")
        await cmd("transform", w(["scale": [1.5, 1.5, 2]]), label: "scale")
        await cmd("transform", w(["mirror": 0]), label: "mirror")
        await cmd("center", c); await cmd("lay_flat", w(["normal": [0, 0, 1]])); await cmd("auto_orient", c); await reload()
        if let i = s.state?.objects[0].instances[0] { note("   size after orient \((0..<3).map { i.max[$0] - i.min[$0] })") }
        await cmd("undo"); await cmd("redo")
        await cmd("clone", w(["n": 2])); await cmd("rename", ["o": 0, "name": "Thử"]); await cmd("printable", w(["value": false])); await cmd("printable", w(["value": true]))
        await cmd("add_shape", ["shape": "cylinder", "o": 0, "type": 1, "size": 8], label: "negative part"); await cmd("add_shape", ["shape": "cube", "o": 0, "type": 2, "size": 8], label: "modifier")
        await cmd("volume_type", ["o": 0, "v": 2, "value": 3]); await cmd("delete_volume", ["o": 0, "v": 2])
        await cmd("simplify", ["o": 2, "v": 0, "ratio": 0.3]); await cmd("split_objects", ["o": 1]); await cmd("split_parts", ["o": 1])
        await cmd("merge", ["ids": [1, 2]])
        await reload()
        if let o = s.state?.objects.last, let i = o.instances.first {
            let mid = (0..<3).map { (i.min[$0] + i.max[$0]) / 2 }
            await cmd("cut", ["o": o.index, "i": 0, "point": mid, "normal": [0, 0, 1], "upper": true, "lower": true, "parts": false])
        }
        await cmd("set_option", ["type": "object", "o": 0, "key": "wall_loops", "value": "5"], label: "object option"); await cmd("clear_object_option", ["o": 0, "key": "wall_loops"])
        await cmd("set_option", ["type": "process", "key": "wall_loops", "value": "3"], label: "process option"); await cmd("save_preset", ["type": "process", "name": "Selftest"]); await cmd("delete_preset", ["type": "process"])
        await cmd("set_option", ["type": "process", "key": "wall_loops", "value": "4"], label: "process option 2"); await cmd("reset_option", ["type": "process", "key": "wall_loops"]); await cmd("discard_preset", ["type": "process"])
        await cmd("add_filament"); await cmd("set_filament", ["index": 1, "color": "#FF0000"])
        await cmd("plate_add"); await cmd("plate_rename", ["plate": 1, "name": "B"]); await cmd("add_shape", ["shape": "cube"], label: "cube on plate 2")
        await cmd("arrange", ["all": true], label: "arrange all"); await cmd("plate_select", ["plate": 1]); await cmd("plate_remove", ["plate": 1]); await cmd("plate_select", ["plate": 0])
        await reload(); await shot("03-edited")
        // painting on a fresh cube
        await cmd("new"); await cmd("add_shape", ["shape": "cube"]); await cmd("center", c); await reload()
        if let i = s.state?.objects.first?.instances.first {
            let o = [(i.min[0] + i.max[0]) / 2, i.min[1] - 200, (i.min[2] + i.max[2]) / 2]
            for k in 0..<3 { await cmd("paint_begin"); let r = await cmd("paint", ["o": 0, "i": 0, "v": 0, "kind": k, "state": k == 2 ? 2 : 1, "radius": 4, "tool": "circle", "origin": o, "dir": [0, 1, 0]], label: "paint \(k)"); note("   hit \(r["hit"] ?? "nil")") }
        }
        await cmd("paint_overhang", c)
        await reload(); s.selection = []; s.tool = .color; await wait(1); await shot("04-paint"); s.tool = .none
        await slice("painted cube"); await shot("05-preview")
        for (n, f) in [("export_gcode", "t.gcode"), ("export_gcode3mf", "t.gcode.3mf"), ("save", "t.3mf"), ("export_stl", "t.stl")] {
            let u = dir.appendingPathComponent(f); await cmd(n, ["path": u.path]); note("   bytes \((try? Data(contentsOf: u).count) ?? -1)")
        }
        await cmd("open", ["path": dir.appendingPathComponent("t.3mf").path], label: "reopen saved 3mf")
        await cmd("open", ["path": dir.appendingPathComponent("t.stl").path, "geometry": true], label: "import stl")
        let files = (try? FileManager.default.contentsOfDirectory(at: s.docs, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "3mf" {
            s.tab = 0; await cmd("open", ["path": f.path], label: "open user file"); await reload(); s.fit(); await wait(2); await shot("06-project")
            await slice("user file"); s.layerHigh = Double(s.layerCount / 2); await shot("07-project-preview")
        }
        s.tab = 2; await shot("08-device"); s.tab = 0
        note("ERROR STATE: \(s.error ?? "none")"); note("DONE")
    }
}
