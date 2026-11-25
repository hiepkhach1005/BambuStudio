#!/usr/bin/env bash
# Cross-compile libslic3r dependencies for iOS arm64 device, deployment target 18.0.
# Idempotent: each lib has a stamp in $BUILD/stamps; FORCE=1 rebuilds.
# Usage: ios/scripts/build_deps.sh [lib ...]   (default: all, in risk order)
# Sources come ONLY from URLs pinned in deps/*/*.cmake, verified by SHA256.
# cmake/ninja live in a venv under the build dir; nothing is installed system-wide.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BUILD="${IOS_BUILD:-$ROOT/ios/build}"
PREFIX="$BUILD/prefix"; DL="$BUILD/dl"; SRC="$BUILD/src"; OBJ="$BUILD/obj"; LOGS="$BUILD/logs"; ST="$BUILD/stamps"
JOBS="${JOBS:-6}"; [ "$JOBS" -gt 6 ] && JOBS=6
TC="$ROOT/ios/cmake/ios-toolchain.cmake"
DEPS="$ROOT/deps"
mkdir -p "$DL" "$SRC" "$OBJ" "$LOGS" "$ST" "$PREFIX/include" "$PREFIX/lib"
if [ ! -x "$BUILD/venv/bin/cmake" ]; then
  python3 -m venv "$BUILD/venv"; "$BUILD/venv/bin/pip" -q install cmake ninja
fi
export PATH="$BUILD/venv/bin:$PATH"
export IOS_DEPS_PREFIX="$PREFIX"; export CMAKE_POLICY_VERSION_MINIMUM=3.5
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CC_IOS="$(xcrun --sdk iphoneos -f clang)"; CXX_IOS="$(xcrun --sdk iphoneos -f clang++)"
IOSMIN=18.0
IOSFLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=$IOSMIN"

fetch() { # name url sha256 file -> prints path, verified
  local n="$1" u="$2" h="$3" f="${4:-$(basename "$2")}"
  mkdir -p "$DL/$n"
  if [ ! -f "$DL/$n/$f" ]; then curl -fsSL --retry 3 -o "$DL/$n/$f.part" "$u"; mv "$DL/$n/$f.part" "$DL/$n/$f"; fi
  h=$(echo "$h" | tr 'A-F' 'a-f')
  if [ "$(shasum -a 256 "$DL/$n/$f" | cut -d' ' -f1)" != "$h" ]; then echo "SHA256 mismatch $n" >&2; rm -f "${DL:?}/${n:?}/${f:?}"; return 1; fi
  echo "$DL/$n/$f"
}
unpack() { # name archive -> fresh $SRC/name, top dir stripped
  local n="$1" a="$2"; rm -rf "${SRC:?}/${n:?}"; mkdir -p "$SRC/$n"
  case "$a" in *.zip) local t; t=$(mktemp -d); unzip -q "$a" -d "$t"; cp -R "$t"/*/. "$SRC/$n"/; rm -rf "${t:?}";;
    *) tar -xf "$a" -C "$SRC/$n" --strip-components=1;; esac
}
cmk() { # name srcdir [cmake args]
  local n="$1" s="$2"; shift 2
  rm -rf "${OBJ:?}/${n:?}"
  cmake -G Ninja -S "$s" -B "$OBJ/$n" -DCMAKE_TOOLCHAIN_FILE="$TC" -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib "$@" || return 1
  cmake --build "$OBJ/$n" -j"$JOBS" || return 1
  cmake --install "$OBJ/$n" || return 1
}
gapply() { ( cd "$1" && git apply --ignore-space-change --whitespace=fix "$2" ); }
# ---- recipes (versions/hashes from deps/<X>/<X>.cmake) ----
b_zlib() {
  local a; a=$(fetch zlib https://github.com/madler/zlib/archive/refs/tags/v1.2.13.zip c2856951bbf30e30861ace3765595d86ba13f2cf01279d901f6c62258c57f4ff v1.2.13.zip)
  unpack zlib "$a"
  # zutil.h TARGET_OS_MAC branch redefines fdopen(), breaking the iOS SDK's <stdio.h>; Apple has fdopen. (cf. qidi-ios 0009, AGPL; re-derived)
  sed -i '' 's|define fdopen(fd,mode) NULL.*$|define Z_IOS_NO_FDOPEN_OVERRIDE 1|' "$SRC/zlib/zutil.h"
  cmk zlib "$SRC/zlib" -DSKIP_INSTALL_FILES=ON
  rm -f "${PREFIX:?}"/lib/libz*.dylib
}
b_boost() {
  local a; a=$(fetch boost https://github.com/boostorg/boost/releases/download/boost-1.84.0/boost-1.84.0.tar.gz 4d27e9efed0f6f152dc28db6430b9d3dfb40c0345da7342eaa5a987dde57bd95)
  unpack boost "$a"
  gapply "$SRC/boost" "$DEPS/Boost/0001-FIX-OBS-cannot-start-streaming-on-MAC.patch" || echo "boost patch not applied"
  cmk boost "$SRC/boost" -DBOOST_EXCLUDE_LIBRARIES="contract;fiber;numpy;wave;test;python;mpi;graph_parallel" \
    -DBOOST_LOCALE_ENABLE_ICU=OFF -DBUILD_TESTING=OFF -DBOOST_CONTEXT_ABI=aapcs -DBOOST_CONTEXT_ARCHITECTURE=arm64 \
    -DBOOST_CONTEXT_BINARY_FORMAT=mach-o
}
b_tbb() {
  local a; a=$(fetch tbb https://github.com/oneapi-src/oneTBB/archive/refs/tags/v2021.5.0.zip 83ea786c964a384dd72534f9854b419716f412f9d43c0be88d41874763e7bb47 v2021.5.0.zip)
  unpack tbb "$a"
  cmk tbb "$SRC/tbb" -DTBB_BUILD_SHARED=OFF -DTBB_BUILD_TESTS=OFF -DTBB_TEST=OFF -DTBB_EXAMPLES=OFF -DTBB_STRICT=OFF -DTBB_DISABLE_HWLOC_AUTOMATIC_SEARCH=ON
}
b_png() {
  local a; a=$(fetch png https://github.com/glennrp/libpng/archive/refs/tags/v1.6.35.zip 3d22d46c566b1761a0e15ea397589b3a5f36ac09b7c785382e6470156c04247f v1.6.35.zip)
  unpack png "$a"
  # libpng 1.6.35 includes <fp.h> on TARGET_OS_MAC; the iOS SDK has none. Use <math.h>.
  # (same idea as kbnhvn/qidi-ios patch 0005, AGPL-3.0; re-derived here)
  sed -i '' 's|include <fp.h>|include <math.h>|' "$SRC/png/pngpriv.h"
  cmk png "$SRC/png" -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_ARM_NEON=on -DPNG_PREFIX=prusaslicer_ -DPNG_FRAMEWORK=OFF -DZLIB_LIBRARY="$SDK/usr/lib/libz.tbd" -DZLIB_INCLUDE_DIR="$SDK/usr/include"
}
b_jpeg() {
  local a; a=$(fetch jpeg https://github.com/libjpeg-turbo/libjpeg-turbo/archive/refs/tags/3.0.1.zip d6d99e693366bc03897677650e8b2dfa76b5d6c54e2c9e70c03f0af821b0a52f 3.0.1.zip)
  unpack jpeg "$a"
  cmk jpeg "$SRC/jpeg" -DCMAKE_INSTALL_LIBDIR="$PREFIX/lib" -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_JPEG8=ON -DWITH_TURBOJPEG=OFF
}
b_expat() { cmk expat "$DEPS/EXPAT/expat" -DBUILD_SHARED_LIBS=OFF; }
b_headers() { # Cereal 1.3.0 + CGAL 5.4 (Eigen is in-tree: src/eigen)
  local a; a=$(fetch cereal https://github.com/USCiLab/cereal/archive/refs/tags/v1.3.0.zip 71642cb54658e98c8f07a0f0d08bf9766f1c3771496936f6014169d3726d9657 v1.3.0.zip)
  unpack cereal "$a"; cp -R "$SRC/cereal/include/cereal" "$PREFIX/include/"
  a=$(fetch cgal https://github.com/CGAL/cgal/archive/refs/tags/v5.4.zip d7605e0a5a5ca17da7547592f6f6e4a59430a0bc861948974254d0de43eab4c0 v5.4.zip)
  unpack cgal "$a"
  gapply "$SRC/cgal" "$DEPS/CGAL/0001-clang19.patch" || echo "CGAL patch skipped"
  cmk cgal "$SRC/cgal" -DCGAL_HEADER_ONLY=ON -DWITH_CGAL_Qt5=OFF -DBUILD_TESTING=OFF
}
b_gmp() {
  local a; a=$(fetch gmp https://github.com/bambulab/gmp/archive/refs/tags/6.2.1.tar.gz 705ae57ee2014b2c6fc0f572c85ee43276b99b6b256ee16c1a9d3a8c4e3609d5 gmp-6.2.1.tar.gz)
  unpack gmp "$a"
  gapply "$SRC/gmp" "$DEPS/GMP/0001-GMP_GCC15.patch"
  gapply "$SRC/gmp" "$DEPS/GMP/0002-GMP_arm64_avoid_x18_reserved_on_darwin.patch"
  ( cd "$SRC/gmp" && { [ -x configure ] || autoreconf -fi; } &&
    CC="$CC_IOS" CXX="$CXX_IOS" CC_FOR_BUILD=/usr/bin/clang CXX_FOR_BUILD=/usr/bin/clang++ \
     CFLAGS="-O2 -DNDEBUG -fPIC $IOSFLAGS" CXXFLAGS="-O2 -DNDEBUG -fPIC $IOSFLAGS" LDFLAGS="$IOSFLAGS" \
     ./configure --host=aarch64-apple-darwin --build="$(uname -m)-apple-darwin$(uname -r)" --disable-assembly \
       --enable-static --disable-shared --enable-cxx --prefix="$PREFIX" && make -j"$JOBS" && make install )
}
b_mpfr() {
  local a; a=$(fetch mpfr https://www.mpfr.org/mpfr-3.1.6/mpfr-3.1.6.tar.bz2 cf4f4b2d80abb79e820e78c8077b6725bbbb4e8f41896783c899087be0e94068)
  unpack mpfr "$a"
  local am; am=$(ls -d /opt/homebrew/Cellar/automake/*/share/automake-*/ 2>/dev/null | tail -1 || true)
  if [ -n "$am" ]; then cp "$am/config.sub" "$am/config.guess" "$SRC/mpfr/"; fi   # 3.1.6 config.sub is too old
  ( cd "$SRC/mpfr" && CC="$CC_IOS" CC_FOR_BUILD=/usr/bin/clang CFLAGS="-O2 -DNDEBUG -fPIC $IOSFLAGS" LDFLAGS="$IOSFLAGS" \
     ./configure --host=aarch64-apple-darwin --build="$(uname -m)-apple-darwin$(uname -r)" --disable-shared --enable-static \
       --with-gmp="$PREFIX" --prefix="$PREFIX" && make -j"$JOBS" && make install )
}
b_qhull() {
  local a; a=$(fetch qhull https://github.com/qhull/qhull/archive/v8.0.1.zip 5287f5edd6a0372588f5d6640799086a4033d89d19711023ef8229dd9301d69b v8.0.1.zip)
  unpack qhull "$a"
  cmk qhull "$SRC/qhull" -DBUILD_APPLICATIONS=OFF -DCMAKE_MACOSX_BUNDLE=OFF -DINCLUDE_INSTALL_DIR=include
  rm -f "${PREFIX:?}"/lib/libqhull*.dylib
}
b_nlopt() {
  local a; a=$(fetch nlopt https://github.com/stevengj/nlopt/archive/v2.5.0.tar.gz c6dd7a5701fff8ad5ebb45a3dc8e757e61d52658de3918e38bab233e7fd3b4ae nlopt-2.5.0.tar.gz)
  unpack nlopt "$a"
  cmk nlopt "$SRC/nlopt" -DNLOPT_PYTHON=OFF -DNLOPT_OCTAVE=OFF -DNLOPT_MATLAB=OFF -DNLOPT_GUILE=OFF -DNLOPT_SWIG=OFF -DNLOPT_TESTS=OFF
}
b_openssl() { # libslic3r needs MD5 + AES
  local a; a=$(fetch openssl https://github.com/openssl/openssl/archive/refs/tags/openssl-3.1.2.tar.gz 8c776993154652d0bb393f506d850b811517c8bd8d24b1008aef57fbe55d3f31 openssl-3.1.2.tar.gz)
  unpack openssl "$a"
  ( cd "$SRC/openssl" && ./Configure ios64-xcrun no-shared no-tests no-asm no-dso no-engine no-async no-ui-console \
      -miphoneos-version-min=$IOSMIN --prefix="$PREFIX" --openssldir="$PREFIX/ssl" && make -j"$JOBS" build_libs && make install_dev )
}
b_freetype() {
  local a; a=$(fetch freetype https://github.com/freetype/freetype/archive/refs/tags/VER-2-12-1.tar.gz 0E72CAE32751598D126CFD4BCEDA909F646B7231AB8C52E28ABB686C20A2BEA1 VER-2-12-1.tar.gz)
  unpack freetype "$a"
  cmk freetype "$SRC/freetype" -DFT_DISABLE_ZLIB=FALSE -DFT_DISABLE_BZIP2=TRUE -DFT_DISABLE_PNG=TRUE -DFT_DISABLE_HARFBUZZ=TRUE -DFT_DISABLE_BROTLI=TRUE
}
b_libnoise() {
  local a; a=$(fetch libnoise https://github.com/bambulab/libnoise/archive/refs/tags/v1.0.0.zip 7aae3433e4c841a1b15ddf40dc995b3d32efb154b92b6796888002e275bff859 v1.0.0.zip)
  unpack libnoise "$a"
  cmk libnoise "$SRC/libnoise"
}
ZARGS() { echo "-DZLIB_LIBRARY=$SDK/usr/lib/libz.tbd -DZLIB_INCLUDE_DIR=$SDK/usr/include"; }
b_assimp() { # 5.4.3 (Assimp.cmake picks it for cmake>=3.22); bundled zlib OFF -> SDK zlib, as on macOS
  local a; a=$(fetch assimp https://github.com/assimp/assimp/archive/refs/tags/v5.4.3.tar.gz 66dfbaee288f2bc43172440a55d0235dfc7bf885dda6435c038e8000e79582cb v5.4.3.tar.gz)
  unpack assimp "$a"
  gapply "$SRC/assimp" "$DEPS/Assimp/0001-FBX-fix-negative-TypedIndex-OOB.patch"
  gapply "$SRC/assimp" "$DEPS/Assimp/0002-glTF1-fix-index-accessor-type-confusion-OOB.patch"
  cmk assimp "$SRC/assimp" $(ZARGS) -DASSIMP_BUILD_TESTS=OFF -DASSIMP_BUILD_SAMPLES=OFF -DASSIMP_BUILD_ASSIMP_TOOLS=OFF -DASSIMP_INSTALL_PDB=OFF \
    -DASSIMP_NO_EXPORT=ON -DASSIMP_BUILD_ALL_IMPORTERS_BY_DEFAULT=OFF -DASSIMP_BUILD_GLTF_IMPORTER=ON -DASSIMP_BUILD_OBJ_IMPORTER=ON \
    -DASSIMP_BUILD_FBX_IMPORTER=ON -DASSIMP_BUILD_ZLIB=OFF -DASSIMP_WARNINGS_AS_ERRORS=OFF
}
b_opencv() { # 4.6.0, modules core/imgproc/imgcodecs (world), flags from deps/OpenCV + iOS extras
  local a; a=$(fetch opencv https://github.com/opencv/opencv/archive/refs/tags/4.6.0.tar.gz 1ec1cba65f9f20fe5a41fda1586e01c70ea0c9a6d7b67c9e13edf0cfe2239277 opencv-4.6.0.tar.gz)
  unpack opencv "$a"
  gapply "$SRC/opencv" "$DEPS/OpenCV/0001-OpenCV-fix.patch"
  gapply "$SRC/opencv" "$DEPS/OpenCV/0002-clang19-macos.patch"
  sed -i '' 's|include <fp.h>|include <math.h>|' "$SRC/opencv/3rdparty/libpng/pngpriv.h"   # bundled libpng, same <fp.h> issue
  cmk opencv "$SRC/opencv" $(ZARGS) -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOCS=OFF -DBUILD_JAVA=OFF \
    -DBUILD_opencv_apps=OFF -DBUILD_APPS_LIST=version -DBUILD_JPEG=ON -DBUILD_PNG=ON -DBUILD_OPENEXR=OFF -DBUILD_TBB=OFF -DBUILD_WEBP=OFF -DBUILD_ZLIB=OFF \
    -DWITH_IPP=OFF -DWITH_ITT=OFF -DWITH_FFMPEG=OFF -DWITH_OPENCL=OFF -DWITH_OPENEXR=OFF -DWITH_OPENJPEG=OFF -DWITH_JASPER=OFF -DWITH_QUIRC=OFF \
    -DWITH_JPEG=OFF -DWITH_WEBP=OFF -DWITH_TIFF=OFF -DWITH_EIGEN=OFF -DWITH_LAPACK=OFF -DWITH_PROTOBUF=OFF -DWITH_ADE=OFF -DWITH_OPENVINO=OFF \
    -DWITH_AVFOUNDATION=OFF -DWITH_CAP_IOS=OFF -DWITH_CAROTENE=OFF -DAPPLE_FRAMEWORK=OFF -DENABLE_PRECOMPILED_HEADERS=OFF \
    -DBUILD_LIST=core,imgcodecs,imgproc,world -DBUILD_opencv_world=ON -DBUILD_opencv_highgui=OFF -DOPENCV_GENERATE_SETUPVARS=OFF \
    -DINSTALL_TESTS=OFF -DINSTALL_C_EXAMPLES=OFF -DINSTALL_PYTHON_EXAMPLES=OFF
}
b_blosc() { # tamasmeszaros fork 1.17.0_tm
  local a; a=$(fetch blosc https://github.com/tamasmeszaros/c-blosc/archive/refs/heads/v1.17.0_tm.zip dcb48bf43a672fa3de6a4b1de2c4c238709dad5893d1e097b8374ad84b1fc3b3 v1.17.0_tm.zip)
  unpack blosc "$a"
  cmk blosc "$SRC/blosc" $(ZARGS) -DBUILD_SHARED=OFF -DBUILD_STATIC=ON -DBUILD_TESTS=OFF -DBUILD_BENCHMARKS=OFF -DPREFER_EXTERNAL_ZLIB=ON
}
b_openexr() { # 2.5.5 (IlmBase+OpenEXR; OpenVDB needs Half)
  local a; a=$(fetch openexr https://github.com/AcademySoftwareFoundation/openexr/archive/refs/tags/v2.5.5.zip 0307a3d7e1fa1e77e9d84d7e9a8694583fbbbfd50bdc6884e2c96b8ef6b902de v2.5.5.zip)
  unpack openexr "$a"
  gapply "$SRC/openexr" "$DEPS/OpenEXR/0001-OpenEXR-GCC13.patch" || echo "exr gcc13 patch skipped"
  cmk openexr "$SRC/openexr" $(ZARGS) -DBUILD_TESTING=OFF -DPYILMBASE_ENABLE=OFF -DOPENEXR_VIEWERS_ENABLE=OFF -DOPENEXR_BUILD_UTILS=OFF -DINSTALL_OPENEXR_EXAMPLES=OFF
}
b_openvdb() { # tamasmeszaros 8.2 patched
  local a; a=$(fetch openvdb https://github.com/tamasmeszaros/openvdb/archive/a68fd58d0e2b85f01adeb8b13d7555183ab10aa5.zip f353e7b99bd0cbfc27ac9082de51acf32a8bc0b3e21ff9661ecca6f205ec1d81 openvdb-a68fd58.zip)
  unpack openvdb "$a"
  gapply "$SRC/openvdb" "$DEPS/OpenVDB/0001-clang19.patch"
  # clang>=17 rejects `OpT::template eval(...)` without a template arg list (cf. qidi-ios 0011, AGPL; re-derived)
  sed -i '' 's|OpT::template eval(|OpT::eval(|' "$SRC/openvdb/openvdb/openvdb/tree/NodeManager.h"
  cmk openvdb "$SRC/openvdb" $(ZARGS) -DOPENVDB_BUILD_PYTHON_MODULE=OFF -DUSE_BLOSC=ON -DOPENVDB_CORE_SHARED=OFF -DOPENVDB_CORE_STATIC=ON \
    -DOPENVDB_ENABLE_RPATH=OFF -DTBB_STATIC=ON -DOPENVDB_BUILD_VDB_PRINT=OFF -DOPENVDB_BUILD_BINARIES=OFF -DDISABLE_DEPENDENCY_VERSION_CHECKS=ON \
    -DUSE_GLFW3=OFF -DOPENVDB_BUILD_UNITTESTS=OFF
}
b_occt() { # 7.6.0; module flags as in deps/OCCT (DataExchange on); no TK vis tools (USE_TK=OFF)
  local a; a=$(fetch occt https://github.com/Open-Cascade-SAS/OCCT/archive/refs/tags/V7_6_0.zip 28334f0e98f1b1629799783e9b4d21e05349d89e695809d7e6dfa45ea43e1dbc V7_6_0.zip)
  unpack occt "$a"
  gapply "$SRC/occt" "$DEPS/OCCT/0001-OCCT-fix.patch"
  cmk occt "$SRC/occt" -DBUILD_LIBRARY_TYPE=Static -DUSE_TK=OFF -DUSE_TBB=OFF -DUSE_FFMPEG=OFF -DUSE_VTK=OFF -DBUILD_DOC_Overview=OFF \
    -DBUILD_MODULE_ApplicationFramework=OFF -DBUILD_MODULE_Draw=OFF -DBUILD_MODULE_FoundationClasses=OFF -DBUILD_MODULE_ModelingAlgorithms=OFF \
    -DBUILD_MODULE_ModelingData=OFF -DBUILD_MODULE_Visualization=OFF -DUSE_FREETYPE=ON -DUSE_RAPIDJSON=OFF -DUSE_OPENGL=OFF -DUSE_GLES2=OFF \
    -DBUILD_WITH_DEBUG=OFF -DINSTALL_DIR_LAYOUT=Unix
}
if [ "${1:-}" = "--one" ]; then "b_$2"; exit $?; fi   # child process: errexit is active here
ALL="zlib png jpeg expat headers boost tbb gmp mpfr qhull nlopt openssl freetype libnoise assimp opencv blosc openexr openvdb occt"
want="${*:-$ALL}"
for l in $want; do
  if [ -f "$ST/$l.ok" ] && [ -z "${FORCE:-}" ]; then echo "[skip] $l"; continue; fi
  echo "[build] $l"; rm -f "${ST:?}/${l:?}.fail"
  if "$0" --one "$l" >"$LOGS/$l.log" 2>&1; then touch "$ST/$l.ok"; echo "[ok] $l"; else touch "$ST/$l.fail"; echo "[FAIL] $l (log $LOGS/$l.log)"; tail -5 "$LOGS/$l.log"; fi
done
