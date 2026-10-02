# Artix + dinit no Android (KernelSU)

Chroot real em imagem ext4. Sem proot. Desktop via **Termux:X11** (GPU).

O dinit sobe no boot via KernelSU. SSH fica dentro.
Serviços Hermes/OmniRoute: só templates dinit em `device/dinit.d/` até haver binários.

---

## O que precisas

- KernelSU + ADB
- Tarball: `~/armtix-dinit-20260124.tar.xz` (home do Termux)
- Módulo `ksu-module` (SELinux do loop)
- App **Termux:X11** (`com.termux.x11`) — F-Droid ou [GitHub nightly](https://github.com/termux/termux-x11/releases). O Termux base **não chega**.

---

## 1. Enviar scripts (PC)

```powershell
cd host
.\deploy.ps1
```

No dispositivo:

```sh
adb shell
su
sh /data/local/tmp/rootfs/host/prepare.sh
```

---

## 2. Módulo SELinux

Instala `ksu-module` no KernelSU Manager.

Reinicia o dispositivo. Sem isto o mount pode ficar sem RW.

---

## 3. Ambiente do zero (recomendado)

Um comando: faz **linux-stop** (estado limpo), instala rootfs (se preciso), sobe o container, aplica stubs dinit, arranca **sshd** como serviço dinit (porta 2222), depois **dbus/elogind**, cria utilizador, XFCE e Termux:X11. **GPU hybris fica de fora** (passo manual depois). No fim corre `linux-status` estrito sem exigir GPU.

```sh
su
/data/linux/bootstrap.sh
# terminal local ou adb com TTY: pergunta criar utilizador (default S)
```

Sem TTY (ex. `adb shell` + `su -c`):

```sh
CREATE_USER=1 ARTIX_USER=<user> ARTIX_PASS='senha' /data/linux/bootstrap.sh
# re-run com user ja em /home: /data/linux/bootstrap.sh basta
```

O bootstrap usa `SKIP_GPU=1` por defeito (nucleo + XFCE). GPU + desktop:

```sh
/data/linux/gpu-desktop.sh
```

Rootfs inconsistente (libs/pacman partidos): **não** há recovery de libs — `YES=1 /data/linux/wipe-chroot.sh && /data/linux/bootstrap.sh`.

Fonte padrão do tarball:

`/data/data/com.termux/files/home/armtix-dinit-20260124.tar.xz`

Se `.xz` falhar, no Termux: `pkg install xz-utils && xz -dk ~/armtix-dinit-….tar.xz`

Queres no status do bootstrap: `[ok]` sshd, dbus, elogind, dbus socket, X11 `:0`.  
GPU / Zink **não** fazem parte desta fase.

---

## 3b. GPU no ecrã (recomendado)

Um comando cobre setup (se falta) + Zink no XFCE + Termux:X11:

```sh
/data/linux/gpu-desktop.sh          # start
/data/linux/gpu-desktop.sh status  # markers + conf
/data/linux/gpu-desktop.sh stop    # para X11/XFCE
/data/linux/gpu-desktop.sh cpu     # desktop softGL (CPU)
```

- **1ª vez:** corre `run-setup-gpu-hybris` se não houver markers, põe `XFCE_USE_ZINK=1` quando existir `artix-gpu-zink.ok`, sobe o desktop.
- **Dias seguintes:** o mesmo `gpu-desktop.sh` (só sobe o ecrã; GPU já está no `rootfs.img`).
- **Boot automático:** só o container (`99-linux.sh`) — GPU/desktop **não** sobem sozinhos.

Setup avançado (sem helper): `/data/linux/run-setup-gpu-hybris.sh`.

---

## 4. Passo a passo (avançado)

```sh
/data/linux/install-rootfs.sh
/data/linux/linux-start.sh
/data/linux/run-setup.sh                      # so nucleo (sshd/dbus/elogind)
SETUP_FULL=1 SKIP_GPU=1 /data/linux/run-setup.sh  # nucleo + XFCE (sem GPU)
SETUP_FULL=1 /data/linux/run-setup.sh         # nucleo + GPU hybris + XFCE
/data/linux/x11-start.sh
STRICT=1 REQUIRE_X11=1 REQUIRE_GPU=0 /data/linux/linux-status.sh
```

O `run-setup.sh` reinicia o container após stubs dinit, arranca **sshd** como serviço dinit (porta 2222, passo 4) e só depois **dbus/elogind**. Se o SSH não subir, falha nesse passo. Em TTY (ou `/dev/tty`) pergunta se queres criar o utilizador; com `CREATE_USER=1` / `0` não pergunta. Com `SETUP_FULL=1` sem TTY exige `ARTIX_USER` + `ARTIX_PASS`.

---

## 5. Autostart

O `prepare.sh` (e o `bootstrap.sh` no fim) instalam automaticamente:

`/data/adb/service.d/99-linux.sh` → sobe o container apos boot (KernelSU late_start + watchdog).

```sh
# repor / actualizar
/data/linux/install-autostart.sh

# saltar na preparacao
SKIP_AUTOSTART=1 sh /data/local/tmp/rootfs/host/prepare.sh
```

XFCE/Termux:X11 **nao** sobe no boot — usa `/data/linux/gpu-desktop.sh` (ou `x11-start.sh`).  
Boot = container; GPU/desktop = sob demanda.

---

## Como usar correctamente

### Container

```sh
/data/linux/linux-start.sh
/data/linux/linux-status.sh
```

Entra pelos helpers (não faças chroot à mão):

```sh
/data/linux/linux-shell.sh            # root → /root
/data/linux/linux-shell.sh <user>     # user → /home/<user>
```

### Utilizadores

No `bootstrap` / `run-setup` (recomendado — pergunta s/N + nome/senha via TTY ou `/dev/tty`):

```sh
/data/linux/bootstrap.sh
# ou so nucleo:
/data/linux/run-setup.sh
# ou sem prompt:
CREATE_USER=1 ARTIX_USER=<user> ARTIX_PASS='senha' /data/linux/bootstrap.sh
```

Ou à mão:

```sh
ARTIX_SUDO=1 /data/linux/artix-user.sh create <user> 'senha'
/data/linux/artix-user.sh passwd <user> 'nova'
/data/linux/artix-user.sh sudo <user>
```

Home do user: `/home/<user>` (`cd ~`).

`/root` é só do root — `cd root` como utilizador normal falha (normal).

Senhas com especiais: aspas simples ou `passwd <user> -` (stdin).

### Pacman

```sh
/data/linux/fix-pacman-mirrors.sh
/data/linux/fix-pacman-sandbox.sh
sudo pacman -Syu
```

Pacotes Arch em falta (ex. direnv) — usa **Arch Linux ARM**, não Arch x86:

```sh
/data/linux/enable-archlinuxarm.sh
sudo pacman -S direnv
```

### Serviços dinit (sistema)

```
/etc/dinit.d/nome
/etc/dinit.d/boot.d/nome → ../nome
```

```sh
/data/linux/install-dinit-services.sh dinit-test
dinitctl status dinit-test
```

No `command =`: **não uses `>`**. Usa um script em ficheiro.

### dinit de teste (user)

O dinit do sistema já corre (`/run/dinitctl`).

Teste isolado:

```sh
~/test-dinit-network.sh
```

Precisa: `--user --container --cgroup-path /sys/fs/cgroup`, serviço `boot`, sem `>` no command.

### XFCE + Termux:X11 (GPU)

Desktop no chroot via **Termux:X11** (display `:0`). Sem TigerVNC.
Default: softGL (CPU). Opcional: `XFCE_USE_ZINK=1` em `/etc/artix-x11.conf` → desktop via **Zink→Vulkan Mali** (requer `/etc/artix-gpu-zink.ok`). Apps GPU avulsas: `gpu-vulkan-run` / `zink-run` / `gpu-run`.

**Pré-requisito:** app Android **Termux:X11** (`com.termux.x11`). O Termux base (`com.termux`) **não chega**.  
Instalar via F-Droid ou [releases GitHub](https://github.com/termux/termux-x11/releases) (`termux-x11-universal-debug.apk` da tag **nightly**).  
Companion `loader.apk` (Android 14+): o `prepare.sh` / `x11-start.sh` instala a partir de `/data/linux/termux-x11/`, ou em Termux `pkg i x11-repo && pkg i termux-x11-nightly`.  
Se faltar o APK, `/data/linux/x11-start.sh` aborta com instruções.  
Nota: em alguns Android 16 (ex. Motorola), `app_process` pode falhar com `NoClassDefFoundError` — actualizar APK+loader nightly e ver `logcat | grep termux-x11`.

```sh
/data/linux/fix-pacman-mirrors.sh
ARTIX_USER=<user> /data/linux/run-setup-xfce.sh
```

Dia a dia:

```sh
/data/linux/x11-start.sh    # Termux:X11 CmdEntryPoint + XFCE
/data/linux/x11-stop.sh     # para só a sessao X11/XFCE
```

Ecrã: app **Termux:X11** no dispositivo.  
Config: `/etc/artix-x11.conf` (`X11_USER`, `X11_DISPLAY`, `XFCE_USE_ZINK`).  
Sessao: `dinitctl restart xfce-x11` (com X0 já activo).

Ativar GPU no desktop (recomendado):

```sh
/data/linux/gpu-desktop.sh
```

Referencia manual (apos `artix-gpu-zink.ok`):

```sh
#   XFCE_USE_ZINK=1  em /etc/artix-x11.conf
# depois:
dinitctl restart xfce-x11
# reverter: /data/linux/gpu-desktop.sh cpu
```

### GPU MediaTek (Moto G86 / Mali-G615 MC2)

Arquitectura (**GLES-first**):

```text
mali_kbase → /dev/mali0 → /opt/android-mali (libGLES_mali.so)
                         → libhybris (/opt/libhybris)
                         → gpu-egl-run
```

Display separado: `mediatek-drm` → `/dev/dri/card0` (não confundir com Mali KBase).

**Não existe** `/dev/dri/renderD128` neste dispositivo — **não** criar artificialmente; **não** instalar Panfrost.

`libGLES_mali.so` / `vulkan.mali.so` são **Android/Bionic**. Runtime isolado em `/opt/android-mali` (cópia selectiva). Mounts `/mnt/system|vendor|apex` só para extracção.

**deps offline (runtime-only):** `deps/` traz `mesa25-android-mali-*.tar.zst` + `libhybris-opt-arm64.tar.zst` + `libc-hybris.so` (+ opcional `sysvk-opt-arm64.tar.zst`). O `deploy`/`prepare` instala-os em `/data/linux/deps/`; `run-setup-xfce` / `run-setup-gpu-hybris` copiam para o chroot. **Sem makepkg/base-devel** no device — libhybris e Mesa vêm pré-compilados. `android-vulkan-bridge.tar.gz` é legado e não é usado no fluxo actual.

```sh
/data/linux/linux-start.sh
/data/linux/run-setup-gpu-hybris.sh  # GLES + /opt; Vulkan apos gles.ok
/data/linux/gpu-check.sh             # PASS precoce = GLES Mali

# se pacman partido: wipe + bootstrap (sem patches de libs)
# YES=1 /data/linux/wipe-chroot.sh && /data/linux/bootstrap.sh
```

Marcadores:

| Ficheiro | Significado |
|----------|-------------|
| `/etc/artix-gpu-gles.ok` | GLES/EGL Mali funcional |
| `/etc/artix-gpu-hybris.ok` | GLES + Vulkan + WSI |
| `/etc/artix-gpu-zink.ok` | Zink (OpenGL→Vulkan Mali) validado |
| `/etc/artix-mesa25.ok` | Mesa 25.1.2 overlay em `/opt/android-mali` |
| `/etc/artix-libhybris.ok` | libhybris-opt overlay em `/opt/libhybris` |
| `/etc/artix-sysvk.ok` | sysvk-opt overlay (Vulkan) |

```sh
gpu-egl-run /tmp/mali-egl-test     # GLES
DISPLAY=:0 gpu-egl-run …           # X11 controlado (nao no startxfce4)
DISPLAY=:0 gpu-vulkan-run vkcube   # apos hybris.ok; vulkaninfo por ultimo
```

**Modelo bootstrap / SETUP_FULL:**

| Camada | Driver |
|--------|--------|
| Desktop XFCE (default) | software (`LIBGL_ALWAYS_SOFTWARE` / softpipe) |
| Desktop XFCE (`XFCE_USE_ZINK=1` + `artix-gpu-zink.ok`) | Zink → Vulkan Mali (`zink-run startxfce4`) |
| Apps GLES | `gpu-egl-run` → Mali |
| Apps Vulkan | `gpu-vulkan-run` → Mali (apos Fase F) |
| Apps OpenGL/Zink | `zink-run` / `gpu-run` |

`STRICT=1` considera **GPU OK** com `artix-gpu-gles.ok` (GLES Mali). Vulkan/Zink não são requisito do gate precoce.

`setup-gpu-mediatek.sh` é **LEGACY** — não usar no bootstrap.

SELinux a bloquear GPU:

```sh
dmesg | grep -iE 'avc|mali|gpu'
```

---

## Comandos do dia a dia

| Quero… | Comando |
|--------|---------|
| Ambiente do zero | `/data/linux/bootstrap.sh` |
| Ver estado | `/data/linux/linux-status.sh` (inclui GPU OK + driver) |
| Gate estrito | `STRICT=1 REQUIRE_X11=1 /data/linux/linux-status.sh` |
| Ligar | `/data/linux/linux-start.sh` |
| Desligar | `/data/linux/linux-stop.sh` |
| Wipe chroot + scripts do projecto | `YES=1 /data/linux/wipe-chroot.sh` (apaga `/data/linux/*` e `99-linux.sh`; Android intacto) |
| Shell (root) | `/data/linux/linux-shell.sh` |
| Shell (user) | `/data/linux/linux-shell.sh nome` |
| Criar user | `/data/linux/artix-user.sh create nome senha` |
| Criar user no setup | `CREATE_USER=1 ARTIX_USER=nome ARTIX_PASS='senha' /data/linux/run-setup.sh` |
| Senha user | `/data/linux/artix-user.sh passwd nome senha` |
| Dar sudo | `/data/linux/artix-user.sh sudo nome` |
| Remover user | `/data/linux/artix-user.sh remove nome` |
| Mirrors ARMtix | `/data/linux/fix-pacman-mirrors.sh` |
| Repo ALARM | `/data/linux/enable-archlinuxarm.sh` |
| Setup XFCE/X11 | `ARTIX_USER=<user> /data/linux/run-setup-xfce.sh` |
| Ligar Termux:X11 + XFCE | `/data/linux/x11-start.sh` |
| Desktop GPU (Zink) | `/data/linux/gpu-desktop.sh` |
| Desktop CPU (softGL) | `/data/linux/gpu-desktop.sh cpu` |
| Parar X11/XFCE | `/data/linux/gpu-desktop.sh stop` ou `x11-stop.sh` |
| Setup GPU MTK (**LEGACY** — nao usar) | `/data/linux/run-setup-gpu-mediatek.sh` |
| Setup GPU hybris (GLES-first) | `/data/linux/run-setup-gpu-hybris.sh` |
| Check GPU | `/data/linux/gpu-check.sh` / `gpu-desktop.sh status` |
| GLES Mali | `gpu-egl-run /tmp/mali-egl-test` |
| Vulkan Mali (X11) | `DISPLAY=:0 gpu-vulkan-run vkcube` |
| Log | `cat /data/linux/boot.log` |
| SSH | `ssh -p 2222 user@<ip>` |
| Desktop | app Termux:X11 (DISPLAY `:0`) |

---

## Troubleshooting

### Scripts: `unexpected do` / `not found`

CRLF do Windows. No device:

```sh
CR=$(printf '\r')
for f in /data/linux/*.sh; do tr -d "$CR" < "$f" > "$f.n" && mv "$f.n" "$f"; done
```

Nunca `sed 's/\r//'`: no BusyBox Android apaga a **letra** `r`  
(`Never`→`Neve`, `run`→`un`).

No PC o `deploy.ps1` já força LF.

---

### `unshare` morre / `[FAILED] boot` / udev / modules / fsck

O dinit tenta early-boot de máquina real. No chroot Android isso falha e o init sai.

```sh
/data/linux/linux-stop.sh
rmdir /data/linux/run/start.lock 2>/dev/null
# atualizar scripts (prepare) e:
/data/linux/fix-dinit-chroot.sh
/data/linux/linux-start.sh
/data/linux/linux-status.sh
```

O fix stubba udev/modules/fsck/cgroups/getty/… para `/bin/true`.

---

### `libgcc_s.so.1` / `libstdc++.so.6` — shared library not found

No Arch/ARMtix actual, `gcc-libs` é **meta**; as libs vêm de `libgcc` + `libstdc++`.  
Se só se fizer `pacman -S gcc-libs`, o meta pode remover as `.so` antigas sem instalar `libgcc`.

**Reparar sem wipe** (host Android / busybox — usa cache pacman `.pkg.tar.xz` ou tarball Artix):

```sh
su -c /data/linux/repair-libgcc.sh
/data/linux/run-setup-gpu-hybris.sh
```

Causa típica: `pacman -Sy gcc-libs` (meta) removeu `/usr/lib/libgcc_s.so.1` sem instalar o pacote `libgcc`. O repair extrai `libgcc-*.pkg.tar.xz` do cache em `/var/cache/pacman/pkg/`.

O setup GPU instala `libgcc libstdc++ gcc-libs` na mesma transação e usa `pacman -Sy --needed` (não `-Syu`) + `IgnorePkg` de kernels/mkinitcpio.

---

### `unshare(0x20020000): Invalid argument`

Kernel sem PID namespace. Normal.

O start faz fallback para mount-only.  
`linux-status.sh` pode mostrar `unshare -m -p: FALHA` e mesmo assim VIVO.

---

### `nsenter: can't open .../ns/pid`

Script antigo. Corre `prepare.sh` de novo (versão actual usa só `-m`).

---

### Mount sem RW / loop `Invalid argument`

1. Módulo `artix_chroot_loop` + reboot  
2. `.img` em `/data/linux/` (não `/sdcard`)  
3. Status com `RW: ok`, sem `nosuid`/`nodev`

```sh
dmesg | grep -iE 'avc|ext4|loop'
/data/linux/linux-status.sh
```

---

### pacman: Landlock / sandbox / CheckSpace / kernel

Em `[options]` (aplicado por `setup-artix` / `fix-pacman-sandbox`):

```
DisableSandbox
# CheckSpace
IgnorePkg = linux-aarch64 linux-aarch64-lts linux-aarch64-headers linux-firmware mkinitcpio mkinitcpio-busybox
```

Sem `DownloadUser` (o user `alpm` falha no chroot Android; não forçar `root` — remover a linha).  
`CheckSpace` falha em `/data` por permissões.  
`IgnorePkg` evita actualizar kernel/firmware/mkinitcpio de PC (o chroot partilha o kernel do telefone).  
O setup GPU usa `pacman -Sy --needed` (não `-Syu`) e instala `libgcc` + `libstdc++` (não só o meta `gcc-libs`).

```sh
/data/linux/fix-pacman-sandbox.sh
```

---

### pacman: 404 / TLS / mirrors mortos

Mirrors eram Artix x86. ARMtix:

```
https://armtix.artixlinux.org/repos/$repo/os/$arch
https://repo.armtixlinux.org/$repo/os/$arch
```

```sh
/data/linux/fix-pacman-mirrors.sh
sudo pacman -Syy
```

---

### `SigLevel = Neve` inválido

Bug do `sed \r` (apagou o `r` de Never).

```sh
sed -i 's/SigLevel = Neve$/SigLevel = Never/g' /etc/pacman.conf
/data/linux/fix-pacman-mirrors.sh
```

---

### `direnv` not found

Não está no ARMtix. Está no ALARM `[extra]`.

```sh
/data/linux/enable-archlinuxarm.sh
sudo pacman -S direnv
```

```sh
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
```

Não uses `artix-archlinux-support` (Arch x86).

---

### Senha não funciona (SSH / login)

```sh
/data/linux/artix-user.sh passwd <user> 'senha'
```

SSH na porta **2222**.  
`linux-shell.sh <user>` não pede senha (és root no Android).

---

### `not in the sudoers file`

```sh
/data/linux/artix-user.sh sudo usuário
```

Ou cria com `ARTIX_SUDO=1`. Sai e volta a entrar.

---

### `cd root` → permission denied

Normal. `/root` = home do root.

```sh
cd ~
# /home/<user>
```

---

### dbus / elogind / logind failed (cgroup)

Causa: `run-in-cgroup = dbus.sv` — o cgroup do Android/chroot não deixa criar.

Corrigir (já no `run-setup.sh`; reaplicar se o pacman sobrescrever):

```sh
/data/linux/run-setup.sh
# ou so os fixes:
/data/linux/fix-dbus-chroot.sh
dinitctl status dbus elogind logind
```

Deve ficar STARTED e existir `/run/dbus/system_bus_socket`.

---

### dinit teste: cgroup / boot / socket

| Erro | Solução |
|------|---------|
| `In multiple cgroups` | `--user --container --cgroup-path /sys/fs/cgroup` |
| `boot: could not find` | cria serviço `boot` no services-dir |
| exit 2 / state vazio | sem `>` no `command=`; usa script `.sh` |
| socket não criado | flags acima + `boot` + vê o log |

```sh
~/test-dinit-network.sh
```

O dinit do **sistema** já usa `/run/dinitctl`.  
Testes usam outro `--socket-path`.

---

### XFCE / Termux:X11 nao arranca

```sh
pm path com.termux.x11          # tem de listar o APK
/data/linux/x11-start.sh
dinitctl status xfce-x11 dbus
cat /var/log/dinit/xfce-x11.log
ls -l /tmp/.X11-unix/           # dentro do chroot: X0
cat /etc/artix-x11.conf
```

Causas tipicas:

| Sintoma | Causa / fix |
|---------|-------------|
| `falta a app Termux:X11` | Instalar APK `com.termux.x11` (F-Droid/GitHub); Termux base nao chega |
| `socket X11 nao apareceu` | Abrir a app Termux:X11; confirmar `setenforce 0`; TMPDIR no mount ns |
| `Cannot open display :0` | CmdEntryPoint fora do mount ns — usa `/data/linux/x11-start.sh` |
| xfce-x11 STOPPED | `/data/linux/x11-start.sh` (X0 tem de existir antes da sessao) |
| ecran preto (app aberta) | compositor xfwm4 + softGL — `x11-stop` + `x11-start` (force `use_compositing=false`) |

Tela preta com socket/sessao OK:

```sh
/data/linux/x11-stop.sh
# opcional: reaplicar prefs
ARTIX_USER=<user> /data/linux/run-setup-xfce.sh
/data/linux/x11-start.sh
```

Reinstalar setup: `ARTIX_USER=<user> /data/linux/run-setup-xfce.sh`  
Depois: `/data/linux/x11-start.sh` → ecran na app Termux:X11.

---

### GPU: llvmpipe / softpipe / sem Mali / invalid ELF header / free(): invalid size

llvmpipe/softpipe no **desktop XFCE** é o default (`XFCE_USE_ZINK=0`) — sessão estável com Mesa **25.1.2** sob `/opt/android-mali`.  
Com `XFCE_USE_ZINK=1` + `/etc/artix-gpu-zink.ok`, o desktop arranca via `zink-run` (OpenGL→Vulkan Mali). Sem marker/zink-run, a sessão faz **fallback automatico** para softGL.

GPU Mali directa: `gpu-egl-run` + `/etc/artix-gpu-gles.ok` / `gpu-check.sh` PASS.

`invalid ELF header` / `Found no drivers` = ICD Bionic no glibc sem hybris — use `run-setup-gpu-hybris.sh` (não o mediatek legado).

`free(): invalid size` / `invalid pointer` no Mesa ≥26 (pacman Artix) — conhecido com softGL e Zink+hybris. O bootstrap/`setup-xfce` instala o overlay `mesa25-android-mali` e remove mesa≥26. Zink no desktop é opt-in (`XFCE_USE_ZINK`).

`GLIBC_2.43 not found` (ex. `liblcms2` / `xfce4-session`): o bootstrap/`setup-artix` e o `setup-xfce` fazem `pacman -Sy glibc` cedo. Sem wipe, no chroot vivo:

```sh
SHELL_CMD='pacman -Sy --noconfirm glibc' /data/linux/linux-shell.sh
/data/linux/x11-stop.sh
/data/linux/x11-start.sh
```

`ngtcp2_…` / pacman partido = rootfs inconsistente — **wipe + bootstrap** (sem patches de libs):

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
DISPLAY=:0 gpu-vulkan-run vkcube   # apos artix-gpu-hybris.ok
```

---

### Container morto / pidfile obsoleto

```sh
/data/linux/linux-stop.sh
/data/linux/linux-start.sh
cat /data/linux/boot.log
```

---

## Paths

| Path | O quê |
|------|--------|
| `/data/linux/rootfs.img` | disco Linux (8G esparso) |
| `/data/linux/mnt` | montagem |
| `/data/linux/boot.log` | log de boot |
| `/data/linux/run/init.pid` | PID do container |
| `/home/<user>` | home do user (não `/root`) |
| `/etc/dinit.d/` + `boot.d/` | serviços sistema |
| `/etc/artix-x11.conf` | user/display Termux:X11 |
| `/etc/artix-gpu.conf` | paths ICD Vulkan / vendor |
| `/mnt/vendor` `/mnt/system` | binds RO Android (GPU ICD) |
| `/etc/pacman.d/mirrorlist` | mirrors ARMtix |
| `/etc/pacman.d/mirrorlist-archarm` | mirrors Arch Linux ARM |
