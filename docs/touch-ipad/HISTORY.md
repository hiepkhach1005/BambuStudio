# Nhật ký (mới nhất ở cuối, chỉ thêm)

## 2026-11-25
- Khảo sát khả thi; chốt phạm vi; tạo nhánh feature/touch-ipad.
- Windows W1: touch_mode, icon toolbar x1.4, checkbox 28, hàng filament 44, dung sai thả 15 px (ý từ PR #10385). Chưa biên dịch.
- Rà W1: sửa thiếu Slic3r::GUI:: trong CheckBox.cpp, AxisCtrlButton.cpp; sửa vị trí chú thích.
- Tạo bộ tracking và skill.
- W3 vuốt cuộn (TouchScroll). Khi duyệt: đổi sang giữ cú nhấn rồi phát lại; sửa wxEVT_DESTROY từ con. Test logic qua; phần Win32 chưa biên dịch.
- W2 cử chỉ 3D (TouchInput + WM_POINTER). Khi duyệt: render trước LeftDown để chọn đúng vật, gỡ ngón kẹt bằng cờ primary, tắt nhấn giữ trên ImGui, dời windows.h xuống cuối, bỏ windowsx.h. Test logic qua; chưa biên dịch.
- D1 PARITY (388 mục theo báo cáo agent) và D3 ARCHITECTURE xong.
- W4: typecheck, 12 test, build qua. Chụp Chrome: nút Export tràn ray 60 px, icon emoji. Giao W4b.
- Chạy W4b, W5, W6, I0/I1a.
- D2 PRIOR_ART xong (6 repo, đều AGPL-3.0 theo báo cáo). Không repo iOS nào tái dùng GUI wx; deps tốt nhất: angelo-hub, qidi-ios.
- W6 toolbar dưới đáy (BottomMiddle, KeepSize, icon 56). Khi duyệt: bảng gizmo dừng trên toolbar. Chưa biên dịch.
- W4b: ray, icon SVG, thẻ, vòng đời bridge. Chạy lại: typecheck sạch, 18 test, build qua; đã xem ảnh ray đóng và Quality.
- W5 duyệt xong, chưa biên dịch. Sửa: Advanced mở được khi sidebar gốc đang thu gọn; ẩn nút web chưa có xử lý native (nozzle chỉ hiển thị, menu object, nút trên plate/part).
- touch_mode thành auto/1/0, mặc định auto (TouchDetect.hpp, GUI_App, Preferences). Test host qua; phần Win32 chưa biên dịch.
- I1a: 93 thư viện tĩnh iOS arm64, kiểm lại bằng verify_deps.sh. Chưa có: OpenMeshCraft (dự phòng MCUT), ios/spikes trống, zlib 1.2.13 lẫn libz của SDK.
- I1b: ios/CMakeLists.txt + shim; libslic3r biên dịch và liên kết cho iPad không sửa src/. App thử SliceSpike đã ký, cài lên iPad, chép Minimalist+Device+Stand.3mf; chưa chạy, chờ người dùng tin cậy chứng chỉ. Chưa slice, chưa so G-code.
- I1c bước 1 (iPad8,4, 2026-11-25): 4 mẫu + Minimalist+Device+Stand.3mf slice qua trên iPad, không văng (DONE all passed). 3mf: 298 lớp, 2,1 s, 223.56 g; số lệnh G1-G3 bằng BambuStudio Mac 2.8.4 CLI (khác phiên bản). Chưa có bản Mac cùng commit. Support thường cho kích thước khác nhau giữa hai lần chạy iPad (2151837/2151667).
- App iPad V1–V4: viết Swift/Metal, LAN; tự kiểm tra trên iPad qua (shape, transform, cut, merge, tô, plate, preset, slice, export, mở lại). Sửa: state() sập khi object thiếu extruder; auto-orient; STEP dùng lớp Step (load_step không có định nghĩa). Minimalist 298 lớp, 223.56 g. STEP và LAN chưa chạy thử.
- Người dùng phản hồi UI iPad; ghi UI_FIXES.md, chưa sửa code; đã chụp Prepare trên Mac và lập bảng so.
