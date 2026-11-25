import SwiftUI

struct PresetList: Decodable { let items: [PresetItem], selected: String }
struct PresetPicker: View {
    @ObservedObject var store: Store
    let type: String, current: String, pick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [PresetItem] = []
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List(items.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { p in
                Button { pick(p.name); dismiss() } label: { HStack { Text(p.name); if !p.system { Image(systemName: "person").foregroundStyle(.secondary) }; Spacer(); if p.name == current { Image(systemName: "checkmark") } }.frame(minHeight: 36) }.foregroundStyle(.primary)
            }.searchable(text: $search).navigationTitle(tr(type == "printer" ? "Printer" : type == "filament" ? "Filament" : "Process")).toolbar { Button(tr("Close")) { dismiss() } }
        }.onAppear { store.query(PresetList.self, "presets", ["type": type]) { items = $0.items.sorted { ($0.system ? 1 : 0, $0.name) < ($1.system ? 1 : 0, $1.name) } } }
    }
}

struct PickTarget: Identifiable { let id = UUID(); let type: String, current: String, index: Int }
struct BedTypes: Decodable { let values: [String], labels: [String] }

struct Sidebar: View {
    @ObservedObject var store: Store
    let scene: SceneController
    @State private var pick: PickTarget?
    @State private var settings: String?
    @State private var mode = 0
    @State private var beds: BedTypes?
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let s = store.state {
                        header("Printer", "printer") { settings = "printer" }
                        presetButton(s.printer) { pick = PickTarget(type: "printer", current: s.printer.name, index: 0) }
                        if let b = beds {
                            HStack { Text(tr("Bed type")).font(.callout); Spacer()
                                Picker("", selection: Binding(get: { s.bedType }, set: { store.run("bed_type", ["value": $0]) })) { ForEach(Array(zip(b.values, b.labels)), id: \.0) { v, l in Text(tr(l)).tag(v) } }.frame(minHeight: 40) }
                        }
                        HStack { header("Filament", "cylinder.split.1x2") { settings = "filament" }; Button { store.run("add_filament") } label: { Image(systemName: "plus").frame(width: 44, height: 40) }.disabled(s.filaments.count >= 16) }
                        ForEach(Array(s.filaments.enumerated()), id: \.offset) { i, f in
                            HStack(spacing: 8) {
                                ColorPicker("", selection: Binding(get: { Color(hex: f.color) }, set: { c in store.run("set_filament", ["index": i, "color": hex(c)]) }), supportsOpacity: false).labelsHidden().overlay(Text("\(i + 1)").font(.caption2).allowsHitTesting(false))
                                Button { pick = PickTarget(type: "filament", current: f.name, index: i) } label: { Text(f.name).lineLimit(1).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading).padding(.horizontal, 8).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8)) }.foregroundStyle(.primary)
                                if s.filaments.count > 1 { Button { store.run("remove_filament", ["index": i]) } label: { Image(systemName: "minus.circle").frame(width: 40, height: 40) } }
                            }
                        }
                        Picker("", selection: $mode) { Text(tr("Process")).tag(0); Text(tr("Objects")).tag(1) }.pickerStyle(.segmented)
                        if mode == 0 {
                            HStack { header("Process", "slider.horizontal.3") { settings = "process" } }
                            presetButton(s.process) { pick = PickTarget(type: "process", current: s.process.name, index: 0) }
                            OptionPages(store: store, type: "process", object: nil)
                        } else { ObjectList(store: store) }
                    }
                }.padding(12)
            }
        }
        .sheet(item: $pick) { t in PresetPicker(store: store, type: t.type, current: t.current) { n in
            if t.type == "filament" { store.run("set_filament", ["index": t.index, "name": n]) } else { store.run("select_preset", ["type": t.type, "name": n]) { if t.type == "printer" { store.fit() } } } } }
        .sheet(isPresented: Binding(get: { settings != nil }, set: { if !$0 { settings = nil } })) { if let t = settings { SettingsSheet(store: store, type: t) } }
        .onAppear { if beds == nil { store.query(BedTypes.self, "bed_types") { beds = $0 } } }
    }
    private func header(_ t: String, _ icon: String, _ gear: @escaping () -> Void) -> some View {
        HStack { Image(systemName: icon); Text(tr(t)).font(.headline); Spacer(); Button(action: gear) { Image(systemName: "gearshape").frame(width: 44, height: 40) } }
    }
    private func presetButton(_ p: PresetRef, _ act: @escaping () -> Void) -> some View {
        Button(action: act) { HStack { Text((p.dirty ? "* " : "") + p.name).lineLimit(2).multilineTextAlignment(.leading); Spacer(); Image(systemName: "chevron.up.chevron.down") }.frame(minHeight: 44).padding(.horizontal, 10).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8)) }.foregroundStyle(p.dirty ? .orange : .primary)
    }
    private func hex(_ c: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        func q(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", q(r), q(g), q(b))
    }
}

struct SettingsSheet: View {
    @ObservedObject var store: Store
    let type: String
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var name = ""
    var body: some View {
        NavigationStack {
            ScrollView { OptionPages(store: store, type: type, object: nil).padding() }
                .navigationTitle(tr(type == "printer" ? "Printer" : type == "filament" ? "Filament" : "Process"))
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button(tr("Save")) { name = type == "printer" ? store.state?.printer.name ?? "" : type == "process" ? store.state?.process.name ?? "" : store.state?.filaments.first?.name ?? ""; name += " - Copy"; saving = true }
                        Button(tr("Discard")) { store.run("discard_preset", ["type": type]) }
                        Button(tr("Delete"), role: .destructive) { store.run("delete_preset", ["type": type]) }
                    }
                    ToolbarItem(placement: .topBarTrailing) { Button(tr("Close")) { dismiss() } }
                }
                .alert(tr("Save preset"), isPresented: $saving) { TextField("", text: $name); Button("OK") { store.run("save_preset", ["type": type, "name": name]) }; Button(tr("Cancel"), role: .cancel) {} }
        }
    }
}

/// Pages and groups as in the desktop Tab.cpp; object != nil edits per-object overrides.
struct OptionPages: View {
    @ObservedObject var store: Store
    let type: String
    let object: Int?
    @State private var options: [String: OptionS] = [:]
    @State private var page = ""
    @State private var search = ""
    @State private var advanced = false
    private static let objectPages: Set<String> = ["Quality", "Strength", "Speed", "Support"]
    private var pages: [LayoutPage] { (store.layout[type] ?? []).filter { object == nil || Self.objectPages.contains($0.title) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { TextField(tr("Search"), text: $search).textFieldStyle(.roundedBorder).frame(height: 40).autocorrectionDisabled(); Toggle(tr("Advanced"), isOn: $advanced).toggleStyle(.button) }
            if search.isEmpty { ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(pages) { p in Button(tr(p.title)) { page = p.title }.buttonStyle(.bordered).tint(p.title == current ? Color(hex: "#00AE42") : .gray) } } } }
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(visible) { g in
                    if !g.title.isEmpty { Text(tr(g.title)).font(.subheadline.bold()).padding(.top, 6) }
                    ForEach(g.options, id: \.self) { k in if let o = options[k] {
                        OptionRow(key: k, option: o, overridden: object.map { i in store.state?.objects.indices.contains(i) == true && store.state!.objects[i].config[k] != nil } ?? (o.dirty == true),
                                  set: { set(k, $0) }, reset: { reset(k) }) } }
                }
            }
        }.onAppear(perform: load).onChange(of: store.state?.process.name) { load() }.onChange(of: store.state?.printer.name) { load() }.onChange(of: store.state?.filaments.first?.name) { load() }.onChange(of: object) { load() }.onChange(of: store.state?.path) { load() }
    }
    private var current: String { pages.contains { $0.title == page } ? page : pages.first?.title ?? "" }
    private var visible: [LayoutGroup] {
        let src = search.isEmpty ? pages.filter { $0.title == current } : pages
        return src.flatMap(\.groups).map { g in LayoutGroup(title: g.title, options: g.options.filter { k in
            guard let o = options[k] else { return false }
            if !search.isEmpty { return k.contains(search.lowercased()) || tr(o.label).localizedCaseInsensitiveContains(search) }
            return advanced || o.mode == 0 || (o.dirty == true)
        }) }.filter { !$0.options.isEmpty }
    }
    private func load() {
        store.query([String: OptionS].self, "options", ["type": type]) { o in
            options = o
            if let i = object, let c = store.state?.objects.indices.contains(i) == true ? store.state?.objects[i].config : nil { for (k, v) in c { options[k]?.value = v } }
        }
    }
    private func set(_ k: String, _ v: String) {
        if let i = object { store.run("set_option", ["type": "object", "o": i, "key": k, "value": v], then: load) } else { store.run("set_option", ["type": type, "key": k, "value": v], then: load) }
    }
    private func reset(_ k: String) { if let i = object { store.run("clear_object_option", ["o": i, "key": k], then: load) } else { store.run("reset_option", ["type": type, "key": k], then: load) } }
}

struct OptionRow: View {
    let key: String, option: OptionS, overridden: Bool, set: (String) -> Void, reset: () -> Void
    @State private var text = ""
    @State private var tip = false
    @FocusState private var focus: Bool
    var body: some View {
        HStack(spacing: 6) {
            Button { tip = true } label: { Text(tr(option.label.isEmpty ? key : option.label)).font(.callout).foregroundStyle(overridden ? .orange : .primary).multilineTextAlignment(.leading) }
                .popover(isPresented: $tip) { ScrollView { Text(tr(option.tooltip)).padding() }.frame(width: 340).frame(maxHeight: 320) }
            Spacer(minLength: 4)
            if overridden { Button(action: reset) { Image(systemName: "arrow.uturn.backward.circle").frame(width: 34, height: 40) } }
            control
        }.frame(minHeight: 44)
    }
    @ViewBuilder private var control: some View {
        let single = !option.value.contains(",")
        if option.readonly { Text(option.value).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
        else if option.type == "bool" && single { Toggle("", isOn: Binding(get: { option.value == "1" }, set: { set($0 ? "1" : "0") })).labelsHidden() }
        else if let v = option.values, option.type == "enum", single {
            Picker("", selection: Binding(get: { option.value }, set: { set($0) })) { ForEach(Array(v.enumerated()), id: \.offset) { i, x in Text(tr(option.labels?.indices.contains(i) == true ? option.labels![i] : x)).tag(x) } }.frame(maxWidth: 170)
        } else {
            TextField("", text: $text, axis: option.multiline ? .vertical : .horizontal).lineLimit(option.multiline ? 4 : 1).keyboardType(option.type == "string" ? .default : .numbersAndPunctuation).autocorrectionDisabled().textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder).frame(width: option.type == "string" ? 170 : 92).frame(minHeight: 40).focused($focus).onSubmit(send).onAppear { text = option.value }.onChange(of: option.value) { if !focus { text = option.value } }.onChange(of: focus) { if !focus { send() } }
            if !option.unit.isEmpty { Text(tr(option.unit)).font(.caption2).foregroundStyle(.secondary).frame(width: 34, alignment: .leading) }
        }
    }
    private func send() {
        let v = option.type == "string" ? text : text.replacingOccurrences(of: " ", with: "")
        if v != option.value { set(v); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if !focus { text = option.value } } }
    }
}

struct ObjectList: View {
    @ObservedObject var store: Store
    @State private var rename: ObjectS?
    @State private var name = ""
    @State private var simplify: (Int, Int)?
    @State private var ratio = 0.5
    @State private var override: Int?
    @State private var clone: Sel?
    @State private var count = "2"
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(store.state?.objects ?? []) { o in
                ForEach(o.instances) { i in instanceRow(o, i) }
                if o.volumes.count > 1 { ForEach(o.volumes) { v in volumeRow(o, v) } }
            }
            if store.state?.objects.isEmpty != false { Text(tr("No objects")).foregroundStyle(.secondary) }
        }
        .alert(tr("Rename"), isPresented: Binding(get: { rename != nil }, set: { if !$0 { rename = nil } })) { TextField("", text: $name); Button("OK") { if let r = rename { store.run("rename", ["o": r.index, "name": name]) } }; Button(tr("Cancel"), role: .cancel) {} }
        .alert(tr("Clone"), isPresented: Binding(get: { clone != nil }, set: { if !$0 { clone = nil } })) { TextField("", text: $count).keyboardType(.numberPad); Button("OK") { if let c = clone, let n = Int(count) { store.run("clone", ["o": c.o, "i": c.i, "n": n]) } }; Button(tr("Cancel"), role: .cancel) {} }
        .sheet(isPresented: Binding(get: { simplify != nil }, set: { if !$0 { simplify = nil } })) {
            VStack(spacing: 16) { Text(tr("Simplify model")).font(.headline); Slider(value: $ratio, in: 0.05...0.95); Text("\(Int(ratio * 100))%"); Button(tr("Apply")) { if let s = simplify { store.run("simplify", ["o": s.0, "v": s.1, "ratio": ratio]) }; simplify = nil }.buttonStyle(.borderedProminent) }.padding(24).presentationDetents([.height(240)])
        }
        .sheet(isPresented: Binding(get: { override != nil }, set: { if !$0 { override = nil } })) {
            if let i = override { NavigationStack { ScrollView { OptionPages(store: store, type: "process", object: i).padding() }.navigationTitle(store.state?.objects.indices.contains(i) == true ? store.state!.objects[i].name : "").toolbar { Button(tr("Close")) { override = nil } } } }
        }
    }
    private func extruderMenu(_ cur: Int, _ set: @escaping (Int) -> Void) -> some View {
        Menu { ForEach(Array((store.state?.filaments ?? []).enumerated()), id: \.offset) { k, f in Button("\(k + 1)  \(f.type)") { set(k + 1) } } } label: {
            Text("\(cur)").font(.caption.bold()).frame(width: 30, height: 30).background(Color(hex: store.state?.filaments.indices.contains(cur - 1) == true ? store.state!.filaments[cur - 1].color : "#888888"), in: RoundedRectangle(cornerRadius: 6)) }
    }
    private func instanceRow(_ o: ObjectS, _ i: InstanceS) -> some View {
        let s = Sel(o: o.index, i: i.index)
        return HStack(spacing: 4) {
            Button { store.selection = [s]; store.sceneStamp += 1; if i.plate >= 0 && i.plate != store.state?.current { store.run("plate_select", ["plate": i.plate]) { store.fit() } } } label: {
                VStack(alignment: .leading) { Text(o.name + (o.instances.count > 1 ? " #\(i.index + 1)" : "")).lineLimit(1); Text(i.plate >= 0 ? tr("Plate") + " \(i.plate + 1)" : tr("Outside")).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.foregroundStyle(o.config.isEmpty ? Color.primary : Color.orange)
            if i.index == 0 { extruderMenu(o.extruder) { store.run("extruder", ["o": o.index, "value": $0]) } }
            Button { store.run("printable", ["o": o.index, "i": i.index, "value": !i.printable]) } label: { Image(systemName: i.printable ? "eye" : "eye.slash").frame(width: 36, height: 44) }
            Menu {
                Button(tr("Rename")) { rename = o; name = o.name }
                Button(tr("Clone")) { clone = s }
                Button(tr("Object settings")) { override = o.index }
                if o.volumes.count == 1 { Button(tr("Simplify model")) { simplify = (o.index, 0) } }
                Menu(tr("Add part")) { shapes(o, 0) }
                Menu(tr("Add negative part")) { shapes(o, 1) }
                Menu(tr("Add modifier")) { shapes(o, 2) }
                Menu(tr("Add support blocker")) { shapes(o, 3) }
                Menu(tr("Add support enforcer")) { shapes(o, 4) }
                Button(tr("Delete"), role: .destructive) { store.selection = []; store.run("delete", ["ids": [[o.index, i.index]]]) }
            } label: { Image(systemName: "ellipsis").frame(width: 36, height: 44) }
        }.padding(.horizontal, 6).background(store.selection.contains(s) ? Color(hex: "#00AE42").opacity(0.22) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
    private func shapes(_ o: ObjectS, _ type: Int) -> some View { ForEach(["cube", "cylinder", "sphere", "cone"], id: \.self) { x in Button(tr(x.capitalized)) { store.run("add_shape", ["shape": x, "o": o.index, "type": type, "size": 10]) } } }
    private func volumeRow(_ o: ObjectS, _ v: VolumeS) -> some View {
        HStack {
            Image(systemName: ["cube", "minus.square", "square.dashed", "nosign", "checkmark.square"][min(4, max(0, v.type))]).foregroundStyle(.secondary)
            Text(v.name).lineLimit(1).font(.callout); Spacer()
            if v.type == 0 || v.type == 2 { extruderMenu(v.extruder) { store.run("extruder", ["o": o.index, "v": v.index, "value": $0]) } }
            Menu {
                Menu(tr("Change type")) { ForEach(Array(["Part", "Negative Part", "Modifier", "Support Blocker", "Support Enforcer"].enumerated()), id: \.offset) { t, n in Button(tr(n)) { store.run("volume_type", ["o": o.index, "v": v.index, "value": t]) } } }
                Button(tr("Simplify model")) { simplify = (o.index, v.index) }
                Button(tr("Delete"), role: .destructive) { store.run("delete_volume", ["o": o.index, "v": v.index]) }
            } label: { Image(systemName: "ellipsis").frame(width: 36, height: 40) }
        }.padding(.leading, 22)
    }
}
