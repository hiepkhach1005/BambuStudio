# iPadOS build: libslic3r from this repo (unmodified sources), no wxWidgets GUI.
# Configure with ios/scripts/build_core.sh. Mirrors the non-GUI parts of ../CMakeLists.txt and ../src/CMakeLists.txt.
cmake_minimum_required(VERSION 3.20)
project(BambuStudioIOS C CXX OBJC OBJCXX)

get_filename_component(REPO "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
list(APPEND CMAKE_MODULE_PATH "${REPO}/cmake/modules")
include("${REPO}/version.inc")
set(SLIC3R_BUILD_ID "${SLIC3R_VERSION}")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_FIND_FRAMEWORK LAST)
set(SLIC3R_STATIC 1)
set(SLIC3R_GUI 0)
set(SLIC3R_PCH 1) # sources rely on the force-included header
set(SLIC3R_ENABLE_OPENMESHCRAFT_BOOLEAN OFF) # no iOS build yet: MCUT backend
set(SLIC3R_ALLOW_MCUT_BOOLEAN ON)
set(TOP_LEVEL_PROJECT_DIR "${REPO}")
set(LIBDIR "${REPO}/src")
include_directories("${CMAKE_CURRENT_SOURCE_DIR}/shim/include" "${LIBDIR}" "${LIBDIR}/libigl")
include_directories(BEFORE SYSTEM "${LIBDIR}/eigen")
add_definitions(-DUNICODE -D_UNICODE)
add_compile_options(-w -Wno-error)
add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-fsigned-char>")

function(slic3r_remap_configs)
endfunction()
function(encoding_check)
endfunction()

# The deps link the SDK zlib; use the same one everywhere.
set(ZLIB_INCLUDE_DIR "${CMAKE_OSX_SYSROOT}/usr/include" CACHE PATH "" FORCE)
set(ZLIB_LIBRARY "${CMAKE_OSX_SYSROOT}/usr/lib/libz.tbd" CACHE FILEPATH "" FORCE)
# boost_iostreams was configured with Homebrew's (macOS) zstd; nothing here uses that filter.
set(CMAKE_IGNORE_PREFIX_PATH /opt/homebrew /usr/local)
set(zstd_FOUND TRUE)
set(zstd_DIR "${CMAKE_CURRENT_SOURCE_DIR}/cmake/zstd-stub" CACHE PATH "" FORCE)
set(Boost_USE_STATIC_LIBS ON)
find_package(Boost 1.83.0 REQUIRED CONFIG COMPONENTS system filesystem thread log log_setup locale regex chrono atomic date_time iostreams nowide)
add_library(boost_libs INTERFACE)
add_library(boost_headeronly INTERFACE)
target_compile_definitions(boost_headeronly INTERFACE BOOST_ASIO_DISABLE_KQUEUE)
target_link_libraries(boost_headeronly INTERFACE Boost::headers)
target_link_libraries(boost_libs INTERFACE boost_headeronly Boost::system Boost::filesystem Boost::thread Boost::log Boost::log_setup
    Boost::locale Boost::regex Boost::chrono Boost::atomic Boost::date_time Boost::iostreams)
if(NOT TARGET Boost::boost)
    add_library(Boost::boost INTERFACE IMPORTED GLOBAL)
    target_link_libraries(Boost::boost INTERFACE Boost::headers)
endif()

find_package(TBB REQUIRED CONFIG)
find_package(ZLIB REQUIRED)
find_package(OpenSSL REQUIRED)
find_package(EXPAT REQUIRED CONFIG)
set(EXPAT_LIBRARIES EXPAT::expat)
find_package(PNG REQUIRED)
add_library(cereal INTERFACE) # header only, in the prefix
target_include_directories(cereal INTERFACE "$ENV{IOS_DEPS_PREFIX}/include")
find_package(NLopt 1.4 REQUIRED)
# QhullConfig.cmake also references dylibs that are not built for iOS.
set(Qhull_FOUND TRUE)
foreach(q qhullcpp qhullstatic_r)
    add_library(Qhull::${q} STATIC IMPORTED GLOBAL)
    set_target_properties(Qhull::${q} PROPERTIES IMPORTED_LOCATION "$ENV{IOS_DEPS_PREFIX}/lib/lib${q}.a"
        INTERFACE_INCLUDE_DIRECTORIES "$ENV{IOS_DEPS_PREFIX}/include")
endforeach()
set(OPENVDB_USE_STATIC_LIBS ON)
set(USE_BLOSC TRUE)
find_package(OpenVDB 5.0 REQUIRED COMPONENTS openvdb)
find_package(libnoise REQUIRED)

set(SRC_DIRS build-utils admesh boost clipper clipper2 miniz minilzo glu-libtess qhull Shiny semver libigl mcut libnest2d libslic3r)
list(REMOVE_ITEM SRC_DIRS build-utils)
foreach(d IN LISTS SRC_DIRS)
    add_subdirectory("${LIBDIR}/${d}" "${CMAKE_BINARY_DIR}/src/${d}" EXCLUDE_FROM_ALL)
endforeach()

# What libslic3r expects from the GUI layer at link time.
add_library(ios_shim STATIC shim/lib/http_stub.cpp shim/lib/nanosvg_impl.cpp ${LIBDIR}/slic3r/Utils/BBLUtil.cpp)
target_link_libraries(ios_shim PUBLIC libslic3r OpenSSL::Crypto)

add_executable(slice_spike MACOSX_BUNDLE EXCLUDE_FROM_ALL spikes/slice/slice_core.cpp spikes/slice/main_ios.mm)
set_source_files_properties(spikes/slice/main_ios.mm PROPERTIES COMPILE_OPTIONS -fobjc-arc)
set_target_properties(slice_spike PROPERTIES MACOSX_BUNDLE_BUNDLE_NAME SliceSpike)
target_link_libraries(slice_spike libslic3r ios_shim Boost::nowide "-framework UIKit" "-framework Foundation" "-framework CoreText" "-framework CoreGraphics" iconv)

add_library(engine STATIC EXCLUDE_FROM_ALL app/engine/Engine.cpp app/engine/Bridge.mm app/engine/Lan.mm)
set_source_files_properties(app/engine/Bridge.mm app/engine/Lan.mm PROPERTIES COMPILE_OPTIONS -fobjc-arc)
target_link_libraries(engine PUBLIC libslic3r ios_shim Boost::nowide OpenSSL::SSL)
