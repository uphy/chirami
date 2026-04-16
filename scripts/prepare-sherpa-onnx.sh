#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cache_root="$repo_root/.build/prebuilts/sherpa-onnx"
src_dir="$cache_root/src"
build_dir="$cache_root/build-swift-macos"
install_dir="$build_dir/install"
version="${SHERPA_ONNX_VERSION:-v1.12.20}"

if ! command -v cmake >/dev/null 2>&1; then
  echo "error: cmake is required to build sherpa-onnx" >&2
  exit 1
fi

mkdir -p "$cache_root"

if [ ! -d "$src_dir/.git" ]; then
  rm -rf "$src_dir"
  git clone --depth 1 --branch "$version" https://github.com/k2-fsa/sherpa-onnx "$src_dir"
fi

if [ -f "$install_dir/lib/libsherpa-onnx-c-api.a" ] \
  && [ -f "$install_dir/lib/libsherpa-onnx-core.a" ] \
  && [ -f "$install_dir/lib/libonnxruntime.a" ] \
  && [ -f "$install_dir/include/sherpa-onnx/c-api/c-api.h" ]; then
  exit 0
fi

rm -rf "$build_dir"
mkdir -p "$build_dir"
cd "$build_dir"

cmake \
  -DSHERPA_ONNX_ENABLE_BINARY=OFF \
  -DSHERPA_ONNX_BUILD_C_API_EXAMPLES=OFF \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_INSTALL_PREFIX=./install \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DSHERPA_ONNX_ENABLE_PYTHON=OFF \
  -DSHERPA_ONNX_ENABLE_TESTS=OFF \
  -DSHERPA_ONNX_ENABLE_CHECK=OFF \
  -DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF \
  -DSHERPA_ONNX_ENABLE_JNI=OFF \
  -DSHERPA_ONNX_ENABLE_C_API=ON \
  -DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF \
  "$src_dir"

make -j"$(sysctl -n hw.ncpu)"
make install
