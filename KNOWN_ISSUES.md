# Known Issues

## Mesa 25 Zink mapper path (fixed 2026-10-12)

Zink `glxinfo -B` aborted with exit 134 and
`library "/vendor/lib64/hw/mapper.mediatek.so" not found` when the boot flow
omitted the root-level `/vendor` bind because `/opt/android-mali/vendor/lib64`
already existed. The mapper was present in the staging tree, but the runtime
required its absolute `/vendor` path.

`device/core/linux-start.sh` now binds the Android vendor directory read-only
at the chroot's `/vendor`, independently of the staging tree. The legacy
`/system` bind remains conditional. `device/gpu/check-mesa25.sh` now reports
the exit code and stderr on Zink failure and does not report a heap pass after
an unsuccessful Zink invocation.

The fix was applied to the active container without restarting XFCE. The full
Mesa 25 check returned `RESULT ok=12 fail=0` and `ENV_OK`. A 60-second Zink
`glxgears` test produced frames, reached its expected timeout (124), and kept
the original XFCE session alive. `/vendor` was confirmed read-only. The
installed boot script was patched without updating its older common helpers;
the backup is `/data/linux/mesa25-fix-backup-BJC305`. A container restart has
not yet been tested with this fix.

The Mali-G615 still reports missing Zink features, including `logicOp`,
`fillModeNonSolid`, `shaderClipDistance`, and a drawing warning for
`VK_EXT_depth_clip_enable`. This fix restores Mesa 25.1.2 initialization and
drawing at the observed OpenGL 3.1 level; it does not establish visual
correctness for all applications or OpenGL 4.6 support.

## Mesa 26 on Android Mali

The current Artix rootfs uses the `mesa25-android-mali` overlay. Mesa 26 has
been associated in this project with `free(): invalid size` / `invalid pointer`
failures in softGL and Zink + hybris. The production setup avoids a Mesa 26
upgrade; do not remove that block based on repository availability alone.

`/data/linux/test-mesa-26.sh` evaluates a separate copy at
`/data/linux/rootfs-mesa26-test.img`. It refuses to overwrite an existing test
image, records package and runtime evidence in a timestamped log, and does not
install packages into `rootfs.img`. Run it only with enough free storage for a
second image and the main container stopped. The test copy is retained for
inspection and must be removed manually when no longer needed.

Reconsider the block only after a reproducible device run records the active
`IgnorePkg`, repository candidate, installed Mesa version, `glxinfo -B`, and
`vkcube` results. A package transaction that succeeds without successful
runtime checks is not sufficient evidence to upgrade the production rootfs.

### Device evaluation (2026-10-11)

On a Moto G86 5G (Mali-G615 MC2), Mesa `1:26.2.4-1` installed in the isolated
test image and `vulkaninfo` detected the Mali driver (Vulkan API 1.3.247,
driver 44.1.0). The production Mesa 25.1.2 baseline rendered through Zink on
that Mali device, reporting OpenGL 3.1 and OpenGL ES 2.0; the driver warned that
the GPU lacks Zink base features `logicOp`, `fillModeNonSolid`, and
`shaderClipDistance`. In a separate run with Mesa 26 libraries explicitly
prioritized from `/usr/lib`, `eglinfo -p surfaceless` failed at
`eglInitialize`. Termux:X11 was later started successfully with the normal
`x11-start.sh` flow and created its `:0` socket. With that socket bound into the
test clone and the Mali vendor overlay exposed there, `vkcube` returned 0 on the
Mali-G615 and loaded AHardwareBuffer functions. This validates the proprietary
Mali Vulkan path, not Mesa 26 Zink. In the same run, Mesa 26 `eglinfo` returned
1 at `eglInitialize`; `glxinfo` printed `couldn't find RGB GLX visual or
fbconfig` despite returning 0, so it provided no valid Mesa 26 renderer result.
The final log is `/data/linux/mesa26-test-20261011-210411.log`. Installing Xvfb
into the clone was also blocked: package downloads returned 404 or DNS errors.
DNS checks confirmed that
`armtix.artixlinux.org` and `repo.armtixlinux.org` serve the world database and
Mesa package with HTTP 200, while `repo.xdan.eu` still has no DNS address. A
subsequent `pacman -Sy` succeeded and confirmed candidate `1:26.2.4-1`; the
runtime rerun reproduced the Mesa 25 baseline followed by Mesa 26
`eglInitialize` failure. Its device log is
`/data/linux/mesa26-test-20261011-204416.log`.

the disposable test image for diagnosis.
**Final production decision for this evaluation: keep Mesa 25.1.2.** Mesa
26.2.4 was not promoted. Its final isolated candidate initialized EGL/Zink on
the Mali-G615, but reported OpenGL 3.1, matching the Mesa 25 baseline; it also
warned that the ICD lacks Zink's required `logicOp` feature. GLX and sustained
drawing were not validated because the X11 `:0` socket was unavailable. No
further Mesa 26 tests are planned as part of Phase 5. The production rootfs
was not changed.

### Maintenance5 code difference

The source comparison found this change in requirement scope:

- Mesa 25 `zink_device_info.py` collects `VK_KHR_maintenance5` optionally. Its
	Vulkan Profiles data places maintenance5 in `gl40_baseline`, not
	`gl21_baseline`.
- Mesa 25 has a fallback for missing maintenance5: point-size behavior is
	lowered in `zink_state.c`, and the compiler avoids relying on the
	maintenance5 default point-size guarantee.
- Mesa 26 changes the extension declaration to `required=True`. Therefore
	`zink_get_physical_device_info()` fails screen initialization if the ICD does
	not advertise it. Mesa 26's Profiles data also moves maintenance5 and its
	feature to `gl21_baseline`, while removing them from `gl40_baseline`.
- The captured Mali-G615 ICD identifies itself as Vulkan `1.3.247` and its raw
	`vulkaninfo` device-extension list does not contain `VK_KHR_maintenance5`.
	It does advertise timeline semaphore and dynamic rendering. The observed
	maintenance5 absence is real in this ICD report; there is no evidence yet
	that the driver implements the extension but omits its advertisement.

Zink's `VK_KHR_maintenance5` use includes the `polygonModePointSize` property
and point-size semantics. Mesa 25 explicitly has fallback handling for those
uses. This supports investigating the new global requirement as a possible
over-broad regression, but does not by itself prove that every Mesa 26 use is
safe without maintenance5. Do not remove the requirement or fabricate Vulkan
capability bits.

The Vulkan Profile data in Mesa 25 already requires maintenance5 for its
`gl40_baseline`; consequently this Mali ICD cannot currently claim that profile
based on the reported capabilities. It reports OpenGL 3.1 on Mesa 25 Zink. The
current evidence does not establish OpenGL 4.6 capability. A workaround that
only restores lower-version initialization would not satisfy the modern GL
target.

### Final candidate result

The candidate removed the global maintenance5 initialization failure while
retaining maintenance5 requirements in the `gl46_optimal` profile. It ported
Mesa 25-style dummy buffer, buffer-view, and surface fallbacks for null
descriptors, including bindless and framebuffer-fetch paths; descriptor-buffer
mode is disabled when the ICD lacks `nullDescriptor`. The ARM64 Mesa 26.2.4
build passed the Kopper gate (`kopper_init_screen=204B`).

On the final isolated runtime, `vulkaninfo --summary` and surfaceless `eglinfo`
returned 0. EGL identified `zink Vulkan 1.3(Mali-G615 MC2 (ARM_PROPRIETARY))`
and reported OpenGL core/compatibility 3.1. The ICD emitted a warning that
`logicOp` required by Zink's base profile is unsupported. GLX was blocked
because socket `:0` was absent, and no sustained draw test ran. This result
does not meet the expected GL 4.6 target or improve on Mesa 25. Do not install
the candidate in production or force a GL version/capability override.

#### Mesa 26.2.4 candidate artifacts (2026-10-12)

The new `host/build-mesa26-android-mali-wsl.sh` built commit
`96cb43121031992b85767f9c1be8f3f48e22b1d2` (`VERSION=26.2.4`) from the
`mesa-26.2.4` tag, on a separate local branch/worktree. Meson confirmed X11,
Wayland, `glx=dri`, softpipe, and Zink. The Mali no-quads patch applied at a
44-line context offset. `kopper_init_screen` measured 204 bytes and the Zink
gate passed. The Zstd tarball passed integrity/listing checks (76 entries); its
SHA-256 is `7ea33015ef4db2fe30c609013e510ce2282f2a2b97c92f9b56146e78928d5aab`.

tests so far show: Mesa 26 softpipe GLX works; Mesa 26 Zink fails during device
feature initialization at the missing maintenance5 requirement; the Mali
Vulkan cube works. This does not yet determine whether a narrowly scoped
Artifacts include the earlier base build and the final isolated candidate
`/home/vagners/arch-root/mesa26-maint5-nullfb-final-20261012.tar.zst`
(SHA-256 `738cb068be68ef5ab0dcf53c92e05a731ee35a17280e596d70e7bf7672ea6297`).
They are diagnostic artifacts only; Mesa 25.1.2 remains the production
version. Phase 5 is closed with the boot-service rotation integration recorded
as deferred because the production container remained active during validation.