# Artix + dinit on Android (KernelSU)

A real Artix chroot on an ext4 image, managed by KernelSU scripts. No proot. The container can start at boot; the XFCE desktop runs on demand through Termux:X11.

GPU hybris/Zink acceleration is supported only on MediaTek mt6878 with Mali-G615 MC2. Other devices should use the software-rendered desktop unless their GPU stack is independently ported.

## Requirements

- Android device with KernelSU, ADB, and the project `ksu-module` installed (reboot after module installation).
- Termux:X11 Android app (`com.termux.x11`); Termux alone is not enough for the desktop.
- Rootfs archive `armtix-dinit-20260921.tar.xz` in Termux home or `/data/local/tmp`; setup downloads it when absent.

## Quick start

On the PC, deploy the scripts:

```powershell
cd host
.\deploy.ps1
```

On Android, prepare and bootstrap:

```sh
adb shell
su
sh /data/local/tmp/rootfs/host/prepare.sh
/data/linux/bootstrap.sh
```

Without a TTY, pass credentials explicitly: `CREATE_USER=1 ARTIX_USER=<user> ARTIX_PASS='password' /data/linux/bootstrap.sh`. Bootstrap configures core services and XFCE but skips GPU hybris. See [Setup](docs/setup.md) for advanced steps, backup/restore, and daily commands.

## Guides

- [Setup and daily operation](docs/setup.md)
- [GPU and desktop](docs/gpu.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Legacy MediaTek GPU flow](docs/gpu-legacy.md)
- [Português: instalação e operação](docs/setup.pt.md)
- [Português: GPU e desktop](docs/gpu.pt.md)
- [Português: solução de problemas](docs/troubleshooting.pt.md)
- [Português: GPU legado](docs/gpu-legacy.pt.md)

## Main commands

| Task | Command |
|---|---|
| Start / stop / status | `/data/linux/linux-start.sh` / `linux-stop.sh` / `linux-status.sh` |
| Enter as root / user | `/data/linux/linux-shell.sh` / `linux-shell.sh <user>` |
| Start desktop | `/data/linux/gpu-desktop.sh` |
| Stop desktop | `/data/linux/gpu-desktop.sh stop` |
| Rootfs backup | `/data/linux/linux-backup.sh` |

Commands run on the Android host as root unless noted. The container autostarts after boot; XFCE and Termux:X11 do not. The accelerated GPU flow is hardware-specific. Mesa 25.1.2 remains the production version; see [known issues](KNOWN_ISSUES.md) before changing the Mesa 26 block.

## Project references

- [Known issues and validation evidence](KNOWN_ISSUES.md)
- [Changelog](CHANGELOG.md)
- [Implementation plan](sdd/plan.md)
