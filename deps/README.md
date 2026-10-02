# deps — artefactos offline para GPU hybris + Mesa 25 (runtime-only)

Ficheiros versionados para evitar download frágil no dispositivo
e **eliminar compilação** (makepkg/base-devel) no chroot.

| Ficheiro | Uso | Obrigatório |
|----------|-----|-------------|
| `mesa25-android-mali-25.1.2-arm64.tar.zst` | Mesa 25.1.2 → `/opt/android-mali` | sim (XFCE + GPU) |
| `libhybris-opt-arm64.tar.zst` | libhybris → `/opt/libhybris` | sim (GPU hybris) |
| `libc-hybris.so` | Bionic Lindroid (patch libc) | sim (GPU; curl fallback) |
| `sysvk-opt-arm64.tar.zst` | mesa ICD wrapper + ahb + WSI → `/usr` | não (Vulkan Fase F) |
| `android-vulkan-bridge.tar.gz` | fontes/patches para build WSL do sysvk-opt | sim (só no host de build) |

Fluxo: `deploy.ps1` → `/data/local/tmp/rootfs/deps` → `prepare.sh` →
`/data/linux/deps/` → `run-setup-xfce` / `run-setup-gpu-hybris` copia para `$ROOT/root/`.

Instaladores no chroot:

- `install-mesa25-android-mali.sh`
- `install-libhybris-opt.sh`
- `install-sysvk-opt.sh` (só se o tarball sysvk existir)

## Layout dos tarballs

```
# mesa25
./opt/android-mali/lib/libgallium-25.1.2.so
./opt/android-mali/lib/libEGL_mesa.so*
…

# libhybris-opt
./opt/libhybris/lib/libhybris-common.so
…

# sysvk-opt (opcional — mesa-vulkan-icd-wrapper + ahb + WSI)
./usr/share/vulkan/icd.d/*wrapper*.json
./usr/share/vulkan/explicit_layer.d/VkLayer_window_system_integration.json
./usr/lib/libvulkan_wrapper.so*
./usr/lib/libahb-wrapper.so*
./usr/lib/libVkLayer_window_system_integration.so*
```

## Porquê runtime-only

- Mesa ≥26: `free(): invalid size` / `invalid pointer` (softGL + Zink+hybris)
- Compilar libhybris/sysvk no telefone é lento e frágil (git/curl/makepkg)

## Regenerar

```sh
# libc Bionic Lindroid (arm64)
curl -fL -o libc-hybris.so \
  https://github.com/Linux-on-droid/vendor_lindroid/raw/lindroid-22.1/prebuilt/arm64/libc.so
```

### libhybris (WSL cross-build AArch64)

Build isolado (Android 16 runtime / VNDK 34 ABI), sem instalar no Artix
nem no telefone:

```sh
# no WSL (x86_64), com gcc-aarch64-linux-gnu + libc6-dev-arm64-cross + zstd
bash rootfs/host/build-libhybris-a16-vndk34-wsl.sh
```

Saída em `~/mali-runtime/`:

- `install/arm64/usr/` — staging
- `artifacts/` — `*.so`, `manifest.txt`, `sha256sums.txt`, `libhybris-opt-arm64.tar.zst`

O script empacota `libhybris-opt-arm64.tar.zst` (layout `./opt/libhybris/...`)
e copia para `rootfs/deps/` (ou `LIBHYBRIS_OPT_OUT=`). No device,
`install-libhybris-opt.sh` extrai esse tarball para `/opt/libhybris`.

### sysvk-opt (WSL cross-build AArch64)

Stack do android-vulkan-bridge (não o `sysvk` leve):
`ahb-wrapper` → `vulkan-wsi-layer` → `mesa-vulkan-icd-wrapper` (branch
`wrapper`). Requer `libhybris-opt-arm64.tar.zst` +
`android-vulkan-bridge.tar.gz` já em `deps/`.

```sh
# no WSL (x86_64), com gcc-aarch64-linux-gnu + meson/cmake/ninja +
# libs aarch64 (libdrm/x11/wayland/xcb) + zstd
bash rootfs/host/build-sysvk-opt-wsl.sh
```

Saída: `~/mali-runtime/artifacts/sysvk-opt-arm64.tar.zst` (também
copiado para `rootfs/deps/` ou `SYSVK_OPT_OUT=`). No device,
`install-sysvk-opt.sh` extrai para `/` e a Fase F do setup activa Vulkan.

### mesa25 overlay (WSL cross-build AArch64)

Rebuild obrigatório com **softpipe + zink** (kopper real). O tarball
antigo tinha só `gallium-drivers=softpipe` → `kopper_stubs` e Zink
falhava no Termux:X11.

Fonte por omissão: `/home/vagners/arch-root/mesa25` (tag 25.1.2).

```sh
# no WSL (x86_64), com aarch64-linux-gnu-gcc + meson/ninja +
# libvulkan-dev:arm64 libdrm/x11/wayland arm64 + zstd
bash rootfs/host/build-mesa25-android-mali-wsl.sh
```

Gate: `kopper_init_screen` ≥ 32 bytes em `libgallium-25.1.2.so`.
Patch: `host/patches/mesa25-zink-mali-no-quads.patch` (Mali: sem QUADS
via GS — primconvert → triangles; evita SIGSEGV no glxgears).
Saída: `mesa25-android-mali-25.1.2-arm64.tar.zst` → `rootfs/deps/`.

`mesa25-*`, `libhybris-opt-*` e `sysvk-opt-*` são builds locais (prefixos
`/opt/android-mali`, `/opt/libhybris`, `/usr` para sysvk); não vêm do mirror ARMtix.

Não incluir aqui pacotes ARMtix (`libngtcp2`, `glibc`, …) — usam mirror/cache.
