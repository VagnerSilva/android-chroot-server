# GPU and desktop

The desktop runs inside the Artix chroot through Termux:X11 on display `:0`; it does not use TigerVNC. The default XFCE renderer is software (softpipe). The accelerated hybris/Zink stack is supported only on MediaTek mt6878 with Mali-G615 MC2 (for example, Moto G86); other SoCs require porting. See [legacy GPU flow](gpu-legacy.md) for scripts that are retained but unsupported.

## Termux:X11 and XFCE

Install the Android app `com.termux.x11` from F-Droid or the Termux:X11 GitHub nightly releases. Base Termux (`com.termux`) is not enough. On Android 14+, the companion `loader.apk` is staged under `/data/linux/termux-x11/`; `prepare.sh` and `x11-start.sh` can install it. The Termux package alternative is `pkg i x11-repo && pkg i termux-x11-nightly`.

With a configured user and a running container:

```sh
ARTIX_USER=<user> /data/linux/run-setup-xfce.sh
/data/linux/x11-start.sh
/data/linux/x11-stop.sh
```

The first command can be rerun to apply XFCE preferences without wiping the rootfs. The X11 configuration is `/etc/artix-x11.conf` (`X11_USER`, `X11_DISPLAY`, `XFCE_USE_ZINK`). The XFCE dinit service expects X0 to exist first. `gpu-desktop.sh` offers a day-to-day entry point:

```sh
/data/linux/gpu-desktop.sh          # setup if needed, then desktop
/data/linux/gpu-desktop.sh status   # markers and configuration
/data/linux/gpu-desktop.sh stop     # stop X11/XFCE
/data/linux/gpu-desktop.sh cpu      # software-rendered desktop
```

The desktop does not start automatically at boot. Container autostart is separate; launch the desktop when needed.

## Supported Mali setup

The setup is GLES-first and uses Android/Bionic vendor libraries in an isolated runtime. It is not a generic Mali/Panfrost setup. Do not create `/dev/dri/renderD128`; this device exposes the Mali KBase node `/dev/mali0`, while `mediatek-drm` provides the separate display node `/dev/dri/card0`.

Offline runtime archives in `deps/` are installed under `/data/linux/deps/` by deployment and copied into the chroot by setup scripts. Mesa and libhybris are prebuilt; do not build them on the device. `android-vulkan-bridge.tar.gz` is legacy and unused in the supported flow.

With the container running, perform setup and inspect the early GLES gate:

```sh
/data/linux/run-setup-gpu-hybris.sh
/data/linux/gpu-check.sh
```

The convenient desktop helper performs the setup when markers are absent. For direct checks:

```sh
gpu-egl-run /tmp/mali-egl-test
DISPLAY=:0 gpu-egl-run <x11-test>
DISPLAY=:0 gpu-vulkan-run vkcube
```

Run `vulkaninfo` last when diagnosing the driver. The status gate `STRICT=1` treats the GLES marker as GPU success; Vulkan and Zink are later, optional capabilities.

## Markers and renderer selection

| Marker | Meaning |
|---|---|
| `/etc/artix-gpu-gles.ok` | Mali GLES/EGL works |
| `/etc/artix-gpu-hybris.ok` | GLES, Vulkan and WSI setup completed |
| `/etc/artix-gpu-zink.ok` | Zink over Mali Vulkan validated |
| `/etc/artix-mesa25.ok` | Mesa 25.1.2 overlay installed in `/opt/android-mali` |
| `/etc/artix-libhybris.ok` | libhybris overlay installed in `/opt/libhybris` |
| `/etc/artix-sysvk.ok` | sysvk overlay installed |

| Workload | Entry point |
|---|---|
| XFCE default | softpipe software rendering |
| XFCE accelerated (only with Zink marker/config) | `XFCE_USE_ZINK=1`, then `zink-run startxfce4` |
| GLES app | `gpu-egl-run` |
| Vulkan app | `gpu-vulkan-run` after hybris setup |
| OpenGL/Zink app | `zink-run` or `gpu-run` |

`gpu-desktop.sh` selects and configures the supported desktop path. Do not set `XFCE_USE_ZINK=1` without `/etc/artix-gpu-zink.ok`; the desktop helper's `cpu` mode returns to software rendering.

## Diagnostics and known limits

If Android SELinux blocks GPU access, inspect `dmesg | grep -iE 'avc|mali|gpu'`. On some Android 16 devices, Termux:X11's `app_process` may fail with `NoClassDefFoundError`; update both the app and loader from nightly and inspect `logcat | grep termux-x11`.

The canonical GPU version status, measurements and promotion criteria are maintained in [`GPU_KNOWLEDGE_BASE.md`](../GPU_KNOWLEDGE_BASE.md). See [`KNOWN_ISSUES.md`](../KNOWN_ISSUES.md) for the detailed historical evaluation. Do not force a GL version or fabricate Vulkan capability bits.

For symptoms such as missing Mali renderer, invalid ELF, black screen, or X11 startup failure, see [Troubleshooting](troubleshooting.md).
