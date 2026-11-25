# Trạng thái (2026-11-25)

- KẾ TIẾP: sửa giao diện iPad theo UI_FIXES.md (người dùng chê chưa giống Bambu Studio).
- iPad: app TouchStudio (ios/app/swift + ios/app/engine) cài và chạy trên iPad thật; tự kiểm tra `--selftest` qua. LAN chưa thử với máy in. Cử chỉ tay chưa có người thử.
- G-code chưa kiểm để in: chưa có bản Mac cùng commit (người dùng hoãn).
- Windows: W1, W2, W3, W5, W6 chưa biên dịch; cần máy người dùng (SSH). W7 chưa làm.
- Commit 724fdd823 đã push lên fork của người dùng; phần app iPad sau đó chưa commit.
- Build + cài: ios/scripts/build_app.sh <udid> [--selftest]. Chứng chỉ miễn phí, app hết hạn sau khoảng 7 ngày.
