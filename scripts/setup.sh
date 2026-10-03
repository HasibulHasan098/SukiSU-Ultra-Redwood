#!/bin/bash
# Put the SukiSU-Ultra v3.2.0 kernel into a Scarlet / CAF 5.4 redwood tree.
# usage: SRC=/path/to/kernel_tree ./setup.sh
set -e
SRC="${SRC:?set SRC to the kernel tree root}"
TAG="${TAG:-v3.2.0}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
KDIR="$SRC/../sukisu-$TAG"
KSU="$SRC/drivers/kernelsu"

[ -d "$SRC/arch/arm64/configs/vendor" ] || { echo "not an arm64 CAF tree: $SRC"; exit 1; }
[ -e "$KSU" ] && { echo "$KSU exists - move it aside first (e.g. drivers/kernelsu.stock)"; exit 1; }

[ -d "$KDIR/.git" ] || git clone --depth 1 --branch "$TAG" https://github.com/SukiSU-Ultra/SukiSU-Ultra "$KDIR"

cd "$KDIR"
git apply -v "$HERE/patches/0001-sukisu-v3.2.0-legacy-5.4-selinux-port.patch" || echo "(patch may already be applied)"

cd "$SRC/drivers"
ln -s "../../sukisu-$TAG/kernel" kernelsu
grep -q "obj-\$(CONFIG_KSU)" Makefile || printf 'obj-$(CONFIG_KSU)\t\t+= kernelsu/\n' >> Makefile
grep -q 'source "drivers/kernelsu/Kconfig"' Kconfig || sed -i '$ i source "drivers/kernelsu/Kconfig"' Kconfig
echo "drivers/kernelsu -> $(readlink -f kernelsu)"
echo "next: SRC=$SRC ./build.sh"
