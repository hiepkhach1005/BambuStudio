# PARITY.md - Ma trận tính năng Bambu Studio (desktop) cho iPadOS 18

Mục tiêu: port SwiftUI cho iPadOS 18 với đầy đủ tính năng và CÙNG bố cục như bản desktop.

## Phạm vi và cách đọc tài liệu

- Snapshot mã nguồn: commit `23a337589` (HEAD của `feature/touch-ipad`). Các số dòng dưới đây tham chiếu theo HEAD. Working tree hiện có 13 file sửa chưa commit (ví dụ `Plater.cpp`, `Preferences.cpp`, `GUI_App.cpp`); nếu đọc theo working tree, số dòng có thể lệch.
- Ký hiệu cột "Phụ thuộc desktop": `wx`, `OpenGL`, `network plugin` (plugin đóng dlopen), `subprocess`, `none`. Có thể ghép bằng `+`.
- Cột "iPad khả thi": `yes`, `LAN only` (chỉ khi máy in ở chế độ LAN), `no`, `unclear`.
- Cột "Trạng thái": tất cả hiện là `todo`.
- Bambu cloud dùng plugin đóng được nạp bằng dlopen/LoadLibrary (`src/slic3r/Utils/NetworkAgent.cpp:283`, `:291`, `:31`). Mọi tính năng cloud được đánh `no` trên iPad.
- Mở/lưu file phải đi qua ứng dụng Files của iPadOS (UIDocumentPicker), không dùng đường dẫn tuyệt đối của hệ điều hành.
- Loại file `FileType` và bảng wildcard nằm ở `src/slic3r/GUI/GUI_App.hpp:109-128` và `src/slic3r/GUI/GUI_App.cpp:831-867`.

---

## 1. Tab chính trên thanh panel (MainFrame)

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Tab Prepare (3D editor) | src/slic3r/GUI/MainFrame.cpp:1162 | wx + OpenGL | yes | todo |
| Tab Preview | src/slic3r/GUI/MainFrame.cpp:1163 | wx + OpenGL | yes | todo |
| Tab Home (WebView trang chủ) | src/slic3r/GUI/MainFrame.cpp:1641 | wx (WebView) + network plugin | no | todo |
| Tab Device (Monitor) | src/slic3r/GUI/MainFrame.cpp:1669 | wx + network plugin | LAN only | todo |
| Tab Multi-device | src/slic3r/GUI/MainFrame.cpp:1688 | wx + network plugin | unclear | todo |
| Tab Project | src/slic3r/GUI/MainFrame.cpp:1695 | wx | yes | todo |
| Tab Calibration | src/slic3r/GUI/MainFrame.cpp:1702 (cũng 1392) | wx + network plugin (gửi lệnh tới máy) | LAN only | todo |
| Tab Filament Manager (web) | src/slic3r/GUI/MainFrame.cpp:1708 | wx (WebView) + network plugin | no | todo |
| Chuyển tab theo panel | src/slic3r/GUI/MainFrame.cpp:4462 (select_tab(wxPanel*)), :4517 (select_tab(size_t)) | wx | yes | todo |
| Tạo tab preset (Print/Filament/Printer) | src/slic3r/GUI/MainFrame.cpp:1834 (create_preset_tabs), :1859 (add_created_tab) | wx | yes | todo |
| Bật/tắt mục Calibration trên menu bar | src/slic3r/GUI/MainFrame.cpp:1362-1368 | wx | yes | todo |

## 2. Menu bar và topbar (MainFrame)

### 2.1 File

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| New Project | src/slic3r/GUI/MainFrame.cpp:3182 | wx | yes | todo |
| Open Project | src/slic3r/GUI/MainFrame.cpp:3188 | wx + file dialog | yes (qua Files app) | todo |
| Recent projects (submenu) | src/slic3r/GUI/MainFrame.cpp:3198 | wx | yes | todo |
| Save Project | src/slic3r/GUI/MainFrame.cpp:3219 | wx + file dialog | yes (qua Files app) | todo |
| Save Project as | src/slic3r/GUI/MainFrame.cpp:3230 | wx + file dialog | yes (qua Files app) | todo |
| Show Project in Folder | src/slic3r/GUI/MainFrame.cpp:3239 | subprocess (Finder) | no | todo |
| Import 3MF/STL/STEP/SVG/OBJ/AMF | src/slic3r/GUI/MainFrame.cpp:3259 | wx + file dialog | yes (qua Files app) | todo |
| Import Configs | src/slic3r/GUI/MainFrame.cpp:3264 | wx + file dialog | yes (qua Files app) | todo |
| Export all objects as one STL | src/slic3r/GUI/MainFrame.cpp:3273 | wx + file dialog | yes (qua Files app) | todo |
| Export all objects as STLs | src/slic3r/GUI/MainFrame.cpp:3276 | wx + file dialog | yes (qua Files app) | todo |
| Export Generic 3MF | src/slic3r/GUI/MainFrame.cpp:3279 | wx + file dialog | yes (qua Files app) | todo |
| Export plate sliced file | src/slic3r/GUI/MainFrame.cpp:3283 | wx + file dialog | yes (qua Files app) | todo |
| Export all plate sliced file | src/slic3r/GUI/MainFrame.cpp:3287 | wx + file dialog | yes (qua Files app) | todo |
| Export G-code | src/slic3r/GUI/MainFrame.cpp:3291 | wx + file dialog | yes (qua Files app) | todo |
| Export toolpaths as OBJ | src/slic3r/GUI/MainFrame.cpp:3295 | wx + file dialog | yes (qua Files app) | todo |
| Quit | src/slic3r/GUI/MainFrame.cpp:3339 (Mac: :3342) | wx | no (iPad không có menu Quit) | todo |

### 2.2 Edit

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Undo | src/slic3r/GUI/MainFrame.cpp:3368 | wx | yes | todo |
| Redo | src/slic3r/GUI/MainFrame.cpp:3372 | wx | yes | todo |
| Cut | src/slic3r/GUI/MainFrame.cpp:3377 | wx | yes | todo |
| Copy | src/slic3r/GUI/MainFrame.cpp:3381 | wx | yes | todo |
| Paste | src/slic3r/GUI/MainFrame.cpp:3385 | wx | yes | todo |
| Delete selected | src/slic3r/GUI/MainFrame.cpp:3389 | wx | yes | todo |
| Delete all | src/slic3r/GUI/MainFrame.cpp:3393 | wx | yes | todo |
| Clone selected | src/slic3r/GUI/MainFrame.cpp:3398 | wx | yes | todo |
| Select all | src/slic3r/GUI/MainFrame.cpp:3505 | wx | yes | todo |
| Deselect all | src/slic3r/GUI/MainFrame.cpp:3517 | wx | yes | todo |

### 2.3 View

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Camera view menu (Default, Top, Bottom, Front, Rear, Left, Right, Isometric 1-3, Fit Camera) | src/slic3r/GUI/MainFrame.cpp:3124-3163 (add_common_view_menu_items) | wx + OpenGL | yes | todo |
| Camera fullscreen | src/slic3r/GUI/MainFrame.cpp:3575 | wx + OpenGL (macOS: CameraFullscreenMac.mm) | unclear | todo |
| Use Perspective View / Use Orthogonal View | src/slic3r/GUI/MainFrame.cpp:3588, :3594 | wx + OpenGL | yes | todo |
| Show Labels by Layer | src/slic3r/GUI/MainFrame.cpp:3622 | wx + OpenGL | yes | todo |
| Show Overhang | src/slic3r/GUI/MainFrame.cpp:3644 | wx + OpenGL | yes | todo |
| Show Wireframe | src/slic3r/GUI/MainFrame.cpp:3670 | wx + OpenGL | yes | todo |
| Các mục View khác có dòng 3604, 3612, 3651 (chưa đọc nhãn) | src/slic3r/GUI/MainFrame.cpp:3604, :3612, :3651 | wx | unclear | todo |

### 2.4 Help

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Keyboard Shortcuts (Shift+?) | src/slic3r/GUI/MainFrame.cpp:3032, :3035 | wx | yes | todo |
| Setup Wizard | src/slic3r/GUI/MainFrame.cpp:3039 | wx | yes | todo |
| Show Configuration Folder | src/slic3r/GUI/MainFrame.cpp:3043 | subprocess (Finder) | no | todo |
| Show Log Folder | src/slic3r/GUI/MainFrame.cpp:3046 | subprocess (Finder) | no | todo |
| Show Tip of the Day | src/slic3r/GUI/MainFrame.cpp:3049 | wx | yes | todo |
| Report issue | src/slic3r/GUI/MainFrame.cpp:3054 | network (web) | unclear | todo |
| Check for Update | src/slic3r/GUI/MainFrame.cpp:3065 | network plugin | no | todo |
| Check for Presets Update | src/slic3r/GUI/MainFrame.cpp:3072 | network plugin | no | todo |
| Open Network Test | src/slic3r/GUI/MainFrame.cpp:3076 | network plugin | LAN only | todo |
| About | src/slic3r/GUI/MainFrame.cpp:3084 | wx | yes | todo |

### 2.5 Publish, Calibration, Preferences (topbar)

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Upload Models (publish) | src/slic3r/GUI/MainFrame.cpp:3095 | network plugin (cloud) | no | todo |
| Download Models | src/slic3r/GUI/MainFrame.cpp:3111 | network plugin (cloud) | no | todo |
| Menu Calibration (topbar): Temperature | src/slic3r/GUI/MainFrame.cpp:3872 | wx | LAN only | todo |
| Calibration: Flow rate (Coarse/Fine) | src/slic3r/GUI/MainFrame.cpp:3879, :3881, :3884 | wx | LAN only | todo |
| Calibration: Pressure advance | src/slic3r/GUI/MainFrame.cpp:3888 | wx | LAN only | todo |
| Calibration: Retraction test | src/slic3r/GUI/MainFrame.cpp:3895 | wx | LAN only | todo |
| Calibration: More (Max flowrate, VFA) | src/slic3r/GUI/MainFrame.cpp:3904, :3907, :3920 | wx | LAN only | todo |
| Calibration: Tutorial | src/slic3r/GUI/MainFrame.cpp:3935 | wx | yes | todo |
| Menu Calibration (m_calib_menu, chèn vào menu bar tại MainFrame.cpp:1366) | src/slic3r/GUI/MainFrame.cpp:3960-4040 | wx | LAN only | todo |
| Preferences (topbar) | src/slic3r/GUI/MainFrame.cpp:3708 | wx | yes | todo |
| Apple menu Preferences (macOS) | src/slic3r/GUI/MainFrame.cpp:3692 | wx (macOS) | no | todo |

---

## 3. Thanh công cụ 3D (GLCanvas3D)

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Khởi tạo toolbar (dispatcher) | src/slic3r/GUI/GLCanvas3D.cpp:8099 (_init_toolbars) | OpenGL | yes | todo |
| Main toolbar | src/slic3r/GUI/GLCanvas3D.cpp:8125 (_init_main_toolbar) | OpenGL + wx | yes | todo |
| Nút Add (nhập model) | src/slic3r/GUI/GLCanvas3D.cpp:8184 | OpenGL | yes (qua Files app) | todo |
| Nút Add plate | src/slic3r/GUI/GLCanvas3D.cpp:8195 | OpenGL | yes | todo |
| Nút Auto orient | src/slic3r/GUI/GLCanvas3D.cpp:8207 | OpenGL | yes | todo |
| Nút Arrange | src/slic3r/GUI/GLCanvas3D.cpp:8231 | OpenGL | yes | todo |
| Nút Layers editing | src/slic3r/GUI/GLCanvas3D.cpp:8257 | OpenGL | yes | todo |
| Nút Split to objects | src/slic3r/GUI/GLCanvas3D.cpp:8309 | OpenGL | yes | todo |
| Nút Split to parts | src/slic3r/GUI/GLCanvas3D.cpp:8330 | OpenGL | yes | todo |
| Nút More (mở rộng) | src/slic3r/GUI/GLCanvas3D.cpp:8361 | OpenGL | yes | todo |
| Nút Assembly view | src/slic3r/GUI/GLCanvas3D.cpp:8410 | OpenGL | yes | todo |
| Gizmo icons đưa vào main toolbar | src/slic3r/GUI/GLCanvas3D.cpp:8352 -> src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:1431 (add_toolbar_items) | OpenGL | yes | todo |
| Separator giữa các nhóm nút | src/slic3r/GUI/GLCanvas3D.cpp:8289, :8395 | OpenGL | yes | todo |
| Select plate toolbar | src/slic3r/GUI/GLCanvas3D.cpp:8437 | OpenGL + ImGui | yes | todo |
| Return toolbar | src/slic3r/GUI/GLCanvas3D.cpp:8598 | OpenGL | yes | todo |
| View toolbar (ủy quyền cho Plater::init_view_toolbar) | src/slic3r/GUI/GLCanvas3D.cpp:8608 | OpenGL | yes | todo |
| Collapse toolbar | src/slic3r/GUI/GLCanvas3D.cpp:8614 | OpenGL | yes | todo |
| Render main toolbar | src/slic3r/GUI/GLCanvas3D.cpp:9819 | OpenGL | yes | todo |
| Render select plate toolbar (ImGui) | src/slic3r/GUI/GLCanvas3D.cpp:9861 | OpenGL + ImGui | yes | todo |
| Render assembly view thumbnail toolbar | src/slic3r/GUI/GLCanvas3D.cpp:10216 | OpenGL | yes | todo |
| Render return toolbar | src/slic3r/GUI/GLCanvas3D.cpp:10602 | OpenGL | yes | todo |
| Render fit camera toolbar | src/slic3r/GUI/GLCanvas3D.cpp:10711 | OpenGL | yes | todo |
| Render collapse toolbar | src/slic3r/GUI/GLCanvas3D.cpp:10808 | OpenGL | yes | todo |
| Render paint toolbar | src/slic3r/GUI/GLCanvas3D.cpp:10822 | OpenGL | yes | todo |
| Tùy chọn Zoom to mouse / drag to move (đọc app_config) | src/slic3r/GUI/GLCanvas3D.cpp:8728 (zoom_to_mouse), :8784 (canvas_drag_to_move) | wx (AppConfig) | yes | todo |

---

## 4. Gizmo (src/slic3r/GUI/Gizmos/)

Enum `GLGizmosManager::EType` ở `src/slic3r/GUI/Gizmos/GLGizmosManager.hpp:72-92`. Đăng ký trong `GLGizmosManager::init()` ở `src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:96`, các dòng `emplace_back` ở `:106-121`. Các gizmo bị comment ở `:123-125`.

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Move | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:106 (GLGizmoMove.cpp) | OpenGL (ImGui) | yes | todo |
| Rotate | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:107 (GLGizmoRotate.cpp) | OpenGL (ImGui) | yes | todo |
| Scale | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:108 (GLGizmoScale.cpp) | OpenGL (ImGui) | yes | todo |
| Flatten | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:109 (GLGizmoFlatten.cpp) | OpenGL (ImGui) | yes | todo |
| Cut (AdvancedCut) | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:110 (GLGizmoAdvancedCut.cpp; GLGizmoCut.cpp còn trong repo) | OpenGL (ImGui) | yes | todo |
| MeshBoolean | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:111 (GLGizmoMeshBoolean.cpp) | OpenGL (ImGui) | yes | todo |
| Assembly | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:112 (GLGizmoAssembly.cpp) | OpenGL (ImGui) | yes | todo |
| MmuSegmentation (Color Painting) | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:113 (GLGizmoMmuSegmentation.cpp) | OpenGL (ImGui) | yes | todo |
| Text (Emboss) | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:114 (GLGizmoText.cpp) | OpenGL + font hệ thống | yes | todo |
| Svg | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:115 (GLGizmoSVG.cpp) | OpenGL (ImGui) | yes | todo |
| FdmSupports | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:116 (GLGizmoFdmSupports.cpp) | OpenGL (ImGui) | yes | todo |
| Seam | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:117 (GLGizmoSeam.cpp) | OpenGL (ImGui) | yes | todo |
| BrimEars | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:118 (GLGizmoBrimEars.cpp) | OpenGL (ImGui) | yes | todo |
| FuzzySkin | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:119 (GLGizmoFuzzySkin.cpp) | OpenGL (ImGui) | yes | todo |
| Measure | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:120 (GLGizmoMeasure.cpp) | OpenGL (ImGui) | yes | todo |
| Simplify (kèm dialog) | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:121 (GLGizmoSimplify.cpp, GLGizmoSimplifyDialog.cpp) | OpenGL (ImGui) | yes | todo |
| SlaSupports (không đăng ký, chỉ SLA) | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:123 (comment) | OpenGL | no | todo |
| FaceDetector (không đăng ký) | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:124 (comment) | OpenGL | unclear | todo |
| Hollow (không đăng ký) | src/slic3r/GUI/Gizmos/GLGizmosManager.cpp:125 (comment; GLGizmoHollow.cpp còn trong repo) | OpenGL | unclear | todo |
| Alignment (GLGizmoAlignment.cpp, không thấy trong init(); được gọi từ GUI_Factories/Plater/GizmoObjectManipulation - chưa đọc luồng gọi) | src/slic3r/GUI/Gizmos/GLGizmoAlignment.cpp | OpenGL | unclear | todo |
| Thanh thao tác đối tượng (vị trí, xoay, scale) | src/slic3r/GUI/Gizmos/GizmoObjectManipulation.cpp (số dòng chưa xác minh) | wx + OpenGL | yes | todo |

---

## 5. Menu theo đối tượng (object-list context menu)

Hàm tạo menu ở `src/slic3r/GUI/GUI_Factories.cpp`. Hàm chọn menu ở `src/slic3r/GUI/GUI_ObjectList.cpp:1821` (show_context_menu), `:1672` (OnContextMenu), `:1686` (list_manipulation).

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Danh sách đối tượng: cột Name | src/slic3r/GUI/GUI_ObjectList.cpp:410 | wx (DataViewCtrl) | yes | todo |
| Danh sách đối tượng: cột Filament | src/slic3r/GUI/GUI_ObjectList.cpp:435 | wx | yes | todo |
| Tooltip lỗi mesh (non-manifold, reversed faces) | src/slic3r/GUI/GUI_ObjectList.cpp:555, :568, :601 | wx | yes | todo |
| Menu mặc định (không chọn) | src/slic3r/GUI/GUI_Factories.cpp:1261 (create_default_menu) | wx | yes | todo |
| Menu chung cho object | src/slic3r/GUI/GUI_Factories.cpp:1277 (create_common_object_menu) | wx | yes | todo |
| Menu object (FFF) | src/slic3r/GUI/GUI_Factories.cpp:1297 (create_object_menu) | wx | yes | todo |
| Menu object BBL | src/slic3r/GUI/GUI_Factories.cpp:1321 (create_bbl_object_menu) | wx | yes | todo |
| Menu object lắp ráp (assembly) | src/slic3r/GUI/GUI_Factories.cpp:1374 (create_bbl_assemble_object_menu) | wx | yes | todo |
| Menu object SLA | src/slic3r/GUI/GUI_Factories.cpp:1386 (create_sla_object_menu) | wx | no (SLA) | todo |
| Menu part | src/slic3r/GUI/GUI_Factories.cpp:1400 (create_part_menu) | wx | yes | todo |
| Menu text part | src/slic3r/GUI/GUI_Factories.cpp:1427 (create_text_part_menu) | wx | yes | todo |
| Menu SVG part | src/slic3r/GUI/GUI_Factories.cpp:1444 (create_svg_part_menu) | wx | yes | todo |
| Menu part BBL | src/slic3r/GUI/GUI_Factories.cpp:1459 (create_bbl_part_menu) | wx | yes | todo |
| Menu part lắp ráp | src/slic3r/GUI/GUI_Factories.cpp:1493 (create_bbl_assemble_part_menu) | wx | yes | todo |
| Menu cutter (cut) | src/slic3r/GUI/GUI_Factories.cpp:1503 (create_cut_cutter_menu) | wx | yes | todo |
| Assembly steps (submenu) | src/slic3r/GUI/GUI_Factories.cpp:471 (append_menu_items_assembly_steps) | wx | yes | todo |
| Delete | src/slic3r/GUI/GUI_Factories.cpp:511 | wx | yes | todo |
| Delete all cutter | src/slic3r/GUI/GUI_Factories.cpp:523 | wx | yes | todo |
| Edit Text | src/slic3r/GUI/GUI_Factories.cpp:536 | wx | yes | todo |
| Edit SVG | src/slic3r/GUI/GUI_Factories.cpp:553 | wx | yes | todo |
| Add generic volume (submenu, primitives) | src/slic3r/GUI/GUI_Factories.cpp:594 (append_submenu_add_generic) | wx | yes | todo |
| Add SVG | src/slic3r/GUI/GUI_Factories.cpp:667 | wx | yes | todo |
| Add volume (Modifier / Negative Part / Support Blocker/Enforcer) | src/slic3r/GUI/GUI_Factories.cpp:672 | wx | yes | todo |
| Layers editing | src/slic3r/GUI/GUI_Factories.cpp:693 | wx | yes | todo |
| Settings (per-object) | src/slic3r/GUI/GUI_Factories.cpp:700 | wx | yes | todo |
| Change type | src/slic3r/GUI/GUI_Factories.cpp:775 | wx | yes | todo |
| Set as individual objects | src/slic3r/GUI/GUI_Factories.cpp:824 | wx | yes | todo |
| Printable | src/slic3r/GUI/GUI_Factories.cpp:846 | wx | yes | todo |
| Rename | src/slic3r/GUI/GUI_Factories.cpp:875 | wx | yes | todo |
| Fix model (netfabb) | src/slic3r/GUI/GUI_Factories.cpp:883 | none (thư viện cục bộ, chưa xác minh) | unclear | todo |
| Export as STL / STLs | src/slic3r/GUI/GUI_Factories.cpp:895 | wx + file dialog | yes (qua Files app) | todo |
| Reload from disk | src/slic3r/GUI/GUI_Factories.cpp:916 | wx + filesystem | yes (cần bookmark của Files app) | todo |
| Replace with STL | src/slic3r/GUI/GUI_Factories.cpp:923 | wx + file dialog | yes (qua Files app) | todo |
| Change extruder | src/slic3r/GUI/GUI_Factories.cpp:930 | wx | yes | todo |
| Scale to print volume | src/slic3r/GUI/GUI_Factories.cpp:1025 | wx | yes | todo |
| Flush options | src/slic3r/GUI/GUI_Factories.cpp:1031 | wx | yes | todo |
| Convert unit (inch/meter) | src/slic3r/GUI/GUI_Factories.cpp:1124 | wx | yes | todo |
| Merge to multipart object / single object | src/slic3r/GUI/GUI_Factories.cpp:1180, :1187 | wx | yes | todo |
| Merge parts to single part / some parts | src/slic3r/GUI/GUI_Factories.cpp:1195, :1203 | wx | yes | todo |
| Mirror (X/Y/Z) | src/slic3r/GUI/GUI_Factories.cpp:1221 | wx | yes | todo |
| Invalidate cut info | src/slic3r/GUI/GUI_Factories.cpp:1238 | wx | yes | todo |
| Multi-selection menu (plater->multi_selection_menu) | src/slic3r/GUI/GUI_ObjectList.cpp:1835 | wx | yes | todo |

---

## 6. Sidebar (Plater)

Constructor `Sidebar::Sidebar` ở `src/slic3r/GUI/Plater.cpp:3967`.

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Panel tiêu đề Printer (thu gọn/mở rộng) | src/slic3r/GUI/Plater.cpp:4020 | wx | yes | todo |
| Nút sửa preset máy (dot) | src/slic3r/GUI/Plater.cpp:4097 | wx | yes | todo |
| Nút Connection (kết nối máy) | src/slic3r/GUI/Plater.cpp:4118 | network plugin | LAN only | todo |
| Combo chọn tấm (bed type) | src/slic3r/GUI/Plater.cpp:4165 | wx | yes | todo |
| Nút Sync info (đồng bộ nozzle/AMS) | src/slic3r/GUI/Plater.cpp:4224 | network plugin (đọc từ máy) | LAN only | todo |
| Diameter buttons (đường kính nozzle) | src/slic3r/GUI/Plater.cpp:4252 | wx | yes | todo |
| Nozzle rack panel | src/slic3r/GUI/Plater.cpp:4316 | wx + network plugin | LAN only | todo |
| Single extruder group | src/slic3r/GUI/Plater.cpp:4333 | wx | yes | todo |
| Tiêu đề Project Filaments | src/slic3r/GUI/Plater.cpp:4427 | wx | yes | todo |
| Nút Purge mode | src/slic3r/GUI/Plater.cpp:4445 | wx | yes | todo |
| Nút Flushing volumes | src/slic3r/GUI/Plater.cpp:4484 | wx | yes | todo |
| Nút đồng bộ filament từ AMS | src/slic3r/GUI/Plater.cpp:4521 | network plugin | LAN only | todo |
| Nút Set filaments to use | src/slic3r/GUI/Plater.cpp:4532 | wx | yes | todo |
| Nút Add filament / Remove last filament | src/slic3r/GUI/Plater.cpp:4568, :4577 | wx | yes | todo |
| Nút Add Mixed Filament | src/slic3r/GUI/Plater.cpp:4647 | wx | yes | todo |
| Nút Add / Remove mixed filament | src/slic3r/GUI/Plater.cpp:4706 (add), :4711 (del) | wx | yes | todo |
| Cảnh báo mixed filament | src/slic3r/GUI/Plater.cpp:4770 | wx | yes | todo |
| Ô tìm kiếm plate/object/part | src/slic3r/GUI/Plater.cpp:4818 | wx | yes | todo |
| Nút Slice now (nhãn thay đổi theo trạng thái) | src/slic3r/GUI/Plater.cpp:17812 | OpenGL + wx | yes | todo |
| Nút Export G-code / Export (nhãn) | src/slic3r/GUI/Plater.cpp:30862 | wx | yes (qua Files app) | todo |
| Hộp thoại Send G-code file / Send now | src/slic3r/GUI/Plater.cpp:20552 | network plugin / LAN | LAN only | todo |
| Nút Print plate / Print all (SideButton) | src/slic3r/GUI/MainFrame.cpp:2213 | wx + network plugin (in) | LAN only | todo |

---

## 7. Trang cài đặt preset (Tab.cpp)

Hàm build chính: `TabPrint::build` (Tab.cpp:3094), `TabPrintModel::build` (:3720), `TabPrintPlate::build` (:4221), `TabPrintPart::build` (:4490), `TabFilament::build` (:5080), `TabPrinter::build` (:5631), `build_fff` (:5651), `build_sla` (:5938), `build_unregular_pages` (:6120). Hàm thêm trang: `Tab::add_options_page` (:759). Tất cả dùng wx + libslic3r config (không phụ thuộc mạng), nên iPad khả thi `yes` trừ khi ghi chú khác.

### 7.1 Print (TabPrint::build)

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Trang Quality | src/slic3r/GUI/Tab.cpp:3100 | wx | yes | todo |
| Quality > Layer height / Line width / Seam / Precision / Ironing / Wall generator / Advanced | src/slic3r/GUI/Tab.cpp:3106, :3111, :3122, :3140, :3153, :3162, :3171 | wx | yes | todo |
| Trang Strength | src/slic3r/GUI/Tab.cpp:3191 | wx | yes | todo |
| Strength > Walls / Top/bottom shells / Sparse infill / Advanced | src/slic3r/GUI/Tab.cpp:3192, :3199, :3215, :3245 | wx | yes | todo |
| Trang Speed | src/slic3r/GUI/Tab.cpp:3261 | wx | yes | todo |
| Speed > Initial layer / Other layers / Travel / Acceleration / Jerk(XY) | src/slic3r/GUI/Tab.cpp:3262, :3265, :3295, :3298, :3311 | wx | yes | todo |
| Trang Support | src/slic3r/GUI/Tab.cpp:3325 | wx | yes | todo |
| Support > Support / Raft / Support filament / Support ironing / Advanced / Tree Support | src/slic3r/GUI/Tab.cpp:3326, :3336, :3340, :3347, :3357, :3404 | wx | yes | todo |
| Trang Others | src/slic3r/GUI/Tab.cpp:3411 | wx | yes | todo |
| Others > Bed adhension / Prime tower / Flush options / Special mode / Advanced | src/slic3r/GUI/Tab.cpp:3412, :3421, :3455, :3460, :3478 | wx | yes | todo |
| Others > G-code output / Post-processing scripts / Notes | src/slic3r/GUI/Tab.cpp:3490, :3498, :3506 | wx | yes | todo |

### 7.2 Model và Plate

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Trang Frequent (TabPrintModel) | src/slic3r/GUI/Tab.cpp:3726 | wx | yes | todo |
| Trang Plate Settings (TabPrintPlate) | src/slic3r/GUI/Tab.cpp:4237 | wx | yes | todo |
| TabPrintPart > Others > Modifier cycle | src/slic3r/GUI/Tab.cpp:4501-4502 | wx | yes | todo |
| TabPrintPart > Setting Overrides > Retraction / Speed | src/slic3r/GUI/Tab.cpp:4704, :4705, :4763 | wx | yes | todo |

### 7.3 Filament (TabFilament)

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Trang Filament (build_filament_page) | src/slic3r/GUI/Tab.cpp:4880 (build_filament_page), :5085 | wx | yes | todo |
| Filament > Basic information | src/slic3r/GUI/Tab.cpp:4883 | wx | yes | todo |
| Filament > Print temperature | src/slic3r/GUI/Tab.cpp:4962 | wx | yes | todo |
| Filament > Volumetric speed limitation | src/slic3r/GUI/Tab.cpp:5041 | wx | yes | todo |
| Filament > Filament scarf seam settings | src/slic3r/GUI/Tab.cpp:5052 | wx | yes | todo |
| Trang Cooling > Part cooling fan / auxiliary fan groups / Exhaust fan | src/slic3r/GUI/Tab.cpp:5087, :5089, :5141, :5178 | wx | yes | todo |
| Trang Advanced > Filament start G-code / end G-code | src/slic3r/GUI/Tab.cpp:5201, :5202, :5212 | wx | yes | todo |
| Trang Notes | src/slic3r/GUI/Tab.cpp:5222 | wx | yes | todo |
| Trang Multi Filament | src/slic3r/GUI/Tab.cpp:5232 | wx | yes | todo |

### 7.4 Printer (TabPrinter::build_fff)

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Trang Basic information > Printable space | src/slic3r/GUI/Tab.cpp:5671, :5672 | wx | yes | todo |
| Trang Advanced | src/slic3r/GUI/Tab.cpp:5780 | wx | yes | todo |
| Trang Basic information > AMS filament load/unload time | src/slic3r/GUI/Tab.cpp:5801 | wx | yes | todo |
| Extruder Clearance / Accessory | src/slic3r/GUI/Tab.cpp:5803, :5809 | wx | yes | todo |
| Trang Machine gcode > Machine start / end G-code | src/slic3r/GUI/Tab.cpp:5819, :5820, :5830 | wx | yes | todo |
| Machine gcode > Printing by object G-code | src/slic3r/GUI/Tab.cpp:5840 | wx | yes | todo |
| Machine gcode > Before layer change / Layer change G-code | src/slic3r/GUI/Tab.cpp:5850, :5861 | wx | yes | todo |
| Machine gcode > Time lapse / Clumping Detection G-code | src/slic3r/GUI/Tab.cpp:5871, :5881 | wx | yes | todo |
| Machine gcode > Change filament / Pause / Template custom G-code | src/slic3r/GUI/Tab.cpp:5891, :5901, :5910 | wx | yes | todo |
| Trang Notes (máy) | src/slic3r/GUI/Tab.cpp:5926 | wx | yes | todo |

### 7.5 Printer (SLA và multi-extruder)

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Trang SLA Motion ability / Speed limitation / Acceleration limitation / Jerk limitation (TabPrinter::build_sla) | src/slic3r/GUI/Tab.cpp:6049, :6081, :6087, :6102 | wx | no (SLA) | todo |
| Trang Single extruder MM setup (build_unregular_pages) | src/slic3r/GUI/Tab.cpp:6120, :6174 | wx | yes | todo |
| Multi-extruder: Basic information / Layer height limits / Position / Retraction | src/slic3r/GUI/Tab.cpp:6196, :6244, :6248, :6252 | wx | yes | todo |
| Multi-extruder: Retraction when switching material | src/slic3r/GUI/Tab.cpp:6267 | wx | yes | todo |
| SLA material (TabSLAMaterial::build) | src/slic3r/GUI/Tab.cpp:9374 | wx | no (SLA) | todo |
| SLA print (TabSLAPrint::build) | src/slic3r/GUI/Tab.cpp:9496 | wx | no (SLA) | todo |

---

## 8. G-code preview

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Khởi tạo GCodeViewer | src/slic3r/GUI/GCodeViewer.cpp:64 (init) | OpenGL | yes | todo |
| Chế độ xem EViewType: Summary, FeatureType, Height, Width, Feedrate, FanSpeed, Temperature, VolumetricRate, Tool, ColorPrint, FilamentId, LayerTime, AdditionalFanSpeed, ThermalIndex (min/max/mean) | src/slic3r/GUI/GCodeRenderer/BaseRenderer.hpp:28-48 | OpenGL | yes | todo |
| Nhãn legend "Multicolor Print" / "Filaments" / "Line Type" | src/slic3r/GUI/GUI_Preview.cpp:786-787 | wx | yes | todo |
| Thanh trượt layer/horizontal (IMSlider, IMToolbar) | src/slic3r/GUI/IMSlider.cpp, src/slic3r/GUI/IMToolbar.cpp (số dòng chưa xác minh) | OpenGL + ImGui | yes | todo |
| Show Labels by Layer, Show Overhang, Show Wireframe (dùng chung với View menu) | src/slic3r/GUI/MainFrame.cpp:3622, :3644, :3670 | OpenGL | yes | todo |
| Export toolpaths as OBJ | src/slic3r/GUI/MainFrame.cpp:3295 | wx + file dialog | yes (qua Files app) | todo |
| Preview: Always show shells | src/slic3r/GUI/Preferences.cpp:1662 (xem mục 13) | wx | yes | todo |

---

## 9. Import / Export file

Các loại file (`FileType`) ở `src/slic3r/GUI/GUI_App.hpp:109-128`. Bảng wildcard theo loại ở `src/slic3r/GUI/GUI_App.cpp:831-867`. Hộp thoại mở: project `GUI_App.cpp:5009`, model `:5025` (multi-select), gcode `:5037`. Hộp thoại lưu: `Plater.cpp:14772`, G-code `:27887`, G-code 3MF `:27980`. Hộp thoại import model trong Plater: `:16145`, `:16315`.

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Đọc STEP (.stp, .step) | src/slic3r/GUI/GUI_App.cpp:831-867 (FT_STEP) | wx + thư viện đọc STEP (chưa xác minh) | unclear | todo |
| Đọc STL | src/slic3r/GUI/GUI_App.cpp:831-867 (FT_STL) | wx | yes | todo |
| Đọc OBJ | src/slic3r/GUI/GUI_App.cpp:831-867 (FT_OBJ) | wx | yes | todo |
| Đọc AMF (.amf, .zip.amf, .xml) | src/slic3r/GUI/GUI_App.cpp:831-867 (FT_AMF) | wx | yes | todo |
| Đọc 3MF (project và model) | src/slic3r/GUI/GUI_App.cpp:831-867 (FT_3MF, FT_PROJECT) | wx | yes | todo |
| Ghi/đọc Gcode 3MF (.gcode.3mf; trên macOS dùng .3mf) | src/slic3r/GUI/GUI_App.cpp:831-867 (FT_GCODE_3MF); lưu tại Plater.cpp:27980 | wx | yes | todo |
| Ghi/đọc G-code (.gcode) | src/slic3r/GUI/GUI_App.cpp:831-867 (FT_GCODE); lưu tại Plater.cpp:27887 | wx | yes | todo |
| Đọc SVG (import/chỉnh sửa) | src/slic3r/GUI/GUI_App.cpp:831-867 (FT_SVG) | wx | yes | todo |
| Texture (.png, .svg) | src/slic3r/GUI/GUI_App.cpp:831-867 (FT_TEX) | wx | yes | todo |
| Masked SLA (.sl1, .sl1s) | src/slic3r/GUI/GUI_App.cpp:831-867 (FT_SL1); Plater.cpp:27887 | wx | no (SLA) | todo |
| INI (import configs) | src/slic3r/GUI/GUI_App.cpp:831-867 (FT_INI) | wx | yes | todo |
| Model hỗ trợ Supported files: gltf, glb, fbx, usd, usda, oltp (chỉ macOS cho usd/usda) | src/slic3r/GUI/GUI_App.cpp:831-867 (FT_MODEL) | wx | unclear | todo |
| Gallery (.stl, .obj) | src/slic3r/GUI/GUI_App.cpp:831-867 (FT_GALLERY) | wx | yes | todo |
| Xuất STL (một file / nhiều file) | src/slic3r/GUI/Plater.cpp:14743 (STL), :14772 (hộp thoại lưu) | wx | yes (qua Files app) | todo |
| Xuất AMF | src/slic3r/GUI/Plater.cpp:14750 | wx | yes (qua Files app) | todo |
| Xuất OBJ | src/slic3r/GUI/Plater.cpp:14762 | wx | yes (qua Files app) | todo |
| Xuất sliced file (cảnh báo) | src/slic3r/GUI/Plater.cpp:28016 | wx | yes | todo |
| Import model từ Files app (mở từ đường dẫn, mở nhiều) | src/slic3r/GUI/Plater.cpp:16145, :16315 | wx | yes (qua Files app) | todo |
| Mở project 3MF từ app (mở project) | src/slic3r/GUI/GUI_App.cpp:5009 | wx | yes (qua Files app) | todo |

---

## 10. Calibration

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Tab Calibration (panel) | src/slic3r/GUI/MainFrame.cpp:1702, :1392 | wx + network plugin | LAN only | todo |
| Menu Calibration (topbar và menu bar) | src/slic3r/GUI/MainFrame.cpp:3872-3935, :3960-4040 | wx | LAN only | todo |
| Dialog Calibration: cập nhật trạng thái máy | src/slic3r/GUI/Calibration.cpp:222 (update_cali) | network plugin | LAN only | todo |
| Dialog Calibration: bắt đầu hiệu chỉnh (gửi lệnh) | src/slic3r/GUI/Calibration.cpp:342 (on_start_calibration) | network plugin (suy ra từ tên hàm, chưa đọc thân hàm) | LAN only | todo |
| Panel đối tượng calibration (MObjectPanel) | src/slic3r/GUI/CalibrationPanel.cpp:42 | wx | yes | todo |
| Wizard calibration (constructor) | src/slic3r/GUI/CalibrationWizard.cpp:75 | wx | yes | todo |
| Wizard trang Start | src/slic3r/GUI/CalibrationWizardStartPage.cpp:8 | wx | yes | todo |
| Wizard trang Cali (CaliPage) | src/slic3r/GUI/CalibrationWizardCaliPage.cpp:17 | wx | yes | todo |
| Wizard trang Preset (PresetPage) | src/slic3r/GUI/CalibrationWizardPresetPage.cpp:129 | wx | yes | todo |
| Wizard trang Save | src/slic3r/GUI/CalibrationWizardSavePage.cpp:80 | wx | yes | todo |
| Lịch sử calibration (HistoryWindow) | src/slic3r/GUI/CaliHistoryDialog.hpp:14 | network plugin | LAN only | todo |

---

## 11. Device tab, máy in, AMS, camera

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Monitor (panel Device) | src/slic3r/GUI/MonitorPage.cpp:6 (MonitorPage); src/slic3r/GUI/Monitor.cpp (MonitorPanel, số dòng chưa xác minh) | wx + network plugin (MQTT/LAN) | LAN only | todo |
| Multi-machine page | src/slic3r/GUI/MultiMachinePage.cpp:11 | wx + network plugin | unclear | todo |
| Multi-device: gửi job tới nhiều máy | src/slic3r/GUI/SendMultiMachinePage.hpp, src/slic3r/GUI/MultiPrintJob.cpp (số dòng chưa xác minh) | network plugin | LAN only | todo |
| Device core (DevManager, DevBed, DevFan, DevHMS, DevLamp, DevChamber, DevNozzleRack, DevFilaSystem...) | src/slic3r/GUI/DeviceCore/ (số dòng chưa xác minh) | network plugin | LAN only | todo |
| Camera (lớp Camera; dòng 24 là get_type_as_string, không phải luồng) | src/slic3r/GUI/Camera.cpp:24 | network plugin + media | LAN only | todo |
| Camera popup | src/slic3r/GUI/CameraPopup.cpp:44 | wx | LAN only | todo |
| Camera fullscreen (macOS) | src/slic3r/GUI/CameraFullscreenMac.mm | wx + AppKit | unclear | todo |
| Media player (MP4, BambuPlayer) | src/slic3r/GUI/MP4/, src/slic3r/GUI/BambuPlayer/ (số dòng chưa xác minh) | ffmpeg/decoder + OpenGL | unclear | todo |
| HMS (cảnh báo máy in; HMSNotifyItem) | src/slic3r/GUI/HMSPanel.cpp:64 | network plugin | LAN only | todo |
| Panel AMS (setting) | src/slic3r/GUI/AMSSetting.cpp:21 | wx + network plugin | LAN only | todo |
| AMS vật liệu (AMSMaterialsSetting) | src/slic3r/GUI/AMSMaterialsSetting.cpp:183 | wx + network plugin | LAN only | todo |
| AMS sấy khô (AMSDryControl) | src/slic3r/GUI/AMSDryControl.cpp:149 | wx + network plugin | LAN only | todo |
| AMS mapping popup | src/slic3r/GUI/AmsMappingPopup.cpp:92 | wx | LAN only | todo |
| AMS widgets (TrayListModel) | src/slic3r/GUI/AmsWidgets.cpp:19 | wx | LAN only | todo |
| Đồng bộ AMS (SyncAmsDialog) | src/slic3r/GUI/SyncAmsDialog.cpp:637 | wx + network plugin | LAN only | todo |
| Điều khiển AMS web (wgtAmsControlWebPanel) | src/slic3r/GUI/DeviceTab/AmsControl/wgtAmsControlWebPanel.cpp (số dòng chưa xác minh) | WebView + cloud | no | todo |
| Bảng điều khiển máy web (wgtDeviceControlPanelWebPanel) | src/slic3r/GUI/DeviceTab/ControlPanel/wgtDeviceControlPanelWebPanel.cpp (số dòng chưa xác minh) | WebView + cloud | no | todo |
| Cập nhật firmware (uiDeviceUpdateVersion) | src/slic3r/GUI/DeviceTab/uiDeviceUpdateVersion.cpp (số dòng chưa xác minh) | network plugin | no | todo |
| Kết nối máy (ConnectPrinter) | src/slic3r/GUI/ConnectPrinter.cpp (số dòng chưa xác minh) | network plugin | LAN only | todo |
| Gửi file in (PrintHostSendDialog) | src/slic3r/GUI/PrintHostDialogs.cpp (lớp: PrintHostSendDialog, PrintHostDialogs.hpp) | network plugin / LAN | LAN only | todo |
| Bind máy với tài khoản (PingCodeBindDialog) | src/slic3r/GUI/BindDialog.hpp:48 | network plugin (cloud) | no | todo |

---

## 12. Dialog (src/slic3r/GUI/*Dialog*.cpp)

Dòng số là khai báo class chính trong `.hpp` cùng tên file, nếu xác minh được. Dấu "(chưa xác minh)" nghĩa là chưa đối chiếu được dòng.

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| AMSNewFilamentDialogs (AMSNewOfficialFilamentDlg) | src/slic3r/GUI/AMSNewFilamentDialogs.cpp (AMSNewFilamentDialogs.hpp:12) | wx + network plugin | LAN only | todo |
| AboutDialog | src/slic3r/GUI/AboutDialog.cpp (AboutDialog.hpp:14) | wx | yes | todo |
| AlertDialog | src/slic3r/GUI/AlertDialog.cpp (AlertDialog.hpp:40) | wx | yes | todo |
| AuxiliaryDialog | src/slic3r/GUI/AuxiliaryDialog.cpp (AuxiliaryDialog.hpp:16) | wx | unclear | todo |
| BedShapeDialog | src/slic3r/GUI/BedShapeDialog.cpp (BedShapeDialog.hpp:52) | wx | yes | todo |
| BetaVersionDialog | src/slic3r/GUI/BetaVersionDialog.cpp (BetaVersionDialog.hpp:24) | wx | yes | todo |
| BindDialog | src/slic3r/GUI/BindDialog.cpp (BindDialog.hpp:48) | network plugin (cloud) | no | todo |
| BonjourDialog (mDNS, tìm máy LAN) | src/slic3r/GUI/BonjourDialog.cpp (BonjourDialog.hpp:23) | network (mDNS) | LAN only | todo |
| CaliHistoryDialog (dòng 14 của .hpp là lớp HistoryWindow) | src/slic3r/GUI/CaliHistoryDialog.cpp (CaliHistoryDialog.hpp:14) | network plugin | LAN only | todo |
| CreateFilamentWebDialog | src/slic3r/GUI/CreateFilamentWebDialog.cpp (CreateFilamentWebDialog.hpp:11) | wx (WebView) + cloud | no | todo |
| CreatePresetsDialog | src/slic3r/GUI/CreatePresetsDialog.cpp (CreatePresetsDialog.hpp:20) | wx | yes | todo |
| DesktopIntegrationDialog (gắn file association) | src/slic3r/GUI/DesktopIntegrationDialog.cpp (DesktopIntegrationDialog.hpp:9) | subprocess / OS | no | todo |
| DeviceErrorDialog | src/slic3r/GUI/DeviceErrorDialog.cpp (chưa xác minh) | network plugin | LAN only | todo |
| DownloadProgressDialog | src/slic3r/GUI/DownloadProgressDialog.cpp (DownloadProgressDialog.hpp:34) | network (download) | unclear | todo |
| EditFilamentWebDialog | src/slic3r/GUI/EditFilamentWebDialog.cpp (EditFilamentWebDialog.hpp:11) | wx (WebView) + cloud | no | todo |
| FilamentMapDialog | src/slic3r/GUI/FilamentMapDialog.cpp (FilamentMapDialog.hpp:63) | wx | yes | todo |
| FilamentPickerDialog | src/slic3r/GUI/FilamentPickerDialog.cpp (FilamentPickerDialog.hpp:21) | wx | yes | todo |
| FilamentSelectDialog | src/slic3r/GUI/FilamentSelectDialog.cpp (FilamentSelectDialog.hpp:24) | wx | yes | todo |
| HelioHistoryDialog | src/slic3r/GUI/HelioHistoryDialog.cpp (HelioHistoryDialog.hpp:25) | cloud (Helio) | no | todo |
| ImageMessageDialog | src/slic3r/GUI/ImageMessageDialog.cpp (ImageMessageDialog.hpp:19) | wx | yes | todo |
| KBShortcutsDialog | src/slic3r/GUI/KBShortcutsDialog.cpp (KBShortcutsDialog.hpp:24) | wx | yes (phím tắt bàn phím ngoài) | todo |
| MinorsLogoutDialog | src/slic3r/GUI/MinorsLogoutDialog.cpp (MinorsLogoutDialog.hpp:12) | cloud | no | todo |
| MixSupplementFilamentDialog | src/slic3r/GUI/MixSupplementFilamentDialog.cpp (MixSupplementFilamentDialog.hpp:22) | wx | yes | todo |
| MixedFilamentDialog | src/slic3r/GUI/MixedFilamentDialog.cpp (MixedFilamentDialog.hpp:58) | wx | yes | todo |
| MixingKitsHelpDialog | src/slic3r/GUI/MixingKitsHelpDialog.cpp (MixingKitsHelpDialog.hpp:17) | wx | yes | todo |
| MsgDialog (ErrorDialog) | src/slic3r/GUI/MsgDialog.cpp (MsgDialog.hpp:111) | wx | yes | todo |
| MultiNozzleTpuTipsDialog | src/slic3r/GUI/MultiNozzleTpuTipsDialog.cpp (MultiNozzleTpuTipsDialog.hpp:19) | wx | yes | todo |
| NetworkTestDialog | src/slic3r/GUI/NetworkTestDialog.cpp (NetworkTestDialog.hpp:49) | network plugin | unclear | todo |
| ParamsDialog (dòng 16 của .hpp là lớp FilamentInfomation; dialog chính chưa xác minh dòng) | src/slic3r/GUI/ParamsDialog.cpp (ParamsDialog.hpp:16) | wx | yes | todo |
| PartSkipDialog | src/slic3r/GUI/PartSkipDialog.cpp (PartSkipDialog.hpp:37) | wx | yes | todo |
| PhysicalPrinterDialog | src/slic3r/GUI/PhysicalPrinterDialog.cpp (PhysicalPrinterDialog.hpp:28) | network (host máy in) | LAN only | todo |
| PlateMoveDialog | src/slic3r/GUI/PlateMoveDialog.cpp (PlateMoveDialog.hpp:13) | wx | yes | todo |
| PlateSettingsDialog | src/slic3r/GUI/PlateSettingsDialog.cpp (chưa xác minh) | wx | yes | todo |
| PrintHostDialogs (PrintHostSendDialog) | src/slic3r/GUI/PrintHostDialogs.cpp (PrintHostDialogs.hpp:26) | network plugin / LAN | LAN only | todo |
| PrintOptionsDialog (PrinterPartsDialog) | src/slic3r/GUI/PrintOptionsDialog.cpp (PrintOptionsDialog.hpp:43) | wx | yes | todo |
| PrivacyUpdateDialog | src/slic3r/GUI/PrivacyUpdateDialog.cpp (PrivacyUpdateDialog.hpp:17) | wx | yes | todo |
| PublishDialog | src/slic3r/GUI/PublishDialog.cpp (PublishDialog.hpp:38) | cloud | no | todo |
| PurgeModeDialog | src/slic3r/GUI/PurgeModeDialog.cpp (PurgeModeDialog.hpp:19) | wx | yes | todo |
| RecenterDialog | src/slic3r/GUI/RecenterDialog.cpp (RecenterDialog.hpp:10) | wx | yes | todo |
| SafetyOptionsDialog | src/slic3r/GUI/SafetyOptionsDialog.cpp (SafetyOptionsDialog.hpp:26) | network plugin (cấu hình máy) | LAN only | todo |
| SavePresetDialog | src/slic3r/GUI/SavePresetDialog.cpp (SavePresetDialog.hpp:27) | wx | yes | todo |
| SendSystemInfoDialog | src/slic3r/GUI/SendSystemInfoDialog.cpp (chưa xác minh) | network (upload) | no | todo |
| SingleChoiceDialog | src/slic3r/GUI/SingleChoiceDialog.cpp (SingleChoiceDialog.hpp:10) | wx | yes | todo |
| StepMeshDialog | src/slic3r/GUI/StepMeshDialog.cpp (StepMeshDialog.hpp:12) | wx | yes | todo |
| SyncAmsDialog | src/slic3r/GUI/SyncAmsDialog.cpp (SyncAmsDialog.hpp:43) | network plugin | LAN only | todo |
| SysInfoDialog | src/slic3r/GUI/SysInfoDialog.cpp (SysInfoDialog.hpp:13) | wx | yes | todo |
| TextureImportDialog (TexturePreviewCanvas) | src/slic3r/GUI/TextureImportDialog.cpp (chưa xác minh) | OpenGL | yes | todo |
| ThermalPreconditioningDialog | src/slic3r/GUI/ThermalPreconditioningDialog.cpp (ThermalPreconditioningDialog.hpp:16) | wx | yes | todo |
| UnsavedChangesDialog | src/slic3r/GUI/UnsavedChangesDialog.cpp (UnsavedChangesDialog.hpp:137, DiffModel) | wx | yes | todo |
| UpdateDialogs (MsgUpdateSlic3r) | src/slic3r/GUI/UpdateDialogs.cpp (UpdateDialogs.hpp:21) | network plugin (kiểm tra cập nhật) | no | todo |
| UserPresetsDialog | src/slic3r/GUI/UserPresetsDialog.cpp (UserPresetsDialog.hpp:22) | cloud sync | unclear | todo |
| UxProgramTermsDialog | src/slic3r/GUI/UxProgramTermsDialog.cpp (UxProgramTermsDialog.hpp:12) | wx | yes | todo |
| VersionPolicyDialog | src/slic3r/GUI/VersionPolicyDialog.cpp (VersionPolicyDialog.hpp:37) | network plugin | unclear | todo |
| WebGuideDialog | src/slic3r/GUI/WebGuideDialog.cpp (WebGuideDialog.hpp:38) | wx (WebView) | no | todo |
| WebUserLoginDialog | src/slic3r/GUI/WebUserLoginDialog.cpp (WebUserLoginDialog.hpp:33) | cloud login (WebView) | no | todo |
| WebViewDialog | src/slic3r/GUI/WebViewDialog.cpp (WebViewDialog.hpp:40) | wx (WebView) + cloud | no | todo |
| WipeTowerDialog | src/slic3r/GUI/WipeTowerDialog.cpp (WipeTowerDialog.hpp:13) | wx | yes | todo |

---

## 13. Preferences (src/slic3r/GUI/Preferences.cpp)

Dialog tạo ở `Preferences.cpp:1265`. Các tab: `add_tab` ở `:1324-1330`. Hàm tạo tab: General `:1440`, User `:1550`, 3D `:1609`, Other `:1742`, Developer `:1832`. Reset: `:2112` (on_reset_all_warnings), `:2134` (on_reset_preferences).

| Tính năng | Nguồn (file:line) | Phụ thuộc desktop | iPad khả thi | Trạng thái |
|---|---|---|---|---|
| Tab General > General Settings (title) | src/slic3r/GUI/Preferences.cpp:1445 | wx | yes | todo |
| General > Language | src/slic3r/GUI/Preferences.cpp:1464 | wx | yes | todo |
| General > Login Region | src/slic3r/GUI/Preferences.cpp:1467 | network plugin | no | todo |
| General > Units (Metric/Imperial) | src/slic3r/GUI/Preferences.cpp:1470 | wx | yes | todo |
| General > Enable dark mode | src/slic3r/GUI/Preferences.cpp:1473 | wx | yes | todo |
| General > Auto Calculate Flush Volume | src/slic3r/GUI/Preferences.cpp:1480 | wx | yes | todo |
| General > Keep only one Bambu Studio instance | src/slic3r/GUI/Preferences.cpp:1483 | wx / OS | no | todo |
| General > Filament Manager (bật/tắt) | src/slic3r/GUI/Preferences.cpp:1494 | wx + network plugin | no | todo |
| General > Multi-device Management | src/slic3r/GUI/Preferences.cpp:1502 | network plugin | LAN only | todo |
| General > Support beta version update | src/slic3r/GUI/Preferences.cpp:1506 | network plugin | no | todo |
| General > Join the User Experience Improvement Program | src/slic3r/GUI/Preferences.cpp:1510 | network plugin | no | todo |
| Tab User > User Settings (title) | src/slic3r/GUI/Preferences.cpp:1556 | wx | yes | todo |
| User > Auto plate type | src/slic3r/GUI/Preferences.cpp:1558 | wx | yes | todo |
| User > time format for print progress | src/slic3r/GUI/Preferences.cpp:1564 | wx | yes | todo |
| User > Keep liveview when printing | src/slic3r/GUI/Preferences.cpp:1568 | network plugin | LAN only | todo |
| User > Automatically transfer modified value when switching presets | src/slic3r/GUI/Preferences.cpp:1572 | wx | yes | todo |
| User > Automatically optimize wipe tower placement | src/slic3r/GUI/Preferences.cpp:1575 | wx | yes | todo |
| User > Auto sync user presets | src/slic3r/GUI/Preferences.cpp:1579 | network plugin (cloud) | no | todo |
| User > Auto check for system presets updates | src/slic3r/GUI/Preferences.cpp:1582 | network plugin (cloud) | no | todo |
| User > Auto-fill previously logged-in accounts | src/slic3r/GUI/Preferences.cpp:1586 | WebView + cloud | no | todo |
| Tab 3D > 3D Settings (title) | src/slic3r/GUI/Preferences.cpp:1614 | wx | yes | todo |
| 3D > Zoom to mouse position | src/slic3r/GUI/Preferences.cpp:1618 | wx | yes | todo |
| 3D > Reverse direction of zoom with mouse wheel | src/slic3r/GUI/Preferences.cpp:1620 | wx | yes | todo |
| 3D > Drag with left mouse button to move | src/slic3r/GUI/Preferences.cpp:1622 | wx | yes | todo |
| 3D > Mouse rotation sensitivity | src/slic3r/GUI/Preferences.cpp:1625 | wx | yes | todo |
| 3D > Display overview (assemble view) | src/slic3r/GUI/Preferences.cpp:1631 | wx | yes | todo |
| 3D > Grabber scale | src/slic3r/GUI/Preferences.cpp:1641 | wx | yes | todo |
| 3D > Tooltip offset | src/slic3r/GUI/Preferences.cpp:1651 | wx | yes | todo |
| 3D > Toolbar Style (Collapsible/Uncollapsible) | src/slic3r/GUI/Preferences.cpp:1657 | wx | yes | todo |
| 3D > Always show shells in preview | src/slic3r/GUI/Preferences.cpp:1662 | wx | yes | todo |
| 3D > Show Objects color scheme in preview | src/slic3r/GUI/Preferences.cpp:1666 | wx | yes | todo |
| 3D > Show Thermal Preconditioning Area | src/slic3r/GUI/Preferences.cpp:1670 | wx | yes | todo |
| 3D > Show the step mesh parameter setting dialog | src/slic3r/GUI/Preferences.cpp:1674 | wx | yes | todo |
| 3D > Import a single SVG and split it | src/slic3r/GUI/Preferences.cpp:1677 | wx | yes | todo |
| 3D > Enable gamma correction for imported obj | src/slic3r/GUI/Preferences.cpp:1680 | wx | yes | todo |
| 3D > Remember last used color scheme | src/slic3r/GUI/Preferences.cpp:1684 | wx | yes | todo |
| 3D > Improve rendering performance by lod | src/slic3r/GUI/Preferences.cpp:1688 | OpenGL | yes | todo |
| 3D > Enable advanced gcode viewer | src/slic3r/GUI/Preferences.cpp:1691 | OpenGL | yes | todo |
| 3D > Show assembly BVH primary bounds | src/slic3r/GUI/Preferences.cpp:1706 | OpenGL | yes | todo |
| 3D > Open full screen camera view on active monitor only | src/slic3r/GUI/Preferences.cpp:1716 | wx / multi-monitor | no | todo |
| Tab Other > Maximum recent projects | src/slic3r/GUI/Preferences.cpp:1749 | wx | yes | todo |
| Other > No warnings when loading 3MF with modified G-codes | src/slic3r/GUI/Preferences.cpp:1753 | wx | yes | todo |
| Other > Don't check printer information when loading 3MF | src/slic3r/GUI/Preferences.cpp:1755 | wx | yes | todo |
| Other > Auto-Backup | src/slic3r/GUI/Preferences.cpp:1761 | wx (file) | yes | todo |
| Other > Show online staff-picked models on home page | src/slic3r/GUI/Preferences.cpp:1780 | cloud | no | todo |
| Other > Show history on the home page | src/slic3r/GUI/Preferences.cpp:1782 | wx | yes | todo |
| Tab Developer Tools > Develop mode | src/slic3r/GUI/Preferences.cpp:1801 | wx | yes | todo |
| Developer > Skip AMS blacklist check | src/slic3r/GUI/Preferences.cpp:1802 | network plugin | LAN only | todo |
| Developer > Enable DevTools For Webview | src/slic3r/GUI/Preferences.cpp:1804 | WebView | no | todo |
| Associate .3mf / .stl / .step to Bambu Studio (Windows) | src/slic3r/GUI/Preferences.cpp:1813-1818 | subprocess / OS | no | todo |
| Developer > Log Level | src/slic3r/GUI/Preferences.cpp:1843 | wx | yes | todo |
| Developer > Internal developer mode | src/slic3r/GUI/Preferences.cpp:1852 | wx | yes | todo |
| Developer > Enable SSL(MQTT) | src/slic3r/GUI/Preferences.cpp:1853 | network plugin | LAN only | todo |
| Developer > Enable SSL(FTP) | src/slic3r/GUI/Preferences.cpp:1854 | network plugin | LAN only | todo |
| Developer > Import Texture Model | src/slic3r/GUI/Preferences.cpp:1856 | wx | yes | todo |
| Download path (Browse) | src/slic3r/GUI/Preferences.cpp:1187 | wx + file dialog | yes (qua Files app) | todo |
| Reset all warnings | src/slic3r/GUI/Preferences.cpp:2112 | wx | yes | todo |
| Reset preferences | src/slic3r/GUI/Preferences.cpp:2134 | wx | yes | todo |

---

## Ghi chú: mục chưa xác minh hoặc có rủi ro

- Các dòng ghi "(số dòng chưa xác minh)" hoặc "chưa xác minh" chưa đối chiếu được bằng grep. Cần đọc thêm trước khi triển khai.
- Cột "Phụ thuộc desktop" của các mục Device, AMS, Dialog và Calibration là suy luận từ tên file/hàm, chưa đọc thân hàm cho từng mục. Cần kiểm chứng khi làm từng mục.
- Mục Preferences tham chiếu theo HEAD và đã kiểm tra lại bằng grep trên bản HEAD.
- Đường dẫn `src/slic3r/GUI/Mouse3DHandlerMac.mm:100` dùng dlopen cho 3Dconnexion: không dùng được trên iPad.
- `src/slic3r/GUI/Plater.cpp` và `src/slic3r/GUI/Preferences.cpp` có sửa chưa commit trong working tree; số dòng ở đây theo HEAD `23a337589`.
- Các mục Monitor/Device/AMS/Calibration tham chiếu theo dòng định nghĩa constructor/hàm đầu tiên, không phải toàn bộ luồng.
