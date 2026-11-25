import SwiftUI
import UniformTypeIdentifiers

@main struct TouchStudioApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup { RootView(store: store, scene: SceneController(store)).onOpenURL { store.open($0, geometry: $0.pathExtension.lowercased() != "3mf") } }
    }
}

struct ShareItem: Identifiable { let id = UUID(); let url: URL }
struct ExportSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController { UIDocumentPickerViewController(forExporting: [url], asCopy: true) }
    func updateUIViewController(_ v: UIDocumentPickerViewController, context: Context) {}
}

struct RootView: View {
    @ObservedObject var store: Store
    @State var scene: SceneController
    @StateObject private var printers = Printers()
    @State private var importing = false
    @State private var addGeometry = false
    @State private var export: ShareItem?
    @State private var confirmNew = false
    @State private var sending = false
    init(store: Store, scene: SceneController) { self.store = store; _scene = State(initialValue: scene) }
    static let types: [UTType] = ["3mf", "stl", "obj", "step", "stp", "oltp", "amf", "gltf", "glb", "fbx"].compactMap { UTType(filenameExtension: $0) } + [.data]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if store.tab == 2 { DeviceView(store: store, printers: printers) } else {
                HStack(spacing: 0) {
                    Group { if store.tab == 0 { Sidebar(store: store, scene: scene) } else { PreviewPanel(store: store) } }.frame(width: 330)
                    Divider()
                    ZStack(alignment: .top) {
                        SceneView(ctl: scene, stamp: store.sceneStamp)
                        if store.tab == 0 { VStack(spacing: 8) { Toolbar(store: store, scene: scene, addFile: { addGeometry = true; importing = true }); ToolPanel(store: store, scene: scene) }.padding(8) }
                        if store.tab == 1 && store.layerCount > 1 { HStack { Spacer(); LayerSlider(store: store) } }
                        VStack { Spacer(); PlateStrip(store: store, scene: scene) }
                        if store.slice.state == "slicing" { sliceProgress }
                        if store.busy && store.slice.state != "slicing" { ProgressView().controlSize(.large).padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)).padding(.top, 200).allowsHitTesting(false) }
                    }
                }
            }
        }
        .tint(Color(hex: "#00AE42"))
        .task { if ProcessInfo.processInfo.arguments.contains("--selftest") { await SelfTest(store).run() } }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.types) { r in
            switch r { case .success(let u): store.open(u, geometry: addGeometry); case .failure(let e): store.error = e.localizedDescription }
        }
        .sheet(item: $export) { ExportSheet(url: $0.url) }
        .sheet(isPresented: $sending) { SendView(store: store, printers: printers) }
        .alert(tr("Error"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") {} } message: { Text(store.error ?? "") }
        .confirmationDialog(tr("New Project"), isPresented: $confirmNew) { Button(tr("New Project"), role: .destructive) { store.selection = []; store.run("new") { store.fit() } } } message: { Text(tr("Unsaved changes will be lost.")) }
    }
    private var topBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button { if store.state?.modified == true { confirmNew = true } else { store.run("new") { store.fit() } } } label: { Label(tr("New Project"), systemImage: "doc") }
                Button { addGeometry = false; importing = true } label: { Label(tr("Open Project"), systemImage: "folder") }
                Button { addGeometry = true; importing = true } label: { Label(tr("Import"), systemImage: "square.and.arrow.down") }
                Divider()
                Button { store.tempExport(store.baseName + ".3mf", "save") { export = ShareItem(url: $0) } } label: { Label(tr("Save Project as"), systemImage: "square.and.arrow.up") }
                Button { store.tempExport(store.baseName + ".stl", "export_stl") { export = ShareItem(url: $0) } } label: { Label(tr("Export all objects as STL"), systemImage: "cube") }
            } label: { Image(systemName: "line.3.horizontal").frame(width: 44, height: 44) }
            Button { store.run("undo") } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }.disabled(store.state?.canUndo != true || store.busy)
            Button { store.run("redo") } label: { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44) }.disabled(store.state?.canRedo != true || store.busy)
            Picker("", selection: $store.tab) { Text(tr("Prepare")).tag(0); Text(tr("Preview")).tag(1); Text(tr("Device")).tag(2) }.pickerStyle(.segmented).frame(width: 330)
            Spacer()
            Text(store.baseName + (store.state?.modified == true ? " *" : "")).lineLimit(1).foregroundStyle(.secondary)
            Spacer()
            Button { store.startSlice() } label: { Label(tr("Slice plate"), systemImage: "square.3.layers.3d").frame(minHeight: 32) }.buttonStyle(.borderedProminent).disabled(store.slice.state == "slicing" || store.busy || store.state?.objects.isEmpty != false)
            Menu {
                Button { sending = true } label: { Label(tr("Print plate"), systemImage: "printer") }
                Button { store.tempExport("\(store.baseName)_plate_\((store.state?.current ?? 0) + 1).gcode.3mf", "export_gcode3mf") { export = ShareItem(url: $0) } } label: { Label(tr("Export plate sliced file"), systemImage: "doc.zipper") }
                Button { store.tempExport("\(store.baseName)_plate_\((store.state?.current ?? 0) + 1).gcode", "export_gcode") { export = ShareItem(url: $0) } } label: { Label(tr("Export G-code"), systemImage: "doc.text") }
            } label: { Label(tr("Export"), systemImage: "paperplane").frame(minHeight: 32) }.buttonStyle(.bordered).disabled(!sliced)
        }.padding(.horizontal, 10).frame(height: 56)
    }
    private var sliced: Bool { guard let s = store.state, s.plates.indices.contains(s.current) else { return false }; return s.plates[s.current].sliced && store.slice.state != "slicing" }
    private var sliceProgress: some View {
        VStack(spacing: 10) {
            ProgressView(value: Double(max(0, min(100, store.slice.percent ?? 0))), total: 100)
            Text("\(store.slice.percent ?? 0)%  \(tr(store.slice.text ?? ""))").font(.callout).lineLimit(1)
            Button(tr("Cancel"), role: .cancel) { store.engine.cancelSlice() }.buttonStyle(.bordered)
        }.padding(18).frame(width: 360).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)).padding(.top, 120)
    }
}

struct PlateStrip: View {
    @ObservedObject var store: Store
    let scene: SceneController
    @State private var rename: PlateS?
    @State private var name = ""
    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.state?.plates ?? []) { p in
                        Button { store.run("plate_select", ["plate": p.index]) { store.fit(); if store.tab == 1 { store.loadPreview(force: true) } } } label: {
                            HStack { Text(p.name.isEmpty ? "\(p.index + 1)" : "\(p.index + 1) \(p.name)"); if p.sliced { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) } }.frame(minWidth: 44, minHeight: 36).padding(.horizontal, 8)
                        }
                        .background(p.index == store.state?.current ? Color(hex: "#00AE42").opacity(0.3) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        .contextMenu {
                            Button(tr("Rename")) { rename = p; name = p.name }
                            Button(tr("Delete"), role: .destructive) { store.run("plate_remove", ["plate": p.index]) { store.fit() } }
                        }
                    }
                    if store.tab == 0 { Button { store.run("plate_add") { store.fit() } } label: { Image(systemName: "plus").frame(width: 44, height: 36) }.background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10)) }
                }
            }.fixedSize(horizontal: false, vertical: true)
            Menu {
                Button(tr("Top")) { scene.look(yaw: -.pi / 2, pitch: 1.56) }
                Button(tr("Front")) { scene.look(yaw: -.pi / 2, pitch: 0.02) }
                Button(tr("Left")) { scene.look(yaw: .pi, pitch: 0.02) }
                Button(tr("Right")) { scene.look(yaw: 0, pitch: 0.02) }
                Button(tr("Rear")) { scene.look(yaw: .pi / 2, pitch: 0.02) }
                Button(tr("Default")) { scene.fit() }
            } label: { Image(systemName: "cube.transparent").frame(width: 44, height: 36).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10)) }
        }.padding(10)
        .alert(tr("Rename"), isPresented: Binding(get: { rename != nil }, set: { if !$0 { rename = nil } })) {
            TextField("", text: $name); Button("OK") { if let p = rename { store.run("plate_rename", ["plate": p.index, "name": name]) } }; Button(tr("Cancel"), role: .cancel) {}
        }
    }
}

struct Toolbar: View {
    @ObservedObject var store: Store
    let scene: SceneController
    let addFile: () -> Void
    private func b(_ icon: String, _ label: String, on: Bool = false, enabled: Bool = true, _ act: @escaping () -> Void) -> some View {
        Button(action: act) { VStack(spacing: 2) { Image(systemName: icon).font(.system(size: 19)); Text(tr(label)).font(.system(size: 9)).lineLimit(1) }.frame(width: 70, height: 44) }
            .accessibilityLabel(tr(label)).background(on ? Color(hex: "#00AE42").opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 8)).disabled(!enabled || store.busy)
    }
    private func toggle(_ t: Tool) { if t == .cut, let (_, i, _) = store.single { store.cutZ = (i.min[2] + i.max[2]) / 2; store.cutTilt = .zero }; if t.paintKind != nil { store.paintState = 1 }; store.tool = store.tool == t ? .none : t }
    var body: some View {
        let one = store.single, any = !store.selection.isEmpty, has = store.state?.objects.isEmpty == false
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                b("plus.square", "Add", addFile)
                Menu { ForEach(["cube", "cylinder", "sphere", "cone"], id: \.self) { s in Button(tr(s.capitalized)) { store.run("add_shape", ["shape": s]) } } } label: { VStack(spacing: 2) { Image(systemName: "shippingbox").font(.system(size: 19)); Text(tr("Add Primitive")).font(.system(size: 9)).lineLimit(1) }.frame(width: 70, height: 44) }
                b("wand.and.rays", "Auto orient", enabled: one != nil) { if let s = one?.2 { store.run("auto_orient", ["o": s.o]) } }
                b("square.grid.3x3.square", "Arrange", enabled: has) { store.run("arrange") }
                b("square.grid.3x3.fill.square", "Arrange all", enabled: has) { store.run("arrange", ["all": true]) { store.fit() } }
                b("square.on.square", "Clone", enabled: one != nil) { if let s = one?.2 { store.run("clone", ["o": s.o, "i": s.i]) } }
                b("rectangle.split.2x1", "Split to objects", enabled: one != nil) { if let s = one?.2 { store.run("split_objects", ["o": s.o]) } }
                b("rectangle.split.3x1", "Split to parts", enabled: one != nil) { if let s = one?.2 { store.run("split_parts", ["o": s.o]) } }
                b("link", "Assemble", enabled: store.selection.count > 1) { let l = Array(Set(store.selection.map(\.o))); store.selection = []; store.run("merge", ["ids": l]) }
                b("trash", "Delete", enabled: any) { let ids = store.ids(); store.selection = []; store.run("delete", ["ids": ids]) }
            }
            HStack(spacing: 2) {
                b("arrow.up.and.down.and.arrow.left.and.right", "Move", on: store.tool == .move, enabled: one != nil) { toggle(.move) }
                b("rotate.3d", "Rotate", on: store.tool == .rotate, enabled: one != nil) { toggle(.rotate) }
                b("arrow.up.left.and.arrow.down.right", "Scale", on: store.tool == .scale, enabled: one != nil) { toggle(.scale) }
                b("square.bottomhalf.filled", "Lay on face", on: store.tool == .layflat, enabled: has) { toggle(.layflat) }
                b("scissors", "Cut", on: store.tool == .cut, enabled: one != nil) { toggle(.cut) }
                b("paintbrush.pointed", "Supports Painting", on: store.tool == .support, enabled: has) { toggle(.support) }
                b("paintbrush", "Seam painting", on: store.tool == .seam, enabled: has) { toggle(.seam) }
                b("paintpalette", "Color Painting", on: store.tool == .color, enabled: has) { toggle(.color) }
            }
        }.padding(5).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct NumField: View {
    let title: String, value: Double, commit: (Double) -> Void
    @State private var text = ""
    @FocusState private var focus: Bool
    var body: some View {
        HStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary).fixedSize()
            TextField("", text: $text).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder).frame(width: 76, height: 40).focused($focus).onSubmit(send)
        }
        .onAppear { text = fmt(value) }.onChange(of: value) { if !focus { text = fmt(value) } }.onChange(of: focus) { if !focus { send() } }
    }
    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
    private func send() { if let v = Double(text.replacingOccurrences(of: ",", with: ".")), abs(v - value) > 0.004 { commit(v) } else { text = fmt(value) } }
}

struct ToolPanel: View {
    @ObservedObject var store: Store
    let scene: SceneController
    @State private var uniform = true
    @State private var keepUp = true
    @State private var keepLow = true
    @State private var asParts = false
    var body: some View {
        Group {
            if let k = store.tool.paintKind { paint(k) }
            else if store.tool == .layflat { Text(tr("Lay on face") + " …").padding(12) }
            else if let (o, i, s) = store.single {
                switch store.tool {
                case .move: HStack { xyz(i.offset) { store.transform(s, ["offset": $0, "drop": false]) }; Button(tr("Center")) { store.run("center", ["o": s.o, "i": s.i]) }.buttonStyle(.bordered); Button("Z=0") { store.transform(s, ["drop": true]) }.buttonStyle(.bordered) }.padding(10)
                case .rotate:
                    VStack { xyz(i.rotation) { store.transform(s, ["rotation": $0]) }
                        HStack { ForEach(0..<3, id: \.self) { a in ForEach([-45, 45, 90], id: \.self) { d in Button("\(["X", "Y", "Z"][a]) \(d)°") { store.transform(s, ["rotateWorld": [a == 0 ? 1 : 0, a == 1 ? 1 : 0, a == 2 ? 1 : 0], "degrees": d]) }.buttonStyle(.bordered).controlSize(.small) } } } }.padding(10)
                case .scale:
                    VStack {
                        HStack { Text("%").frame(width: 24); xyz(i.scale.map { $0 * 100 }) { v in scale(s, i.scale, v.map { $0 / 100 }) } }
                        HStack { Text("mm").frame(width: 24); xyz((0..<3).map { i.max[$0] - i.min[$0] }) { v in scale(s, i.scale, (0..<3).map { k in let d = i.max[k] - i.min[k]; return d > 0.001 ? i.scale[k] * v[k] / d : i.scale[k] }) } }
                        HStack { Toggle(tr("uniform scale"), isOn: $uniform).frame(width: 190); ForEach(0..<3, id: \.self) { a in Button(tr("Mirror") + " " + ["X", "Y", "Z"][a]) { store.transform(s, ["mirror": a]) }.buttonStyle(.bordered) } }
                    }.padding(10)
                case .cut: cut(o, i, s)
                default: EmptyView()
                }
            }
        }.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    private func xyz(_ v: [Double], _ set: @escaping ([Double]) -> Void) -> some View {
        HStack { ForEach(0..<3, id: \.self) { k in NumField(title: ["X", "Y", "Z"][k], value: v[k]) { n in var c = v; c[k] = n; set(c) } } }
    }
    private func scale(_ s: Sel, _ old: [Double], _ new: [Double]) {
        var n = new
        if uniform, let k = (0..<3).first(where: { abs(new[$0] - old[$0]) > 1e-6 }), old[k] > 0 { n = old.map { $0 * new[k] / old[k] } }
        store.transform(s, ["scale": n])
    }
    private func cut(_ o: ObjectS, _ i: InstanceS, _ s: Sel) -> some View {
        VStack {
            HStack { Text("Z"); Slider(value: $store.cutZ, in: i.min[2]...max(i.max[2], i.min[2] + 0.01)).frame(width: 260); NumField(title: "mm", value: store.cutZ) { store.cutZ = $0 } }
            HStack { Text("X°"); Slider(value: $store.cutTilt.x, in: -90...90).frame(width: 150); Text("Y°"); Slider(value: $store.cutTilt.y, in: -90...90).frame(width: 150) }
            HStack {
                Toggle(tr("Upper part"), isOn: $keepUp); Toggle(tr("Lower part"), isOn: $keepLow); Toggle(tr("Cut to parts"), isOn: $asParts)
                Button(tr("Perform cut")) {
                    let (p, n) = scene.cutPlane(i)
                    store.run("cut", ["o": s.o, "i": s.i, "point": [Double(p.x), Double(p.y), Double(p.z)], "normal": [Double(n.x), Double(n.y), Double(n.z)], "upper": keepUp, "lower": keepLow, "parts": asParts]) { store.selection = []; store.tool = .none }
                }.buttonStyle(.borderedProminent).disabled(!keepUp && !keepLow)
            }.toggleStyle(.button)
        }.padding(10)
    }
    private func paint(_ kind: Int) -> some View {
        VStack(spacing: 8) {
            HStack {
                Picker("", selection: $store.paintTool) { Text(tr("Circle")).tag("circle"); Text(tr("Sphere")).tag("sphere"); Text(tr("Fill")).tag("fill"); Text(tr("Triangle")).tag("triangle") }.pickerStyle(.segmented).frame(width: 320)
                Text(tr("Pen size")); Slider(value: $store.paintRadius, in: 0.4...10).frame(width: 120)
            }
            HStack {
                if kind == 2 { ForEach(Array((store.state?.filaments ?? []).enumerated()), id: \.offset) { k, f in
                    Button { store.paintState = k + 1 } label: { Circle().fill(Color(hex: f.color)).frame(width: 34, height: 34).overlay(Circle().stroke(store.paintState == k + 1 ? Color(hex: "#00AE42") : .gray, lineWidth: store.paintState == k + 1 ? 4 : 1)).overlay(Text("\(k + 1)").font(.caption2)) } } }
                else { Picker("", selection: $store.paintState) { Text(tr(kind == 0 ? "Enforce supports" : "Enforce seam")).tag(1); Text(tr(kind == 0 ? "Block supports" : "Block seam")).tag(2) }.pickerStyle(.segmented).frame(width: 300).onAppear { if store.paintState > 2 { store.paintState = 1 } } }
                Button(tr("Erase")) { store.paintState = 0 }.buttonStyle(.bordered).tint(store.paintState == 0 ? .red : nil)
                if let s = store.single?.2 {
                    if kind == 0 { Button(tr("Auto")) { store.run("paint_overhang", ["o": s.o, "i": s.i]) }.buttonStyle(.bordered) }
                    Button(tr("Erase all painting"), role: .destructive) { store.run("paint_clear", ["o": s.o, "kind": kind]) }.buttonStyle(.bordered)
                }
                Button(tr("Done")) { store.tool = .none; store.run("state") }.buttonStyle(.borderedProminent)
            }
        }.padding(10)
    }
}

struct LayerSlider: View {
    @ObservedObject var store: Store
    var body: some View {
        let n = Double(max(1, store.layerCount - 1))
        VStack(spacing: 6) {
            Text("\(Int(store.layerHigh) + 1)").font(.callout.monospacedDigit())
            GeometryReader { g in
                let h = g.size.height
                ZStack(alignment: .top) {
                    Capsule().fill(.gray.opacity(0.4)).frame(width: 8)
                    knob.offset(y: h * (1 - store.layerHigh / n) - 22).gesture(DragGesture(coordinateSpace: .named("bar")).onChanged { v in store.layerHigh = max(store.layerLow, min(n, ((1 - v.location.y / h) * n).rounded())) })
                    knob.offset(y: h * (1 - store.layerLow / n) - 22).gesture(DragGesture(coordinateSpace: .named("bar")).onChanged { v in store.layerLow = min(store.layerHigh, max(0, ((1 - v.location.y / h) * n).rounded())) })
                }.frame(maxWidth: .infinity).coordinateSpace(name: "bar")
            }
            Text("\(Int(store.layerLow) + 1)").font(.callout.monospacedDigit())
            Stepper("", value: Binding(get: { store.layerHigh }, set: { store.layerHigh = max(store.layerLow, min(n, $0)) })).labelsHidden().rotationEffect(.degrees(-90)).frame(height: 90)
        }.frame(width: 64).padding(.vertical, 20).padding(.bottom, 60)
    }
    private var knob: some View { Circle().fill(Color(hex: "#00AE42")).frame(width: 28, height: 28).frame(width: 44, height: 44).contentShape(Rectangle()) }
}

struct PreviewPanel: View {
    @ObservedObject var store: Store
    private func time(_ s: Double) -> String { let m = Int(s / 60); return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m \(Int(s) % 60)s" }
    var body: some View {
        List {
            Picker(tr("Color scheme"), selection: $store.colorBy) { Text(tr("Line Type")).tag(0); Text(tr("Filament")).tag(1); Text(tr("Speed")).tag(2); Text(tr("Layer Height")).tag(3); Text(tr("Line Width")).tag(4) }
            Toggle(tr("Travel"), isOn: $store.showTravel)
            if store.slice.state == "done", store.slice.plate == store.state?.current, store.state?.plates[store.state!.current].sliced == true {
                Section(tr("Total estimation")) {
                    row("Total time", time(store.slice.time ?? 0)); row("Prepare time", time(store.slice.prepare ?? 0))
                    row("Filament", String(format: "%.2f g  ·  %.2f m", store.slice.weight ?? 0, (store.slice.length ?? 0) / 1000))
                    row("Cost", String(format: "%.2f", store.slice.cost ?? 0)); row("Layer", "\(store.slice.layers ?? 0)"); row("Filament change times", "\(store.slice.toolchanges ?? 0)")
                }
                if let r = store.slice.roles { Section(tr("Line Type")) { ForEach(r.sorted { $0[1] > $1[1] }, id: \.self) { x in
                    if x.count == 2, Int(x[0]) < roleNames.count { HStack { RoundedRectangle(cornerRadius: 3).fill(Color(hex: roleColors[Int(x[0])])).frame(width: 18, height: 18); Text(tr(roleNames[Int(x[0])])); Spacer(); Text(time(x[1])).monospacedDigit() } } } } }
                if let w = store.slice.warnings, !w.isEmpty { Section(tr("Warning")) { ForEach(w, id: \.self) { Text($0).foregroundStyle(.orange) } } }
                if let c = store.slice.conflict, !c.isEmpty { Text(c).foregroundStyle(.red) }
            } else { Text(tr("Slice plate") + " …").foregroundStyle(.secondary) }
        }.listStyle(.insetGrouped)
    }
    private func row(_ a: String, _ b: String) -> some View { HStack { Text(tr(a)); Spacer(); Text(b).monospacedDigit() } }
}
