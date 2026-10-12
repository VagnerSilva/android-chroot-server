#!/usr/bin/env bash
# ============================================================
# build-mesa26-android-mali-wsl.sh
#
# Build Mesa 26.2.4 for AArch64 with softpipe + Zink + real Kopper
# for the isolated Android Mali test image. Does not install to host
# /usr or touch the phone/rootfs.
#
# Requires an existing local Mesa repository with branch mesa-26.2.4.
# The script creates a detached worktree so patches never modify that
# repository's current checkout.
# ============================================================
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
START_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log()  { printf '>> %s\n' "$*"; }
warn() { printf '!! %s\n' "$*" >&2; }
fail() { printf '!! %s\n' "$*" >&2; exit 1; }

ARCH_ROOT=${ARCH_ROOT:-/home/vagners/arch-root}
MESA_REPO=${MESA_REPO:-$ARCH_ROOT/mesa26}
MESA_REF=${MESA_REF:-mesa-26.2.4}
MESA_CROSS=${MESA_CROSS:-$ARCH_ROOT/mesa25-cross/aarch64-linux-gnu.ini}
MESA_WORKTREE=${MESA_WORKTREE:-$ARCH_ROOT/mesa26-worktree-zink-arm64}
PREFIX=/opt/android-mali
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 2)}
KOPPER_MIN_SIZE=${KOPPER_MIN_SIZE:-32}
OVERWRITE_OUTPUT=${OVERWRITE_OUTPUT:-0}

DEPS_DIR_DEFAULT=
if [ -d "$SCRIPT_DIR/../deps" ]; then
  DEPS_DIR_DEFAULT=$(cd "$SCRIPT_DIR/../deps" && pwd)
fi
MESA26_OUT=${MESA26_OUT:-$DEPS_DIR_DEFAULT}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "comando ausente: $1"
}

prepare_source() {
  [ -d "$MESA_REPO/.git" ] || fail "MESA_REPO ausente ou nao e repositorio Git: $MESA_REPO (configure MESA_REPO para o clone Mesa que contem $MESA_REF)"
  [ -f "$MESA_REPO/meson.build" ] || fail "MESA_REPO nao contem meson.build: $MESA_REPO"
  git -C "$MESA_REPO" show-ref --verify --quiet "refs/heads/$MESA_REF" \
    || fail "branch local ausente: $MESA_REF em $MESA_REPO; faca fetch/checkout explicitamente e rode novamente"

  local source_commit
  source_commit=$(git -C "$MESA_REPO" rev-parse "refs/heads/$MESA_REF^{commit}")
  MESA_VERSION=$(git -C "$MESA_REPO" show "$source_commit:VERSION" 2>/dev/null || true)
  [ "$MESA_VERSION" = 26.2.4 ] \
    || fail "a branch $MESA_REF declara VERSION=${MESA_VERSION:-ausente}, esperado 26.2.4"

  if [ -e "$MESA_WORKTREE" ]; then
    [ -f "$MESA_WORKTREE/.git" ] \
      || fail "MESA_WORKTREE ja existe e nao e worktree Git: $MESA_WORKTREE"
    local worktree_commit
    worktree_commit=$(git -C "$MESA_WORKTREE" rev-parse HEAD 2>/dev/null) \
      || fail "nao foi possivel ler o worktree existente: $MESA_WORKTREE"
    [ "$worktree_commit" = "$source_commit" ] \
      || fail "worktree aponta para outro commit; preserve-o e escolha MESA_WORKTREE distinto"
    log "reutilizar worktree Mesa 26.2.4: $MESA_WORKTREE"
  else
    git -C "$MESA_REPO" worktree add --detach "$MESA_WORKTREE" "$source_commit" \
      || fail "nao foi possivel criar worktree destacado para $MESA_REF"
  fi

  MESA_SRC=$MESA_WORKTREE
  MESA_COMMIT=$source_commit
  log "source branch=$MESA_REF commit=$MESA_COMMIT version=$MESA_VERSION"

  local target patch_file
  target="$MESA_SRC/src/gallium/drivers/zink/zink_screen.c"
  patch_file="$SCRIPT_DIR/patches/mesa25-zink-mali-no-quads.patch"
  [ -f "$target" ] || fail "zink_screen.c ausente na source Mesa 26"
  if grep -q 'Force gallium primconvert' "$target"; then
    log "patch Mali no-quads ja aplicado no worktree"
  elif [ -f "$patch_file" ]; then
    patch -p1 -d "$MESA_SRC" --dry-run < "$patch_file" >/dev/null 2>&1 \
      || fail "patch Mali no-quads nao aplica nesta branch; rebaseie/verifique o patch antes do build"
    patch --no-backup-if-mismatch -p1 -d "$MESA_SRC" < "$patch_file" \
      || fail "falha ao aplicar patch Mali no-quads no worktree"
  else
    fail "patch Mali no-quads ausente: $patch_file"
  fi

  local null_descriptor_patch="$SCRIPT_DIR/patches/mesa26-zink-null-descriptor-fallback.patch"
  if grep -q 'Cannot use db descriptor mode without robustness2.nullDescriptor' "$target"; then
    log "fallback nullDescriptor ja aplicado no worktree"
  elif [ -f "$null_descriptor_patch" ]; then
    patch --dry-run --no-backup-if-mismatch -p1 -d "$MESA_SRC" \
      < "$null_descriptor_patch" >/dev/null 2>&1 \
      || fail "patch experimental nullDescriptor nao aplica em Mesa $MESA_VERSION"
    patch --no-backup-if-mismatch -p1 -d "$MESA_SRC" < "$null_descriptor_patch" \
      || fail "falha ao aplicar patch experimental nullDescriptor"
    log "fallback Mesa25 nullDescriptor aplicado como experimento Mesa26"
  else
    fail "patch experimental nullDescriptor ausente: $null_descriptor_patch"
  fi
}

guard_host() {
  log "verificar host e dependencias"
  case "$(uname -s)" in
    Linux) ;;
    *) fail "host deve ser Linux/WSL" ;;
  esac
  for command_name in git aarch64-linux-gnu-gcc meson ninja pkg-config zstd readelf strings python3 tar; do
    require_command "$command_name"
  done

  [ -f "$MESA_CROSS" ] || fail "cross file ausente: $MESA_CROSS"
  export PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
  pkg-config --exists vulkan || fail "pkg-config vulkan (arm64) ausente"
  pkg-config --exists libdrm || fail "pkg-config libdrm (arm64) ausente"
  pkg-config --exists x11 || fail "pkg-config x11 (arm64) ausente"
  pkg-config --exists wayland-client || fail "pkg-config wayland-client (arm64) ausente"
  log "vulkan=$(pkg-config --modversion vulkan) libdrm=$(pkg-config --modversion libdrm)"
}

BUILD_SUFFIX=${BUILD_SUFFIX:-$(git -C "$MESA_REPO" rev-parse --short "refs/heads/$MESA_REF" 2>/dev/null || printf unknown)}
BUILD_DIR=${BUILD_DIR:-$ARCH_ROOT/mesa26-build-zink-arm64-$BUILD_SUFFIX}
DESTDIR=${DESTDIR:-$ARCH_ROOT/mesa26-package-zink-$BUILD_SUFFIX}
LOGS_DIR=${LOGS_DIR:-$ARCH_ROOT/logs-mesa26-zink-$BUILD_SUFFIX}
TAR_NAME=mesa26-android-mali-26.2.4-arm64.tar.zst
OPT_TARBALL=${OPT_TARBALL:-$ARCH_ROOT/$TAR_NAME}

configure_mesa() {
  mkdir -p "$LOGS_DIR"
  if [ -f "$BUILD_DIR/build.ninja" ]; then
    log "reconfigurar build existente sem apagar: $BUILD_DIR"
    meson setup --reconfigure "$BUILD_DIR" "$MESA_SRC" \
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
      > "$LOGS_DIR/meson-setup.log" 2>&1 \
      || fail "Meson reconfigure falhou; veja $LOGS_DIR/meson-setup.log"
  else
    mkdir -p "$BUILD_DIR"
    log "meson setup $MESA_VERSION: platforms=x11,wayland glx=dri softpipe+zink"
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
      > "$LOGS_DIR/meson-setup.log" 2>&1 \
      || fail "Meson setup falhou; veja $LOGS_DIR/meson-setup.log"
  fi

  python3 - "$BUILD_DIR" <<'PY' || fail "validacao das opcoes Meson falhou"
import json
import sys

build_dir = sys.argv[1]
with open(f"{build_dir}/meson-info/intro-buildoptions.json", encoding="utf-8") as stream:
    options = {item["name"]: item.get("value") for item in json.load(stream)}
with open(f"{build_dir}/meson-info/intro-projectinfo.json", encoding="utf-8") as stream:
    project = json.load(stream)

drivers = options.get("gallium-drivers")
platforms = options.get("platforms")
glx = options.get("glx")
version = project.get("version")
print(f"project-version={version}")
print(f"platforms={platforms} glx={glx} gallium-drivers={drivers}")
if version != "26.2.4":
    raise SystemExit(f"Meson source version is {version}, expected 26.2.4")
if not drivers or not {"softpipe", "zink"}.issubset(set(drivers)):
    raise SystemExit("softpipe and zink must both be enabled")
if not platforms or not {"x11", "wayland"}.issubset(set(platforms)) or "android" in platforms:
    raise SystemExit("platforms must include x11,wayland and exclude android")
if glx != "dri":
    raise SystemExit(f"GLX must be dri, got {glx}")
PY
  log "Meson effective options validated"
}

build_mesa() {
  log "meson compile -j$JOBS"
  meson compile -C "$BUILD_DIR" -j "$JOBS" > "$LOGS_DIR/meson-build.log" 2>&1 \
    || fail "Meson compile falhou; veja $LOGS_DIR/meson-build.log"
}

gate_kopper() {
  local gallium=$1
  local symbol_size
  symbol_size=$(readelf -Ws "$gallium" | awk '/[[:space:]]kopper_init_screen([[:space:]]|$)/ { size=$3 } END { if (size != "") print size }')
  [ -n "$symbol_size" ] || fail "Kopper symbol ausente: $gallium"
  log "kopper_init_screen=${symbol_size}B (min=$KOPPER_MIN_SIZE)"
  [ "$symbol_size" -ge "$KOPPER_MIN_SIZE" ] \
    || fail "Kopper aparenta stub; GLX/Kopper nao sera empacotado"
  strings "$gallium" | grep -E 'pipe_zink_create_screen|zink_create_screen|zink:' >/dev/null \
    || fail "marcadores Zink ausentes em $gallium"
  log "gate Kopper/Zink passou"
}

install_mesa() {
  [ ! -e "$DESTDIR" ] || fail "DESTDIR ja existe; preserve-o e escolha DESTDIR distinto: $DESTDIR"
  mkdir -p "$DESTDIR"
  DESTDIR="$DESTDIR" meson install -C "$BUILD_DIR" > "$LOGS_DIR/meson-install.log" 2>&1 \
    || fail "Meson install falhou; veja $LOGS_DIR/meson-install.log"

  local gallium dri_dir
  gallium=$(find "$DESTDIR$PREFIX/lib" -maxdepth 1 -type f -name 'libgallium-*.so' -print -quit)
  [ -n "$gallium" ] || fail "libgallium ausente no DESTDIR"
  dri_dir="$DESTDIR$PREFIX/lib/dri"
  [ -f "$dri_dir/libdril_dri.so" ] || fail "megadriver libdril_dri.so ausente"
  ln -sfn libdril_dri.so "$dri_dir/zink_dri.so"
  ln -sfn libdril_dri.so "$dri_dir/swrast_dri.so"
  ln -sfn libdril_dri.so "$dri_dir/kms_swrast_dri.so"
  gate_kopper "$gallium"
}

package_mesa() {
  [ "$OVERWRITE_OUTPUT" = 0 ] || [ "$OVERWRITE_OUTPUT" = 1 ] \
    || fail "OVERWRITE_OUTPUT deve ser 0 ou 1"
  if [ -e "$OPT_TARBALL" ] && [ "$OVERWRITE_OUTPUT" != 1 ]; then
    fail "tarball ja existe; preserve-o ou use OPT_TARBALL distinto: $OPT_TARBALL"
  fi
  [ -d "$DESTDIR$PREFIX" ] || fail "prefixo instalado ausente: $DESTDIR$PREFIX"
  mkdir -p "$(dirname "$OPT_TARBALL")"
  tar -C "$DESTDIR" -I zstd -cf "$OPT_TARBALL" opt
  log "tarball criado: $OPT_TARBALL"

  if [ -n "$MESA26_OUT" ]; then
    mkdir -p "$MESA26_OUT"
    local out_copy="$MESA26_OUT/$TAR_NAME"
    if [ -e "$out_copy" ] && [ "$OVERWRITE_OUTPUT" != 1 ]; then
      fail "artefato de destino ja existe: $out_copy (use MESA26_OUT distinto ou OVERWRITE_OUTPUT=1)"
    fi
    cp -f "$OPT_TARBALL" "$out_copy"
    log "copiado para: $out_copy"
  fi
}

main() {
  log "START $START_TS"
  guard_host
  prepare_source
  log "MESA_SRC=$MESA_SRC"
  log "MESA_REF=$MESA_REF commit=$MESA_COMMIT"
  log "BUILD_DIR=$BUILD_DIR"
  log "DESTDIR=$DESTDIR"
  configure_mesa
  build_mesa
  install_mesa
  package_mesa
  log "DONE $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

main "$@"