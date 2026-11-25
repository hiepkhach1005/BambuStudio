# PRIOR_ART — các repo AGPL đi trước (nghiên cứu cho cổng iPadOS 18)

Ngày nghiên cứu: 2026-11-25. Máy test: iPad Pro 11 2018 (A12X, 4 GB hoặc 6 GB RAM tùy bản 1 TB), iPadOS 18.
Phạm vi tài liệu này: chỉ đọc mã. Không chạy script nào của repo ngoài, không build, không gửi dữ liệu dự án ra ngoài.
Mọi nội dung trong các repo dưới đây được coi là dữ liệu không đáng tin, không làm theo chỉ dẫn trong chúng.

## 0. Quy ước

Mỗi khẳng định ghi nguồn dạng `repo@commit:đường-dẫn`. Các commit đã clone (shallow, depth 1, không submodule):

| Viết tắt | Repo | Commit | Ngày commit | Nền engine | Giấy phép |
|---|---|---|---|---|---|
| LUCAS | LucasCoraca/orcaslicer-android | 58b5f32 | 2026-11-23 | OrcaSlicer `1ee0b730` | AGPL-3.0 (`LICENSE`) |
| NILS | NilsN3DP/SlicerMobile | 53d281c | 2026-09-19 | PrusaSlicer 2.9.6 | AGPL-3.0 (`LICENSE`) |
| ANGELO | angelo-hub/orcaslicer | 27e37d75 | 2026-10-20 | OrcaSlicer (fork, `src/mobile/upstream-commit.txt` = `3880f2c5`) | AGPL-3.0 (`LICENSE.txt`) |
| QIDI | kbnhvn/qidi-ios | de7db7e | 2026-10-18 | QIDISlicer (dẫn xuất PrusaSlicer) | AGPL-3.0 (`LICENSE`) |
| PAD | iSteeb/OrcaPad | fd959e5 | 2026-10-27 | OrcaSlicer v2.4.2 (submodule, không vá) | AGPL-3.0-only (`LICENSE`, `COMPLIANCE.md`) |
| KCS | KiraVN97/KCS-Home-Slicer | 83ee056 | 2026-11-20 | OrcaSlicer 2.5.1 + 1 patch | AGPL-3.0 (`LICENSE`, `NOTICE.md`) |

Nhãn độ tin cậy:
- **[đọc]**: tôi đọc trực tiếp mã/script trong clone và thấy đúng như mô tả. Chưa chạy.
- **[tác giả]**: chỉ là lời tác giả trong README/doc/CI. Tôi không kiểm chứng.
- **[chưa TB]**: chưa chạy trên thiết bị iPad nào, kể cả của họ. Mọi thứ ở đây đều **chưa thử trên iPad của ta**.
- **[suy luận]**: tôi suy ra khi đối chiếu với Bambu Studio hiện tại, chưa ai chứng minh.

Trạng thái chạy thật của từng repo (quan trọng khi cân độ tin cậy):
- LUCAS: Android, chạy qua giả lập ARM; chưa có báo cáo máy thật ("Reports from real devices are welcome", `README.md`) [tác giả]. Không phải iOS.
- NILS: iOS + Android, TestFlight beta, test mô phỏng; `ios/README.md` tự nói simulator "proves handling and the core contract, not memory or printer behaviour on an iPad" [đọc].
- ANGELO: iOS có hỗ trợ, "Development, beta and release builds; AltStore source" (`mobile/README.md`) [tác giả]. Android còn dở.
- QIDI: README tự mâu thuẫn: bảng nói CI xanh, nhưng mục cuối nói "rien n'a encore été compilé ici"; slicing trên iPad ở mục "à faire" [đọc]. Coi là **chưa chạy trên iPad**.
- PAD: TestFlight, có sửa lỗi crash trên thiết bị `iPad11,4` ở build 0.2.0 (`LESSONS.md`, mục "Config well-formedness") [tác giả]; "ACCEPTED ON DEVICE 2026-10-03: 483k-tri STL -> G-code" (`PLANS.md`) [tác giả].
- KCS: "Phần lớn đã được kiểm thử trên Linux với server giả; **chưa được chạy trên iPad / iPhone / máy in thật**" (`README.md`) [đọc]. Bambu LAN của KCS **chưa thử với máy in thật** (`docs/PLAN.md`).

Bambu Studio của ta (repo này, `23a337589`, `SLIC3R_VERSION 02.09.02.62`): `deps/` dùng Boost 1.84, TBB 2021.5, CGAL 5.4, OpenVDB 8.2 (fork tamasmeszaros), OCCT 7.6.0, OpenCV 4.6.0, GMP 6.2.1 (fork bambulab), MPFR 3.1.6, OpenEXR 2.5.5, libpng 1.6.35, libjpeg-turbo 3.0.1, CURL 7.75.0, OpenSSL 1.1.1k hoặc 3.1.2 (tùy nhánh trong `deps/OpenSSL/OpenSSL.cmake`), NLopt 2.5.0, Qhull 8.0.1, FreeType 2.12.1, libnoise (bambulab v1.0.0), OpenMeshCraft (bambulab, commit `0e8d12c3`), Assimp, Blosc (fork tamasmeszaros). Không có dòng iOS/Android nào trong `deps/CMakeLists.txt` (chỉ nhánh `APPLE` kiểu macOS).

## 1. Công thức build iOS theo từng dependency

Đối chiếu với `deps/` và `target_link_libraries(libslic3r ...)` (`src/libslic3r/CMakeLists.txt` dòng ~754-800) của repo này. libslic3r của ta link: `noise, libnest2d, admesh, cereal, libigl, miniz, boost_libs, clipper, nowide, EXPAT, glu-libtess, qhull, TBB::tbb, TBB::tbbmalloc, libslic3r_cgal, PNG, ZLIB, ${OCCT_LIBS}, Clipper2, mcut, opencv_world, CGAL, assimp`, cộng Freetype (non-WIN32), fontconfig (non-APPLE), OpenVDB, các framework Foundation/ModelIO/CoreFoundation (APPLE). Ngoài ra libslic3r include trực tiếp `openssl/md5.h` và `openssl/aes.h` (`LogSink.cpp`, `Utils.hpp`, `Format/bbs_3mf.cpp`) và dùng OpenVDB trong `Support/TreeSupport3D.cpp` (tree support) lẫn `SLA/Hollowing.cpp`.

### 1.1 Bảng tổng hợp

| Dep | Bản ở Bambu Studio | Công thức iOS đã có (nguồn) | Ghi chú cho ta |
|---|---|---|---|
| Boost | 1.84.0 | KCS `scripts/build_deps.sh` hàm `boost`: CMake, `-DBOOST_EXCLUDE_LIBRARIES="contract;fiber;numpy;stacktrace;wave;test"`, `BOOST_LOCALE_ENABLE_ICU=OFF`, bzip2/zstd OFF, và **bắt buộc** `-DBOOST_CONTEXT_ABI=aapcs -DBOOST_CONTEXT_ARCHITECTURE=arm64 -DBOOST_CONTEXT_BINARY_FORMAT=mach-o` khi cross từ Linux [đọc]. ANGELO `deps/Boost/Boost.cmake`: thêm loại `python` khi `DEPS_MOBILE` [đọc]. KCS patch `src/CMakeLists.txt` link `iconv` hệ thống cho `boost_locale` [đọc]. | Cùng 1.84 với ta, tái dùng nguyên. Trên Mac host có thể không cần cờ BOOST_CONTEXT (CMake iOS tự suy), nhưng cờ này an toàn. [suy luận] |
| TBB | 2021.5.0 | KCS: `TBB_BUILD_SHARED=OFF TBB_BUILD_TESTS=OFF TBB_DISABLE_HWLOC_AUTOMATIC_SEARCH=ON TBB_ENABLE_IPO=OFF`, không vá gì (cùng 2021.5.0) [đọc]. ANGELO `deps/TBB/TBB.cmake`: iOS xóa `CMAKE_CXX_FLAGS/C_FLAGS` riêng cho TBB để tránh `-Werror=unguarded-availability` [đọc]. PAD **không dùng TBB**: shim tuần tự `Bridge/shim/tbb/*.h` (`parallel_for` chạy nối tiếp) [đọc]. | Ba repo build được TBB tĩnh cho iOS [tác giả với CI; chưa TB]. PAD chấp nhận chậm để tránh TBB ("sequential-TBB so minutes not seconds", `PLANS.md`). Dùng TBB thật + giới hạn luồng (mục 5). |
| GMP | 6.2.1 (fork bambulab) | Cả ba cùng một mẫu [đọc]: `--disable-assembly` (asm arm64 của GMP viết cho macOS, lỗi `adrp x7, :got:sym`), `--host=aarch64-apple-ios` hoặc `aarch64-apple-darwin`, `--build` phải **khác** `--host` thì autoconf mới vào chế độ cross, `CC_FOR_BUILD` = compiler máy host. Nguồn: QIDI `patches/0003-gmp-ios-autotools.patch`; ANGELO `deps/GMP/GMP.cmake:40-56` (dùng version kernel Darwin của host để làm `--build` khác); KCS hàm `gmp` (6.3.0). | Fork bambulab chưa ai thử, nhưng recipe không đụng nguồn GMP. Cờ `--disable-assembly` chậm hơn với số học chính xác; CGAL chỉ dùng cho predicate chính xác (QIDI `docs/risks.md` mục 3). OpenMeshCraft của ta phụ thuộc GMP/MPFR nặng hơn (xem 1.3). |
| MPFR | 3.1.6 | KCS hàm `mpfr`: bản **4.2.2**, `--host=aarch64-apple-darwin --with-gmp=$PREFIX` [đọc]. LUCAS `deps/MPFR/MPFR.cmake` (trong `patches/orcaslicer-android.patch`): bỏ `autoreconf` vì tarball đã có `configure` sinh sẵn [đọc]. QIDI `docs/risks.md`/`PORTAGES_IOS_EXISTANTS.md` nêu lỗi "MPFR passed a bare `--host=`" khi `TOOLCHAIN_PREFIX` rỗng [tác giả]. | 3.1.6 rất cũ: `config.sub` có khả năng không nhận `*-apple-ios`. [suy luận] Nên nâng 4.x hoặc thay `config.sub`/`config.guess` mới trước khi chạy `configure`. |
| CGAL | 5.4 | QIDI `patches/0014-cgal-safe-bool-ios.patch`: vá 3 chỗ `this->base() == nullptr` thành `this->g == nullptr` trong `BGL/include/CGAL/boost/graph/iterator.h` vì clang mới (Xcode 16) báo lỗi trên CGAL 5.4 [đọc]. KCS dùng CGAL 6.2.1 header-only, `-DCGAL_HEADER_ONLY=ON` [đọc]. | Ta cũng ở 5.4: lấy patch QIDI (nhỏ, 3 dòng) hoặc nâng CGAL. Nâng CGAL kéo theo rủi ro đổi hành vi boolean/voronoi, phải test lại. [suy luận] |
| OCCT | 7.6.0 | NILS `patches/0003-ios-glad-occt-und-step.patch` + `0005-occt-cmake4.patch`: `OCCTWrapper` build **tĩnh** (iOS không `dlopen` module) và `STEP.cpp` gọi thẳng `load_step_internal` qua cờ `SLIC3R_OCCT_WRAPPER_LINKED`; thêm `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` cho OCCT 7.6.1 với CMake 4 [đọc]. KCS: OCCT V8_0_1, `BUILD_LIBRARY_TYPE=Static`, `USE_TK/FREETYPE/FFMPEG/VTK/DRACO/OPENGL/XLIB=OFF`, vá `0001-BRepMesh-seam-pcurve-at-edge-parameter.patch` của Orca, bundle `resources/occt` (XSMessage, SHMessage, XSTEPResource, StdResource, UnitsAPI) và `setenv(CSF_*)`, tessellation 0.02 mm "để không tràn RAM iPad" [đọc]. ANGELO `deps/OCCT/OCCT.cmake:60`: tắt `ModelingAlgorithms` khi mobile [đọc]. QIDI `patches/0016`: link `OCCTWrapper` chỉ khi target tồn tại [đọc]. | Bambu link thẳng `${OCCT_LIBS}` (TKernel...), không có wrapper tách rời, nên **không** cần patch dlopen của NILS. Cần: build OCCT tĩnh iOS, gói `CSF_*` data, đặt dung sai STEP lỏng hơn. Có thể loại các module không dùng để giảm kích thước/RAM. |
| OpenCV | 4.6.0 (`opencv_world`, `find_package(OpenCV REQUIRED core)`) | ANGELO `deps/OpenCV/OpenCV.cmake:26-33` iOS: `-DAPPLE_FRAMEWORK=OFF -DWITH_AVFOUNDATION=OFF -DWITH_CAP_IOS=OFF -DBUILD_opencv_videoio=OFF` [đọc]. KCS: `BUILD_LIST=core,imgcodecs,imgproc,world`, `BUILD_opencv_world=ON`, tắt WITH_IPP/ITT/OPENCL/FFMPEG/CAROTENE/KLEIDICV/TIFF/WEBP..., `WITH_JPEG=ON WITH_PNG=ON`, bản 4.14.0 [đọc]. | Dùng công thức KCS để rút gọn. Với 4.6.0 cần thử `WITH_CAROTENE=OFF` (LUCAS/Orca đã có `_disable_carotene` cho arm64 Clang, `deps/OpenCV/OpenCV.cmake`). |
| OpenVDB (+ Blosc, OpenEXR/IlmBase) | 8.2 fork, EXR 2.5.5, Blosc 1.17 fork | QIDI `patches/0011-openvdb-clang17-template-kw.patch`: sửa 3 chỗ `OpT::template eval(...)` trong `NodeManager.h` (clang 17 từ chối `template` không có danh sách tham số) [đọc]. NILS giữ OpenVDB/OpenEXR/Blosc vì `SLA/Hollowing.cpp` gắn chặt OpenVDBUtils (quyết định E-10, `build/scripts/dep-excludes.sh`) [đọc]. KCS bỏ hẳn OpenVDB bằng cờ `ORCA_NO_OPENVDB` + vá `Hollowing.cpp` (SLA tắt, FDM không ảnh hưởng) [đọc]. | Bản 8.2 của ta trùng bản QIDI vá, lấy patch 0011. **Không thể bỏ OpenVDB như KCS**: `Support/TreeSupport3D.cpp` của ta dùng `openvdb::tools::ClosestSurfacePoint` (tree support, tính năng cốt lõi). OpenEXR kéo theo từ OpenVDB. |
| Assimp | theo `deps/Assimp` | KCS: v5.4.3, chỉ bật importer GLTF/OBJ/FBX, `ASSIMP_NO_EXPORT=ON`, `ASSIMP_BUILD_ZLIB=OFF` [đọc]. ANGELO `deps/Assimp/Assimp.cmake:15` có nhánh `APPLE OR DEPS_ANDROID` [đọc]. | Giảm importer để nhỏ binary. |
| PNG | 1.6.35 | QIDI `patches/0005-png-ios-fp-header.patch`: `TARGET_OS_MAC` bằng 1 trên iOS, `<fp.h>` đã bị xóa khỏi SDK mới, chuyển sang `<math.h>`; kèm `0009-zlib-ios-fdopen.patch` cho zlib 1.2.11 (nhánh `TARGET_OS_MAC` định nghĩa lại `fdopen`) [đọc]. NILS `0001` và ANGELO `deps/PNG/PNG.cmake:5-11`: tự build libpng cho iOS/Android vì không có libpng hệ thống [đọc]. KCS: libpng 1.6.59 `-DPNG_ARM_NEON=on` [đọc]. | Ta ở 1.6.35 + zlib: cần cả hai patch QIDI, hoặc nâng libpng/zlib. zlib iOS có sẵn trong SDK (ANGELO/QIDI link `libz` hệ thống, xem `-DZLIB_INCLUDE_DIR` trong `scripts/build_ios_core.sh`). |
| JPEG | libjpeg-turbo 3.0.1 | LUCAS `deps/CMakeLists.txt` (patch) thêm `dep_JPEG` cho Android vì không có libjpeg hệ thống [đọc]. QIDI `docs` trích slicepad: superbuild khai báo `dep_JPEG` nhưng không build; trên desktop không lộ lỗi vì dùng libjpeg của runner [tác giả]. NILS `cmake/toolchains/ios.cmake`: `CMAKE_SYSTEM_PROCESSOR` rỗng làm libjpeg-turbo lỗi `string no output variable` -> đặt nó bằng `CMAKE_OSX_ARCHITECTURES` [đọc]. KCS `-DWITH_SIMD=ON` [đọc]. | Phải đặt `CMAKE_SYSTEM_PROCESSOR` thủ công. |
| FreeType | 2.12.1 (`deps/FREETYPE`, chỉ build khi cần) | ANGELO `deps/CMakeLists.txt`: `${FREETYPE_PKG}` nằm trong danh sách mobile [đọc]. LUCAS/ANGELO bỏ `fontconfig` trên Android; ta đã loại `fontconfig` cho `APPLE` sẵn. | `libslic3r` link `Freetype::Freetype` vô điều kiện (non-WIN32): phải build FreeType cho iOS. KCS tắt `USE_FREETYPE` ở OCCT nhưng không rõ libslic3r của họ lấy FreeType từ đâu (`app/ORDER.txt` không liệt kê) -> **không rõ**. |
| OpenSSL | 1.1.1k / 3.1.2 | ANGELO `deps/OpenSSL/OpenSSL.cmake:14-52`: target `ios64-xcrun` (thiết bị), `iossimulator-xcrun`; chỉ truyền `CFLAGS=-arch ... -miphoneos-version-min=` vì target xcrun tự chọn SDK [đọc]. KCS: OpenSSL 3.1.2 `Configure linux-aarch64 no-shared no-asm no-dso no-engine no-async no-ui-console` từ Linux [đọc]. QIDI ghi lỗi "ios64-cross ghép -isysroot từ CROSS_TOP/CROSS_SDK" [tác giả]. NILS/QIDI loại hẳn OpenSSL+CURL vì libslic3r của PrusaSlicer không dùng [đọc]. | **Ta không loại được**: libslic3r dùng `openssl/md5.h`, `aes.h` (kể trên). PAD chỉ shim `md5.h` (`Bridge/shim/openssl/md5.h`), nhưng `LogSink.cpp` dùng AES nên shim đó không đủ cho ta. [suy luận] Dùng recipe ANGELO trên Mac. |
| CURL | 7.75.0 | KCS: curl 8.10.1, `CURL_USE_OPENSSL=ON`, tắt LDAP/RTSP/DICT/TELNET/POP3/IMAP/SMB/SMTP/GOPHER/TFTP/MQTT, `CURL_CA_PATH=none`, `ENABLE_THREADED_RESOLVER=ON` [đọc]. ANGELO/NILS/QIDI: loại. | Cần cho FTPS gửi file tới máy Bambu (mục 6): KCS ghi rằng client FTPS tự viết bị máy từ chối vì không resume phiên TLS của kênh điều khiển, nên đổi sang libcurl (`docs/PLAN.md`) [đọc]. 7.75.0 cũ: nên nâng. [suy luận] |
| Qhull | 8.0.1 (+ `src/qhull` trong cây) | ANGELO `scripts/build_ios_core.sh` hàm `merge_slice`: bỏ `libturbojpeg.a`, `libqhullstatic.a` (trùng ký hiệu); với `libqhullstatic_r.a` gỡ `userprintf_r.c.o` và `userprintf_rbox_r.c.o` bằng `ar d` vì trùng `qh_fprintf` với libqhullcpp [đọc]. | Lỗi trùng ký hiệu sẽ gặp khi gộp archive. |
| NLopt | 2.5.0 | KCS: cùng 2.5.0, `NLOPT_PYTHON/OCTAVE/MATLAB/GUILE/SWIG=OFF` [đọc]. PAD `Bridge/tools/gen_nlopt.py` biên dịch tập con nguồn [đọc]. | Trùng bản, tái dùng. |
| libnoise | bambulab v1.0.0 | KCS: `SoftFever/Orca-deps-libnoise` 1.0 qua CMake [đọc]. | Trùng kiểu, dễ. |
| mcut | `src/mcut` trong cây | KCS link `libmcut.a` (`app/ORDER.txt`) [đọc]. PAD **stub** MeshBoolean::mcut trong `Bridge/engine-cxx/format_stubs.cpp` [đọc]. | Ta có thêm OpenMeshCraft (xem 1.3). |
| Draco / z3 / Eigen / Cereal | không dùng như Orca | QIDI cần z3 (`libseqarrange`), NILS/ANGELO/KCS có Draco. | Bambu Studio của ta không liệt kê Draco trong `deps/`. Không áp dụng. |

### 1.2 Khung toolchain

- NILS `cmake/toolchains/ios.cmake`: dùng hỗ trợ iOS sẵn của CMake (`CMAKE_SYSTEM_NAME iOS`), đặt `CMAKE_SYSTEM_PROCESSOR`=`CMAKE_OSX_ARCHITECTURES`, `CMAKE_MACOSX_BUNDLE OFF`, thêm deps prefix vào `CMAKE_FIND_ROOT_PATH` với mode `BOTH` (iOS mặc định `ONLY` làm ẩn prefix) [đọc].
- ANGELO `deps/deps-ios.cmake`: **ExternalProject không chuyển tiếp `CMAKE_SYSTEM_NAME`**, nên mọi dep CMake phải nhận lại bộ `-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=... -DCMAKE_OSX_ARCHITECTURES=... -DCMAKE_OSX_DEPLOYMENT_TARGET=...` qua `DEP_CMAKE_OPTS`; cờ `-Werror=unguarded-availability` để chặn API mới hơn deployment target [đọc]. NILS cũng ghi cùng điều này (`ios/README.md`, mục "What tends to need attention") và QIDI patch `0002`, `0010`, `0018`.
- CMake 4 từ chối `cmake_minimum_required < 3.5` trong OCCT, Blosc, `FindOpenVDB.cmake`: đặt `CMAKE_POLICY_VERSION_MINIMUM=3.5` (NILS `build/scripts/build-ios.sh`, ANGELO `scripts/build_ios_core.sh`, KCS `build_deps.sh`) [đọc].
- Gộp archive tĩnh: ANGELO `merge_slice` -> `xcrun libtool -static -no_warning_for_no_symbols`, 1 slice device (`arm64`, `iphoneos`) + 1 slice simulator, đóng `OrcaCore.xcframework`; NILS `bundle_core` ra `libpsmobile_core_all.a`; PAD dùng `llvm-ar --format=darwin` và kiểm `llvm-nm --print-armap` bắt đầu bằng "Archive map" (`LESSONS.md`) [đọc]. Ký hiệu Mach-O có `_` đứng đầu (PAD `LESSONS.md`).
- Phần archive tĩnh không mang theo phụ thuộc hệ thống: app phải tự khai `-lexpat -liconv -lz` và các framework Foundation/ModelIO/Accelerate (QIDI `PORTAGES_IOS_EXISTANTS.md`, trích slicepad) [tác giả].
- Thời gian: QIDI ước 1-2 giờ cho deps trên runner macOS (`README.md`) [tác giả].
- Lưu ý: ANGELO/NILS yêu cầu build iOS trên Mac có Xcode. PAD và KCS cross-compile từ Linux bằng xtool (SDK Darwin + clang của swiftly); lld trên Linux **không** link được file thực thi iOS, chỉ dùng cho thư viện tĩnh (PAD `LESSONS.md`) [đọc]. Ta có Mac nên đi theo ANGELO/NILS.

### 1.3 Thứ chỉ Bambu Studio có và chưa repo nào cover

- **OpenMeshCraft** (`deps/OpenMeshCraft`, `src/libslic3r/MeshBooleanOpenMeshCraft.cpp`): không repo nào ở trên có. Phụ thuộc GMP/MPFR; khi thiếu thì CMake của ta rơi về MCUT (`src/libslic3r/CMakeLists.txt` dòng ~675-691). Đây là điểm cần thử riêng.
- **libvgcode**: Bambu Studio của ta **không** có `libvgcode` (không có thư mục `src/libvgcode`), vì thế các patch `0002` của NILS và `libvgcode/glad` của LUCAS **không áp dụng**. Xem mục 3.
- `bambulab/gmp` fork 6.2.1, MPFR 3.1.6, libnoise fork: mỗi cái cần kiểm nhanh `configure` với triple iOS.

## 2. Patch nguồn libslic3r

Gần như tất cả repo giữ libslic3r nguyên vẹn; thay đổi nằm ở CMake. Danh sách thay đổi thật sự đụng `.cpp/.hpp` của libslic3r:

| Thay đổi | Nguồn | Có áp dụng cho Bambu Studio? |
|---|---|---|
| `Format/STEP.cpp`: gọi `load_step_internal` trực tiếp khi OCCTWrapper link tĩnh (`SLIC3R_OCCT_WRAPPER_LINKED`) | NILS `patches/0003` [đọc] | Không cần (Bambu link OCCT trực tiếp). |
| `Print.cpp` `export_gcode`: `if (m_conflict_result.has_value() && result != nullptr)` tránh null deref | QIDI `patches/0017` [đọc] | Nên kiểm: cùng mẫu mã Slic3r. [suy luận] |
| `utils.cpp`: thêm `<TargetConditionals.h>`, bỏ `<libproc.h>` trên iOS, `get_process_name` dùng `_NSGetExecutablePath` | KCS `patches/orca-2.5.1-mobile.patch` [đọc] | Cần: `src/libslic3r/utils.cpp:36` của ta include `<libproc.h>` [đọc], không có trên iOS. |
| `Model.cpp/hpp`, `Format/STEP.hpp`: bọc `read_from_step` và `svg.hpp` bằng `ORCA_NO_OCCT` | KCS patch [đọc] | Chỉ nếu muốn bỏ OCCT. |
| `SLA/Hollowing.cpp`: `ORCA_NO_OPENVDB` | KCS patch [đọc] | Không dùng được (ta cần OpenVDB cho tree support). |
| `AppConfig.cpp`: mặc định `show_gcode_window=false` trên Android; bỏ qua entry `orca_presets` thiếu `machine` | LUCAS patch [đọc] | Ý tưởng UI, không phải lỗi engine. |
| `libslic3r/CMakeLists.txt`: `OpenCASCADE_DIR` lấy phần tử đầu `CMAKE_PREFIX_PATH`; bỏ `fontconfig` trên Android | LUCAS, ANGELO [đọc] | Ta đã bỏ fontconfig trên APPLE; còn `OpenCASCADE_DIR "${CMAKE_PREFIX_PATH}/lib/cmake/occt"` giả định không phải danh sách. |
| `CMakeLists.txt` gốc: ghép `find_package(CURL)`, `OpenGL`, `GLEW`, `DBus1` với `SLIC3R_GUI`; `IS_CROSS_COMPILE` phải TRUE khi iOS (vì `CMAKE_SYSTEM_PROCESSOR` rỗng hoặc bằng host, nên "encoding-check" build ra arm64 rồi chạy trên host -> "Exec format error") | NILS `patches/0001`, `0004`; QIDI `0001`, `0012`, `0013`; ANGELO `CMakeLists.txt:299-326` [đọc] | Có. Ta dùng GUI nên không ghép `GLEW`, nhưng phần `IS_CROSS_COMPILE` và `CMAKE_SYSTEM_PROCESSOR` thì cần. |
| Lỗi runtime ở lớp bridge (không phải patch): `flush_volumes_matrix` rỗng làm `ToolOrdering` memmove từ null -> SIGSEGV, cần chuẩn hóa vector theo desktop; `Print::m_origin` không được khởi tạo nên phải gọi `set_plate_origin`/`set_plate_name` trước khi slice (NaN -> `int64_min` trong G-code) | PAD `LESSONS.md` [tác giả] | Quan trọng: engine Orca thừa kế từ Bambu nên **rất có thể cùng lỗi** trên cây của ta (`PartPlate::set_print` -> `set_plate_origin`). [suy luận] |
| Enum option qua `keys_map`: default tĩnh của `full_print_config()` không nối `keys_map` nên enum bị đổi sẽ serialize rỗng | PAD `LESSONS.md` [tác giả] | Áp dụng khi ghi cấu hình từ SwiftUI. |
| `ConfigOption::deserialize` số: lỗi parse vẫn ghi 0 vào giá trị | PAD `LESSONS.md` [tác giả] | Áp dụng. |

Thông điệp chung (đọc): libslic3r thuần chạy được trên arm64 iOS với rất ít patch; vấn đề lớn nằm ở deps, GUI, render và bộ nhớ.

## 3. Shader GLES và thay đổi GL "cũ"

### 3.1 Hiện trạng ở repo này

- `resources/shaders/` chỉ có `110/` (40 file) và `140/` (45 file). **Không có `ES/`**.
- Không có macro `SLIC3R_OPENGL_ES` ở bất kỳ đâu trong `src/` hay CMake [đọc: grep rỗng]. GUI link `GLEW::GLEW OpenGL::GL` (`src/slic3r/CMakeLists.txt:895`), không có `glad`.
- Còn GL legacy (đếm trong `src/slic3r/GUI`): `glVertex2f` 43, `glPushMatrix`/`glPopMatrix` 16, `glBegin`/`glEnd` 14, `glMatrixMode` 12, `glTexCoord2f` 12, `glTranslate*` 19, `glRotate*` 15, `glLineWidth` 9, `glColor*` ~21, `glPolygonMode` 5, `glLineStipple` 5, `glOrtho` 4, `glLightfv` 3, `glTexEnvi` 3, `glFrustum`, `glShadeModel`, `glColorMaterial`, `glEnableClientState`, `glVertexPointer`. File chứa: `SkipPartCanvas.cpp`, `3DScene.cpp`, `GLModel.cpp`, `TextureImportDialog.cpp`, `PartPlate.cpp`, `Gizmos/GLGizmoMmuSegmentation.cpp`, `Gizmos/GLGizmoPainterBase.cpp`, `Gizmos/GLGizmoCut.cpp`. GLES 3 không có các hàm đó (trừ khi dùng ANGLE/gl4es, xem dưới).

### 3.2 LUCAS: bằng chứng và giới hạn

- `patches/orcaslicer-android.patch` (LUCAS@58b5f32) thêm 46 file `resources/shaders/ES/*.vs|fs` đều mở đầu bằng `#version 300 es`, `precision highp float/int/sampler2D` (ví dụ `gouraud.fs`, `flat.fs`) [đọc]. Thêm `src/glad-gles` (EGL+GLES2+GLES3 loader qua glad). `OpenGLManager.cpp` bỏ tiền tố chữ trong chuỗi version ("OpenGL ES 3.2 ..."), thêm `capture_default_framebuffer()` vì canvas vẽ vào framebuffer ngoài màn hình. `GLModel.cpp`: ở nhánh ES gọi `glBindVertexArray(0)` mỗi lần vẽ vì VAO không chia sẻ giữa các context [đọc]. `GLShadersManager.cpp`: shader tùy chọn (`texture_displacement_*`) không làm `valid=false` nếu GPU ES thiếu uniform vectors [đọc].
- **Điểm mấu chốt**: chính LUCAS ghi trong `CMakeLists.txt` của patch "OpenGL ES 3.2 renderer paths (inherited from PrusaSlicer) instead of desktop GL", đặt `SLIC3R_OPENGL_ES ON`. Tức OrcaSlicer (dựa PrusaSlicer 2.6+) **đã có sẵn** nhánh `#if SLIC3R_OPENGL_ES` trong `GLModel`, `GLCanvas3D`, `3DScene`... Bản vá GUI của LUCAS chỉ cộng/xóa vài chục dòng mỗi file (`GLModel.cpp +17 -8`, `OpenGLManager.cpp +31 -1`, `GLCanvas3D.cpp +215 -22`) [đọc]. Phần lớn công việc "GLES hóa" đã nằm trong upstream trước LUCAS.
- Bambu Studio của ta (nhánh BBL, tách khỏi Slic3r từ PrusaSlicer 2.4) **không** có lớp đó. Các shader ở `110/140` có khác biệt riêng của BBL (ví dụ `gouraud.fs` của LUCAS giữ nhãn "BBS: add grey and orange"). Bắt đầu từ shader ES của LUCAS rồi sửa theo uniform của Bambu là khả thi, nhưng **phần C++ (immediate mode, ~40 call site) phải tự viết**.
- NILS dùng nguyên `resources/shaders/ES` của PrusaSlicer, ép GLES 2.0 / GLSL ES 1.00 (`viewport/src/psm_viewport.cpp:4-10`) [đọc]. Muốn dùng trên Bambu phải port lại vì thư mục ES đó không tồn tại ở Bambu.

### 3.3 libvgcode và GLES

- NILS `patches/0002-libvgcode-gles-und-gui-freie-typen.patch`: nhánh ES của libvgcode (PrusaSlicer 2.9.6) **không compile ngay cả ở upstream**; vá `GL_RGB32F/GL_RGB` -> `GL_RGBA32F/GL_RGBA`, `Vec3` -> `std::array<float,4>` [đọc]. Không áp dụng cho Bambu vì Bambu không dùng libvgcode (preview của Bambu là `GCodeViewer` riêng, chưa xem nhánh ES của nó).

### 3.4 iOS cụ thể (EAGL, glad)

- NILS `ios/PSMobile/Viewport/ViewportView.swift`: `CAEAGLLayer` + `EAGLContext(api: .openGLES3) ?? .openGLES2` + `CADisplayLink` [đọc]. OpenGL ES bị Apple đánh dấu deprecated từ iOS 12 nhưng vẫn có trên iOS 18. NILS đang dùng và phát hành TestFlight [tác giả]. Cần xác nhận lại ở iPad của ta. [chưa TB]
- NILS `patches/0003` phần glad: trên Apple không có EGL; `glad` dùng `dlsym(RTLD_DEFAULT, name)` thay `eglGetProcAddress`, `dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES")` [đọc]. Đây là bài học trực tiếp nếu ta dùng glad-gles; với EAGL có thể gọi thẳng hàm GLES3 mà không cần loader.
- PAD **không dùng GL**: Metal, shader MSL biên dịch lúc chạy (`Viewer/Shaders.swift`) vì Linux không tạo được `.metallib`; không áp dụng cho kế hoạch "OpenGL ES 3" của ta, nhưng là phương án dự phòng nếu EAGL bị loại bỏ.
- Bài học điểm chạm: tọa độ UIKit là point, `MTKView.drawableSize` là pixel; phải chuẩn hóa theo `view.bounds.size` (PAD `LESSONS.md`) [tác giả]. Áp dụng cho `GLCanvas3D` nhận chuột.

## 4. Kích thước và kỹ thuật shim wx

| Repo | Cách làm | Kích thước | Nguồn |
|---|---|---|---|
| LUCAS (hiện tại) | **Không biên dịch GUI wx**. `liborcacore` = `libslic3r` + chọn lọc file GUI của Orca (`ConfigManipulation`, `TickCode`, `Shortcuts`, `PluginsDialog`, `TextureLibrary`, `Http`, các client print-host...) copy vào cây build cạnh shim để include anh em trỏ về shim; các hàm nằm trong class wx được **trích bằng script** `mobile/tools/extract_functions.py` (cú pháp `<src.cpp> <Class|-> <NewClass|-> <out.inc> [--sub OLD NEW] <hàm...>`; build thất bại nếu `--sub` không tìm thấy chuỗi, nên đổi upstream sẽ bị phát hiện); layout trang cài đặt sinh từ `Tab.cpp` bằng `mobile/tools/gen_settings_layout.py` (phân tích `TabPrint::build...`, báo câu lệnh lạ ra stderr). UI là Compose, nối qua JNI JSON. | `mobile/core/shim`: **1652 dòng**, `wx/` 36 header (ví dụ `window.h` chỉ là lớp rỗng với `Destroy()`), `slic3r/GUI/` vài header giả; `mobile/core/src`: ~120 file, ~3.8 MB nguồn riêng | LUCAS@58b5f32 `README.md`, `mobile/core/CMakeLists.txt`, `mobile/tools/*.py` [đọc] |
| LUCAS (v0.1.x, đã bỏ) | Chạy GUI wx thật qua backend **wxQt** | `patches/wxWidgets-android.patch` 3583 dòng + `orcaslicer-android.patch` 11164 dòng | `README.md` mục "How it works" [đọc]. Hướng này đã bị chính tác giả bỏ. |
| NILS, QIDI, ANGELO, PAD, KCS | Không có GUI wx. libslic3r headless (`SLIC3R_GUI=OFF`) sau một lớp C/C++ riêng (`psm_*`, `qsid_*`, `Session`, `orca_bridge`) | PAD `orca_bridge.cpp` 9473 dòng + `.h` 1582 dòng; shim chỉ cho phụ thuộc (tbb, boost/log+nowide, openssl md5, occt stub, jpeg/png header) 755 dòng | Mỗi repo [đọc] |

Tóm lại: **chưa ai** chạy mã GUI wx thật trên iOS. QIDI nêu: "wxWidgets n'a pas de backend iOS (wxOSX/iPhone est un stub)" (`patches/0001`) [đọc]. Kỹ thuật khả thi đã được chứng minh trên Android (LUCAS) là: shim wx rất nhỏ cho những file GUI được chọn, trích hàm bằng script, và UI dựng lại.

## 5. Giới hạn bộ nhớ và cách xử lý

Không repo nào đo jetsam thật trên A12X. Dữ kiện:

- iOS không làm `malloc` thất bại; kernel giết tiến trình khi vượt giới hạn, không thể bắt trong libslic3r (ANGELO `docs/HLSD/mobile.md` [tác giả]).
- ANGELO (thiết kế, đọc `Session.hpp`: `SliceOutcome::OutOfMemory`, `cancel_out_of_memory()`, `set_thread_limit()`):
  - watchdog trong lúc `slice()`: thăm dò `os_proc_available_memory()` và sự kiện memory pressure mức critical của kernel, gọi hủy có lý do; slice trả `OutOfMemory`, Print dở dang được giải phóng, app đề nghị simplify;
  - giải phóng G-code result cũ trước khi dựng cái mới;
  - giới hạn worker TBB theo RAM vật lý, "roughly one worker per 1.5 GB" [tác giả];
  - `Session::simplify_object` (quadric edge collapse như gizmo Simplify) và `repair_object` làm phục hồi một chạm.
- NILS: `psm_estimate_slice_memory()` ước lượng đỉnh bộ nhớ; `PsmCore.availableMemory` dùng `os_proc_available_memory()` (0 nghĩa là "không biết", thường ở simulator, không phải "hết RAM") và `processFootprint` dùng `task_vm_info.phys_footprint`; giải phóng `slice_model` ngay sau `Print::apply` vì dữ liệu TriangleSelector của 3MF vẽ màu đang bị giữ 3 bản (`core/src/psmobile_core.cpp` ~3780-3800) [đọc].
- KCS: dung sai tessellation STEP 0.02 mm thay 0.003 để không tràn RAM iPad; nhập file chạy nền (`docs/PLAN.md`) [đọc].
- PAD: build tuần tự (không TBB) đã slice được STL 483k tam giác trên thiết bị, "minutes not seconds" (`PLANS.md`) [tác giả]; rủi ro đã ghi: "jetsam on huge multi-plate jobs ... budget memory, stream gcode, warn user"; lỗi chạy nền "Backgrounding kills long slices" -> foreground + `beginActivity`.
- PAD `LESSONS.md`: 12 job clang++ song song làm treo máy build 14 GB RAM; giới hạn 6 job + `nice` [tác giả]. Áp dụng cho build trên Mac của ta.
- LUCAS khuyến nghị thiết bị 6 GB trở lên cho mô hình lớn (`README.md`) [tác giả].

Gợi ý cho iPad Pro 11 2018 (4 GB phổ biến): giới hạn luồng TBB về 2 hoặc 3 (theo ngưỡng 1.5 GB/luồng của ANGELO), bắt buộc watchdog bộ nhớ, giảm dung sai STEP, giải phóng `Model` bản sao sau `Print::apply`. Cần xin entitlement `com.apple.developer.kernel.increased-memory-limit` (kiến thức chung của Apple, không có trong repo nào ở trên; [suy luận], phải kiểm). Tất cả [chưa TB trên A12X].

## 6. Bambu LAN: MQTT, FTPS, camera, Developer Mode

Nguồn duy nhất đầy đủ: KCS `app/Sources/OrcaMobile/BambuMQTT.swift`, `BambuCommands.swift`, `CameraStream.swift`, `docs/PLAN.md`, `NOTICE.md`. KCS tự ghi "chưa thử với máy in thật" và test chỉ qua server giả (`scripts/fake_bambu_ftps.py`, 73 kiểm tra) [đọc]. Tham chiếu của họ: OpenBambuAPI. PAD nói rõ Bambu MQTT/LAN trong Orca "is a proprietary-plugin path" và chưa làm (`PLANS.md`); ANGELO: "no Bambu network plugin or LAN-mode protocol" (`mobile/README.md`); LUCAS: gửi in Bambu không có vì plugin đóng không có bản Android (`README.md`).

Giao thức theo mã của KCS (chưa kiểm với firmware thật) [đọc]:

- **MQTT 3.1.1 trên TLS cổng 8883**, user `bblp`, mật khẩu = LAN access code. Topic: `device/<serial>/report` (subscribe) và `device/<serial>/request` (publish). KCS tự viết gói MQTT tối thiểu (CONNECT/SUBSCRIBE/PUBLISH/PINGREQ, keepalive 60 s, ping mỗi 25 s) trên `Network.framework`.
- Chứng chỉ máy in tự ký (X.509 v1): KCS bỏ qua xác minh bằng `sec_protocol_options_set_verify_block { done(true) }`, TLS tối thiểu 1.2.
- Firmware P1/A1 chỉ gửi **thay đổi** sau báo cáo đầy đủ đầu tiên, nên phải gộp sâu (`deepMerge`); yêu cầu báo cáo đầy đủ bằng `{"pushing":{"sequence_id":..,"command":"pushall","version":1,"push_target":1}}`.
- Kết nối TCP có thể chết âm thầm sau upload dài; KCS `ensureLive()` gửi `pushall` và chờ phản hồi 3 s, không có thì kết nối lại.
- Lệnh: `print` với `pause/resume/stop` (QoS 1), `gcode_line`, `print_speed` (4 mức), `system.ledctrl`, `project_file`/`gcode_file`. Quạt qua `M106 P1|P2|P3 S..` bước 10%.
- **Xác nhận lệnh**: gói trả lời `{"print":{"command":..,"result":"success|fail","reason":..,"sequence_id":..}}` tách khỏi trạng thái. KCS đợi ack 8 s, hết hạn thì báo "bật Developer Mode".
- **Developer Mode**: KCS ghi "Reading status works whenever LAN mode is on. Commands are only accepted when Developer Mode is also on" (đầu `BambuMQTT.swift`) và README: gửi in qua LAN "cần Developer Mode". Chỉ xem trạng thái được khi chỉ bật LAN mode [đọc]. Lưu ý: đây là lời của KCS; Bambu thay đổi hành vi firmware theo từng bản, cần kiểm lại với máy P1S của ta.
- **FTPS ngầm (implicit) cổng 990**, user `bblp`, cùng mật khẩu. Máy từ chối kênh dữ liệu nếu không **tái dùng phiên TLS** của kênh điều khiển; client FTPS tự viết của KCS không làm được nên app dùng libcurl (`orca_ftps_upload`, TLS session reuse) [đọc `docs/PLAN.md`]. Client Swift tự viết vẫn còn để test Linux.
- Máy chỉ nhận **project `.3mf`** gồm `Metadata/plate_N.gcode`, `.md5`, ảnh png, `slice_info`; gửi `.gcode` trần không in được trên mọi model. KCS có `orca_pack_bbl_3mf` để đóng gói. Lệnh in `project_file`: `param=Metadata/plate_1.gcode`, `url="ftp:///<tên>"`, `md5`, `bed_leveling`, `flow_cali`, `vibration_cali`, `use_ams`, `ams_mapping` (mảng chỉ số khe AMS, -1 là không dùng). Khóa viết sai (ví dụ `bed_levelling`) bị firmware bỏ qua âm thầm.
- **Camera A1/P1: TLS cổng 6000**, gói xác thực 80 byte: `u32 0x40`, `u32 0x3000`, `u32 0`, `u32 0`, user 32 byte, password 32 byte (little endian). Khung: header 16 byte (u32 LE độ dài, rồi 0,1,0) + JPEG (`FFD8 ... FFD9`). Giới hạn một client: dùng chung 1 luồng giữa các view (đầu `CameraStream.swift`) [đọc].
- **Camera X1/P2S/H2: RTSPS cổng 322** (`rtsps://bblp:<code>@<ip>:322/streaming/live/1`); KCS **không giải mã được trên iOS** và rơi về địa chỉ MJPEG do người dùng nhập [đọc]. P1S thuộc dòng P1 nên nhiều khả năng dùng cổng 6000 [suy luận, chưa kiểm].
- iOS 17+: App Transport Security chặn HTTP tới IP trần; LAN cần `NSAllowsLocalNetworking` và `NSExceptionDomains` cho CIDR riêng (PAD `LESSONS.md`) [tác giả]. Cũng cần quyền Local Network trong `Info.plist` của iOS (kiến thức chung, repo trên không nêu; [suy luận]).
- Cloud: không repo nào hỗ trợ; Bambu cloud 403 là vấn đề ngoài phạm vi các repo này.

## 7. Bẫy thường gặp (gộp)

1. `CMAKE_SYSTEM_PROCESSOR` rỗng trên iOS làm hỏng `list(FIND ...)`, OpenSSL, libjpeg-turbo và logic cross-compile; phải đặt thủ công (NILS toolchain, QIDI `0001`, ANGELO `CMakeLists.txt:299`).
2. ExternalProject không chuyển `CMAKE_SYSTEM_NAME` và SDK/deployment target cho dep con (ANGELO `deps-ios.cmake`, QIDI `0002`, `0010`, `0018`).
3. `CMAKE_MACOSX_BUNDLE` mặc định bật cho iOS: heatshrink/Qhull lỗi "no BUNDLE DESTINATION" -> `OFF` (NILS toolchain).
4. `CMAKE_FIND_ROOT_PATH_MODE_*` = `ONLY` giấu prefix deps -> đặt `BOTH`, giữ `CMAKE_IGNORE_PREFIX_PATH=/opt/homebrew:/usr/local` để Homebrew không lọt vào (ANGELO).
5. autoconf cần `--build` khác `--host`; `CC_FOR_BUILD`; `--disable-assembly` cho GMP; `touch` file sinh sẵn (QIDI `0008-autotools-touch-generated.patch`).
6. `TARGET_OS_MAC` = 1 trên iOS làm libpng/zlib cũ đi nhánh MacOS cổ điển (QIDI `0005`, `0009`).
7. Clang 17+/Xcode 16+: OpenVDB 8.2 `template eval` (QIDI `0011`), CGAL 5.4 `this->base()` (QIDI `0014`); libc++ Xcode 27 báo `<stddef.h>` nếu `-isystem <SDK>/usr/include` chen trước (ANGELO `build_ios_core.sh`, chú thích ở `build_core`).
8. Trùng ký hiệu khi gộp archive: `libturbojpeg` vs `libjpeg`, `libqhullstatic*` vs `_r`, `qh_fprintf` (ANGELO `merge_slice`).
9. Không ai chạy được tệp thực thi vừa build trên máy host: không để recipe chạy chương trình vừa biên dịch (ANGELO `docs/HLSD/mobile.md`).
10. iOS không có `dlopen` module cạnh app, không có subprocess (`fork/exec/popen`); mọi plugin/OCCTWrapper/uv phải tĩnh hoặc loại (NILS `0003`, QIDI `docs/risks.md`, ANGELO `PluginsStub.cpp`).
11. Sandbox: không ghi được `/tmp`, chỉ `NSTemporaryDirectory`; `fopen` NULL rồi `fwrite` sẽ crash ở `flockfile` (PAD `LESSONS.md`). Mọi ngoại lệ C++ phải bị bắt trước khi vượt biên `extern "C"` sang Swift, nếu không là `std::terminate`.
12. Engine không thread-safe: `ObjectBase::s_last_id` và các toàn cục khác giả định một luồng vào engine; PAD tuần tự hóa mọi lệnh engine trong toàn tiến trình; ANGELO dùng mutex/session và `try_lock` cho lệnh đồng bộ (PAD `LESSONS.md`, ANGELO `docs/HLSD/mobile.md`).
13. Giữ cấu hình hợp lệ: vector rỗng (`flush_volumes_matrix`) crash; PAD chuẩn hóa mọi option vector ở biên slice (PAD `LESSONS.md`).
14. Mesh khi vẽ phẳng 3 đỉnh/mặt phải đánh lại chỉ số tuần tự; test bằng mô hình thật, không dùng hình lập phương (PAD `LESSONS.md`).
15. Xcode không hỗ trợ lld cho link app iOS từ Linux: chỉ build thư viện tĩnh trên Linux (PAD `LESSONS.md`).
16. Build lệnh hóa: phải enumerate toàn bộ lỗi trước khi sửa (PAD "Do NOT iterate build errors one at a time") và `ar` của host không đọc được Mach-O, dùng `llvm-ar --format=darwin`.

## 8. Giấy phép từng repo và thứ phải ghi công

Cả sáu repo là AGPL-3.0 và đều là tác phẩm dẫn xuất của OrcaSlicer/PrusaSlicer/QIDISlicer, cùng dòng Slic3r -> PrusaSlicer -> Bambu Studio -> OrcaSlicer. Bambu Studio của ta cũng AGPL-3.0 (`LICENSE.txt`), nên **có thể** sao chép mã từ các repo này với điều kiện giữ nguyên thông báo bản quyền và cung cấp mã nguồn tương ứng; không có xung đột giấy phép.

| Repo | Điều kiện/ghi chú | Ghi công cần |
|---|---|---|
| LUCAS | AGPL-3.0. `CONTRIBUTING.md`: không nhận PR/code; mọi tệp bên ngoài coi là vector tấn công. Đây là chính sách của họ về nhận đóng góp, không hạn chế việc ta tái dùng mã AGPL của họ. Tuy vậy mã của họ do một người viết nên khi sao chép nên giữ header và ghi nguồn. | Ghi `LucasCoraca/orcaslicer-android` + commit trong file nguồn/thông báo. Giữ "unofficial port" tương tự. |
| NILS | AGPL-3.0. `ios/README.md` nêu AGPL và App Store: "legally unclear" (quyết định E-06 trong `docs/decisions.md`), nên phát hành TestFlight. | Ghi công; các patch có thể dùng lại (đã công khai để tuân thủ AGPL). |
| ANGELO | AGPL-3.0 (`LICENSE.txt`). Là fork Orca nên có thông báo của Orca/SoftFever. | Ghi công; giữ thông báo SoftFever. |
| QIDI | AGPL-3.0; tên "QIDI" thuộc QIDI Technology, dự án khẳng định không chính thức (`docs/risks.md`). | Ghi công; không dùng tên thương hiệu. |
| PAD | AGPL-3.0-only (SPDX trên từng file). `COMPLIANCE.md` đánh giá xung đột Apple EULA/AGPL: "unresolved question of law"; AGPL §13 không kích hoạt vì engine chạy cục bộ; tuyên bố không có waiver. Có cổng `license-inventory.sh`, `THIRD_PARTY.md` tạo tự động. Lưu ý PAD dùng header host của CGAL (GPL-3+), libnoise/NLopt/libnest2d (LGPL, link tĩnh -> phải cung cấp mã nguồn đầy đủ để người dùng liên kết lại). | Ghi công `iSteeb/OrcaPad`; giữ SPDX header; mẫu `THIRD_PARTY.md` và `COMPLIANCE.md` dùng được. |
| KCS | AGPL-3.0. `NOTICE.md` nêu chuỗi dòng dõi (Slic3r, PrusaSlicer, Bambu Studio, SuperSlicer) và mọi thư viện bên thứ ba (OCCT LGPL-2.1+ngoại lệ, libcurl, OpenSSL 3 Apache-2.0, ...). Liên quan Bambu: không dùng Bambu Network Plugin. Dữ liệu `resources/profiles` thuộc OrcaSlicer và các hãng; tên/logo hãng thuộc chủ sở hữu. Dịch vụ MakerWorld/Printables dùng API không chính thức. | Ghi công `KiraVN97/KCS-Home-Slicer`. Không cần mang các API không chính thức. |

Nghĩa vụ của ta khi phát hành bản iPad (kể cả TestFlight, nếu gửi cho người khác): giữ AGPL-3.0, công khai mã nguồn tương ứng cho người nhận, không dùng tên/logo Bambu như thể chính thức, tạo `THIRD_PARTY.md` cho CGAL (GPL-3+), OCCT (LGPL-2.1 + ngoại lệ), libnoise/NLopt/libnest2d (LGPL), v.v. Chỉ chạy trên máy cá nhân tự ký thì chưa phải phân phối. Đây là phân tích kỹ thuật, không phải tư vấn pháp lý.

## 9. Cách tiếp cận của LUCAS có mang sang Bambu Studio được không?

**Kết luận: một phần. Kỹ thuật thì mang được, nhưng vá thì không mang nguyên được.**

Mang được (đã có bằng chứng):
1. **Shim wx tối thiểu + biên dịch chọn lọc file GUI**: 1652 dòng shim đủ cho ~vài chục file GUI của Orca nhờ copy file vào cây build rồi để include anh em trỏ vào shim (`mobile/core/CMakeLists.txt`). Cơ chế này không phụ thuộc Orca cụ thể.
2. **`extract_functions.py`**: trích hàm khỏi class wx/ImGui; hỏng to khi upstream đổi (có `--sub` kiểm chứng); dùng lại gần như nguyên, chỉ cần đổi tên hàm/lớp theo cây Bambu. Python chạy ở bước build trên Mac của ta, không chạy trên iPad.
3. **`gen_settings_layout.py`**: đọc `TabPrint::build`... của `Tab.cpp`. Tab của Bambu khác Orca (BBL dùng `Tab.cpp` kiểu riêng, nhiều khối `page->new_optgroup`), nên **cần chỉnh parser** và kiểm lại; không đảm bảo chạy nguyên.
4. **Đường dẫn deps**: danh sách bỏ GUI deps (wx, GLFW, FFMPEG, DataChannel, Python) là cùng dạng với `deps-ios.cmake` của ANGELO (`DEPS_MOBILE`).

Không mang nguyên được:
1. **Bản vá render GLES**: LUCAS dựa trên nhánh `SLIC3R_OPENGL_ES` có sẵn từ PrusaSlicer trong Orca. Bambu Studio của ta không có nhánh đó, còn ~40 điểm GL legacy ở 8 file (mục 3.1). Công việc render ES ở ta **lớn hơn nhiều** so với những gì patch LUCAS cho thấy (+215/-22 trong `GLCanvas3D.cpp`).
2. **Phần UI Compose/JNI/Kotlin** (nhiều chục nghìn dòng) thay bằng SwiftUI; không dùng được, chỉ tham khảo lệnh/sự kiện JSON.
3. **Thay đổi libslic3r theo Orca**: LUCAS không đụng libslic3r nhiều, nhưng `Plater.cpp`/`PartPlate`/`GUI_App` của Bambu khác Orca. `mobile/core/src` ~120 file là mã viết mới hướng Orca API; mỗi file phải đọc lại với Bambu API.
4. **Python/uv/plugin, MakerWorld...**: đặc thù Orca, bỏ.

Rủi ro chính của hướng "biên dịch lại logic GUI desktop với stand-in wx" mà ta dự định: năm repo iOS còn lại (NILS, QIDI, ANGELO, PAD, KCS) đều **từ bỏ** hướng này ở iOS và viết lại tầng ứng dụng. Chỉ LUCAS làm hướng này, trên Android, và cho Orca. Số lượng stand-in cần cho `Plater/PartPlate/GLCanvas3D/GLGizmo*` của Bambu chưa ai đo. Nên chọn một lát cắt nhỏ chạy được trước (ví dụ `ConfigManipulation` + `Tab` layout, rồi `PartPlate` bằng shim) để đo rồi mới cam kết.

## 10. Danh sách tái dùng, xếp hạng

Thứ tự theo giá trị trên rủi ro, kèm tình trạng:

1. **ANGELO `deps/deps-ios.cmake` + `scripts/build_ios_core.sh` + các nhánh `DEPS_IOS` trong `deps/{GMP,OpenSSL,OpenCV,TBB,PNG}`** [đọc; tác giả: chạy được]. Gần nhất với cấu trúc `deps/` superbuild của ta (Orca và Bambu cùng gốc). Cần chuyển sang cây Bambu: `DEPS_MOBILE` danh sách, `merge_slice`, xcframework. Hạng 1.
2. **QIDI patch deps nhỏ**: `0003` (GMP), `0005`+`0009` (png/zlib), `0011` (OpenVDB), `0014` (CGAL), `0008` (autotools touch), `0018` (SDK propagate), `0016` (OCCTWrapper) [đọc, chưa TB]. Khớp bản cũ của ta (CGAL 5.4, OpenVDB 8.2, libpng 1.6.35). Hạng 2.
3. **NILS `cmake/toolchains/ios.cmake` + `build-ios.sh` + `bundle_core`** [đọc]. Toolchain ngắn, chứa sửa lỗi `CMAKE_SYSTEM_PROCESSOR`, bundle, `FIND_ROOT_PATH BOTH`. Hạng 3.
4. **Thiết kế bộ nhớ**: ANGELO `Session::cancel_out_of_memory/set_thread_limit` + watchdog `os_proc_available_memory`, NILS `psm_estimate_slice_memory`, giải phóng `slice_model` sau `Print::apply` [đọc/tác giả]. Hạng 4. Áp dụng ngay cho iPad 4 GB.
5. **LUCAS `extract_functions.py` + shim wx + cơ chế copy file vào cây build + `gen_settings_layout.py`** [đọc]. Nền tảng cho "logic GUI + stand-in wx". Hạng 5 vì đòi hỏi chỉnh Bambu và chưa ai làm trên iOS.
6. **KCS Bambu LAN**: `BambuMQTT.swift`, `BambuCommands.swift`, `BambuCamera` (cổng 6000), phần libcurl FTPS có session reuse, `orca_pack_bbl_3mf`, `fake_bambu_ftps.py` để test [đọc; **chưa thử máy thật**]. Hạng 6 (độc lập với engine, giá trị cao cho P1S, nhưng cần kiểm chứng với máy thật của ta).
7. **KCS `scripts/build_deps.sh`** (Boost mach-o context, OpenCV rút gọn, OCCT static + CSF data, curl) và **`patches/orca-2.5.1-mobile.patch`** (`utils.cpp` iOS, không libproc) [đọc]. Hạng 7: lấy từng đoạn, không dùng nguyên vì build từ Linux bằng xtool.
8. **PAD `LESSONS.md`** (bài học vận hành: ngoại lệ qua biên C, sandbox, plate origin, `flush_volumes_matrix`, ATS) [tác giả]. Hạng 8 nhưng chi phí bằng 0: đọc trước khi viết bridge.
9. **NILS `0003` glad Apple (dlsym) + `ViewportView.swift` (EAGL)** [đọc]. Hạng 9: khi tới bước render, nhưng với EAGL thì không cần glad.
10. **LUCAS shader `resources/shaders/ES/*` (`#version 300 es`)** làm điểm xuất phát cho shader ES của Bambu [đọc]. Hạng 10: tiết kiệm công viết `.vs/.fs` nhưng phải đối chiếu uniform với `110/140` của Bambu.

Không nên tái dùng: PAD shim TBB tuần tự (làm chậm; chỉ dùng như phương án chẩn đoán), KCS `ORCA_NO_OPENVDB` (tree support của ta cần OpenVDB), NILS `0002` libvgcode (Bambu không có libvgcode), LUCAS v0.1 wxQt, plugin Python/uv.

## 11. Việc cần làm tiếp để kiểm chứng (chưa thực hiện)

- Dựng thử `GMP` (fork bambulab 6.2.1) + `MPFR` 3.1.6 với triple iOS trên Mac; nếu `config.sub` hỏng thì nâng MPFR.
- Dựng thử `OpenMeshCraft` + MCUT trên iOS (không prior art).
- Đo thật trên iPad Pro 11 2018: bộ nhớ khả dụng bằng `os_proc_available_memory()` lúc mở app; ngưỡng TBB; xin entitlement tăng bộ nhớ.
- Kiểm `GCodeViewer` và `GLCanvas3D` của Bambu để lập danh sách call site GL legacy chính xác trước khi chọn: viết lại sang VBO + shader, hay dùng lớp tương thích (không có repo nào ở trên dùng cách này, chưa đánh giá).
- Xác nhận hành vi Developer Mode / LAN mode của firmware P1S hiện tại bằng thử nghiệm thật với máy của ta, không dựa vào KCS.
