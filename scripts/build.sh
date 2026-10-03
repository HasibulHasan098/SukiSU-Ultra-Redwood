#!/bin/bash
# Build the redwood 5.4 kernel with SukiSU-Ultra builtin (Neutron clang 24).
# usage: SRC=/path/to/kernel_tree [CLANG=/path/to/clang/bin] ./build.sh [outname] [KCONFIG assignments...]
#   e.g. ./build.sh suki CONFIG_LOCALVERSION="-Scarlet-v6.1-beta4-@27c44e41" CONFIG_LOCALVERSION_AUTO=n
set -e
SRC="${SRC:?set SRC to the kernel tree root}"
CLANG="${CLANG:?set CLANG to a dir containing clang/lld/llvm-ar/llvm-nm/llvm-objcopy}"
KR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$SRC/../out_suki}"
NAME="${1:-suki}"; shift 2>/dev/null || true
OUT="$SRC/../out_$NAME"

export PATH="$CLANG:/usr/bin:/bin"
cd "$SRC"

MKARGS=(ARCH=arm64 "O=$OUT"
	CROSS_COMPILE=aarch64-linux-gnu-
	CROSS_COMPILE_COMPAT=arm-linux-gnueabihf-
	CLANG_TRIPLE=aarch64-linux-gnu-
	LLVM=1 LLVM_IAS=1
	# the fork derives these from GitHub / a full .git; pin them to the v3.2.0 release
	KSU_VERSION=13375 "KSU_VERSION_FULL=v3.2.0-0af1ab28@HEAD")

make "${MKARGS[@]}" vendor/xiaomi-qgki_defconfig
KCONFIG_CONFIG="$OUT/.config" scripts/kconfig/merge_config.sh -m -y "$OUT/.config" \
	arch/arm64/configs/vendor/redwood.config \
	"$KR/config/redwood_sukisu.fragment"
for a in "$@"; do
	n="${a%%=*}"; v="${a#*=}"
	case "$v" in
		n) scripts/config --file "$OUT/.config" -d "$n" ;;
		y) scripts/config --file "$OUT/.config" -e "$n" ;;
		m) scripts/config --file "$OUT/.config" -m "$n" ;;
		*) scripts/config --file "$OUT/.config" --set-val "$n" "$v" ;;
	esac
done
make "${MKARGS[@]}" olddefconfig
grep -E '^CONFIG_KSU|^CONFIG_KPM|^CONFIG_MODULES' "$OUT/.config"
make "${MKARGS[@]}" -j"$(nproc)" Image
ls -l "$OUT/arch/arm64/boot/Image"
