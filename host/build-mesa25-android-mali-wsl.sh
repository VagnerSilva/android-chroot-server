#!/usr/bin/env bash
# ============================================================
# build-mesa25-android-mali-wsl.sh
#
# Rebuild Mesa 25.1.2 (AArch64) com softpipe + zink + kopper real
# para overlay /opt/android-mali (Termux:X11 / XFCE softGL + Zink).
#
# Causa do overlay antigo: gallium-drivers=softpipe apenas →
# kopper_stubs (kopper_init_screen=8B) → Zink falha sem DRM.
#
# Por omissao usa a arvore ja existente:
#   /home/vagners/arch-root/mesa25  (tag mesa-25.1.2)
#   /home/vagners/arch-root/mesa25-cross/aarch64-linux-gnu.ini
#
# Saida:
#   ~/…/mesa25-android-mali-25.1.2-arm64.tar.zst
#   + copia para rootfs/deps/ (MESA25_OUT=)
#
# NÃO instala no /usr do host WSL.
# NÃO toca no telefone — so gera o tarball.
#
# Env:
#   ARCH_ROOT=/home/vagners/arch-root
#   MESA_SRC=…/mesa25
#   MESA_CROSS=…/mesa25-cross/aarch64-linux-gnu.ini
#   MESA25_OUT=/path/to/rootfs/deps
#   JOBS=$(nproc)
#   SKIP_PACKAGE=0
#   FORCE_RECONFIGURE=1
# ============================================================
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
START_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log()  { printf '>> %s\n' "$*"; }
warn() { printf '!! %s\n' "$*" >&2; }
fail() { printf '!! %s\n' "$*" >&2; exit 1; }

ARCH_ROOT=${ARCH_ROOT:-/home/vagners/arch-root}
MESA_SRC=${MESA_SRC:-$ARCH_ROOT/mesa25}
MESA_CROSS=${MESA_CROSS:-$ARCH_ROOT/mesa25-cross/aarch64-linux-gnu.ini}
BUILD_DIR=${BUILD_DIR:-$ARCH_ROOT/mesa25-build-zink-arm64}
DESTDIR=${DESTDIR:-$ARCH_ROOT/mesa25-package-zink}
LOGS_DIR=${LOGS_DIR:-$ARCH_ROOT/logs-mesa25-zink}
TAR_NAME=mesa25-android-mali-25.1.2-arm64.tar.zst
OPT_TARBALL=${OPT_TARBALL:-$ARCH_ROOT/$TAR_NAME}
PREFIX=/opt/android-mali
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 2)}
SKIP_PACKAGE=${SKIP_PACKAGE:-0}
FORCE_RECONFIGURE=${FORCE_RECONFIGURE:-1}
KOPPER_MIN_SIZE=${KOPPER_MIN_SIZE:-32}

DEPS_DIR_DEFAULT=""
if [ -d "$SCRIPT_DIR/../deps" ]; then
  DEPS_DIR_DEFAULT=$(cd "$SCRIPT_DIR/../deps" && pwd)
fi
MESA25_OUT=${MESA25_OUT:-$DEPS_DIR_DEFAULT}

guard_host() {
  log "verificar host"
  case "$(uname -s)" in
    Linux) ;;
    *) fail "host deve ser Linux/WSL" ;;
  esac
  command -v aarch64-linux-gnu-gcc >/dev/null || fail "aarch64-linux-gnu-gcc ausente"
  command -v meson >/dev/null || fail "meson ausente"
  command -v ninja >/dev/null || fail "ninja ausente"
  command -v pkg-config >/dev/null || fail "pkg-config ausente"
  command -v zstd >/dev/null || fail "zstd ausente"
  command -v readelf >/dev/null || fail "readelf ausente"

  [ -d "$MESA_SRC" ] || fail "MESA_SRC ausente: $MESA_SRC"
  [ -f "$MESA_SRC/meson.build" ] || fail "nao parece fonte Mesa: $MESA_SRC"
  [ -f "$MESA_CROSS" ] || fail "cross file ausente: $MESA_CROSS"

  export PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
  pkg-config --exists vulkan \
    || fail "pkg-config vulkan (arm64) ausente — apt install libvulkan-dev:arm64"
  pkg-config --exists libdrm \
    || fail "pkg-config libdrm (arm64) ausente"
  pkg-config --exists x11 \
    || fail "pkg-config x11 (arm64) ausente"
  pkg-config --exists wayland-client \
    || warn "wayland-client ausente — build pode falhar se platforms incluir wayland"

  log "vulkan=$(pkg-config --modversion vulkan) libdrm=$(pkg-config --modversion libdrm)"
}

apply_patches() {
  local patch_dir="$SCRIPT_DIR/patches"
  local p="$patch_dir/mesa25-zink-mali-no-quads.patch"
  local target="$MESA_SRC/src/gallium/drivers/zink/zink_screen.c"
  [ -f "$target" ] || fail "zink_screen.c ausente: $target"
  if grep -q 'Force gallium primconvert' "$target" 2>/dev/null; then
    log "patch mali-no-quads ja aplicado em MESA_SRC"
    return 0
  fi
  if [ -f "$p" ]; then
    log "aplicar $p"
    # patch pode falhar se whitespace differ — fallback sed via marker
    if command -v patch >/dev/null 2>&1 && patch -p1 -d "$MESA_SRC" --dry-run <"$p" >/dev/null 2>&1; then
      patch -p1 -d "$MESA_SRC" <"$p" || fail "patch falhou"
    else
      warn "patch(1) dry-run falhou — aplicar via python"
      python3 - "$target" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text()
needle="""      if (!screen->have_triangle_fans || !screen->info.feats.features.geometryShader)
         modes &= ~BITFIELD_BIT(MESA_PRIM_QUADS);
      modes &= ~BITFIELD_BIT(MESA_PRIM_QUAD_STRIP);"""
insert="""      if (!screen->have_triangle_fans || !screen->info.feats.features.geometryShader)
         modes &= ~BITFIELD_BIT(MESA_PRIM_QUADS);
      /* Mali proprietary: GS quad lowering SIGSEGV in gdrv0 (glxgears QUAD_STRIP).
       * Force gallium primconvert → triangles instead of zink GS path.
       */
      if (zink_driverid(screen) == VK_DRIVER_ID_ARM_PROPRIETARY)
         modes &= ~BITFIELD_BIT(MESA_PRIM_QUADS);
      modes &= ~BITFIELD_BIT(MESA_PRIM_QUAD_STRIP);"""
if needle not in t:
    raise SystemExit("needle not found for mali-no-quads")
p.write_text(t.replace(needle, insert, 1))
print("python-patch OK")
PY
    fi
  else
    warn "patch ausente: $p — continuar sem quirk Mali quads"
  fi
}

configure_mesa() {
  mkdir -p "$LOGS_DIR"
  if [ -d "$BUILD_DIR" ] && [ "$FORCE_RECONFIGURE" = "1" ]; then
    log "FORCE_RECONFIGURE=1 — limpar $BUILD_DIR"
    rm -rf "$BUILD_DIR"
  fi

  if [ -f "$BUILD_DIR/build.ninja" ] && [ "$FORCE_RECONFIGURE" != "1" ]; then
    log "reutilizar build dir existente: $BUILD_DIR"
    return 0
  fi

  log "meson setup → $BUILD_DIR (softpipe+zink, platforms=x11,wayland)"
  # softpipe: XFCE softGL | zink: GLX→Vulkan (kopper)
  # SEM android em platforms → kopper.c (nao stubs)
  # vulkan-drivers vazio: ICD fica no sysvk-opt
  meson setup "$BUILD_DIR" "$MESA_SRC" \
    --cross-file "$MESA_CROSS" \
    --prefix="$PREFIX" \
    --libdir=lib \
    -Dbuildtype=release \
    -Dplatforms=x11,wayland \
    -Dopengl=true \
    -Degl=enabled \
    -Dgles1=disabled \
    -Dgles2=enabled \
    -Dglx=dri \
    -Dgbm=enabled \
    -Dglvnd=enabled \
    -Dllvm=disabled \
    -Dshared-llvm=disabled \
    -Dgallium-drivers=softpipe,zink \
    -Dvulkan-drivers= \
    -Dbuild-tests=false \
    -Dlibunwind=disabled \
    -Dlmsensors=disabled \
    -Dmicrosoft-clc=disabled \
    -Dvalgrind=disabled \
    -Db_ndebug=true \
    >"$LOGS_DIR/meson-setup.log" 2>&1 \
    || fail "meson setup falhou (ver $LOGS_DIR/meson-setup.log)"

  # confirmar opcoes
  python3 - "$BUILD_DIR" <<'PY' || fail "validacao meson options falhou"
import json,sys
b=sys.argv[1]
with open(f"{b}/meson-info/intro-buildoptions.json") as f:
    opts={x["name"]:x.get("value") for x in json.load(f)}
gd=opts.get("gallium-drivers")
plat=opts.get("platforms")
print("gallium-drivers=", gd)
print("platforms=", plat)
if not gd or "zink" not in gd:
    raise SystemExit("zink ausente em gallium-drivers")
if not plat or "android" in plat:
    raise SystemExit("platforms invalido (precisa x11/wayland sem android)")
if "softpipe" not in gd:
    raise SystemExit("softpipe ausente — XFCE softGL quebraria")
PY
  log "meson options OK"
}

build_mesa() {
  log "meson compile -j$JOBS"
  meson compile -C "$BUILD_DIR" -j "$JOBS" \
    >"$LOGS_DIR/meson-build.log" 2>&1 \
    || fail "meson compile falhou (ver $LOGS_DIR/meson-build.log)"
  log "compile OK"
}

install_mesa() {
  log "DESTDIR install → $DESTDIR"
  rm -rf "$DESTDIR"
  mkdir -p "$DESTDIR"
  DESTDIR="$DESTDIR" meson install -C "$BUILD_DIR" \
    >"$LOGS_DIR/meson-install.log" 2>&1 \
    || fail "meson install falhou (ver $LOGS_DIR/meson-install.log)"

  GALLIUM="$DESTDIR$PREFIX/lib/libgallium-25.1.2.so"
  [ -f "$GALLIUM" ] || GALLIUM=$(ls -1 "$DESTDIR$PREFIX"/lib/libgallium-*.so 2>/dev/null | head -n1)
  [ -f "$GALLIUM" ] || fail "libgallium ausente apos install"

  # megadriver: zink_dri.so symlink
  DRI="$DESTDIR$PREFIX/lib/dri"
  if [ -f "$DRI/libdril_dri.so" ]; then
    ln -sfn libdril_dri.so "$DRI/zink_dri.so"
    ln -sfn libdril_dri.so "$DRI/swrast_dri.so" 2>/dev/null || true
    ln -sfn libdril_dri.so "$DRI/kms_swrast_dri.so" 2>/dev/null || true
  fi

  gate_kopper "$GALLIUM"
}

gate_kopper() {
  local gallium=$1
  log "gate kopper: $gallium"
  local sz
  # readelf|awk: awk sai cedo → SIGPIPE no readelf; nao usar pipefail aqui
  set +o pipefail
  sz=$(readelf -Ws "$gallium" | awk '/[[:space:]]kopper_init_screen([[:space:]]|$)/ { print $3; exit }')
  set -o pipefail
  [ -n "$sz" ] || fail "simbolo kopper_init_screen ausente"
  log "kopper_init_screen size=${sz}B (min $KOPPER_MIN_SIZE)"
  if [ "$sz" -lt "$KOPPER_MIN_SIZE" ]; then
    set +o pipefail
    strings "$gallium" | grep -E 'kopper_stubs\.c|kopper\.c' | sort -u || true
    set -o pipefail
    fail "kopper ainda stubbed (size=$sz) — Zink nao funcionara no Termux:X11"
  fi
  set +o pipefail
  if strings "$gallium" | grep -q 'kopper_stubs\.c'; then
    warn "string kopper_stubs.c ainda presente — size=$sz OK, seguir"
  fi
  if ! strings "$gallium" | grep -qE 'pipe_zink_create_screen|zink_create_screen|zink:'; then
    set -o pipefail
    fail "simbolos zink ausentes em $gallium"
  fi
  set -o pipefail
  log "gate kopper PASS"
}

package_tarball() {
  if [ "$SKIP_PACKAGE" = "1" ]; then
    warn "SKIP_PACKAGE=1"
    return 0
  fi
  log "empacotar $OPT_TARBALL"
  [ -d "$DESTDIR$PREFIX" ] || fail "DESTDIR$PREFIX ausente"
  # layout: ./opt/android-mali/...
  tar -C "$DESTDIR" -I zstd -cf "$OPT_TARBALL" opt
  ls -lh "$OPT_TARBALL"

  if [ -n "$MESA25_OUT" ]; then
    mkdir -p "$MESA25_OUT"
    cp -a "$OPT_TARBALL" "$MESA25_OUT/$TAR_NAME"
    log "copiado → $MESA25_OUT/$TAR_NAME"
  fi
}

main() {
  log "START $START_TS"
  log "MESA_SRC=$MESA_SRC"
  log "BUILD_DIR=$BUILD_DIR"
  log "DESTDIR=$DESTDIR"
  guard_host
  apply_patches
  configure_mesa
  build_mesa
  install_mesa
  package_tarball
  log "DONE $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  log "tarball: $OPT_TARBALL"
  log "proximo: deploy deps + install-mesa25 no device + zink-run glxinfo -B"
}

main "$@"
