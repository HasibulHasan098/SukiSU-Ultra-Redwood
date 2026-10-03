# SukiSU-Ultra on Scarlet redwood (5.4.302)

SukiSU-Ultra **v3.2.0** built **BUILTIN** (not a `.ko`) into the Scarlet / CAF
Qualcomm **5.4.302** kernel for **Xiaomi redwood**, packaged as a flashable `boot.img`.

## Tested on

| | |
|---|---|
| Device | Xiaomi POCO X5 Pro 5G — `redwood` / model `22101320G` (also matches `redwoodin`) |
| OS under test | **LineageOS 23.2 — Android 16**, security patch level 2026-09, virtual A/B (slot `_a`) |
| Kernel | Scarlet redwood `5.4.302-Scarlet-v6.1-beta4-@27c44e41` (CAF 5.4, QGKI style) |
| Manager | SukiSU-Ultra `v3.2.0 (13375)` |
| Build host | Ubuntu 26.04.1 LTS x86_64, Neutron clang / LLD **24.0.0** (same compiler version as the shipped Lineage 23.2 kernel banner) |

Root was verified on that exact setup: `su -c id` -> `uid=0(root) ... context=u:r:su:s0` with
SELinux **Enforcing**, and the manager reports `Working / Built-in`.

## Why v3.2.0 and not the current release

SukiSU-Ultra `main` / v4.2.0 is GKI-era code. On this 5.4 vendor tree it fails with ~55
structural errors (`selinux_state.policy`, `handle_inode_event`, `file_operations.iterate`,
`register_trace_prio_sys_enter`, `vdso_clock_mode`, `TWA_RESUME`, ...).
v3.2.0 is the last line that ports cleanly: **3 files, 41 added lines**, all version guards.

## What the patch does

`patches/0001-sukisu-v3.2.0-legacy-5.4-selinux-port.patch`

- `kernel/selinux/sepolicy.c` — pre-5.7 `add_filename_trans()`: `struct filename_trans` *is* the
  hashtab key and there is one `filename_trans_datum` per key (the 5.7+ code uses
  `filename_trans_key` + `stypes` ebitmap + a `next` chain).
- `kernel/selinux/rules.c` — `get_policydb()` takes `selinux_state.ss->policydb` before 5.10
  (`selinux_state.policy->policydb` only exists from 5.10); `SELINUX_POLICY_INSTEAD_SELINUX_SS`
  is now conditional on >= 5.10.
- `kernel/Makefile` — probe: if the tree already backports `current_sid()` into
  `security/selinux/include/objsec.h` (this Xiaomi 5.4 tree does), define
  `KSU_COMPAT_HAS_CURRENT_SID` so the fork does not redefine it.

## Build

```bash
# 1. toolchain: any clang >= 14 that can build this tree; 24.0.0 is what we used
CLANG=/path/to/clang/bin  SRC=/path/to/scarlet_redwood  OUTDIR=$PWD

# 2. optional: llvm binutils prefix shim
CLANG=$CLANG ./scripts/make-shim.sh

# 3. drop SukiSU into the tree (clones tag v3.2.0, applies the patch, links drivers/kernelsu)
SRC=$SRC ./scripts/setup.sh

# 4. build
SRC=$SRC CLANG=$CLANG ./scripts/build.sh suki \
    'CONFIG_LOCALVERSION="-Scarlet-v6.1-beta4-@27c44e41"' CONFIG_LOCALVERSION_AUTO=n
```

Config recipe: `arch/arm64/configs/vendor/xiaomi-qgki_defconfig` (the tree's own committed
build config) + `arch/arm64/configs/vendor/redwood.config` +
`config/redwood_sukisu.fragment`. `CONFIG_KSU` defaults to **off** in the bundled fork, so the
fragment turns on `KSU / KPM / KPROBES / KRETPROBES / OVERLAY_FS / MODULES` and selects the
**kprobes** hook mode.

`KSU_VERSION=13375` and `KSU_VERSION_FULL=v3.2.0-<sha>@<branch>` are passed on the command line
because the fork's Makefile derives them from the GitHub API or a full `.git`; a shallow clone
of the tag reports a lower version than the v3.2.0 manager expects.

Result: `arch/arm64/boot/Image`, 34,017,288 bytes (stock base: 31,303,688), **zero `.ko`**,
82 `ksu_*` symbols in `System.map`.

## Package and flash

```bash
# swap the kernel into the ROM's own boot image (ramdisk is left byte-identical)
BOOT=/path/to/boot_lineage23.img MB=/path/to/magiskboot OUTDIR=$PWD \
    ./scripts/pack.sh /path/to/out_suki/arch/arm64/boot/Image boot_sukisu.img

fastboot flash boot boot_sukisu.img     # Xiaomi also accepts: fastboot flash boot_ab ...
fastboot reboot
```

Then install `SukiSU_v3.2.0_13375-release.apk` and open it once — the manager installs its own
ksud to `/data/adb/ksu/bin/ksud`. In this APK the userspace is hidden behind decoy names:
`lib/arm64-v8a/libzakozako.so` = ksud, `libzakoboot.so` = ksuinit. There is no `libksud.so`
until v4.2.0.

Revert: `fastboot flash boot <stock Lineage boot.img>`.

Prebuilt flashable files for this exact build are attached to
[release v3.2.0-redwood-1](https://github.com/HasibulHasan098/SukiSU-Ultra-Redwood/releases/tag/v3.2.0-redwood-1)
(`boot_sukisu.img`, `SukiSU_v3.2.0_Scarlet_redwood_AK3.zip`, and a mirror of the matching
`SukiSU_v3.2.0_13375-release.apk` manager).

## Verified on device

- Manager home: `Working` + `Built-in`, version `v3.2.0-0af1ab28@HEAD`, hook type `Kprobes`,
  kernel `5.4.302-Scarlet-v6.1-beta4-@27c44e41`, Android 16, SELinux Enforcing.
- `dmesg`: every kprobe registers with rc 0 (`register___arm64_sys_execve kprobe: 0`,
  `execve_kp: 0`, `vfs_read_kp: 0`, `input_event_kp: 0`) and `ksu_handle_bprm_ksud` fires.
- `su -c id` -> uid 0, `u:r:su:s0`; Superuser allowlist and per-app profile UI work;
  root file writes work.
- Device boots normally from the swapped kernel (online in ~50 s).

## Known limitations

- **KPM reports "Unsupported (Kernel not patched)".** In the v3.2.0 source, `kernel/kpm/kpm.c`
  ships stub-only — every `sukisu_kpm_*` entry point prints `Stub function called` and returns
  `-1`; the real ELF loader is delivered as a separate hotpatch for GKI kernels. The supercall
  dispatch itself reaches KPM fine (`KernelSU: KPM: calling before arg2=34`). Kernel-side root,
  allowlist, sulog, modules-as-magisk-style and dynamic signature all work.
- Built without `LTO_CLANG` / `CFI_CLANG`: `xiaomi-qgki_defconfig` does not carry them. This is
  also friendlier for kprobe patching and KPM-style text modification.
- The `CONFIG_IKCONFIG` blob inside the shipped boot kernels is misleading (`5.4.147`,
  `LOCALVERSION="-qgki"`, clang 11 on a kernel whose banner says clang 24 / 5.4.302). Do not use
  `extract-ikconfig` on them to infer the real build config.
- No `.ko` is shipped by this ROM at all (no `/vendor/lib/modules`), so vermagic compatibility
  with prebuilt modules is not a constraint here.

## Layout

```
README.md
patches/   0001-sukisu-v3.2.0-legacy-5.4-selinux-port.patch
config/    redwood_sukisu.fragment          KSU/KPM/kprobes switches
           redwood_sukisu_defconfig         savedefconfig of the working build
           redwood_sukisu_defconfig.full    full .config of the working build
scripts/   setup.sh build.sh pack.sh make-shim.sh
docs/      PORTING.md
```

[docs/PORTING.md](docs/PORTING.md) has the details: why the current fork line does not build on
5.4, the exact API cliffs, kbuild gotchas in this tree, config archaeology, and how the KPM stub
was traced.

Upstream: [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) (tag `v3.2.0`),
Scarlet kernel by Tashar @ Atom-X-Devs, AnyKernel3 by osm0sis. Kernel sources GPL-2.0.
