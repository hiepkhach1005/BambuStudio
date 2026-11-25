# Kiến trúc bản iPadOS 18

Số dòng lấy theo commit `23a337589` (`git show 23a337589:<file>`); cây làm việc đang có người sửa nên có thể lệch vài dòng.
Đường dẫn tắt: `GUI/` = `src/slic3r/GUI/`, `lib/` = `src/libslic3r/`, `Utils/` = `src/slic3r/Utils/`.

Nhãn độ chắc chắn: **[đo]** đọc/đếm/chạy trực tiếp; **[suy]** suy từ code, chưa chạy; **[?]** chưa biết, cần thử. Chưa có dòng code iOS nào được biên dịch hay chạy trên máy.

## 1. Kết luận chính

1. **libslic3r gần sạch GUI** nhưng không độc lập: `lib/LogSink.cpp:6-7,313` gọi `Utils/BBLUtil.hpp`, `Utils/Http.hpp`; `tests/CMakeLists.txt` cũng ghi rõ libslic3r tham chiếu symbol lớp GUI (Http, encryption, nanosvg). Cần file thay thế, không cần sửa thuật toán. [đo]
2. **`SLIC3R_GUI=0` hiện không build được**: `src/BambuStudio.cpp:81-93` include `wx/stdpaths.h`, `PartPlate`, `GLCanvas3D`, `Plater`, `GLFW` ngoài `#ifdef`; target này còn kéo `add_subdirectory(src)` thẳng. Phải có target iOS riêng, không dùng cờ cũ. [đo]
3. **Plater/Tab/ObjectList không biên dịch nguyên file được.** Logic nằm lẫn với wx, phải trích hàm. Selection, 3DScene, PartPlate, GCodeRenderer, đa số gizmo thì biên dịch nguyên file với shim: wx trực tiếp rất ít, vướng chủ yếu là `wxGetApp()`.
4. **OpenGL ES trên iOS chỉ tới 3.0**; `SDK iPhoneOS27.2` không có `glTexBuffer`/`glPolygonMode` trong header ES3 [đo]. `AdvancedRenderer` dùng texture buffer nên phải đổi sang texture 2D. Các shader còn lại dễ: **39/45 file `resources/shaders/140` qua được glslc ở ES 3.10** chỉ bằng cách đổi dòng version và thêm precision [đo; chưa biên dịch bằng driver Apple].
5. **RAM là rủi ro vận hành lớn nhất** (4 GB, riêng bản 1 TB là 6 GB).

## 2. Module và thư mục

```
ios/
  CMakeLists.txt            target gốc riêng cho iOS
  cmake/                    toolchain, patch deps, FindXxx thay thế
  scripts/                  build_deps.sh, build_core.sh, gen_schema.py, compare_gcode.py
  shim/
    wx/                     header giả <wx/*.h>: wxString, wxPoint, wxSize, wxColour,
                            wxMouseEvent, wxKeyEvent, wxTimer, wxEvent/queue, wxPostEvent
    gl/GL/glew.h            map sang <OpenGLES/ES3/gl.h> + hàm giả
    gui/                    GUI_App.hpp, Plater.hpp, GUI_ObjectList.hpp, MsgDialog.hpp, I18N.hpp... giả
    lib/                    LogSink_ios.cpp, Http_stub.cpp, PostProcessor_ios.cpp
  core/
    host/                   AppHost (thân của wxGetApp()), PlaterCore, ObjectTree, SnapshotStack
    extract/                các hàm trích từ Plater/Tab/GUI_ObjectList (có ghi nguồn)
    render/                 GLES context, texture 2D thay buffer, phác thảo touch
    abi/                    bsc.h + phần hiện thực
  App/                      SwiftUI (Xcode): Shell, Sidebar, Canvas, Settings, Files, Icons
  tests/
src/                        upstream, chỉ sửa khi có hook nhỏ trong #if TARGET_OS_IPHONE
```

Chiều phụ thuộc (một chiều): `App (Swift)` → `bsc.h (C)` → `core` → `GUI upstream + shim` → `libslic3r`. Swift không thấy kiểu C++ nào. UI tuyệt đối không chứa luật (giới hạn giá trị, tương thích preset...); luật ở C++.

**Đường include:** `ios/shim/gui`, `ios/shim/wx`, `ios/shim/gl` đặt trước `src/`. Chú ý: include kiểu `"GUI_App.hpp"` trong `GUI/Selection.cpp` được tìm *trước tiên trong thư mục của chính file đó*, nên `-I` KHÔNG thay được. Hai cách:
- A (chọn): script tạo cây symlink `build/overlay/slic3r/GUI/` gồm symlink tới file upstream được phép dùng, còn header thay thế là symlink tới shim. Clang tìm theo thư mục của đường dẫn đã mở (symlink), không phải đường dẫn thật. [đo: thử file nhỏ với Apple clang; chưa thử trên cả GUI]
- B: clang VFS overlay (`-ivfsoverlay`), không đụng đĩa. Dự phòng.

Không sửa include trong upstream để dễ merge.

## 3. C ABI (`ios/core/abi/bsc.h`)

Quy ước chung:

```c
typedef struct bsc_app bsc_app;         /* một cho mỗi tiến trình */
typedef struct bsc_doc bsc_doc;         /* Model + PartPlateList + undo */
typedef struct bsc_job bsc_job;
typedef struct bsc_view bsc_view;       /* GLCanvas + camera */
typedef uint64_t bsc_id;                /* ObjectID, không phải con trỏ/chỉ số */

typedef enum { BSC_OK=0, BSC_E_ARG, BSC_E_STATE, BSC_E_IO, BSC_E_PARSE, BSC_E_VERSION,
               BSC_E_CONFIG, BSC_E_VALIDATE, BSC_E_CANCELED, BSC_E_MEMORY,
               BSC_E_UNSUPPORTED, BSC_E_INTERNAL } bsc_code;
typedef struct { bsc_code code; char *message; char *detail_json; } bsc_error;
void bsc_error_clear(bsc_error *);
void bsc_free(void *);                  /* mọi bộ đệm trả về từ ABI */
```

| Nhóm | Hàm chính | Nguồn logic |
|---|---|---|
| App | `bsc_app_create(paths, callbacks, err)`, `bsc_app_destroy`, `bsc_app_memory_warning` | `set_resources_dir/set_data_dir/set_temporary_dir` (`lib/Utils.hpp:105-111,209`) |
| Tài liệu | `bsc_doc_new/open/import/save/restore/close`, `bsc_doc_undo/redo`, `bsc_doc_snapshot_json` | `load_bbs_3mf` (`lib/Format/bbs_3mf.hpp:296`), `store_bbs_3mf` (`:329`), `Plater::priv::load_files` (`Plater.cpp:12299`) |
| Preset | `bsc_presets_list(kind)`, `_select`, `_dirty`, `_save_as`, `_delete`, `_compatible` | `lib/PresetBundle.cpp` (0 wx) |
| Cấu hình | `bsc_schema_json(tab)`, `bsc_config_get(scope,key)`, `bsc_config_set_batch(scope,json,decisions)`, `bsc_config_reset` | `PrintConfig`, `ConfigManipulation` |
| Cảnh | thêm/xóa/nhân bản/đổi tên, transform, split/merge, plate, layer range, paint, arrange, orient | `Selection`, `PartPlate`, hàm trích ObjectList/Plater |
| Slice | `bsc_slice_start(doc,plate)`, `bsc_job_cancel/wait/state/release`, `bsc_slice_result_json`, `bsc_export_gcode/3mf` | `PrintBase`, trích `BackgroundSlicingProcess` |
| View | `bsc_view_create/resize/render/touch/destroy`, `bsc_view_set_mode`, `bsc_gizmo_open` | `GLCanvas3D` |

`scope` là: `global_print`, `filament[i]`, `printer`, `object(id)`, `volume(id)`, `layer(id,range)`, `plate(i)`; tương ứng các lớp con của Tab (`TabPrintModel` `Tab.cpp:3720`, `TabPrintPlate` `:4221`, `TabPrintPart` `:4490`).

### Luồng (threading)

- Một **luồng engine = main thread**. Lý do: code upstream giả định UI + Model + GL cùng một luồng (`GLCanvas3D`, `Plater`, `UndoRedo`); tách luồng là viết lại giả định. Mọi hàm `bsc_*` sửa dữ liệu phải gọi từ main, kiểm tra bằng `dispatch_assert_queue`; sai thì trả `BSC_E_STATE`.
- Ngoại lệ gọi được từ mọi luồng: `bsc_job_cancel`, `bsc_job_state`, `bsc_free`, `bsc_error_clear`.
- Slice chạy trên luồng riêng bằng `create_thread` (stack 4 MB, `lib/Thread.hpp:47-55`) + TBB. Không dùng GCD/`Task`: stack nhỏ và không điều khiển được. Stack của worker TBB trên iOS: **[?]**.
- Việc nặng khác (nạp STEP, simplify, arrange) chạy qua `Jobs/BoostThreadWorker.cpp` (0 wx [đo]); chỉ thay phần đẩy về UI.
- Callback từ C++ **luôn được chuyển về main** qua hàng đợi thay `wxQueueEvent/CallAfter`. Cấm gọi ngược vào `bsc_*` sửa dữ liệu trong lúc đang ở trong một lời gọi `bsc_*` khác; callback phải hoãn tới vòng kế tiếp.

### Job, tiến độ, hủy

- Tiến độ: `set_status_callback` (`lib/PrintBase.hpp:485`), dữ liệu là `SlicingStatus` (percent, text, flags, warning_step, warning_object_id; `:439-477`). Gộp tối đa ~10 lần/giây trước khi đưa lên Swift, nhưng không được bỏ cảnh báo và trạng thái cuối.
- Hủy: `PrintBase::cancel()` (`:507`) đặt cờ atomic; worker ném `CanceledException` tại `throw_if_canceled` (`:553` và lân cận). Hủy là *hợp tác*: đoạn không gọi kiểm tra (có thể cả OCCT, CGAL) không dừng ngay.
- `Print::apply()` tự dừng tiến trình nền qua cancel callback khi cấu hình đổi (`:224-284`); callback đó phải **chờ** worker dừng, đúng như `stop_internal()` (`BackgroundSlicingProcess.cpp:639-640`). Thiếu bước chờ là lỗi đua dữ liệu.
- Job mang `generation`; kết quả trễ của generation cũ bị bỏ (upstream cũng làm vậy với `SlicingStatusEvent`).
- Trạng thái: `queued → processing → exporting → done | failed | canceled`, đúng một sự kiện kết thúc.
- Kết quả `GCodeProcessorResult` thuộc plate; view và job giữ tham chiếu có đếm, không copy `moves`.
- Thumbnail lúc export gọi callback từ luồng slice (`BackgroundSlicingProcess.cpp:226,252`) nhưng phải vẽ GL trên main. Main **không bao giờ** được chặn chờ job khi job đang chờ thumbnail → mọi `wait` chỉ dùng cho test, và test phải bơm vòng main.

### Sở hữu và lỗi

- `create/open/start` → người gọi sở hữu, gọi `destroy/close/release`. `const char*` trong callback chỉ sống trong callback. Dữ liệu lớn trả `{ptr,len}` mượn, có hàm release.
- Không exception nào qua ranh giới: mỗi hàm ABI bọc `catch (CanceledException) / SlicingError / std::bad_alloc / std::exception / ...`. Lỗi Jetsam **không** bắt được, không ném `bad_alloc`.
- Hộp thoại đồng bộ (`MessageDialog.ShowModal()`) là chỗ khó nhất: SwiftUI không có modal đồng bộ. Cách làm: lời gọi trả `BSC_E_STATE` kèm `detail_json = {"decision_id","text","choices"}`; UI hỏi rồi gọi lại với `decisions`. Muốn vậy hàm trích phải chạy thử trên **bản sao config** và không có tác dụng phụ trước câu hỏi. Không chạy run loop lồng.
- ABI có `BSC_ABI_VERSION`; mọi struct tham số vào có trường `size` đầu tiên.

## 4. File GUI: dùng thế nào

Đếm bằng regex: `wx` = số lần xuất hiện `wx[A-Z]…` (kể cả comment, không kể `wxGetApp`), `app` = `wxGetApp()`, `imgui` = `ImGui::`. Số đo cho thấy mức dính, không phải số giờ.

| File | Dòng | wx | app | imgui | Cách dùng |
|---|---:|---:|---:|---:|---|
| `lib/PresetBundle.cpp` | 8225 | 0 | 0 | 0 | Nguyên file |
| `Utils/RaycastManager.cpp` | 390 | 0 | 0 | 0 | Nguyên file |
| `Jobs/BoostThreadWorker.cpp`, `PlaterJob.cpp` | 185, 17 | 0 | 0 | 0 | Nguyên file (cần header shim) |
| `GLShader.cpp` | 461 | 0 | 0 | 0 | Nguyên + hook version |
| `GLModel.cpp` | 2043 | 0 | 4 | 0 | Shim |
| `MeshUtils.cpp` | 652 | 0 | 14 | 0 | Shim |
| `Camera.cpp` | 831 | 0 | 6 | 37 | Shim |
| `Utils/UndoRedo.cpp` | 1392 | 0 | 2 | 0 | Shim `plater()->get_partplate_list()` (`:920`) |
| `Selection.cpp` | 3671 | 0 | 90 | 0 | Shim |
| `3DScene.cpp` | 3057 | 0 | 31 | 0 | Shim + sửa GL_QUADS |
| `3DBed.cpp` | 926 | 0 | 24 | 0 | Shim |
| `PartPlate.cpp` | 8354 | 34 | 118 | 24 | Shim + bỏ hàm GL cũ |
| `GCodeViewer.cpp` | 445 | 0 | 1 | 0 | Shim |
| `GCodeRenderer/BaseRenderer.cpp` | 4762 | 13 | 95 | 600 | Shim; panel ImGui giữ lúc đầu |
| `GCodeRenderer/AdvancedRenderer.cpp` | 2880 | 8 | 17 | 0 | Shim + texture 2D; là renderer mục tiêu |
| `GCodeRenderer/LegacyRenderer.cpp` | 2559 | 11 | 20 | 16 | Không build (`GL_POINT_SPRITE` `:2144`, `glMultiDrawElements` `:2494`); thay factory ở `GCodeViewer.cpp:426-433` |
| `GLShadersManager.cpp` | 151 | 1 | 6 | 0 | Shim, ép gl31 |
| `GLTexture.cpp` | 1246 | 39 | 7 | 0 | Trích (bỏ phần vẽ chữ bằng wxDC) |
| `OpenGLManager.cpp` | 1401 | 34 | 0 | 0 | Trích `FrameBuffer`, `GLInfo`; thay context |
| `ImGuiWrapper.cpp` | 3358 | 72 | 8 | 621 | Shim + sửa input/font |
| `IMSlider.cpp` | 1711 | 13 | 12 | 143 | Shim, sau này SwiftUI |
| `GLToolbar.cpp` | 2408 | 41 | 4 | 0 | Thay bằng SwiftUI; giữ trạng thái enable |
| `GLCanvas3D.cpp` | 14959 | 256 | 440 | 446 | **Shim lớn**, xem dưới |
| `GLCanvas3D.hpp` | 1604 | 127 | 0 | 0 | Shim wxTimer/wxEvent |
| `Plater.cpp` | 32959 | 3236 | 1005 | 0 | **Trích hàm** |
| `Tab.cpp` | 9695 | 673 | 264 | 0 | **Trích** + sinh schema |
| `GUI_ObjectList.cpp` | 7516 | 578 | 210 | 0 | **Trích** phần sửa Model; cây UI thay |
| `ObjectDataViewModel.cpp` | 2553 | 349 | 6 | 0 | Thay bằng `ObjectTree` |
| `ConfigManipulation.cpp` | 1343 | 118 | 27 | 0 | Shim + hook hộp thoại |
| `BackgroundSlicingProcess.cpp` | 1010 | 22 | 12 | 0 | Shim event; gần nguyên |
| `Field / OptionsGroup / PresetComboBoxes` | 2479 / 1490 / 2976 | 410 / 182 / 255 | 30 / 25 / 65 | 0 | Thay |
| `GUI_App.cpp` | 9656 | 839 | 124 | 0 | Thay (`AppHost`) |
| `GUI_Preview.cpp` | 896 | 43 | 30 | 0 | Thay |
| `GUI_Factories.cpp` | 2736 | 444 | 34 | 0 | Thay menu; trích điều kiện hiện mục |
| `UnsavedChangesDialog.cpp` | 2886 | 741 | 44 | 0 | Trích diff, thay UI |
| `NotificationManager.cpp` | 3486 | 56 | 63 | 264 | Shim lúc đầu |
| `Jobs/ArrangeJob`, `OrientJob`, `FillBedJob` | 1238, 264, 443 | 1, 0, 1 | 30, 3, 2 | 0 | Shim |
| `Jobs/EmbossJob.cpp` | 2305 | 5 | 16 | 0 | Shim |
| `PrintJob/SendJob/BindJob/UpgradeNetworkJob` | – | – | – | – | Loại (cloud) |
| `GUI/Overview/*.cpp` (Assembly) | 19605 | – | – | – | Hoãn; shim rỗng cho `m_assembly_steps` **[?]** |

### Gizmo (`GUI/Gizmos/*.cpp` + `GLGizmoBase.hpp`: 37543 dòng, wx 744, app 553, imgui 1661)

Đăng ký thật tại `GLGizmosManager.cpp:106-121`: 16 gizmo. `GLGizmoCut`, `SlaSupports`, `Hollow`, `FaceDetector` không đăng ký (`:123-125`) → không build.

| Nhóm | File (wx/app/imgui) |
|---|---|
| Shim dễ | Rotate 0/17/17, Alignment 0/1/0, Assembly 0/3/10, Move 1/13/0, Flatten 2/10/7, Scale 4/6/0, Base 2/27/17, Common 1/4/0 |
| Shim vừa | Seam 8/9/68, FuzzySkin 8/8/89, FdmSupports 13/11/113, MmuSegmentation 8/30/154, PainterBase 2/62/36, BrimEars 4/25/65, MeshBoolean 9/43/12, Measure 13/44/174, AdvancedCut 33/50/146, Manager 13/30/0 |
| Trích/thay một phần | SVG 39/18/115 (chọn file), Text 257/41/366 (liệt kê font wx → CoreText), Simplify 15/19/0 (kèm `GLGizmoSimplifyDialog` 244 wx → thay SwiftUI), GizmoObjectManipulation 22/12/221 |

Panel ImGui của gizmo **giữ ImGui ở pha 1** để đúng chức năng, phóng to style; pha 2 mới đổi sang SwiftUI từng cái. Đây không trái "cùng layout".

### `wxGetApp()` phải cung cấp gì

Bề mặt thật nhỏ hơn con số. Ví dụ Selection: `plater()->canvas3D…/take_snapshot/get_partplate_list/get_camera`, `obj_list()->delete_from_model_and_list`, `obj_manipul()`, shader, `preset_bundle`. 3DScene: shader + vài màu filament. `AppHost` cài đúng tập này, phương thức chưa có thì **không khai báo** để lỗi lộ lúc biên dịch; hạn chế stub im lặng. `preset_bundle` xuất hiện 2535 lần trong 110 file GUI [đo]: `AppHost.preset_bundle` phải là con trỏ thật tới `PresetBundle`, không bọc.

`GLCanvas3D`: cân nhắc giữa biên dịch cả file và trích. Chọn **biên dịch cả file với shim** vì picking/drag/undo quyện trong `on_mouse` (`:5757` trở đi) và viết lại chắc chắn lệch hành vi. Kèm rủi ro R2; nếu E4 cho thấy >~400 symbol thiếu thì chuyển sang chia nhỏ hàm theo script.

### Hàm trích từ Plater / ObjectList

`Plater::priv::load_files` `:12299`, `load_model_objects` `:13929`, `update_background_process` `:15585`, `on_slicing_update` `:17355`, `generate_thumbnail(s)` `:21084`, `take_snapshot` `:24054`, `undo_redo_to` `:24188/24224`, `load_project` `:25000`, `save_project` `:25177`, `export_3mf` `:28535`. ObjectList: `load_generic_subobject` `:2616`, `del_subobject_from_object` `:3213`, `split` `:3299`, `merge` `:3356`, `merge_volumes` `:3684`, `add_layer_item` `:5243`, `instances_to_separated_object` `:6572`.

Quy tắc trích: mỗi hàm có header `// extracted-from: <file>:<hàm> @<commit> sha256=<thân hàm gốc>`; CI script so lại sha khi merge upstream để biết hàm nào phải xem lại. `load_files` dài và đầy hộp thoại: trích theo *pha* (đọc → quyết định → áp dụng). Không hứa giữ nguyên 100%.

## 5. Schema màn hình cài đặt

Ba nguồn khác nhau, đừng nhập một:

1. **Định nghĩa option** (`ConfigOptionDef`, `lib/Config.hpp:2233-2430`): type, label, tooltip, sidetext, min/max, mode, enum_values/labels, gui_type, multiline, readonly. Lấy lúc chạy bằng cách duyệt `print_config_def.options`. Không parse `PrintConfig.cpp`.
2. **Bố cục** (trang → nhóm → dòng → option): chỉ có trong code dựng Tab: `TabPrint::build` `:3094`, `TabPrintModel::build` `:3720`, `TabPrintPlate::build` `:4221`, `TabPrintPart::build` `:4490`, `TabFilament::build` `:5080` + overrides `:4704`, `TabPrinter::build_fff` `:5651`, trang máy in động `:6049`, `build_unregular_pages` `:6120`.
3. **Luật động**: `toggle_options` (`:3555`, `:4513`, `:5366`, `:6643`) và `ConfigManipulation::toggle_print_fff_options` (trả qua callback `cb_toggle_field/cb_toggle_line`, `ConfigManipulation.hpp:32-33`).

**Chọn: chạy code `build()` với `Page`/`ConfigOptionsGroup`/`Line` ghi âm**, không dùng regex. `Tab.cpp` có 501 lời gọi `append_single_option_line`, trong đó khoảng 466 có khóa là literal [đo]; phần còn lại qua biến, lambda (`append_nozzle_scaled_option`, `Tab.cpp:3101`) hoặc theo điều kiện máy in, nên regex sẽ thiếu. Trích thân `build*()` vào `ios/core/extract/tab_build.inc` bằng script cắt theo tên hàm + cân ngoặc, biên dịch với lớp ghi âm, xuất JSON:

```json
{"tab":"print","pages":[{"id":"Quality","title":"Quality","icon":"empty","groups":[
  {"title":"Layer height","icon":"param_layer_height","lines":[
    {"label":"Layer height","path":"layer-height","options":[{"key":"layer_height","index":-1}],
     "widget":null,"flags":{"nozzle_mirror":true}}]}]}]}
```

- Trường `Line` phải giữ: `label_path`, `full_width`, `subline`, `nozzle_diameter_mirror`, `multi_nozzle_auto`, `nozzle_group_header/parent`, `toggle_visible` (`OptionsGroup.hpp:52-90`).
- Khoảng 54 chỗ liên quan `append_line`/widget riêng [đo, gồm cả dòng thường] → đánh `widget:"<tên>"` và SwiftUI có danh sách thủ công (hình bàn in, compatible printers, ramming, flush volumes...). Build fail nếu gặp widget chưa có tên.
- Danh sách theo số extruder/máy in: sinh schema **lúc chạy** mỗi khi đổi máy in, không bake vào app.
- Chuỗi giữ nguyên msgid tiếng Anh; dịch bằng `resources/i18n/*/BambuStudio.mo`, cần bộ đọc .mo nhỏ (hoặc boost::locale **[?]**).
- Hiển thị/khóa: `bsc_config_set_batch` trả về danh sách thay đổi `{key,index,enabled,visible,value,source}`; UI không tự tính.
- `ConfigManipulation::update_print_fff_config` trộn kiểm tra và `MessageDialog` (`:235-506`) → dùng cơ chế decision của §3.

Kiểm tra: danh sách khóa `(tab,page,group,key)` từ bản ghi âm so với dump cùng commit trên Mac (thêm hook chỉ trong build test).

## 6. Khoảng trống GLES 3.0

| Vấn đề | Chỗ | Xử lý |
|---|---|---|
| Đọc phiên bản GL | `OpenGLManager.cpp:93-113` lấy token đầu, gặp `"OpenGL ES 3.0 …"` ra 0.0 → `valid_version=false` (`:408`), **shader không nạp** | `GLInfo` iOS báo mức 33 cho logic, kèm cờ `is_gles` |
| Nhánh shader | `GLShadersManager.cpp:36-37` chọn 140/ hay 110/; `gouraud_light_instanced` đòi 3.3; instancing dùng `gl_InstanceID`, `glVertexAttribDivisor` (có trong ES 3.0) | Dùng 140 |
| `#version 140` | `resources/shaders/140/*` (45 file) | Lúc nạp đổi thành `#version 300 es` + precision highp; hook ở `GLShaderProgram::init_from_files` (`GLShader.cpp:60-70`) |
| 6 shader không qua | `gcode.vs/.fs`, `gcode_options.vs/.fs`: `samplerBuffer`; `gaussian_blur33.fs:10`, `silhouette_composite.fs:11`: tên biến `sample` là từ dành riêng [đo] | Bản ES ghi đè trong `ios/`, hoặc thay chuỗi lúc nạp |
| Texture buffer | `GLTexture.cpp:846` (`glTexBuffer`), `OpenGLManager.cpp:1035`; `AdvancedRenderer.cpp:2015,2057,2118,2151,2195,2637,2682`; `gcode.vs:6-8,16-22,46,81` | Texture 2D `RGBA32F`, `NEAREST`, rộng 4096; `texelFetch(s, ivec2(i%4096,i/4096),0)`; cập nhật bằng `glTexSubImage2D`. Dữ liệu chia theo layer nên kích thước vừa |
| Lọc float | `RGBA32F` không lọc/render được nếu không có extension | Chỉ dùng NEAREST, không gắn FBO |
| `GL_QUADS` | `3DScene.cpp:287,343` | `push_quad` (`3DScene.hpp:214`) đẩy 2 tam giác; phải sửa luôn `qverts_range`/`quad_indices_size` và assert `3DScene.cpp:158-159`. Có dùng thật: skirt/brim và toolpath ở `GLCanvas3D.cpp:11591,11840-11860,12040` |
| `GL_QUADS` khác | `GLGizmoCut.cpp:105` (không đăng ký), `TextureImportDialog.cpp`, `SkipPartCanvas.cpp` (không port nguyên) | Không build |
| Immediate mode + ma trận | `PartPlate.cpp:983-1052` (`render_grabber/render_face`) và phần `#if 0` `:1070-1150` | Không thấy nơi gọi `render_grabber` ngoài khai báo [đo]; loại bằng `#if` |
| Client state | `GLGizmoMmuSegmentation.cpp:1052-1054` | Attrib pointer/VAO |
| `glColor4fv` | `GLModel.cpp:1250` nhánh không shader | No-op + log lỗi |
| `glPolygonMode` | `ImGuiWrapper.cpp:3082` (FILL: no-op); `GLGizmoSimplify.cpp:725-730` (wireframe); `GLGizmoPainterBase.cpp:2026` chỉ trong macro debug | Simplify: mesh có barycentric như `mm_gouraud_wireframe` |
| `glMapBuffer` | Chỉ `MP4/PBOReader.cpp:69` | Không build MP4; ES có `glMapBufferRange` nếu cần |
| Line width / stipple | `GLCanvas3D.cpp:12551,12604`, `OpenGLManager.cpp:765-777` (Apple ≥3.0 đã ép 1.0); stipple `GLSelectionRectangle.cpp:145` (chặn bởi phiên bản), `GLGizmoMove.cpp:452`, `GLGizmoScale.cpp:424`, `GLGizmoAdvancedCut.cpp:1754`, `GLGizmoPainterBase.cpp:280` | Width 1 hoặc dải tam giác; stipple bỏ (đúng như Mac core) |
| Point sprite / MultiDraw | `LegacyRenderer.cpp` | Không build |
| `glGetTexImage` | `GLTexture.cpp:773` | Đọc qua FBO |
| `GL_CLAMP`, border | `GLCanvas3D.cpp:288-289` (nhánh <3.0), `GLTexture.cpp:43` | `CLAMP_TO_EDGE`; Border cần kiểm tra nơi dùng |
| S3TC | `GLTexture.cpp:442,1012-1056…`, `ImGuiWrapper.cpp:2867`; cờ `OpenGLManager.cpp:372` | Cờ = false; RGBA8 tốn RAM hơn, cân nhắc ASTC sau |
| FBO 0 | iOS không có framebuffer mặc định là 0: `OpenGLManager.cpp:530,736,749,1143,1177,1276,1284,1321`, `LegacyRenderer.cpp:627`, `ModelPreview.cpp:224` | Shim `glBindFramebuffer(…,0)` → FBO của view |
| MSAA texture | `LegacyRenderer.cpp:576` ; renderbuffer `OpenGLManager.cpp:1251-1254` | Chỉ renderbuffer; resolve blit cùng kích thước/định dạng |
| `glReadPixels` picking | `OpenGLManager.cpp:641,1176` | Đọc **1 pixel khi chạm**, không đọc mỗi frame; đồng bộ GPU |
| `GL_MAX_TEXTURE_SIZE` | `OpenGLManager.cpp:214-217` chia đôi, rồi chia tiếp nếu RAM <6 GB | Giữ |

Context: `EAGLContext(.openGLES3)` + `CAEAGLLayer` trong `UIView` tự viết (không `GLKView`, để nắm FBO). Vẽ theo yêu cầu: `CADisplayLink` chỉ chạy khi dirty/đang chạm. Mất foreground: `glFinish` và **cấm gọi GL** khi ở background. API GLES bị Apple đánh dấu lỗi thời từ iOS 12 [đo: header SDK], vẫn còn trong SDK 27.2; tương lai xa **[?]**. Simulator: GLES chạy bằng phần mềm **[?]**, chỉ dùng test logic. glGetError (`glsafe`) tốn kém: bản Release đảm bảo tắt.

## 7. Cử chỉ

Nguyên tắc: chuyển cử chỉ thành `wxMouseEvent/wxGestureEvent` giả rồi gọi `GLCanvas3D::on_mouse/on_gesture/on_mouse_wheel` (`:5757`, `:5715`, `:5459`), để gizmo (`GLGizmoBase::on_mouse`) dùng chung.

| Cử chỉ | Sự kiện |
|---|---|
| Chạm 1 ngón | Move → LeftDown → LeftUp (Move trước để cập nhật hover/picking) |
| Chạm đúp | LeftDClick |
| Giữ 0.5 s trên vật | Menu ngữ cảnh (RightDown+Up); haptic |
| Kéo 1 ngón bắt đầu trên vật/grabber | LeftDown + drag (di chuyển/gizmo) |
| Kéo 1 ngón trên nền | Xoay camera (chuột trái kéo nền) |
| Kéo 2 ngón | Pan: `wxEVT_GESTURE_PAN` (`:5721`) |
| Chụm | Zoom: `wxEVT_GESTURE_ZOOM` (`:5728`) |
| Xoay 2 ngón | `wxEVT_GESTURE_ROTATE` (`:5742`), khóa hướng |
| Chạm 2/3 ngón | Undo / redo |
| Pencil | Vẽ paint; ngón tay = camera khi Pencil đang hoạt động |
| Chuột/trackpad + bàn phím ngoài | Map thẳng kể cả hover, wheel, Cmd |

Chi tiết dễ sai:
- Zoom dùng `m_mouse.position` (`:5736`) → cập nhật vị trí tâm chụm trước; `GetDelta` là delta mỗi bước, `GetZoomFactor` là tích lũy từ đầu cử chỉ; `IsGestureStart` đặt lại biến static.
- Từ 1 ngón sang 2 ngón giữa chừng: phải **hủy** drag (khôi phục transform), không gửi LeftUp vì sẽ commit. Trì hoãn LeftDown ~80 ms hoặc vượt 8 pt. Đường hủy đúng trong upstream: **[?]**, cần tìm (Esc/reset drag).
- Ngưỡng drag trong `on_mouse` tính theo pixel (`move_requires_threshold`, `:5925`): nhân `contentScaleFactor`; vùng chạm grabber tối thiểu 44 pt bằng cách mở rộng hình pick.
- `on_mouse` nhân `scale` khi `ENABLE_RETINA_GL`; chỉ scale một lần.
- ImGui nhận trước (`update_mouse_data`); sau LeftUp phải gửi Leaving để tránh hover kẹt.
- Ctrl/Shift/Alt của desktop: thanh chế độ chọn (cộng thêm, theo part, khung chọn).

## 8. File và sao lưu

- `UIDocumentPickerViewController` `asCopy:false`; `CFBundleDocumentTypes` (3mf, stl, obj, step, gcode...), `LSSupportsOpeningDocumentsInPlace`, `UIFileSharingEnabled`.
- Mở: `startAccessingSecurityScopedResource` → `NSFileCoordinator` đọc → **copy vào sandbox** `tmp/work/<uuid>/` → `stop`. C++ chỉ thấy đường dẫn sandbox; tránh iCloud biến mất giữa chừng và `load_bbs_3mf` ghi `lock.txt/origin.txt` (`bbs_3mf.cpp:1811-1825`). Bookmark lưu trong `Application Support` (trên iOS dùng `.minimalBookmark`/mặc định; tùy chọn `withSecurityScope` chỉ của macOS).
- Lưu: ghi ra file tạm sandbox bằng `store_bbs_3mf` → kiểm tra mở lại được zip → `NSFileCoordinator` `.forReplacing` + `replaceItemAt`. So `contentModificationDate` lúc mở; đổi thì hỏi. Save As dùng exporter, sau đó giữ bookmark mới.
- Không `UIDocument` ở pha 1: nó tự lưu theo lịch riêng, va với undo/backup.
- Sao lưu upstream: `Model::get_backup_path` (`lib/Model.cpp:1135-1200`) tạo `temporary_dir()/bamboo_model/<ngày>/<giờ>#<pid>#<id>`. Hai vấn đề: `temporary_dir` phải là `Application Support/backup` (iOS dọn `tmp`), và "còn sống hay không" dựa trên **pid** trong `lock.txt` — pid trên iOS có thể tái dùng và không hỏi được tiến trình khác. Thay bằng con trỏ phiên `active.json` của app. Nhánh dung lượng dưới 2 GB tự chuyển sang `data_dir/tmp`.
- Loại `backup` khỏi iCloud backup (`isExcludedFromBackup`). Ghi một phần từng object (`save_object_mesh`, `backup_soon`, `set_backup_interval`; `bbs_3mf.hpp:334-348`): `set_backup_callback` đưa việc UI về main. Khi `scenePhase==.background`: `beginBackgroundTask`, ghi nốt, hết hạn thì dừng ở ranh giới file.
- Khôi phục: `has_restore_data`, `LoadStrategy` restore; giữ tối đa N phiên.
- Slice khi ra nền: iOS treo app. Hết thời gian thì hủy và nói rõ; `isIdleTimerDisabled` khi đang slice. Không dùng BGProcessing ở pha 1.

## 9. Ngân sách RAM (A12X, 4 GB)

Giới hạn thật trên mỗi app **[?]** (thường khoảng hơn nửa RAM, đo bằng `os_proc_available_memory()` ở E1). Kế hoạch trên giả định trần 2 GB, mục tiêu đỉnh 1,5 GB; thử thêm entitlement `com.apple.developer.kernel.increased-memory-limit` (không chắc được cấp và có tác dụng trên máy này).

| Mục | Mục tiêu |
|---|---:|
| App + SwiftUI + ImGui + font | 120 MB |
| PresetBundle (chỉ nạp vendor cần) | 100 MB |
| Model + mesh + raycast | 250 MB |
| Print/slice (đỉnh) | 700 MB |
| `GCodeProcessorResult.moves` | 200 MB |
| GPU (FBO, texture, gcode) | 150 MB |

- `MoveVertex` (`lib/GCode/GCodeProcessor.hpp:208-250`) ước ~136 B [suy, chưa chạy `sizeof`], chưa kể vector điểm cung. 1 triệu move ≈ 136 MB; `std::vector` nở đôi gây đỉnh tạm cao hơn. Thêm mỗi segment/đỉnh 3-4 texel `RGBA32F` (16 B) trong AdvancedRenderer.
- FBO 2388×1668 RGBA8+D24S8, MSAA4 ≈ 128 MB + resolve 16 MB [tính] → dùng MSAA 2 hoặc 1, hạ khi có áp lực.
- Giữ kết quả của **một plate**; plate khác chỉ giữ file gcode và thống kê, nạp lại khi xem.
- Undo: giới hạn byte, giảm khi có memory warning. Kiểm tra `UndoRedo` và `total_physical_memory()` (cách tính ngưỡng theo RAM máy, không theo trần app).
- TBB: 8 nhân (4P+4E), thử 4 luồng (`tbb::global_control`); ít luồng thường giảm đỉnh RAM. Phải kiểm chứng G-code không đổi theo số luồng (E2).
- Memory pressure: xóa cache FBO/undo/preset ẩn → nếu đang slice thì **hủy có thông báo** trước khi Jetsam giết.
- Dung lượng app: `resources` 378 MB, trong đó `hms` 205 MB (thiết bị/cloud, bỏ lúc đầu), `fonts` 35, `images` 35, `profiles` 28, `web` 23 (bỏ) [đo].

## 10. CMake

Thực trạng: `SLIC3R_GUI` mặc định 1 (`CMakeLists.txt:43`), chỉ thêm define (`:142`) và nhánh `src/CMakeLists.txt:46-121`. Dù tắt GUI, top-level vẫn đòi `OpenGL`, `GLEW`, `glfw3`, OpenSSL, CURL (`CMakeLists.txt:544-548,616-626`) và vẫn tạo `BambuStudio` (`src/CMakeLists.txt:142`), link `IOKit`, `AVKit` (`:163-166`).

Vấn đề Apple:
- `APPLE` đúng cả với iOS. `CMakeLists.txt:85-98` đặt deployment target 10.15 nếu trống; `deps/CMakeLists.txt:177` **ép 10.15 bằng FORCE** → deps iOS phải sửa dòng này hoặc có CMake riêng.
- `-Werror=*availability` (`CMakeLists.txt:356-358`, `deps/deps-macos.cmake`): với deployment 18.0 ít va; riêng code gọi GLES cần `GLES_SILENCE_DEPRECATION`.
- `deps/CMakeLists.txt:62-74` chỉ biết cross-arch, không biết cross-SDK: arm64 → arm64 thì `IS_CROSS_COMPILE=FALSE`. Hệ quả: GMP/MPFR gắn `-mmacosx-version-min` và `--build=…` không `--host`; OpenSSL `darwin64-arm64-cc` + `-mmacosx-version-min`.

Làm: **`ios/CMakeLists.txt` là project gốc riêng**, không sửa top-level. `project(BambuTouch C CXX OBJC OBJCXX)`, `CMAKE_SYSTEM_NAME=iOS`, `CMAKE_OSX_SYSROOT=iphoneos`, `CMAKE_OSX_ARCHITECTURES=arm64`, `CMAKE_OSX_DEPLOYMENT_TARGET=18.0`, `CMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY`, `CMAKE_FIND_ROOT_PATH`=deps iOS. Nó tự khai báo `boost_libs`, `boost_headeronly`, `libcurl`, include Eigen, hằng version (`version.inc`)... những thứ top-level định nghĩa trước `add_subdirectory(src/libslic3r)`, rồi `add_subdirectory` từng thư viện trong `src/CMakeLists.txt:4-44`. **[?]** `src/libslic3r/CMakeLists.txt` có chỗ dùng đường dẫn/biến của top-level (`encoding_check`, `SLIC3R_RESOURCES_DIR`, PCH…); nếu quá nhiều thì tạo hook `if(CMAKE_SYSTEM_NAME STREQUAL "iOS")` nhỏ trong upstream. Sản phẩm: `libbsc.a` (gộp) → `BambuCore.xcframework`; Xcode link tĩnh.

Deps bỏ: wxWidgets, GLFW, GLEW, FFMPEG, OpenCSG, WebView2, libharu, hidapi, JPEG/TIFF (nếu không ai cần). CURL bỏ bằng stub Http. OpenSSL: libslic3r cần **MD5** (`lib/Utils.hpp:15`, `bbs_3mf.cpp:40`) và **AES** (`LogSink.cpp:16`, bị thay) → giữ libcrypto; `ios64-cross`/`iossimulator-*` của OpenSSL 3.1.

| Dep | Vấn đề dự kiến trên iOS |
|---|---|
| Boost 1.84 | CMake build; `BOOST_CONTEXT_ABI=aapcs` (`Boost.cmake`); bỏ process. Patch sẵn có cho Mac: **[?]** |
| TBB 2021.5 | Cũ; build tĩnh cho iOS **[?]** |
| GMP 6.2.1 / MPFR 3.1.6 | autotools: `--host=aarch64-apple-darwin`, giữ patch `x18` (`GMP/0002-…`: bắt buộc với Darwin); thử `--disable-assembly` nếu lỗi |
| OCCT 7.6.0 | Link `TKV3d`, `TKService` (`lib/CMakeLists.txt` `OCCT_LIBS`); trên macOS kéo Cocoa/OpenGL. `lib/Shape/TextShape.cpp:82,251` dùng `Font_*` của TKService nên không bỏ được chỉ bằng danh sách link. Rủi ro cao nhất trong deps: bản iOS của TKService/OpenGl **[?]**; tối thiểu patch STEP không cần visualization |
| OpenCV 4.6 world | Chỉ core/imgproc/imgcodecs; cờ iOS khác |
| CGAL | Header + GMP; `-frounding-math` chỉ áp trong `libslic3r_cgal` |
| OpenMeshCraft | Không có thì CMake FATAL trừ `SLIC3R_ALLOW_MCUT_BOOLEAN=ON` (`src/CMakeLists.txt:23-36`); nhưng thay backend có thể **đổi kết quả boolean so với Mac** |
| Assimp, OpenVDB/EXR/Blosc, Freetype, NLopt, Qhull, libnoise, PNG, EXPAT | Thường build được, **[?]** |

File đặc thù: `MacUtils.mm` chỉ dùng Foundation; `ModelIO.mm` dùng ModelIO (có trong SDK iOS [đo]). `fork/execv` bị cấm ở watchOS/tvOS nhưng **không** bị cấm lúc biên dịch trên iOS [đo: `unistd.h:456,459`]; sandbox chặn lúc chạy. `lib/GCode/PostProcessor.cpp` (include `boost/process.hpp`, dòng 152; gọi từ `BackgroundSlicingProcess.cpp:861,979`) thay bằng bản trả lỗi `BSC_E_UNSUPPORTED` khi `post_process` khác rỗng: **báo, không im lặng bỏ qua**. `-fno-vectorize` cho `PrintConfig.cpp`, `PresetBundle.cpp` (clang 21 crash) phải giữ; build song song trên Mac 16 GB RAM / 10 nhân [đo]: giới hạn `-j` (~4) cho CGAL/PCH.

Ký: cần team Apple; tài khoản free hết hạn 7 ngày. Phân phối App Store với AGPL-3.0: xung đột có thể có, cần ý kiến pháp lý; chạy trên máy mình thì không vướng. Tên/nhãn "Bambu Studio" cũng không nên dùng khi phát hành.

## 11. Kiểm thử

**So G-code với bản Mac cùng commit.**
1. Build công cụ `bsc_cli` trên macOS từ **cùng nguồn core** (cờ giống hệt, không GUI) và app test trên iPad; thêm bộ ba: Bambu Studio Mac thật (`--slice`, `--load_settings`, `--load_filaments`, `--outputdir`, `--datadir`; `PrintConfig.cpp:11449-11773`).
2. So cặp: (a) Mac CLI gốc ↔ Mac `bsc_cli` (bắt lỗi trích/shim), (b) Mac `bsc_cli` ↔ iPad (bắt lỗi nền tảng). Tách vậy mới biết lỗi do đâu.
3. Chuẩn hóa tối thiểu: ngày giờ, đường dẫn, tên máy, phiên bản app, thumbnail. Còn lại **byte-equal**; khác là fail, mở danh sách ngoại lệ có lý do. Không hứa trước: `-O2`/FMA/`libm` giữa SDK iOS và macOS có thể lệch số thập phân cuối **[?]**; nếu vậy, hạ xuống so từng lệnh với dung sai 0,001 mm và **báo** số dòng lệch thay vì tuyên bố bằng nhau.
4. Corpus: `tests/data/20mm_cube.obj`, `bridge.obj`, `overhang.obj`, `extruder_idler.obj`, `test_3mf/…/Büchse.3mf` (tên Unicode); thêm: multi-plate, multi-color có wipe tower, tree support, Arachne, gyroid, paint, modifier, variable layer, STEP, boolean, H2D nhiều nozzle, spiral. Chạy 3 lần để dò phi tất định, và với 1/4/8 luồng TBB. File 3MF giữ config nhúng, và thử cả ghi-đọc: 3MF do iPad lưu phải mở được trên Mac với cùng config.
5. Chế độ: hủy ở 1%, 10%, 50%, 90% rồi slice lại, kết quả bằng lần sạch; bật ASan/TSan trên simulator; memory pressure giả lập.

**Khác:** Catch2 có sẵn `tests/fff_print`, `tests/filament_group` chạy trên Mac; chú ý `tests/libslic3r` đã không còn biên dịch theo ghi chú trong `tests/CMakeLists.txt`. Schema: snapshot JSON. Render: ảnh chuẩn so Mac với ngưỡng, lưu ý GL khác driver. Undo: hash model sau N thao tác. File: iCloud Drive, USB, SMB, tệp chưa tải, hết chỗ, đổi từ app khác. Không test trên simulator cho hiệu năng hoặc GLES.

## 12. Gói việc (mỗi file chỉ một chủ)

| ID | Việc | Sở hữu riêng | Chờ | Xong khi |
|---|---|---|---|---|
| I0 | Thí nghiệm E1–E5 | `ios/spikes/` | – | Có số đo |
| I1a | Deps iOS | `ios/cmake/deps/`, `ios/scripts/build_deps.sh` | E1 | Mọi `.a` là `platform iOS` (vtool) |
| I1b | CMake core + shim lib | `ios/CMakeLists.txt`, `ios/cmake/*.cmake`, `ios/shim/lib/` | I1a | Link được, slice cube trên máy |
| I1c | Cổng chất lượng G-code | `ios/tests/gcode/`, `ios/scripts/compare_gcode.py` | I1b | (a),(b) xanh trên corpus nhỏ |
| I2a | ABI | `ios/core/abi/` | I1b | Header đóng băng v1 + test |
| I2b | Shell SwiftUI | `ios/App/Shell`, `Icons`, `App.xcodeproj` (**chỉ I2b sửa project**) | I2a | Layout như desktop |
| I2c | Tệp + sao lưu | `ios/App/Files`, `ios/core/host/Session*` | I2a | Test §8 |
| I3a | Shim wx/GL/AppHost | `ios/shim/wx`, `shim/gl`, `shim/gui`, `ios/core/host/AppHost*` | E4 | Selection+3DScene+PartPlate biên dịch |
| I3b | GLES + shader | `ios/core/render/`, `ios/shaders/` | I3a | Cảnh + bàn in |
| I3c | Canvas + cử chỉ | `ios/App/Canvas`, `ios/core/host/Canvas*` | I3b | Chọn/kéo/xoay |
| I3d | G-code preview | `ios/core/render/gcode/` | I3b | AdvancedRenderer texture 2D |
| I4a | PlaterCore trích | `ios/core/extract/plater/` | I2a, I3a | Mở/lưu/undo/slice |
| I4b | Schema + cài đặt | `ios/core/extract/tab/`, `ios/App/Settings` | I2a | So danh sách khóa khớp Mac |
| I4c | Cây object | `ios/core/extract/objlist/`, `ios/App/Sidebar` | I4a | Thao tác ObjectList |
| I5x | Gizmo: 4 nhóm, mỗi agent một nhóm | `ios/core/gizmo/<nhóm>/` | I3c | Theo §4 |
| I6 | LAN, về sau | `ios/core/lan/`, `ios/App/Device` | I4 | – |

Quy tắc chống va: upstream `src/` **chỉ được sửa qua một người giữ khóa** (I3a), bằng patch nhỏ trong `#if TARGET_OS_IPHONE`, vì agent Windows (W2–W7) cũng đang sửa `GLCanvas3D`, `Plater`, `Field`, `GUI_App`. Mọi thứ khác đặt trong `ios/`. Đổi ABI phải qua I2a. Agent không sửa `project.pbxproj` ngoài I2b (dùng thư mục synchronized của Xcode để thêm file không đụng project). I4b không sửa `Tab.cpp`.

Thứ tự tới hạn: E1 → I1a → I1b → **I1c (dừng ở đây nếu G-code sai)** → I2a → song song {I2b, I2c, I4b} và {I3a → I3b → I3c/I3d} → I4a/I4c → I5.

## 13. Rủi ro lớn và thí nghiệm rẻ nhất

| # | Rủi ro | Thí nghiệm | Ngưỡng |
|---|---|---|---|
| R1 | Deps không build cho iOS (OCCT, OpenMeshCraft, GMP) | E1: chỉ GMP + TBB + OCCT ở `iphoneos`, 1 exe link `STEPCAFControl_Reader`; ½–1 ngày | OCCT lỗi → STEP tạm tắt, bàn lại |
| R2 | Shim GUI phình thành viết lại | E4: `-fsyntax-only` cho `Selection.cpp`, `3DScene.cpp`, `PartPlate.cpp`, `GLCanvas3D.cpp` với overlay + header giả; đếm lỗi/symbol | >400 symbol ở GLCanvas3D → trích thay vì cả file |
| R3 | Hết RAM | E2: CLI trên Mac, đo peak `footprint` với 5 model lớn, 1/4/8 luồng; rồi máy thật với 1 model nặng | Đỉnh >1,5 GB → giới hạn model + cảnh báo |
| R4 | G-code lệch giữa Mac và iOS | E3: libslic3r tối thiểu + cube + `extruder_idler`, diff | Lệch vượt dung sai → dừng |
| R5 | GLES: `RGBA32F` + `texelFetch` trong vertex shader đủ nhanh? | E5: app 1 view, 2 triệu segment instanced, texture 4096 rộng; ½ ngày | <20 fps → LOD theo layer; hoặc Metal cho preview |
| R6 | Hộp thoại đồng bộ trong logic trích | Trích riêng `update_print_fff_config`, viết test 10 ca decision | Không tách sạch → fork file đó |
| R7 | Trích hàm lỗi thời khi upstream đổi | Script sha (§4) chạy trên 20 commit gần nhất | >20% đổi/tháng → thu hẹp phần trích |
| R8 | Apple gỡ GLES | Không có thí nghiệm; chỉ để `render/` sau một lớp mỏng | – |
| R9 | `fork`, thread stack, nền app | Trong E3: chạy slice nền, kill, đo stack worker TBB (`pthread_get_stacksize_np`) | stack <2 MB → đặt lại qua TBB/arena |
| R10 | AGPL/App Store, ký | Hỏi pháp lý; pha đầu chỉ cài cá nhân | – |

## 14. Chưa biết

- Trần RAM thật của iPad Pro 11 2018 trên iPadOS 18, hiệu quả entitlement, RAM của đúng máy thử (4 hay 6 GB).
- Driver Apple có chấp nhận đủ 39 shader (mới kiểm bằng glslc ở ES 3.10, không phải 3.00).
- Số symbol thật phải shim (mới đếm bằng regex), phần Assembly/Overview kéo vào GLCanvas3D.
- Byte-equality G-code; tính tất định theo số luồng TBB.
- OCCT/TBB/OpenMeshCraft trên iOS; `load_files` trích được theo pha hay không.
- Cách hủy drag sạch giữa chừng trong `on_mouse`.
- `sizeof(MoveVertex)`, stack TBB, kích thước preset nạp thật.
