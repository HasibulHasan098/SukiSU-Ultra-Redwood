#!/bin/bash
# Swap a freshly built Image into an existing boot image (kernel only, ramdisk untouched).
# usage: BOOT=/path/to/boot.img MB=/path/to/magiskboot [OUTDIR=.] ./pack.sh /path/to/Image boot_sukisu.img
set -e
BOOT="${BOOT:?set BOOT to the stock boot.img you are replacing}"
MB="${MB:?set MB to a magiskboot binary}"
OUTDIR="${OUTDIR:-$PWD}"
IMG="$1"; NAME="${2:-boot_sukisu.img}"
[ -f "$IMG" ] || { echo "no image: $IMG"; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
cp "$BOOT" base.img
"$MB" unpack base.img
grep -E 'HEADER_VER|KERNEL_SZ|RAMDISK_SZ|KERNEL_FMT|RAMDISK_FMT' header || true
cp "$IMG" kernel
"$MB" repack base.img "$NAME"
cp "$NAME" "$OUTDIR/$NAME"
echo "wrote $OUTDIR/$NAME"
