# Troubleshooting

Run device-side commands from the Android host as root unless a step says otherwise. For GPU-specific renderer limits, see [GPU and desktop](gpu.md).

| Symptom | Likely cause | Action |
|---|---|---|
| `unexpected do` or script `not found` | Windows CRLF line endings | `deploy.ps1` forces LF. On-device cleanup is below; never use `sed 's/\\r//'` with Android BusyBox because it can delete the letter `r`. |
| `unshare` fails, dinit `[FAILED] boot`, udev/modules/fsck errors | Real-machine early boot is not available inside this Android chroot | Run `linux-stop.sh`, refresh scripts with `prepare.sh`, run `fix-dinit-chroot.sh`, then start and check status. The fix stubs unsupported early-boot services. |
| `libgcc_s.so.1` or `libstdc++.so.6` missing | Incomplete GCC runtime after pacman transaction | Run `su -c /data/linux/repair-libgcc.sh`, then rerun the needed setup. |
| `unshare(...): Invalid argument` | Kernel has no PID namespace support | Expected on some kernels; start falls back to mount-only. Status may report PID namespace failure while the container is alive. |
| `nsenter: can't open .../ns/pid` | Old deployed scripts | Rerun `prepare.sh`; current start path supports mount-only namespace mode. |
| Image mount is not RW or loop reports `Invalid argument` | Loop SELinux module/reboot, image on unsupported storage, or mount flags | Install `ksu-module` and reboot; keep image under `/data/linux`, then inspect status and `dmesg | grep -iE 'avc|ext4|loop'`. |
| Pacman hangs at 100% / Landlock | Android kernel and pacman sandbox mismatch | Run `fix-pacman-sandbox.sh` on the Android host with the container running. It disables the sandbox in the chroot and installs a reapply hook. |
| Pacman 404, TLS, or dead mirrors | Wrong or stale mirror list | Run `fix-pacman-mirrors.sh`, then `sudo pacman -Syy` inside the chroot. |
| `SigLevel = Neve` | Historical CRLF cleanup corrupted `Never` | Correct the line to `SigLevel = Never`, then rerun `fix-pacman-mirrors.sh`; avoid the unsafe BusyBox `sed` expression noted above. |
| `direnv` package not found | Package is not in ARMtix | Enable Arch Linux ARM with `enable-archlinuxarm.sh`; install ARM packages only, not Arch x86 packages. |
| SSH/login password rejected or sudo denied | User credential/group configuration | Use `artix-user.sh passwd <user> 'password'` or `artix-user.sh sudo <user>`, then reconnect. SSH listens on port 2222. |
| `cd root` permission denied | A regular user tried to enter `/root` | Expected; use `cd ~` for `/home/<user>`. |
| dbus/elogind/logind fails with cgroup error | Android cgroup cannot use `run-in-cgroup` | Rerun `run-setup.sh` or `fix-dbus-chroot.sh`, then inspect `dinitctl status dbus elogind logind` and `/run/dbus/system_bus_socket`. |
| User dinit test: cgroup, missing boot, or empty state | Test service setup/arguments | Use `--user --container --cgroup-path /sys/fs/cgroup`, define a `boot` service, and avoid `>` in `command =`; call a script instead. |
| XFCE/Termux:X11 will not start | App/loader missing, X0 absent, or session config | Confirm `pm path com.termux.x11`, open the app, run `x11-start.sh`, inspect `dinitctl status xfce-x11 dbus`, `/var/log/dinit/xfce-x11.log`, and `/etc/artix-x11.conf`. |
| Container appears dead or pidfile is stale | Previous start/stop did not finish cleanly | Run `linux-stop.sh`, then `linux-start.sh`; inspect `/data/linux/boot.log`. |

For CRLF cleanup on the device, this preserves the contents except CR bytes and replaces each file atomically:

```sh
CR=$(printf '\r')
for f in /data/linux/*.sh; do tr -d "$CR" < "$f" > "$f.n" && mv "$f.n" "$f"; done
```

For X11-specific symptoms such as a missing socket, black screen, or `Cannot open display :0`, use the [GPU and desktop guide](gpu.md). For Mesa 26 evidence and the production decision, see [`KNOWN_ISSUES.md`](../KNOWN_ISSUES.md).
