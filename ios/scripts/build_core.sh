#!/usr/bin/env bash
# Configure and build libslic3r for iPad. Usage: build_core.sh [target]
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$IOS/build/venv/bin:$PATH" IOS_DEPS_PREFIX="$IOS/build/prefix"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
cmake -G Ninja -S "$IOS" -B "$IOS/build/core" -DCMAKE_TOOLCHAIN_FILE="$IOS/cmake/ios-toolchain.cmake" -DCMAKE_OSX_SYSROOT="$SDK"
cmake --build "$IOS/build/core" -j"${JOBS:-6}" --target "${1:-libslic3r}" -- -k 0
