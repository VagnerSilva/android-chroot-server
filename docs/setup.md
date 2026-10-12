# Setup and daily operation

This guide covers deploying the scripts, creating the Artix rootfs, and operating the container. GPU and Termux:X11 setup is in [GPU and desktop](gpu.md); fixes for common failures are in [Troubleshooting](troubleshooting.md).

## Requirements

- Android device with KernelSU and ADB access.
- The `ksu-module` installed through KernelSU Manager, followed by a device reboot (loop-device SELinux policy).
- Termux:X11 (`com.termux.x11`) for the desktop. Termux alone does not provide the X server.
- The `armtix-dinit-20260921.tar.xz` rootfs archive in Termux home or `/data/local/tmp`; setup downloads it if absent.
- For the supported accelerated GPU path, MediaTek mt6878 with Mali-G615 MC2. Other devices can use the software desktop.

## Deploy and bootstrap

On the PC, from the repository:

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

Install `ksu-module` in KernelSU Manager and reboot. Then bootstrap the environment:

```sh
su
/data/linux/bootstrap.sh
```

Bootstrap stops the container for a clean start, installs the rootfs if needed, starts dinit, configures sshd, dbus/elogind and XFCE, and installs container autostart. It skips GPU hybris. On a TTY it asks whether to create a user (default yes); without a TTY, provide the credentials explicitly:

```sh
CREATE_USER=1 ARTIX_USER=<user> ARTIX_PASS='password' /data/linux/bootstrap.sh
```

If that user's home already exists, rerun `/data/linux/bootstrap.sh` without the creation variables. For a broken rootfs, there is no in-place library recovery; wiping is destructive to `/data/linux` and requires explicit confirmation:

```sh
YES=1 /data/linux/wipe-chroot.sh && /data/linux/bootstrap.sh
```

Rootfs archive lookup order is the command argument or `ARMTIX_TAR`, Termux home, `/data/local/tmp`, then the ARMtix download URL. If extracting `.xz` fails in Termux, install `xz-utils` and run `xz -dk` on the archive.

## Advanced setup

The individual steps are available when bootstrap is not appropriate:

```sh
/data/linux/install-rootfs.sh
/data/linux/linux-start.sh
/data/linux/run-setup.sh
SETUP_FULL=1 SKIP_GPU=1 /data/linux/run-setup.sh
/data/linux/x11-start.sh
STRICT=1 REQUIRE_X11=1 REQUIRE_GPU=0 /data/linux/linux-status.sh
```

`run-setup.sh` without `SETUP_FULL=1` configures core services. `SETUP_FULL=1 SKIP_GPU=1` adds XFCE without GPU; omitting `SKIP_GPU` requests GPU setup as well. On a TTY, setup can prompt for a user. Non-interactive full setup requires `ARTIX_USER` and `ARTIX_PASS`. If sshd fails, setup stops at that step.

## Start at boot

`prepare.sh` and `bootstrap.sh` install `/data/adb/service.d/99-linux.sh`. It starts the container after boot; XFCE and Termux:X11 remain on demand. Reinstall or update the boot service with:

```sh
/data/linux/install-autostart.sh
```

To skip autostart installation while preparing scripts:

```sh
SKIP_AUTOSTART=1 sh /data/local/tmp/rootfs/host/prepare.sh
```

## Daily commands

| Task | Command |
|---|---|
| Start / stop / status | `/data/linux/linux-start.sh`, `/data/linux/linux-stop.sh`, `/data/linux/linux-status.sh` |
| Strict status gate | `STRICT=1 REQUIRE_X11=1 /data/linux/linux-status.sh` |
| Root shell / user shell | `/data/linux/linux-shell.sh` / `/data/linux/linux-shell.sh <user>` |
| Create, change, grant sudo, or remove a user | `/data/linux/artix-user.sh create <user> 'password'`; `passwd <user> 'newpass'`; `sudo <user>`; `remove <user>` |
| Backup rootfs | `/data/linux/linux-backup.sh` (container stopped; refuses to overwrite an existing backup) |
| Start/stop desktop | `/data/linux/gpu-desktop.sh` / `/data/linux/gpu-desktop.sh stop` |
| Boot log | `cat /data/linux/boot.log` |
| SSH | `ssh -p 2222 <user>@<device-ip>` |

Commands run on the Android host as root unless noted. `linux-shell.sh <user>` enters that user's home without asking for a password. The root account's home is `/root`; regular users live under `/home/<user>`.

## Pacman and dinit

With the container running, repair ARMtix mirrors or the Android-incompatible pacman sandbox from the Android host:

```sh
/data/linux/fix-pacman-mirrors.sh
/data/linux/fix-pacman-sandbox.sh
```

The sandbox fix disables Landlock sandboxing in the chroot and installs a hook to reapply the setting after pacman upgrades. For packages absent from ARMtix, `enable-archlinuxarm.sh` enables the Arch Linux ARM repository; do not use Arch x86 packages.

Install a system dinit service and inspect it with:

```sh
/data/linux/install-dinit-services.sh dinit-test
dinitctl status dinit-test
```

In a dinit service `command =` value, do not use `>`; call a script file instead. The system dinit control socket already runs at `/run/dinitctl`. The isolated user-network test is `~/test-dinit-network.sh` and requires a `boot` service plus `--user --container --cgroup-path /sys/fs/cgroup`.

## Backup and restore

The default backup is `/data/linux/rootfs.img.bak`. Stop the container first. The backup command checks that the image is unmounted, verifies free space, and compares the completed copy; it never overwrites an existing backup.

For an explicit restore, preserve the current image separately and confirm before replacement:

```sh
/data/linux/linux-stop.sh
/data/linux/linux-backup.sh /data/linux/rootfs.img.pre-restore
printf 'Type RESTORE to replace rootfs.img: '
read -r answer
[ "$answer" = RESTORE ] || exit 1
test ! -e /data/linux/rootfs.img.restore.tmp || exit 1
cp -p /data/linux/rootfs.img.bak /data/linux/rootfs.img.restore.tmp
cmp -s /data/linux/rootfs.img.bak /data/linux/rootfs.img.restore.tmp || exit 1
mv /data/linux/rootfs.img.restore.tmp /data/linux/rootfs.img
```

For Mesa 26 evaluation, use only the isolated-copy procedure in [`KNOWN_ISSUES.md`](../KNOWN_ISSUES.md); do not install the candidate into the production rootfs.
