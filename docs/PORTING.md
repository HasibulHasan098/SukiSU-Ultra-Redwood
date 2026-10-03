# Porting notes

Everything that cost time while getting SukiSU-Ultra onto this tree.

## Target

| | |
|---|---|
| Tree | Scarlet redwood — Qualcomm CAF **5.4.302** arm64 (`VERSION=5.4 SUBLEVEL=302` in the root `Makefile`) |
| Style | QGKI: every driver is builtin, `# CONFIG_MODULES is not set` in the shipped config, all `.ko`-shaped drivers compiled `obj-y` |
| ROM | LineageOS 23.2 (Android 16), virtual A/B, partition names may appear as `boot_ab` |
| Shipped kernel | `5.4.302-Scarlet-v6.1-beta4-@27c44e41`, banner compiler `Neutron clang 24.0.0 / LLD 24.0.0` |

## Choosing the fork line

`main` / `v4.2.0` is GKI-era. Against 5.4 it produces ~55 structural errors, all of them API
generations this tree predates:

- `selinux_state.policy` (6.x) vs `selinux_state.ss->policydb` (this tree)
- `ss->policydb` vs global `policydb`
- `filename_trans_key` + ebitmap `stypes` + `next` chain (5.7+)
- `symtab_search` / `hashtab_key_params` (5.9+)
- `handle_inode_event` fsnotify signature (5.7+)
- `file_operations.iterate` removed in 6.x — **and this 5.4 tree already backported the removal**,
  so `iterate_shared` only; a version check alone is not enough, probe `include/linux/fs.h`
- `register_trace_prio_sys_enter` (6.2+), `vdso_clock_mode`, `TWA_RESUME`

**v3.2.0** is the last line that ports with only SELinux-layer guards: 3 files, 41 added lines.
If you need a newer fork, budget for rewriting the SELinux and fsnotify layers, not for a
two-line patch.

The tree also ships its own 5.4-native fork. Keep it as a reference implementation — the
pre-5.7 `add_filename_trans()` and the `selinux_state.ss->policydb` accessor pattern are both
already solved there:

```bash
mv drivers/kernelsu drivers/kernelsu.stock     # before linking the new fork in
```

## The three guards

1. **`kernel/selinux/sepolicy.c`** — wrap the modern block in
   `#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 7, 0)` and add the legacy branch:
   `struct filename_trans` *is* the key, one `filename_trans_datum` per key,
   `hashtab_search` / `hashtab_insert` on `db->filename_trans`, then
   `ebitmap_set_bit(&db->filename_trans_ttypes, src->value - 1, 1)`.
2. **`kernel/selinux/rules.c`** — `get_policydb()` must return `&selinux_state.ss->policydb`
   below 5.10; `SELINUX_POLICY_INSTEAD_SELINUX_SS` is only correct from 5.10 up.
3. **`kernel/Makefile`** — this Xiaomi tree backported `current_sid()` into
   `security/selinux/include/objsec.h`, so the fork's own copy collides. Probe the header and
   define `KSU_COMPAT_HAS_CURRENT_SID` rather than editing the C:

```make
ifeq ($(shell grep -q " current_sid(void)" $(srctree)/security/selinux/include/objsec.h; echo $$?),0)
ccflags-y += -DKSU_COMPAT_HAS_CURRENT_SID
endif
```

`include/linux/pgtable.h` is missing on some 5.4 drops and newer forks expect it; v3.2.0 does
not, so no shim is needed here. If you move to a newer line, that header shim is the first thing
you will hit.

## Building

Iterate on the fork without rebuilding the kernel:

```bash
# flask.h is generated, so security/selinux must be built first in a partial build
make ... security/selinux/
make ... -k drivers/kernelsu/          # -k to see the whole error surface at once
```

Gotchas in this tree:

- `LLVM=1 LLVM_IAS=1` + `CROSS_COMPILE=aarch64-linux-gnu-`. Using
  `CROSS_COMPILE=aarch64-linux-androidkernel-` breaks the *host* tools too, because
  `scripts/Makefile.clang` composes `--target=$(notdir $(CROSS_COMPILE:%-=%))` and `HOSTCC`
  inherits it -> `clang: error: version 'kernel' in target triple ... is invalid`.
- `scripts/config` here supports `-e / -d / -m / --set-val`, **not** `-o`.
- `arch/arm64/kernel/vdso32/Makefile` builds the compat VDSO with
  `CC_COMPAT = $(CC) --target=arm-linux-gnueabi`, so no 32-bit gcc is required.
- The fork's `Makefile` curls the GitHub API for its version and otherwise counts commits in
  `../.git`. A shallow clone of the tag reports a lower `KSU_VERSION` than the manager expects,
  so pin both on the command line (`KSU_VERSION=13375`, `KSU_VERSION_FULL=v3.2.0-<sha>@<branch>`).
- `CONFIG_KSU` is `tristate` and defaults **off** in the bundled fork; `OVERLAY_FS` is a hard
  dependency. `KPM` needs `64BIT` and selects `KALLSYMS(_ALL)`.

## Config archaeology

`arch/arm64/configs/vendor/xiaomi-qgki_defconfig` is the tree's own committed build config
(a `savedefconfig` result: ~615 explicit lines, ~1640 after `olddefconfig`). The CAF blend script
(`scripts/gki/generate_defconfig.sh` + `envsetup.sh`) would combine `gki_defconfig` with
`xiaomi_GKI.config` / `xiaomi_QGKI.config`, but **those fragments are not in this drop**, so the
committed defconfig is the closest thing to the maintainer's real config.

Do not trust `extract-ikconfig` on the shipped boot kernels. The embedded blob in the Lineage 23.2
kernel claims `Linux/arm64 5.4.147`, `CONFIG_LOCALVERSION="-qgki"`, `CONFIG_CLANG_VERSION=110002`
— while the image's own banner and vermagic say `5.4.302-Scarlet-v6.1-beta4` built with clang 24.
The SpeedOS stock kernel carries a *different* blob. Both are stale.

Consequences of that recipe: `LTO_CLANG` and `CFI_CLANG` are **off**. For a kernel whose whole
job is kprobe-based syscall hooking plus KPM-style text patching, that is the friendlier
situation; CFI on a 5.4 QGKI build is a known source of panics for this kind of hooking.

## Packaging

`magiskboot` repack of a header-v3 image swaps the kernel and leaves everything else alone —
verify rather than assume:

```bash
magiskboot unpack base.img; cp Image kernel; magiskboot repack base.img out.img
# then unpack both and compare: kernel sha256 == built Image, ramdisk.cpio sha256 == original
```

The image keeps its `AVBf` footer. That is fine on an unlocked bootloader with a custom ROM (this
is the same path Magisk uses), but keep the stock `boot.img` next to the new one as the revert.

## KPM: why it says "Unsupported"

`kernel/kpm/kpm.c` in the v3.2.0 source is **stub-only**. Every entry point is a
`noinline NO_OPTIMIZE` function that prints and returns -1:

```c
noinline NO_OPTIMIZE void sukisu_kpm_version(void __user *out, unsigned int bufferSize, void __user *result)
{
        int res = -1;
        printk("KPM: Stub function called (sukisu_kpm_version). buffer=%p size=%d\n", out, bufferSize);
        if (copy_to_user(result, &res, sizeof(res)) < 1)
                printk("KPM: Copy to user failed.");
}
```

The dispatch is wired correctly and does reach KPM (`KernelSU: KPM: calling before arg2=34` in
dmesg, `sukisu_handle_kpm()` decoding `SUKISU_KPM_VERSION`), which is why the manager shows the
feature as present-but-unsupported instead of failing. The real ELF loader/patch engine ships as
a separate hotpatch aimed at GKI kernels ("Kernel not patched"). Root, allowlist, sulog, magisk-
style modules and the dynamic manager signature are all independent of it and work.

## Manager pairing

Kernel v3.2.0 pairs with manager **v3.2.0 (13375)**. In that APK the userspace is behind decoy
names — `lib/arm64-v8a/libzakozako.so` is ksud (Rust), `libzakoboot.so` is ksuinit; there is no
`libksud.so` until v4.2.0. The manager installs ksud itself to `/data/adb/ksu/bin/ksud` on first
launch, so no manual push is needed.

The kernel's manager allowlist is compiled in (`manager_sign.h`): without an explicit
`KSU_EXPECTED_SIZE` / `KSU_EXPECTED_HASH`, only the ShirkNeko/SukiSU signing key is accepted,
plus the dynamic-sign path (`/data/adb/ksu/.dynamic_manager`).
