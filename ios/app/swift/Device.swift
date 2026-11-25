import SwiftUI
import Security

struct PrinterInfo: Codable, Identifiable, Hashable { var id: String { serial }; var name: String, host: String, serial: String }

/// Access codes live in the keychain, never in preferences.
enum Keychain {
    static func get(_ k: String) -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "printer", kSecAttrAccount as String: k, kSecReturnData as String: true]
        var r: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess ? String(data: r as? Data ?? Data(), encoding: .utf8) ?? "" : ""
    }
    static func set(_ k: String, _ v: String?) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "printer", kSecAttrAccount as String: k]
        SecItemDelete(q as CFDictionary)
        if let v { SecItemAdd(q.merging([kSecValueData as String: Data(v.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]) { $1 } as CFDictionary, nil) }
    }
}

@MainActor final class Printers: ObservableObject {
    @Published var list: [PrinterInfo] = []
    @Published var active: PrinterInfo?
    @Published var connected = false
    @Published var connecting = false
    @Published var message = ""
    @Published var report: [String: Any] = [:]
    @Published var frame: UIImage?
    private(set) var link: LanBridge?
    private var seq = 1
    init() { if let d = UserDefaults.standard.data(forKey: "printers"), let l = try? JSONDecoder().decode([PrinterInfo].self, from: d) { list = l } }
    private func persist() { UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: "printers") }
    func add(_ p: PrinterInfo, code: String) { list.removeAll { $0.serial == p.serial }; list.append(p); Keychain.set(p.serial, code); persist() }
    func remove(_ p: PrinterInfo) { if active == p { disconnect() }; list.removeAll { $0 == p }; Keychain.set(p.serial, nil); persist() }
    func disconnect() { link?.disconnect(); link = nil; connected = false; active = nil; report = [:]; frame = nil }
    func connect(_ p: PrinterInfo) {
        disconnect()
        active = p; connecting = true; message = ""
        let l = LanBridge(host: p.host, serial: p.serial, code: Keychain.get(p.serial), ca: Bundle.main.bundleURL.appendingPathComponent("bbl_res/cert/printer.cer").path)
        link = l
        Task.detached {
            let err = l.connectMqtt({ j in Task { @MainActor in if self.link === l { self.merge(j) } } }, closed: { r in Task { @MainActor in if self.link === l { self.connected = false; self.message = r } } })
            await MainActor.run {
                guard self.link === l else { return }
                self.connecting = false; self.connected = err == nil; self.message = err ?? ""
                if err == nil { self.send(["pushing": ["sequence_id": "0", "command": "pushall"]]); self.camera(l) }
            }
        }
    }
    private func camera(_ l: LanBridge) {
        l.startCamera({ d in Task { @MainActor in if self.link === l, let i = UIImage(data: d) { self.frame = i } } }, closed: { r in Task { @MainActor in if self.link === l && self.frame == nil { self.message = "camera: " + r } } })
    }
    private func merge(_ j: String) {
        guard let o = try? JSONSerialization.jsonObject(with: Data(j.utf8)) as? [String: Any], let p = o["print"] as? [String: Any] else { return }
        if let r = p["result"] as? String, r.lowercased() == "fail" { message = "\(p["command"] ?? ""): \(p["reason"] ?? "failed")" }
        if p["command"] as? String == "push_status" || p["command"] == nil { report = deep(report, p) }
    }
    private func deep(_ a: [String: Any], _ b: [String: Any]) -> [String: Any] {
        var r = a
        for (k, v) in b { if let x = r[k] as? [String: Any], let y = v as? [String: Any] { r[k] = deep(x, y) } else { r[k] = v } }
        return r
    }
    func send(_ o: [String: Any]) {
        guard let l = link, let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return }
        Task.detached { if !l.publish(s) { await MainActor.run { self.message = "cannot send the command" } } }
    }
    func cmd(_ c: String, _ extra: [String: Any] = [:]) { seq += 1; send(["print": ["sequence_id": "\(seq)", "command": c].merging(extra) { $1 }]) }
    func gcode(_ g: String) { cmd("gcode_line", ["param": g + "\n"]) }
    func light(_ on: Bool) { seq += 1; send(["system": ["sequence_id": "\(seq)", "command": "ledctrl", "led_node": "chamber_light", "led_mode": on ? "on" : "off", "led_on_time": 500, "led_off_time": 500, "loop_times": 0, "interval_time": 0]]) }
    func num(_ k: String) -> Double { (report[k] as? NSNumber)?.doubleValue ?? Double(report[k] as? String ?? "") ?? 0 }
    var state: String { report["gcode_state"] as? String ?? "" }
    var trays: [(Int, String, String)] {
        var r: [(Int, String, String)] = []
        for a in ((report["ams"] as? [String: Any])?["ams"] as? [[String: Any]]) ?? [] {
            let ai = Int(a["id"] as? String ?? "0") ?? 0
            for t in a["tray"] as? [[String: Any]] ?? [] { if let ti = Int(t["id"] as? String ?? ""), let ty = t["tray_type"] as? String, !ty.isEmpty { r.append((ai * 4 + ti, ty, "#" + String((t["tray_color"] as? String ?? "888888").prefix(6)))) } }
        }
        return r
    }
}

struct AddPrinter: View {
    @ObservedObject var printers: Printers
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = ""
    @State private var serial = ""
    @State private var code = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField(tr("Printer name"), text: $name)
                TextField("IP", text: $host).keyboardType(.numbersAndPunctuation)
                TextField(tr("Serial Number"), text: $serial).textInputAutocapitalization(.characters)
                SecureField(tr("Access code"), text: $code)
            }.autocorrectionDisabled().navigationTitle(tr("Add printer"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("OK") { let s = serial.trimmingCharacters(in: .whitespaces); printers.add(PrinterInfo(name: name.isEmpty ? s : name, host: host.trimmingCharacters(in: .whitespaces), serial: s), code: code.trimmingCharacters(in: .whitespaces)); dismiss() }.disabled(host.isEmpty || serial.isEmpty || code.isEmpty) }
            }
        }
    }
}

struct DeviceView: View {
    @ObservedObject var store: Store
    @ObservedObject var printers: Printers
    @State private var adding = false
    @State private var stopping = false
    @State private var nozzle = 0.0
    @State private var bed = 0.0
    var body: some View {
        HStack(spacing: 0) {
            List {
                ForEach(printers.list) { p in
                    Button { printers.connect(p) } label: { HStack { Image(systemName: "printer"); VStack(alignment: .leading) { Text(p.name); Text(p.host).font(.caption).foregroundStyle(.secondary) }; Spacer(); if printers.active == p { if printers.connecting { ProgressView() } else { Circle().fill(printers.connected ? .green : .red).frame(width: 10) } } }.frame(minHeight: 48) }.foregroundStyle(.primary)
                        .swipeActions { Button(tr("Delete"), role: .destructive) { printers.remove(p) } }
                }
                Button { adding = true } label: { Label(tr("Add printer"), systemImage: "plus") }.frame(minHeight: 48)
            }.frame(width: 300)
            Divider()
            if printers.active == nil { ContentUnavailableView(tr("No printer"), systemImage: "printer") } else { status }
        }.sheet(isPresented: $adding) { AddPrinter(printers: printers) }
    }
    private var status: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !printers.message.isEmpty { Text(printers.message).foregroundStyle(.orange) }
                ZStack { RoundedRectangle(cornerRadius: 12).fill(.black); if let f = printers.frame { Image(uiImage: f).resizable().scaledToFit() } else { Image(systemName: "video.slash").foregroundStyle(.gray).font(.largeTitle) } }.frame(height: 400).clipShape(RoundedRectangle(cornerRadius: 12))
                HStack { Text(printers.state).font(.headline); Text(printers.report["subtask_name"] as? String ?? "").lineLimit(1); Spacer(); Text("\(Int(printers.num("layer_num")))/\(Int(printers.num("total_layer_num")))"); Text("-\(Int(printers.num("mc_remaining_time")) / 60)h\(Int(printers.num("mc_remaining_time")) % 60)m") }
                ProgressView(value: min(100, max(0, printers.num("mc_percent"))), total: 100)
                HStack {
                    Button(tr("Pause")) { printers.cmd("pause") }.disabled(printers.state != "RUNNING")
                    Button(tr("Resume")) { printers.cmd("resume") }.disabled(printers.state != "PAUSE")
                    Button(tr("Stop"), role: .destructive) { stopping = true }.disabled(!["RUNNING", "PAUSE", "PREPARE"].contains(printers.state))
                    Button { printers.light(true) } label: { Image(systemName: "lightbulb.fill") }
                    Button { printers.light(false) } label: { Image(systemName: "lightbulb.slash") }
                    Picker("", selection: Binding(get: { Int(printers.num("spd_lvl")) }, set: { printers.cmd("print_speed", ["param": "\($0)"]) })) { Text(tr("Silent")).tag(1); Text(tr("Standard")).tag(2); Text(tr("Sport")).tag(3); Text(tr("Ludicrous")).tag(4) }
                }.buttonStyle(.bordered).controlSize(.large).disabled(!printers.connected)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    GridRow { Text(tr("Nozzle")); Text(String(format: "%.0f / %.0f °C", printers.num("nozzle_temper"), printers.num("nozzle_target_temper"))).monospacedDigit(); NumField(title: "°C", value: nozzle) { nozzle = min(300, max(0, $0)); if idle { printers.gcode("M104 S\(Int(nozzle))") } } }
                    GridRow { Text(tr("Bed")); Text(String(format: "%.0f / %.0f °C", printers.num("bed_temper"), printers.num("bed_target_temper"))).monospacedDigit(); NumField(title: "°C", value: bed) { bed = min(110, max(0, $0)); if idle { printers.gcode("M140 S\(Int(bed))") } } }
                    GridRow { Text("Wi-Fi"); Text(printers.report["wifi_signal"] as? String ?? "–") }
                }
                HStack { ForEach(["X-10", "X10", "Y-10", "Y10", "Z-10", "Z10"], id: \.self) { m in Button(m) { printers.gcode("M211 S\nM211 X1 Y1 Z1\nM1002 push_ref_mode\nG91\nG1 \(m) F\(m.hasPrefix("Z") ? 900 : 3000)\nM1002 pop_ref_mode\nM211 R") } }
                    Button(tr("Home")) { printers.gcode("G28") } }.buttonStyle(.bordered).controlSize(.large).disabled(!idle)
                if !printers.trays.isEmpty { Text("AMS").font(.headline); HStack { ForEach(printers.trays, id: \.0) { t in VStack { RoundedRectangle(cornerRadius: 8).fill(Color(hex: t.2)).frame(width: 56, height: 56); Text("\(Character(UnicodeScalar(65 + t.0 / 4)!))\(t.0 % 4 + 1) \(t.1)").font(.caption) } } } }
            }.padding(20)
        }.confirmationDialog(tr("Stop"), isPresented: $stopping) { Button(tr("Stop"), role: .destructive) { printers.cmd("stop") } }
    }
    private var idle: Bool { printers.connected && ["IDLE", "FINISH", "FAILED"].contains(printers.state) }
}

struct SendView: View {
    @ObservedObject var store: Store
    @ObservedObject var printers: Printers
    @Environment(\.dismiss) private var dismiss
    @State private var target: PrinterInfo?
    @State private var progress = 0.0
    @State private var working = false
    @State private var note = ""
    @State private var useAms = true
    @State private var leveling = true
    @State private var timelapse = false
    @State private var map: [Int: Int] = [:]
    var body: some View {
        NavigationStack {
            Form {
                Section(tr("Printer")) {
                    ForEach(printers.list) { p in Button { target = p; if printers.active != p || !printers.connected { printers.connect(p) } } label: { HStack { Text(p.name); Spacer(); if target == p { Image(systemName: "checkmark") } } } }
                    if printers.list.isEmpty { Text(tr("No printer")) }
                }
                Section {
                    Toggle("AMS", isOn: $useAms); Toggle(tr("Bed Leveling"), isOn: $leveling); Toggle(tr("Timelapse"), isOn: $timelapse)
                    if useAms { ForEach(Array((store.state?.filaments ?? []).enumerated()), id: \.offset) { i, f in
                        Picker(selection: Binding(get: { map[i] ?? -1 }, set: { map[i] = $0 })) { Text("–").tag(-1); ForEach(printers.trays, id: \.0) { t in Text("\(Character(UnicodeScalar(65 + t.0 / 4)!))\(t.0 % 4 + 1) \(t.1)").tag(t.0) } } label: { HStack { Circle().fill(Color(hex: f.color)).frame(width: 20); Text("\(i + 1) \(f.type)") } } } }
                }
                if working { ProgressView(value: progress) }
                if !note.isEmpty { Text(note) }
                if !printers.message.isEmpty { Text(printers.message).foregroundStyle(.orange) }
            }.navigationTitle(tr("Print plate"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Close")) { dismiss() } }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button(tr("Send")) { go(false) }.disabled(!ready)
                    Button(tr("Print")) { go(true) }.disabled(!ready || (useAms && usedFilaments.contains { (map[$0] ?? -1) < 0 }))
                }
            }
        }
    }
    private var ready: Bool { target != nil && target == printers.active && printers.connected && !working }
    private var usedFilaments: [Int] { (store.slice.filaments ?? []).map { Int($0[0]) } }
    private func go(_ start: Bool) {
        guard let l = printers.link, let s = store.state else { return }
        let plate = s.current
        let name = String("\(store.baseName)_p\(plate + 1)".unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII || "_-".unicodeScalars.contains($0) ? Character($0) : "_" }) + ".gcode.3mf"
        working = true; note = ""; progress = 0
        store.tempExport(name, "export_gcode3mf", ["plate": plate]) { url in
            Task.detached {
                let err = l.upload(url.path, as: name) { v in Task { @MainActor in progress = v } }
                await MainActor.run {
                    working = false
                    if let err { note = err; return }
                    note = tr("Successfully sent.")
                    if start {
                        let m = s.filaments.indices.map { map[$0] ?? -1 }
                        printers.cmd("project_file", ["param": "Metadata/plate_\(plate + 1).gcode", "project_id": "0", "profile_id": "0", "task_id": "0", "subtask_id": "0", "subtask_name": name.replacingOccurrences(of: ".gcode.3mf", with: ""), "file": name,
                                                      "url": "ftp:///\(name)", "bed_type": "auto", "timelapse": timelapse, "bed_leveling": leveling, "flow_cali": false, "vibration_cali": false, "layer_inspect": false, "use_ams": useAms, "ams_mapping": useAms ? m : []])
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if store.error != nil { working = false } }
    }
}
