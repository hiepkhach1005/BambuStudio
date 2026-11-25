# Sửa giao diện iPad (ghi 2026-11-25, chưa sửa code)

Nguồn: [U] người dùng nói; [C] thấy trong code/ảnh iPad; [?] phải đối chiếu ảnh Bambu Studio. Đã chụp tab Prepare trên Mac (ios/build/bs3.png, không commit): xem bảng cuối. Preview và Device chưa chụp.

## ĐỊNH HƯỚNG MỚI NHẤT [U] (ưu tiên hơn mọi mục dưới)
- KHÔNG cần giống y chang Bambu Studio; bố cục iPad hiện tại đã ổn, giữ lại. Thanh trên không cần nền tối.
- Thêm đủ tab như Bambu: Home, Prepare, Preview, Device, Project, Calibration.
- Chỉnh cho hài hòa, hợp thiết kế iPadOS (control gốc, cỡ và canh lề đều). Bảng so dưới chỉ để tham khảo nội dung/chức năng.
- Vẫn giữ: tiếng Anh mặc định + chọn ngôn ngữ, chữ và giá trị mặc định đúng Bambu, plate đầy đủ chức năng.
- Thứ tự: (1) ngôn ngữ, mặc định; (2) Theme.swift cỡ/canh; (3) 6 tab: Home = dự án gần đây/mở/mới, Project = thông tin 3mf, Calibration = mẫu hiệu chuẩn; (4) plate; (5) Print/Slice, sidebar, preview.

## Yêu cầu của người dùng
1. [U] Nhìn giống Prusa/Orca, phải giống Bambu Studio.
2. [U] Mặc định tiếng Anh; chọn ngôn ngữ trong cài đặt ở menu 3 gạch.
3. [U] Giá trị mặc định phải giống Bambu Studio.
4. [U] Phần plate chưa giống ("place": hiểu là plate, hỏi lại nếu cần).
5. [U] Chữ và nút phải giống Bambu Studio.
6. [U] Cỡ chữ, nút, khoảng cách, canh trái/phải không đều, không theo chuẩn iPad.

## Việc cần làm
- Ngôn ngữ: Store.swift Translator đang theo ngôn ngữ hệ thống -> UserDefaults, mặc định en; bỏ bảng extraVi hoặc chỉ dùng khi chọn vi; thêm Settings vào menu App.swift topBar.
- Chữ: tr() phải dùng đúng msgid gốc (vd "Color Scheme", "Total Estimation"); hiện có chuỗi tự đặt ("Arrange all", "Object settings", "Default"...). Không dịch bằng cách hạ chữ thường.
- Mặc định: Engine.cpp tự chọn preset/bed. [C] P1S 0.4 ra "Tấm in làm mát" (Cool Plate). Đối chiếu PresetBundle/Plater: default_print_profile, default_filament_profile, default_bed_type, màu sợi, flush. Process hiện "0.20mm Standard @BBL X1C" [?]. Có thể khác do preset đã lưu trên Mac của người dùng.
- Thông số: ẩn/hiện và bật/tắt theo ConfigManipulation/Tab::toggle_options (hiện hiện hết theo mode) [C]; nút Simple/Advanced, icon nhóm, Global/Objects, Multi-line label [?]. Hai key max_volumetric_extrusion_rate_slope_* bị thiếu.
- Plate: [C] hiện chỉ là lưới phẳng + nút số. Cần theo PartPlate.cpp: mặt bàn bo góc/tay cầm, logo và texture theo loại bàn, số plate, cụm icon cạnh plate (xóa, định hướng, xếp, khóa, cài đặt plate, tên), lưới đậm mỗi 5 ô, màu nền gốc, dải ảnh plate bên trái ở Preview.
- Toolbar: thứ tự và icon theo GLCanvas3D.cpp (dùng SVG trong resources/images, không SF Symbols); gộp thành một hàng; gizmo theo GLGizmosManager, gizmo kéo trực tiếp.
- Thanh trên: tab Prepare/Preview/Device/Project/Calibration như MainFrame.cpp; nút Slice plate/Print plate gộp kèm menu ▾ như gốc; thiếu Home, Project, Calibration.
- Sidebar: khối Printer (ảnh máy, nozzle, bed type), Project Filaments (nút Flushing volumes, +, -, AMS sync), Process theo Plater.cpp Sidebar.
- Preview: chú giải nằm nổi bên phải trong khung 3D và slider layer + slider bước ngang, như GCodeViewer/IMSlider; hiện đang là danh sách bên trái.
- Chuẩn iPad: lưới 8 pt; vùng chạm >= 44 pt; một cỡ điều khiển; nhãn canh trái, ô nhập và đơn vị canh phải theo cột cố định; cỡ chữ theo text style (headline/body/caption), không 9 pt; thiết kế token chung (Theme.swift) rồi thay mọi số rải rác. Làm cho 1194x834 ngang trước.

## So với ảnh Prepare của Bambu Studio trên Mac (đã xem)
| Vùng | Bambu Studio | iPad hiện tại |
|---|---|---|
| Thanh trên | nền tối, icon Home, tab có icon: Prepare (nền xanh), Preview, Device, Project, Calibration | nền trắng, segmented 3 tab, tiếng Việt |
| Góc phải trên | 2 nút tách ▾: Slice plate (xanh), Print plate (xám khi chưa slice) | Slice + Xuất |
| Printer | dải tiêu đề xám + gear; thẻ ảnh máy "Bambu Lab P1S", thẻ ảnh bàn "Textured...", nút Sync info; khối Nozzle: Diameter 0.4, Flow Standard | nút tên preset + dòng Loại bàn in; không ảnh, không nozzle |
| Bed | Textured PEI (máy người dùng) | Cool Plate |
| Project Filaments | dải xám; icon AMS + gear; "Filament" + và -; ô màu VUÔNG có số, combo, nút ⋯ | ColorPicker tròn, nút trừ từng dòng |
| Process | dải xám; pill Global/Objects cùng hàng; công tắc Advanced; icon danh sách và so sánh; combo + lưu + tìm | segmented lớn riêng, ô tìm luôn hiện |
| Tab thông số | chữ gạch chân xanh: Quality Strength Speed Support Others; tab có thay đổi màu cam | nút bo xám, tab không đổi màu |
| Dòng thông số | nhãn trái thụt, ô nhập cùng cột, đơn vị TRONG ô, checkbox vuông xanh; tiêu đề nhóm đậm + icon + kẻ ngang | ô rải bên phải, đơn vị ngoài, công tắc iOS |
| Toolbar 3D | một hàng icon nét mảnh, không chữ, nền trắng; nút chỉ áp dụng khi chọn vật thì mờ | 2 hàng icon + chữ |
| Thumbnail | thẻ ảnh vật ở góc phải trên khung 3D | không có |
| Plate đang chọn | tối, texture "Bambu Textured PEI Plate", viền có tay cầm, lưới trắng, góc loại trừ sáng | lưới xám, góc đỏ |
| Plate khác | cùng hàng, xám nhạt, không có texture | có, cùng kiểu plate chính |
| Cạnh plate | 5 nút dọc bên phải: xóa, định hướng, xếp, khóa, cài đặt; bút xanh đổi tên ở góc trên; số 01/02 xanh cạnh dưới phải | chỉ dải nút số dưới |
| Điều hướng | khối lập phương Top/Front + trục góc trái dưới, nút fit cạnh đó; trục XYZ tại gốc bàn | menu góc phải dưới |
| Nền 3D | xám nhạt #E6E6E6 (ước lượng) | xám xanh |

Chữ trong nhóm: Layer height; Line width (Default, Initial layer, Initial layer infill, Outer wall, Inner wall, Top surface, Sparse infill, Internal solid infill, Support); Seam; Precision.
Lưu ý: ảnh dùng dự án và preset của người dùng (0.28mm Extra Draft đã sửa), nên số trong ảnh KHÔNG phải mặc định. Mặc định phải so bằng dự án mới.
iPad giữ bố cục này, chỉ tăng vùng chạm lên 44 pt.

## Phiên sau
Chụp thêm Preview, Device, và dự án mới (File > New) để so mặc định; sau đó sửa. Không chụp mã truy cập. Chụp: `open -a BambuStudio` rồi dùng ios/build/win.swift lấy id cửa sổ.
