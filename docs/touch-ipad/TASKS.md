# Việc

Trạng thái: todo / doing / code (chưa biên dịch) / built / tested / blocked

| ID | Việc | File sở hữu | Model | Trạng thái |
|---|---|---|---|---|
| D1 | Kiểm kê tính năng | PARITY.md | Haiku | xong, duyệt mẫu phần đầu |
| D2 | Học repo đi trước | PRIOR_ART.md | Sonnet | xong |
| D3 | Thiết kế iPad | ARCHITECTURE.md | Opus (chạy từ trước #9) | xong, chưa duyệt chi tiết |
| W1 | Nút/hàng lớn | Widgets, OG_CustomCtrl, Preferences | Sonnet | code |
| W2 | Cử chỉ canvas 3D | GLCanvas3D.*, TouchInput.* | Sonnet | code |
| W3 | Vuốt cuộn | Widgets/TouchScroll.*, ParamsPanel, 2 vùng cuộn Plater | Sonnet | code |
| W4 | Sidebar React | src/slic3r/GUI/TouchWeb/sidebar | Sonnet | built (web), chưa chạy WebView2 |
| W5 | Cầu nối C++ ↔ web, ray trái | Plater.*, TouchWeb/*.cpp | Sonnet | code |
| W6 | Toolbar dưới, nút Slice lớn | GLToolbar, GLCanvas3D (sau W2), GLGizmosManager | Sonnet | code |
| W7 | Bàn phím ảo | Field.*, Widgets/TextInput | Haiku | todo |
| I0/I1a | Thí nghiệm và deps iOS | ios/cmake, ios/scripts, ios/spikes | Sonnet | xong |
| I1b..I6 | Theo ARCHITECTURE.md mục 12 | theo mục 12 | Haiku | V1–V4 có code và chạy trên iPad; còn: thử LAN, gizmo kéo, chữ/khắc/boolean/đo, phân tách đầu nối khi cắt, thumbnail 3mf, tô khối lượng lớn, in lần đầu |

Các sửa src/ dùng chung cho iPad (I3a) chỉ làm sau W5/W6.
