# Artix + dinit on Android (KernelSU)

> Languages: **English** · [Português](README.pt.md)

Real chroot on an ext4 image. No proot. Desktop via **Termux:X11** (GPU).

dinit starts at boot through KernelSU. SSH runs inside the container.
Hermes/OmniRoute services: dinit templates only in `device/dinit.d/` until binaries exist.

**GPU hybris (acceleration):** validated **only** on MediaTek **mt6878** + Mali-G615 MC2 (e.g. Moto G86). SoftGL/CPU works on other devices; the hybris/Zink stack is **not** generic.

---

## Requirements

- KernelSU + ADB
- Tarball: `armtix-dinit-20260921.tar.xz` — Termux home or `/data/local/tmp` (auto-download if missing: [armtix-dinit-20260921.tar.xz](https://armtix.artixlinux.org/images/armtix-dinit-20260921.tar.xz))
- `ksu-module` (SELinux for loop devices)
- **Termux:X11** app (`com.termux.x11`) — F-Droid or [GitHub nightly](https://github.com/termux/termux-x11/releases). Base Termux alone is **not enough**.
- For accelerated GPU: **mt6878** SoC (blobs under `/vendor/lib64/.../mt6878/`) — other chips need manual adaptation

---

## 1. Push scripts (PC)

```powershell
cd host
.\deploy.ps1
```

On the device:

```sh
adb shell
su
sh /data/local/tmp/rootfs/host/prepare.sh
```

---

## 2. SELinux module

Install `ksu-module` in KernelSU Manager.

Reboot the device. Without this, the mount may not be RW.

---

## 3. Fresh environment (recommended)

One command: runs **linux-stop** (clean state), installs the rootfs (if needed), starts the container, applies dinit stubs, starts **sshd** as a dinit service (port 2222), then **dbus/elogind**, creates a user, XFCE and Termux:X11. **GPU hybris is skipped** (manual step later). Ends with a strict `linux-status` that does not require GPU.

```sh
su
/data/linux/bootstrap.sh
# local terminal or adb with TTY: prompts to create a user (default Y)
```

Without TTY (e.g. `adb shell` + `su -c`):

```sh
CREATE_USER=1 ARTIX_USER=<user> ARTIX_PASS='password' /data/linux/bootstrap.sh
# re-run when user already has /home: /data/linux/bootstrap.sh is enough
```

Bootstrap defaults to `SKIP_GPU=1` (core + XFCE). GPU + desktop:

```sh
/data/linux/gpu-desktop.sh
```

Inconsistent rootfs (broken libs/pacman): there is **no** lib recovery — `YES=1 /data/linux/wipe-chroot.sh && /data/linux/bootstrap.sh`.

Tarball resolution order:

1. argument / `ARMTIX_TAR`
2. Termux home: `~/armtix-dinit-20260921.tar.xz`
3. `/data/local/tmp/armtix-dinit-20260921.tar.xz`
4. download to `/data/local/tmp`: https://armtix.artixlinux.org/images/armtix-dinit-20260921.tar.xz

If `.xz` fails, in Termux: `pkg install xz-utils && xz -dk ~/armtix-dinit-….tar.xz`

After bootstrap you want `[ok]` for sshd, dbus, elogind, dbus socket, X11 `:0`.  
GPU / Zink are **not** part of this phase.

---

## 3b. On-screen GPU (recommended)

**mt6878 / Mali-G615 MC2 only.** On other devices use softGL (`gpu-desktop.sh cpu` / XFCE default).

One command covers setup (if missing) + Zink in XFCE + Termux:X11:

```sh
/data/linux/gpu-desktop.sh          # start
/data/linux/gpu-desktop.sh status  # markers + config
/data/linux/gpu-desktop.sh stop    # stop X11/XFCE
/data/linux/gpu-desktop.sh cpu     # softGL desktop (CPU)
```

- **First time:** runs `run-setup-gpu-hybris` if markers are missing, sets `XFCE_USE_ZINK=1` when `artix-gpu-zink.ok` exists, starts the desktop.
- **Later days:** same `gpu-desktop.sh` (only brings up the display; GPU is already in `rootfs.img`).
- **Autostart:** container only (`99-linux.sh`) — GPU/desktop do **not** start on their own.

Advanced setup (no helper): `/data/linux/run-setup-gpu-hybris.sh`.

---

## 4. Step by step (advanced)

```sh
/data/linux/install-rootfs.sh
/data/linux/linux-start.sh
/data/linux/run-setup.sh                      # core only (sshd/dbus/elogind)
SETUP_FULL=1 SKIP_GPU=1 /data/linux/run-setup.sh  # core + XFCE (no GPU)
SETUP_FULL=1 /data/linux/run-setup.sh         # core + GPU hybris + XFCE
/data/linux/x11-start.sh
STRICT=1 REQUIRE_X11=1 REQUIRE_GPU=0 /data/linux/linux-status.sh
```

`run-setup.sh` restarts the container after dinit stubs, starts **sshd** as a dinit service (port 2222, step 4), then **dbus/elogind**. If SSH fails to start, it fails at that step. On a TTY (or `/dev/tty`) it asks whether to create a user; with `CREATE_USER=1` / `0` it does not ask. With `SETUP_FULL=1` and no TTY it requires `ARTIX_USER` + `ARTIX_PASS`.

---

## 5. Autostart

`prepare.sh` (and `bootstrap.sh` at the end) install automatically:

`/data/adb/service.d/99-linux.sh` → starts the container after boot (KernelSU late_start + watchdog).

```sh
# reinstall / update
/data/linux/install-autostart.sh

# skip during prepare
SKIP_AUTOSTART=1 sh /data/local/tmp/rootfs/host/prepare.sh
```

XFCE/Termux:X11 do **not** start at boot — use `/data/linux/gpu-desktop.sh` (or `x11-start.sh`).  
Boot = container; GPU/desktop = on demand.

---

## Correct usage

### Container

```sh
/data/linux/linux-start.sh
/data/linux/linux-status.sh
```

Enter via helpers (do not chroot by hand):

```sh
/data/linux/linux-shell.sh            # root → /root
/data/linux/linux-shell.sh <user>     # user → /home/<user>
```

### Users

In `bootstrap` / `run-setup` (recommended — prompts y/N + name/password via TTY or `/dev/tty`):

```sh
/data/linux/bootstrap.sh
# or core only:
/data/linux/run-setup.sh
# or without prompt:
CREATE_USER=1 ARTIX_USER=<user> ARTIX_PASS='password' /data/linux/bootstrap.sh
```

Or manually:

```sh
ARTIX_SUDO=1 /data/linux/artix-user.sh create <user> 'password'
/data/linux/artix-user.sh passwd <user> 'newpass'
/data/linux/artix-user.sh sudo <user>
```

User home: `/home/<user>` (`cd ~`).

`/root` is root-only — `cd root` as a normal user fails (expected).

Passwords with special characters: single quotes or `passwd <user> -` (stdin).

### Pacman

```sh
/data/linux/fix-pacman-mirrors.sh
/data/linux/fix-pacman-sandbox.sh
sudo pacman -Syu
```

Missing Arch packages (e.g. direnv) — use **Arch Linux ARM**, not Arch x86:

```sh
/data/linux/enable-archlinuxarm.sh
sudo pacman -S direnv
```

### System dinit services

```
/etc/dinit.d/name
/etc/dinit.d/boot.d/name → ../name
```

```sh
/data/linux/install-dinit-services.sh dinit-test
dinitctl status dinit-test
```

In `command =`: **do not use `>`**. Use a script file instead.

### User dinit test

System dinit is already running (`/run/dinitctl`).

Isolated test:

```sh
~/test-dinit-network.sh
```

Needs: `--user --container --cgroup-path /sys/fs/cgroup`, a `boot` service, no `>` in command.

### XFCE + Termux:X11 (GPU)

Desktop in the chroot via **Termux:X11** (display `:0`). No TigerVNC.
Default: softGL (CPU). Optional: `XFCE_USE_ZINK=1` in `/etc/artix-x11.conf` → desktop via **Zink→Vulkan Mali** (requires `/etc/artix-gpu-zink.ok`). Standalone GPU apps: `gpu-vulkan-run` / `zink-run` / `gpu-run`.

**Prerequisite:** Android app **Termux:X11** (`com.termux.x11`). Base Termux (`com.termux`) is **not enough**.  
Install from F-Droid or [GitHub releases](https://github.com/termux/termux-x11/releases) (`termux-x11-universal-debug.apk` from the **nightly** tag).  
Companion `loader.apk` (Android 14+): `prepare.sh` / `x11-start.sh` install it from `/data/linux/termux-x11/`, or in Termux `pkg i x11-repo && pkg i termux-x11-nightly`.  
If the APK is missing, `/data/linux/x11-start.sh` aborts with instructions.  
Note: on some Android 16 devices (e.g. Motorola), `app_process` may fail with `NoClassDefFoundError` — update APK+loader nightly and check `logcat | grep termux-x11`.

```sh
/data/linux/fix-pacman-mirrors.sh
ARTIX_USER=<user> /data/linux/run-setup-xfce.sh
```

Day to day:

```sh
/data/linux/x11-start.sh    # Termux:X11 CmdEntryPoint + XFCE
/data/linux/x11-stop.sh     # stop X11/XFCE session only
```

Display: **Termux:X11** app on the device.  
Config: `/etc/artix-x11.conf` (`X11_USER`, `X11_DISPLAY`, `XFCE_USE_ZINK`).  
Session: `dinitctl restart xfce-x11` (with X0 already active).

Enable GPU on the desktop (recommended):

```sh
/data/linux/gpu-desktop.sh
```

Manual reference (after `artix-gpu-zink.ok`):

```sh
#   XFCE_USE_ZINK=1  in /etc/artix-x11.conf
# then:
dinitctl restart xfce-x11
# revert: /data/linux/gpu-desktop.sh cpu
```

### MediaTek mt6878 GPU (Moto G86 / Mali-G615 MC2)

**Scope:** the hybris setup (`run-setup-gpu-hybris`, `gpu-desktop`, overlays in `deps/`) is **specific** to the **mt6878** platform + **Mali-G615 MC2** GPU. Hardcoded paths: `/vendor/lib64/egl/mt6878/`, `/vendor/lib64/hw/mt6878/`, etc. Other MediaTek/Mali SoCs are **not** supported without changing the setup.

Architecture (**GLES-first**):

```text
mali_kbase → /dev/mali0 → /opt/android-mali (libGLES_mali.so)
                         → libhybris (/opt/libhybris)
                         → gpu-egl-run
```

Separate display: `mediatek-drm` → `/dev/dri/card0` (do not confuse with Mali KBase).

**There is no** `/dev/dri/renderD128` on this device — do **not** create it artificially; do **not** install Panfrost.

`libGLES_mali.so` / `vulkan.mali.so` are **Android/Bionic**. Isolated runtime under `/opt/android-mali` (selective copy). Mounts `/mnt/system|vendor|apex` are for extraction only.

**Offline deps (runtime-only):** `deps/` ships `mesa25-android-mali-*.tar.zst` + `libhybris-opt-arm64.tar.zst` + `libc-hybris.so` (+ optional `sysvk-opt-arm64.tar.zst`). `deploy`/`prepare` install them under `/data/linux/deps/`; `run-setup-xfce` / `run-setup-gpu-hybris` copy them into the chroot. **No makepkg/base-devel** on the device — libhybris and Mesa are prebuilt. `android-vulkan-bridge.tar.gz` is legacy and unused in the current flow.

```sh
/data/linux/linux-start.sh
/data/linux/run-setup-gpu-hybris.sh  # GLES + /opt; Vulkan after gles.ok
/data/linux/gpu-check.sh             # early PASS = GLES Mali

# if pacman is broken: wipe + bootstrap (no lib patches)
# YES=1 /data/linux/wipe-chroot.sh && /data/linux/bootstrap.sh
```

Markers:

| File | Meaning |
|------|---------|
| `/etc/artix-gpu-gles.ok` | GLES/EGL Mali working |
| `/etc/artix-gpu-hybris.ok` | GLES + Vulkan + WSI |
| `/etc/artix-gpu-zink.ok` | Zink (OpenGL→Vulkan Mali) validated |
| `/etc/artix-mesa25.ok` | Mesa 25.1.2 overlay in `/opt/android-mali` |
| `/etc/artix-libhybris.ok` | libhybris-opt overlay in `/opt/libhybris` |
| `/etc/artix-sysvk.ok` | sysvk-opt overlay (Vulkan) |

```sh
gpu-egl-run /tmp/mali-egl-test     # GLES
DISPLAY=:0 gpu-egl-run …           # controlled X11 (not inside startxfce4)
DISPLAY=:0 gpu-vulkan-run vkcube   # after hybris.ok; vulkaninfo last
```

**Bootstrap / SETUP_FULL model:**

| Layer | Driver |
|-------|--------|
| XFCE desktop (default) | software (`LIBGL_ALWAYS_SOFTWARE` / softpipe) |
| XFCE desktop (`XFCE_USE_ZINK=1` + `artix-gpu-zink.ok`) | Zink → Vulkan Mali (`zink-run startxfce4`) |
| GLES apps | `gpu-egl-run` → Mali |
| Vulkan apps | `gpu-vulkan-run` → Mali (after Phase F) |
| OpenGL/Zink apps | `zink-run` / `gpu-run` |

`STRICT=1` treats **GPU OK** with `artix-gpu-gles.ok` (GLES Mali). Vulkan/Zink are not required for the early gate.

`setup-gpu-mediatek.sh` is **LEGACY** — do not use it in bootstrap.

SELinux blocking GPU:

```sh
dmesg | grep -iE 'avc|mali|gpu'
```

---

## Day-to-day commands

| I want to… | Command |
|------------|---------|
| Fresh environment | `/data/linux/bootstrap.sh` |
| Check status | `/data/linux/linux-status.sh` (includes GPU OK + driver) |
| Strict gate | `STRICT=1 REQUIRE_X11=1 /data/linux/linux-status.sh` |
| Start | `/data/linux/linux-start.sh` |
| Stop | `/data/linux/linux-stop.sh` |
| Wipe chroot + project scripts | `YES=1 /data/linux/wipe-chroot.sh` (deletes `/data/linux/*` and `99-linux.sh`; Android untouched) |
| Shell (root) | `/data/linux/linux-shell.sh` |
| Shell (user) | `/data/linux/linux-shell.sh name` |
| Create user | `/data/linux/artix-user.sh create name password` |
| Create user during setup | `CREATE_USER=1 ARTIX_USER=name ARTIX_PASS='password' /data/linux/run-setup.sh` |
| Set password | `/data/linux/artix-user.sh passwd name password` |
| Grant sudo | `/data/linux/artix-user.sh sudo name` |
| Remove user | `/data/linux/artix-user.sh remove name` |
| ARMtix mirrors | `/data/linux/fix-pacman-mirrors.sh` |
| ALARM repo | `/data/linux/enable-archlinuxarm.sh` |
| XFCE/X11 setup | `ARTIX_USER=<user> /data/linux/run-setup-xfce.sh` |
| Start Termux:X11 + XFCE | `/data/linux/x11-start.sh` |
| GPU desktop (Zink) | `/data/linux/gpu-desktop.sh` |
| CPU desktop (softGL) | `/data/linux/gpu-desktop.sh cpu` |
| Stop X11/XFCE | `/data/linux/gpu-desktop.sh stop` or `x11-stop.sh` |
| MTK GPU setup (**LEGACY** — do not use) | `/data/linux/run-setup-gpu-mediatek.sh` |
| Hybris GPU setup (GLES-first) | `/data/linux/run-setup-gpu-hybris.sh` |
| GPU check | `/data/linux/gpu-check.sh` / `gpu-desktop.sh status` |
| GLES Mali | `gpu-egl-run /tmp/mali-egl-test` |
| Vulkan Mali (X11) | `DISPLAY=:0 gpu-vulkan-run vkcube` |
| Log | `cat /data/linux/boot.log` |
| SSH | `ssh -p 2222 user@<ip>` |
| Desktop | Termux:X11 app (DISPLAY `:0`) |

---

## Troubleshooting

### Scripts: `unexpected do` / `not found`

Windows CRLF. On the device:

```sh
CR=$(printf '\r')
for f in /data/linux/*.sh; do tr -d "$CR" < "$f" > "$f.n" && mv "$f.n" "$f"; done
```

Never use `sed 's/\r//'`: on Android BusyBox it deletes the **letter** `r`  
(`Never`→`Neve`, `run`→`un`).

On the PC, `deploy.ps1` already forces LF.

---

### `unshare` dies / `[FAILED] boot` / udev / modules / fsck

dinit tries real-machine early-boot. Inside an Android chroot that fails and init exits.

```sh
/data/linux/linux-stop.sh
rmdir /data/linux/run/start.lock 2>/dev/null
# refresh scripts (prepare) then:
/data/linux/fix-dinit-chroot.sh
/data/linux/linux-start.sh
/data/linux/linux-status.sh
```

The fix stubs udev/modules/fsck/cgroups/getty/… to `/bin/true`.

---

### `libgcc_s.so.1` / `libstdc++.so.6` — shared library not found

On current Arch/ARMtix, `gcc-libs` is a **meta** package; the libs come from `libgcc` + `libstdc++`.  
If you only run `pacman -S gcc-libs`, the meta may remove old `.so` files without installing `libgcc`.

**Repair without wipe** (Android host / busybox — uses pacman cache `.pkg.tar.xz` or Artix tarball):

```sh
su -c /data/linux/repair-libgcc.sh
/data/linux/run-setup-gpu-hybris.sh
```

Typical cause: `pacman -Sy gcc-libs` (meta) removed `/usr/lib/libgcc_s.so.1` without installing the `libgcc` package. Repair extracts `libgcc-*.pkg.tar.xz` from the cache in `/var/cache/pacman/pkg/`.

GPU setup installs `libgcc libstdc++ gcc-libs` in one transaction and uses `pacman -Sy --needed` (not `-Syu`) + `IgnorePkg` for kernels/mkinitcpio.

---

### `unshare(0x20020000): Invalid argument`

Kernel without PID namespace. Expected.

Start falls back to mount-only.  
`linux-status.sh` may show `unshare -m -p: FAIL` while still ALIVE.

---

### `nsenter: can't open .../ns/pid`

Old script. Run `prepare.sh` again (current version uses `-m` only).

---

### Mount not RW / loop `Invalid argument`

1. `artix_chroot_loop` module + reboot  
2. `.img` under `/data/linux/` (not `/sdcard`)  
3. Status shows `RW: ok`, without `nosuid`/`nodev`

```sh
dmesg | grep -iE 'avc|ext4|loop'
/data/linux/linux-status.sh
```

---

### pacman: Landlock / sandbox / CheckSpace / kernel

In `[options]` (applied by `setup-artix` / `fix-pacman-sandbox`):

```
DisableSandbox
# CheckSpace
IgnorePkg = linux-aarch64 linux-aarch64-lts linux-aarch64-headers linux-firmware mkinitcpio mkinitcpio-busybox
```

No `DownloadUser` (`alpm` fails in Android chroot; do not force `root` — remove the line).  
`CheckSpace` fails on `/data` due to permissions.  
`IgnorePkg` avoids updating PC kernel/firmware/mkinitcpio (the chroot shares the phone kernel).  
GPU setup uses `pacman -Sy --needed` (not `-Syu`) and installs `libgcc` + `libstdc++` (not only the `gcc-libs` meta).

```sh
/data/linux/fix-pacman-sandbox.sh
```

---

### pacman: 404 / TLS / dead mirrors

Mirrors were Artix x86. ARMtix:

```
https://armtix.artixlinux.org/repos/$repo/os/$arch
https://repo.armtixlinux.org/$repo/os/$arch
```

```sh
/data/linux/fix-pacman-mirrors.sh
sudo pacman -Syy
```

---

### Invalid `SigLevel = Neve`

`sed \r` bug (deleted the `r` from Never).

```sh
sed -i 's/SigLevel = Neve$/SigLevel = Never/g' /etc/pacman.conf
/data/linux/fix-pacman-mirrors.sh
```

---

### `direnv` not found

Not in ARMtix. Available in ALARM `[extra]`.

```sh
/data/linux/enable-archlinuxarm.sh
sudo pacman -S direnv
```

```sh
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
```

Do not use `artix-archlinux-support` (Arch x86).

---

### Password does not work (SSH / login)

```sh
/data/linux/artix-user.sh passwd <user> 'password'
```

SSH on port **2222**.  
`linux-shell.sh <user>` does not ask for a password (you are root on Android).

---

### `not in the sudoers file`

```sh
/data/linux/artix-user.sh sudo username
```

Or create with `ARTIX_SUDO=1`. Log out and back in.

---

### `cd root` → permission denied

Expected. `/root` is root's home.

```sh
cd ~
# /home/<user>
```

---

### dbus / elogind / logind failed (cgroup)

Cause: `run-in-cgroup = dbus.sv` — the Android/chroot cgroup cannot create it.

Fix (already in `run-setup.sh`; reapply if pacman overwrites):

```sh
/data/linux/run-setup.sh
# or just the fixes:
/data/linux/fix-dbus-chroot.sh
dinitctl status dbus elogind logind
```

Should be STARTED with `/run/dbus/system_bus_socket` present.

---

### dinit test: cgroup / boot / socket

| Error | Fix |
|-------|-----|
| `In multiple cgroups` | `--user --container --cgroup-path /sys/fs/cgroup` |
| `boot: could not find` | create a `boot` service in the services-dir |
| exit 2 / empty state | no `>` in `command=`; use a `.sh` script |
| socket not created | flags above + `boot` + check the log |

```sh
~/test-dinit-network.sh
```

**System** dinit already uses `/run/dinitctl`.  
Tests use a different `--socket-path`.

---

### XFCE / Termux:X11 will not start

```sh
pm path com.termux.x11          # must list the APK
/data/linux/x11-start.sh
dinitctl status xfce-x11 dbus
cat /var/log/dinit/xfce-x11.log
ls -l /tmp/.X11-unix/           # inside chroot: X0
cat /etc/artix-x11.conf
```

Typical causes:

| Symptom | Cause / fix |
|---------|-------------|
| `falta a app Termux:X11` | Install APK `com.termux.x11` (F-Droid/GitHub); base Termux is not enough |
| `socket X11 nao apareceu` | Open the Termux:X11 app; confirm `setenforce 0`; TMPDIR in the mount ns |
| `Cannot open display :0` | CmdEntryPoint outside the mount ns — use `/data/linux/x11-start.sh` |
| xfce-x11 STOPPED | `/data/linux/x11-start.sh` (X0 must exist before the session) |
| black screen (app open) | xfwm4 compositor + softGL — `x11-stop` + `x11-start` (force `use_compositing=false`) |

Black screen with socket/session OK:

```sh
/data/linux/x11-stop.sh
# optional: reapply prefs
ARTIX_USER=<user> /data/linux/run-setup-xfce.sh
/data/linux/x11-start.sh
```

Reinstall setup: `ARTIX_USER=<user> /data/linux/run-setup-xfce.sh`  
Then: `/data/linux/x11-start.sh` → display in the Termux:X11 app.

---

### GPU: llvmpipe / softpipe / no Mali / invalid ELF header / free(): invalid size

llvmpipe/softpipe on the **XFCE desktop** is the default (`XFCE_USE_ZINK=0`) — stable session with Mesa **25.1.2** under `/opt/android-mali`.  
With `XFCE_USE_ZINK=1` + `/etc/artix-gpu-zink.ok`, the desktop starts via `zink-run` (OpenGL→Vulkan Mali). Without marker/zink-run, the session **falls back automatically** to softGL.

Direct Mali GPU: `gpu-egl-run` + `/etc/artix-gpu-gles.ok` / `gpu-check.sh` PASS.

`invalid ELF header` / `Found no drivers` = Bionic ICD on glibc without hybris — use `run-setup-gpu-hybris.sh` (not legacy mediatek).

`free(): invalid size` / `invalid pointer` on Mesa ≥26 (Artix pacman) — known with softGL and Zink+hybris. Bootstrap/`setup-xfce` installs the `mesa25-android-mali` overlay and removes mesa≥26. Zink on the desktop is opt-in (`XFCE_USE_ZINK`).

`GLIBC_2.43 not found` (e.g. `liblcms2` / `xfce4-session`): bootstrap/`setup-artix` and `setup-xfce` run `pacman -Sy glibc` early. Without wipe, on a live chroot:

```sh
SHELL_CMD='pacman -Sy --noconfirm glibc' /data/linux/linux-shell.sh
/data/linux/x11-stop.sh
/data/linux/x11-start.sh
```

`ngtcp2_…` / broken pacman = inconsistent rootfs — **wipe + bootstrap** (no lib patches):

```sh
YES=1 /data/linux/wipe-chroot.sh
/data/linux/bootstrap.sh
/data/linux/run-setup-gpu-hybris.sh
```

```sh
/data/linux/linux-stop.sh && /data/linux/linux-start.sh
/data/linux/run-setup-gpu-hybris.sh
/data/linux/gpu-check.sh
gpu-egl-run /tmp/mali-egl-test
DISPLAY=:0 gpu-vulkan-run vkcube   # after artix-gpu-hybris.ok
```

---

### Dead container / stale pidfile

```sh
/data/linux/linux-stop.sh
/data/linux/linux-start.sh
cat /data/linux/boot.log
```

---

## Paths

| Path | What |
|------|------|
| `/data/linux/rootfs.img` | Linux disk (8G sparse) |
| `/data/linux/mnt` | mount point |
| `/data/linux/boot.log` | boot log |
| `/data/linux/run/init.pid` | container PID |
| `/home/<user>` | user home (not `/root`) |
| `/etc/dinit.d/` + `boot.d/` | system services |
| `/etc/artix-x11.conf` | Termux:X11 user/display |
| `/etc/artix-gpu.conf` | Vulkan ICD / vendor paths |
| `/mnt/vendor` `/mnt/system` | RO Android binds (GPU ICD) |
| `/etc/pacman.d/mirrorlist` | ARMtix mirrors |
| `/etc/pacman.d/mirrorlist-archarm` | Arch Linux ARM mirrors |
