#!/bin/bash
# Create the llvm-binutils prefix shim used by the build (only needed if a step
# still asks for $(CROSS_COMPILE)ar / nm / objcopy by name).
# usage: CLANG=/path/to/clang/bin ./make-shim.sh [dest]
set -e
CLANG="${CLANG:?set CLANG to a dir containing clang/ld.lld/llvm-*}"
DEST="${1:-$(dirname "$0")/../shim}"
mkdir -p "$DEST"; cd "$DEST"
for p in aarch64-linux-gnu- aarch64-linux-androidkernel- arm-linux-androideabi- arm-linux-gnueabihf-; do
	ln -sf "$CLANG/llvm-ar"    "${p}ar"
	ln -sf "$CLANG/ld.lld"     "${p}ld"
	ln -sf "$CLANG/llvm-nm"    "${p}nm"
	ln -sf "$CLANG/llvm-objcopy" "${p}objcopy"
	ln -sf "$CLANG/llvm-objdump" "${p}objdump"
	ln -sf "$CLANG/llvm-readelf" "${p}readelf"
	ln -sf "$CLANG/llvm-strip"   "${p}strip"
done
echo "shim ready in $DEST"
