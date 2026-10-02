#!/usr/bin/env bash
# ============================================================
# build-sysvk-opt-wsl.sh
#
# Cross-build isolado (AArch64) no WSL da stack Vulkan recomendada
# pelo android-vulkan-bridge:
#   1) ahb-wrapper
#   2) vulkan-wsi-layer
#   3) mesa-vulkan-icd-wrapper (xMeM/mesa branch wrapper @ 25.1.2)
#
# Empacota deps/sysvk-opt-arm64.tar.zst (layout ./usr/...) para
# install-sysvk-opt.sh / setup-gpu-hybris.sh Fase F.
#
# Work tree: ~/mali-runtime/
# Prefixo runtime: /usr  (ICD + WSI + ahb)
# Staging WSL:     ~/mali-runtime/install/sysvk-destdir/
#
# NÃO instala no sistema WSL (/usr, /opt do host).
# NÃO acede/modifica Artix, telefone, /system ou /vendor.
# NÃO rebuilda libhybris — usa deps/libhybris-opt-arm64.tar.zst.
#
# Env úteis:
#   MALI_RUNTIME=~/mali-runtime
#   BRIDGE_TAR=path/to/android-vulkan-bridge.tar.gz
#   LIBHYBRIS_OPT_TAR=path/to/libhybris-opt-arm64.tar.zst
#   MESA_WRAPPER_GIT=https://github.com/xMeM/mesa
#   MESA_WRAPPER_REF=wrapper   (ou tag/commit; default: branch wrapper)
#   WSI_GIT=https://github.com/xMeM/vulkan-wsi-layer
#   ANDROID_HEADERS_30_GIT=https://github.com/Linux-on-droid/android-headers-30
#   FORCE_NATIVE=1
#   SKIP_PACKAGE=1
#   SKIP_MESA=1                (so ahb+WSI; diagnostico)
#   SYSVK_OPT_OUT=/path/to/rootfs/deps
#   JOBS=$(nproc)
# ============================================================
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
START_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log()  { printf '>> %s\n' "$*"; }
warn() { printf '!! %s\n' "$*" >&2; }
fail() { printf '!! %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
MALI_RUNTIME=${MALI_RUNTIME:-$HOME/mali-runtime}
MESA_WRAPPER_GIT=${MESA_WRAPPER_GIT:-https://github.com/xMeM/mesa}
MESA_WRAPPER_REF=${MESA_WRAPPER_REF:-wrapper}
WSI_GIT=${WSI_GIT:-https://github.com/xMeM/vulkan-wsi-layer}
ANDROID_HEADERS_30_GIT=${ANDROID_HEADERS_30_GIT:-https://github.com/Linux-on-droid/android-headers-30}
FORCE_NATIVE=${FORCE_NATIVE:-0}
SKIP_PACKAGE=${SKIP_PACKAGE:-0}
SKIP_MESA=${SKIP_MESA:-0}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 2)}
SYSVK_OPT_TAR_NAME=sysvk-opt-arm64.tar.zst
OPT_TARBALL=""

DEPS_DIR_DEFAULT=""
if [ -d "$SCRIPT_DIR/../deps" ]; then
  DEPS_DIR_DEFAULT=$(cd "$SCRIPT_DIR/../deps" && pwd)
fi

BRIDGE_TAR=${BRIDGE_TAR:-${DEPS_DIR_DEFAULT:+$DEPS_DIR_DEFAULT/android-vulkan-bridge.tar.gz}}
LIBHYBRIS_OPT_TAR=${LIBHYBRIS_OPT_TAR:-${DEPS_DIR_DEFAULT:+$DEPS_DIR_DEFAULT/libhybris-opt-arm64.tar.zst}}

SRC_DIR=$MALI_RUNTIME/src
DEPS_STAGE=$MALI_RUNTIME/deps-sysvk
HYBRIS_STAGE=$DEPS_STAGE/libhybris
ANDROID_HDR_STAGE=$DEPS_STAGE/android-headers
BUILD_ROOT=$MALI_RUNTIME/build/sysvk
DESTDIR=$MALI_RUNTIME/install/sysvk-destdir
ARTIFACTS_DIR=$MALI_RUNTIME/artifacts
LOGS_DIR=$MALI_RUNTIME/logs
TOOLCHAIN_FILE=$BUILD_ROOT/aarch64-toolchain.cmake
MESON_CROSS=$BUILD_ROOT/aarch64-cross.ini

BRIDGE_SRC=$SRC_DIR/android-vulkan-bridge
AHB_SRC=""
WSI_SRC=$SRC_DIR/vulkan-wsi-layer
MESA_SRC=$SRC_DIR/mesa-wrapper
HEADERS_30_SRC=$SRC_DIR/android-headers-30

# ---------------------------------------------------------------------------
# Guardas
# ---------------------------------------------------------------------------
guard_host() {
  log "verificar host"
  case "$(uname -s)" in
    Linux) ;;
    *) fail "host deve ser Linux/WSL (uname -s=$(uname -s))" ;;
  esac

  HOST_ARCH=$(uname -m)
  case "$HOST_ARCH" in
    x86_64|amd64) ;;
    aarch64|arm64)
      if [ "$FORCE_NATIVE" != "1" ]; then
        fail "host é $HOST_ARCH; este script espera cross em x86_64 (FORCE_NATIVE=1 para nativo)"
      fi
      warn "FORCE_NATIVE=1: build nativo aarch64 permitido"
      ;;
    *) fail "arquitectura de host não suportada: $HOST_ARCH" ;;
  esac

  if [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
    log "WSL detectado"
  else
    log "Linux nativo (não-WSL) — OK se toolchain aarch64 existir"
  fi

  case "$PWD" in
    */data/linux*|*/opt/android-mali*|*/apex/*)
      fail "cwd parece Artix/Android ($PWD); execute no WSL home"
      ;;
  esac
  if [ -d /data/linux ] && [ -f /etc/artix-release ]; then
    fail "ambiente Artix detectado; este script é só para WSL/host de build"
  fi
  if [ -d /system ] && [ -d /vendor ] && [ -f /system/build.prop ]; then
    fail "ambiente Android detectado; não executar no telefone"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "ferramenta ausente: $1"
}

check_tools() {
  log "verificar ferramentas"
  local req=(
    git make cmake ninja meson pkg-config python3
    tar gzip xz zstd file readelf patch sed
    aarch64-linux-gnu-gcc aarch64-linux-gnu-g++
    aarch64-linux-gnu-ar aarch64-linux-gnu-strip
  )
  local c
  for c in "${req[@]}"; do
    need_cmd "$c"
  done

  # pkg-config multiarch
  if command -v aarch64-linux-gnu-pkg-config >/dev/null 2>&1; then
    PKG_CONFIG_BIN=aarch64-linux-gnu-pkg-config
  else
    PKG_CONFIG_BIN=pkg-config
    export PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
    export PKG_CONFIG_SYSROOT_DIR=/
    warn "usar pkg-config generico com PKG_CONFIG_LIBDIR=$PKG_CONFIG_LIBDIR"
  fi

  local pcs=(libdrm x11 x11-xcb xcb xcb-dri3 xcb-present xcb-xfixes wayland-client zlib)
  local missing=()
  for c in "${pcs[@]}"; do
    if ! "$PKG_CONFIG_BIN" --exists "$c" 2>/dev/null; then
      missing+=("$c")
    fi
  done
  if ((${#missing[@]})); then
    fail "pkg-config aarch64 ausente: ${missing[*]}  →  sudo apt-get install -y libdrm-dev:arm64 libx11-dev:arm64 libxcb-dri3-dev:arm64 libxcb-present-dev:arm64 libxcb-xfixes0-dev:arm64 libwayland-dev:arm64 zlib1g-dev:arm64"
  fi

  [ -f /usr/include/vulkan/vulkan.h ] || \
    fail "vulkan headers ausentes → sudo apt-get install -y libvulkan-dev"

  # xcb-util (WSI)
  if ! "$PKG_CONFIG_BIN" --exists xcb-keysyms 2>/dev/null; then
    warn "xcb-keysyms ausente (recomendado: libxcb-keysyms1-dev:arm64)"
  fi

  local tmpdir
  tmpdir=$(mktemp -d)
  echo 'int main(void){return 0;}' >"$tmpdir/t.c"
  aarch64-linux-gnu-gcc -o "$tmpdir/t" "$tmpdir/t.c" \
    || { rm -rf "$tmpdir"; fail "aarch64-linux-gnu-gcc nao consegue linkar"; }
  file "$tmpdir/t" | grep -Eqi 'ARM aarch64|aarch64' \
    || { rm -rf "$tmpdir"; fail "GCC cross nao produziu AArch64"; }
  rm -rf "$tmpdir"
  log "toolchain aarch64 OK ($(aarch64-linux-gnu-gcc --version | head -n1))"
}

setup_tree() {
  log "criar arvore $MALI_RUNTIME"
  mkdir -p \
    "$SRC_DIR" "$DEPS_STAGE" "$BUILD_ROOT" \
    "$DESTDIR" "$ARTIFACTS_DIR" "$LOGS_DIR"
}

# ---------------------------------------------------------------------------
# Fontes / deps
# ---------------------------------------------------------------------------
resolve_inputs() {
  [ -n "${BRIDGE_TAR:-}" ] && [ -f "$BRIDGE_TAR" ] || \
    fail "BRIDGE_TAR ausente (android-vulkan-bridge.tar.gz). Defina BRIDGE_TAR= ou coloque em rootfs/deps/"
  [ -n "${LIBHYBRIS_OPT_TAR:-}" ] && [ -f "$LIBHYBRIS_OPT_TAR" ] || \
    fail "LIBHYBRIS_OPT_TAR ausente (libhybris-opt-arm64.tar.zst). Corra build-libhybris primeiro."
  log "bridge:  $BRIDGE_TAR"
  log "hybris:  $LIBHYBRIS_OPT_TAR"
}

extract_bridge() {
  log "extrair android-vulkan-bridge"
  rm -rf "$BRIDGE_SRC"
  mkdir -p "$SRC_DIR"
  tar -xzf "$BRIDGE_TAR" -C "$SRC_DIR"
  # tarball tipico: android-vulkan-bridge-main/
  if [ -d "$SRC_DIR/android-vulkan-bridge-main" ]; then
    mv "$SRC_DIR/android-vulkan-bridge-main" "$BRIDGE_SRC"
  elif [ -d "$SRC_DIR/android-vulkan-bridge" ]; then
    : # ja no nome certo
  else
    # primeiro top-level dir
    local top
    top=$(find "$SRC_DIR" -mindepth 1 -maxdepth 1 -type d | head -n1)
    [ -n "$top" ] || fail "estrutura inesperada em $BRIDGE_TAR"
    mv "$top" "$BRIDGE_SRC"
  fi
  AHB_SRC=$BRIDGE_SRC/ahb-wrapper/src
  [ -f "$AHB_SRC/ahb-wrapper.c" ] || fail "ahb-wrapper.c ausente em $AHB_SRC"
  [ -d "$BRIDGE_SRC/vulkan-wsi-layer/patch" ] || fail "patches WSI ausentes"
  [ -f "$BRIDGE_SRC/mesa-vulkan-icd-wrapper/0001-mesa-vulkan-icd-wrapper-Enable-Android-Vulkan-driver.patch" ] || \
    fail "patch mesa wrapper ausente"
}

stage_hybris() {
  log "staging libhybris-opt → $HYBRIS_STAGE"
  rm -rf "$HYBRIS_STAGE"
  mkdir -p "$DEPS_STAGE"
  tar -I zstd -xf "$LIBHYBRIS_OPT_TAR" -C "$DEPS_STAGE"
  # tarball: opt/libhybris/...
  if [ -d "$DEPS_STAGE/opt/libhybris" ]; then
    mv "$DEPS_STAGE/opt/libhybris" "$HYBRIS_STAGE"
    rmdir "$DEPS_STAGE/opt" 2>/dev/null || true
  fi
  [ -e "$HYBRIS_STAGE/lib/libhybris-common.so" ] || \
    [ -e "$HYBRIS_STAGE/lib/libhybris-common.so.1" ] || \
    fail "libhybris-common.so ausente apos extract"
  [ -f "$HYBRIS_STAGE/include/hybris/dlfcn/dlfcn.h" ] || \
    fail "hybris/dlfcn/dlfcn.h ausente apos extract"
}

fetch_android_headers_30() {
  log "android-headers-30"
  if [ ! -d "$HEADERS_30_SRC/.git" ]; then
    rm -rf "$HEADERS_30_SRC"
    git clone --depth 1 "$ANDROID_HEADERS_30_GIT" "$HEADERS_30_SRC"
  else
    git -C "$HEADERS_30_SRC" fetch --depth 1 origin || true
    git -C "$HEADERS_30_SRC" pull --ff-only || true
  fi

  log "instalar android-headers-30 em staging ($ANDROID_HDR_STAGE)"
  rm -rf "$ANDROID_HDR_STAGE"
  mkdir -p "$ANDROID_HDR_STAGE"
  # Makefile tipico: PREFIX=/usr DESTDIR=...
  if [ -f "$HEADERS_30_SRC/Makefile" ]; then
    make -C "$HEADERS_30_SRC" PREFIX=/usr DESTDIR="$ANDROID_HDR_STAGE" install \
      >"$LOGS_DIR/android-headers-30-install.log" 2>&1 \
      || fail "android-headers-30 install falhou (ver $LOGS_DIR/android-headers-30-install.log)"
  else
    # fallback: copiar arvore include
    mkdir -p "$ANDROID_HDR_STAGE/usr/include"
    if [ -d "$HEADERS_30_SRC/include" ]; then
      cp -a "$HEADERS_30_SRC/include/." "$ANDROID_HDR_STAGE/usr/include/"
    else
      fail "android-headers-30 sem Makefile nem include/"
    fi
  fi

  # Esperado: usr/include/android/...
  if [ ! -d "$ANDROID_HDR_STAGE/usr/include/android" ]; then
    # alguns trees instalam directo em include/android relativo a PREFIX
    if [ -d "$ANDROID_HDR_STAGE/usr/android" ]; then
      mkdir -p "$ANDROID_HDR_STAGE/usr/include"
      mv "$ANDROID_HDR_STAGE/usr/android" "$ANDROID_HDR_STAGE/usr/include/android"
    elif [ -d "$ANDROID_HDR_STAGE/include/android" ]; then
      mkdir -p "$ANDROID_HDR_STAGE/usr"
      mv "$ANDROID_HDR_STAGE/include" "$ANDROID_HDR_STAGE/usr/include"
    else
      warn "layout android-headers inesperado; listar:"
      find "$ANDROID_HDR_STAGE" -maxdepth 4 -type d | head -40 >&2
      fail "usr/include/android ausente apos install de android-headers-30"
    fi
  fi
}

fetch_wsi() {
  log "vulkan-wsi-layer ($WSI_GIT)"
  if [ ! -d "$WSI_SRC/.git" ]; then
    rm -rf "$WSI_SRC"
    git clone --depth 1 "$WSI_GIT" "$WSI_SRC"
  else
    git -C "$WSI_SRC" fetch --depth 1 origin || true
    git -C "$WSI_SRC" pull --ff-only || true
  fi

  log "aplicar patches WSI do bridge"
  git -C "$WSI_SRC" checkout -- . 2>/dev/null || true
  local p
  for p in "$BRIDGE_SRC"/vulkan-wsi-layer/patch/*.patch; do
    [ -f "$p" ] || continue
    log "  patch $(basename "$p")"
    patch -d "$WSI_SRC" -p1 --forward <"$p" \
      || patch -d "$WSI_SRC" -p1 --forward --dry-run <"$p" >/dev/null 2>&1 \
      || fail "falha a aplicar $p"
  done

  # GCC ≥15 (C++): designators têm de seguir a ordem da struct Vulkan
  local sp="$WSI_SRC/wsi/x11/surface_properties.cpp"
  if [ -f "$sp" ] && grep -q '\.flags = 0,' "$sp" && grep -A2 '\.flags = 0,' "$sp" | grep -q '\.pNext = NULL,'; then
    log "fix GCC15 designated-init em surface_properties.cpp"
    # trocar bloco flags/pNext → pNext/flags (ordem da VkXcbSurfaceCreateInfoKHR)
    perl -i -0pe 's/(\.sType = VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,\n)\s*\.flags = 0,\n\s*\.pNext = NULL,/$1      .pNext = NULL,\n      .flags = 0,/s' "$sp" \
      || fail "falha a corrigir designated-init em $sp"
  fi
}

fetch_mesa() {
  if [ "$SKIP_MESA" = "1" ]; then
    warn "SKIP_MESA=1 — nao clonar mesa wrapper"
    return 0
  fi
  log "mesa wrapper ($MESA_WRAPPER_GIT @ $MESA_WRAPPER_REF)"
  if [ ! -d "$MESA_SRC/.git" ]; then
    rm -rf "$MESA_SRC"
    git clone --depth 1 --branch "$MESA_WRAPPER_REF" "$MESA_WRAPPER_GIT" "$MESA_SRC" \
      || git clone --depth 1 "$MESA_WRAPPER_GIT" "$MESA_SRC"
    if ! git -C "$MESA_SRC" rev-parse --verify "$MESA_WRAPPER_REF" >/dev/null 2>&1; then
      git -C "$MESA_SRC" fetch --depth 1 origin "$MESA_WRAPPER_REF" || true
    fi
    git -C "$MESA_SRC" checkout "$MESA_WRAPPER_REF" 2>/dev/null || true
  else
    git -C "$MESA_SRC" fetch --depth 1 origin "$MESA_WRAPPER_REF" || true
    git -C "$MESA_SRC" checkout "$MESA_WRAPPER_REF" 2>/dev/null || true
  fi

  log "aplicar patch mesa Android/hybris do bridge"
  git -C "$MESA_SRC" reset --hard HEAD >/dev/null 2>&1 || true
  git -C "$MESA_SRC" clean -fd >/dev/null 2>&1 || true
  git -C "$MESA_SRC" checkout -- . 2>/dev/null || true
  local mp="$BRIDGE_SRC/mesa-vulkan-icd-wrapper/0001-mesa-vulkan-icd-wrapper-Enable-Android-Vulkan-driver.patch"
  patch -d "$MESA_SRC" -p1 --forward <"$mp" \
    || fail "falha a aplicar patch mesa wrapper"

  # glibc ≥2.41: once_flag/call_once em stdlib.h conflitam com o shim Mesa.
  # Manter shim pthread (mtx_t), mas nao redefinir once_flag/call_once.
  log "patch glibc once_flag conflict em src/c11/threads*.{h,c}"
  MESA_SRC="$MESA_SRC" python3 - <<'PY'
from pathlib import Path
import os
src = Path(os.environ["MESA_SRC"])
th = src / "src/c11/threads.h"
text = th.read_text()
needle = "#include <stdlib.h>\n"
inject = """#include <stdlib.h>

/* glibc >= 2.41 exposes once_flag/call_once via stdlib.h */
#if defined(__GLIBC__) && defined(__GLIBC_PREREQ) && __GLIBC_PREREQ(2, 41)
#  define MESA_SKIP_ONCE_FLAG 1
#endif
"""
if "MESA_SKIP_ONCE_FLAG" not in text:
    if needle not in text:
        raise SystemExit("stdlib include nao encontrado em threads.h")
    text = text.replace(needle, inject, 1)

# Skip typedef once_flag under MESA_SKIP_ONCE_FLAG (HAVE_PTHREAD branch)
old_td = """typedef pthread_mutex_t mtx_t;
typedef pthread_once_t  once_flag;
#  define ONCE_FLAG_INIT PTHREAD_ONCE_INIT"""
new_td = """typedef pthread_mutex_t mtx_t;
#  ifndef MESA_SKIP_ONCE_FLAG
typedef pthread_once_t  once_flag;
#  define ONCE_FLAG_INIT PTHREAD_ONCE_INIT
#  endif"""
if old_td in text:
    text = text.replace(old_td, new_td, 1)

old_decl = "void call_once(once_flag *, void (*)(void));"
new_decl = """#ifndef MESA_SKIP_ONCE_FLAG
void call_once(once_flag *, void (*)(void));
#endif"""
if old_decl in text and "MESA_SKIP_ONCE_FLAG" not in text.split(old_decl)[0][-80:]:
    text = text.replace(old_decl, new_decl, 1)

th.write_text(text)
print("patched", th)

tp = src / "src/c11/impl/threads_posix.c"
tpt = tp.read_text()
if "MESA_SKIP_ONCE_FLAG" not in tpt:
    # wrap call_once definition
    import re
    tpt2, n = re.subn(
        r"(void\s+call_once\(once_flag \*flag, void \(\*func\)\(void\)\)\s*\{)",
        r"#ifndef MESA_SKIP_ONCE_FLAG\n\1",
        tpt,
        count=1,
    )
    if n != 1:
        raise SystemExit("call_once def nao encontrada em threads_posix.c")
    # close the ifndef after the function — find matching closing brace after call_once
    # simpler: after pthread_once line's function end
    # Insert #endif after the call_once function body
    idx = tpt2.find("#ifndef MESA_SKIP_ONCE_FLAG\nvoid\ncall_once") 
    if idx < 0:
        idx = tpt2.find("#ifndef MESA_SKIP_ONCE_FLAG\nvoid call_once")
    if idx < 0:
        # try alternate form from sub
        idx = tpt2.find("#ifndef MESA_SKIP_ONCE_FLAG")
    # find end of function: first "}\n\n" after call_once
    start = tpt2.find("call_once(once_flag")
    brace = tpt2.find("{", start)
    depth = 0
    i = brace
    while i < len(tpt2):
        if tpt2[i] == "{":
            depth += 1
        elif tpt2[i] == "}":
            depth -= 1
            if depth == 0:
                tpt2 = tpt2[: i + 1] + "\n#endif /* MESA_SKIP_ONCE_FLAG */" + tpt2[i + 1 :]
                break
        i += 1
    else:
        raise SystemExit("nao encontrou fim de call_once")
    tp.write_text(tpt2)
    print("patched", tp)
else:
    print("threads_posix ja patchado")
PY

  # Reescrever paths absolutos /usr e /lib do patch para staging + DESTDIR
  # O patch usa #include <android/...> ⇒ include dir = .../usr/include (pai de android/)
  local android_inc="$ANDROID_HDR_STAGE/usr/include"
  local hybris_inc="$HYBRIS_STAGE/include/hybris"
  local dest_lib="$DESTDIR/usr/lib"
  [ -d "$android_inc/android" ] || fail "android include staging ausente: $android_inc/android"
  [ -d "$hybris_inc" ] || fail "hybris include staging ausente: $hybris_inc"

  log "ajustar paths hardcoded do patch mesa → staging"
  # Substituir apenas literais /usr/... (com aspas), nunca substrings de paths ja absolutos
  find "$MESA_SRC" -type f \( -name 'meson.build' -o -name '*.c' -o -name '*.h' -o -name '*.cpp' \) \
    -print0 | xargs -0 sed -i \
      -e "s#'/usr/include/android'#'${android_inc}'#g" \
      -e "s#\"/usr/include/android\"#\"${android_inc}\"#g" \
      -e "s#'/usr/include/hybris'#'${hybris_inc}'#g" \
      -e "s#\"/usr/include/hybris\"#\"${hybris_inc}\"#g" \
      -e "s#'-L/lib'#'-L${dest_lib}'#g" \
      -e "s#dirs: \['/lib'\]#dirs: ['${dest_lib}']#g"
}

write_cmake_toolchain() {
  cat >"$TOOLCHAIN_FILE" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
set(CMAKE_AR aarch64-linux-gnu-ar)
set(CMAKE_RANLIB aarch64-linux-gnu-ranlib)
set(CMAKE_STRIP aarch64-linux-gnu-strip)
set(CMAKE_FIND_ROOT_PATH /usr/aarch64-linux-gnu /usr)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
EOF
}

write_meson_cross() {
  cat >"$MESON_CROSS" <<EOF
[binaries]
c = 'aarch64-linux-gnu-gcc'
cpp = 'aarch64-linux-gnu-g++'
ar = 'aarch64-linux-gnu-ar'
strip = 'aarch64-linux-gnu-strip'
pkg-config = '${PKG_CONFIG_BIN}'
cmake = 'cmake'

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[built-in options]
prefix = '/usr'
libdir = 'lib'
EOF
}

# ---------------------------------------------------------------------------
# Builds
# ---------------------------------------------------------------------------
build_ahb() {
  log "build ahb-wrapper"
  local bdir=$BUILD_ROOT/ahb
  rm -rf "$bdir"
  mkdir -p "$bdir"

  # CMakeLists hardcodeia /usr/include/hybris — ajustar
  local cm="$AHB_SRC/CMakeLists.txt"
  cp -a "$cm" "$cm.bak"
  sed -i "s|/usr/include/hybris|${HYBRIS_STAGE}/include/hybris|g" "$cm"

  cmake -S "$AHB_SRC" -B "$bdir" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_C_FLAGS="-I${HYBRIS_STAGE}/include/hybris -I${HYBRIS_STAGE}/include" \
    -DCMAKE_SHARED_LINKER_FLAGS="-L${HYBRIS_STAGE}/lib -Wl,-rpath-link,${HYBRIS_STAGE}/lib" \
    -DCMAKE_EXE_LINKER_FLAGS="-L${HYBRIS_STAGE}/lib -Wl,-rpath-link,${HYBRIS_STAGE}/lib" \
    >"$LOGS_DIR/ahb-cmake.log" 2>&1 \
    || { mv -f "$cm.bak" "$cm"; fail "ahb cmake falhou (ver $LOGS_DIR/ahb-cmake.log)"; }

  cmake --build "$bdir" -j"$JOBS" \
    >"$LOGS_DIR/ahb-build.log" 2>&1 \
    || { mv -f "$cm.bak" "$cm"; fail "ahb build falhou (ver $LOGS_DIR/ahb-build.log)"; }

  DESTDIR="$DESTDIR" cmake --install "$bdir" \
    >"$LOGS_DIR/ahb-install.log" 2>&1 \
    || { mv -f "$cm.bak" "$cm"; fail "ahb install falhou"; }

  mv -f "$cm.bak" "$cm"

  # Aceitar libahb-wrapper.so ou libahb-wrapper.so.1
  if ! ls "$DESTDIR"/usr/lib/libahb-wrapper.so* >/dev/null 2>&1; then
    # alguns cmake usam lib64
    if ls "$DESTDIR"/usr/lib64/libahb-wrapper.so* >/dev/null 2>&1; then
      mkdir -p "$DESTDIR/usr/lib"
      cp -a "$DESTDIR"/usr/lib64/libahb-wrapper.so* "$DESTDIR/usr/lib/"
    else
      fail "libahb-wrapper.so ausente apos install"
    fi
  fi
  # symlink sem versao se so .so.N
  if [ ! -e "$DESTDIR/usr/lib/libahb-wrapper.so" ]; then
    local real
    real=$(ls "$DESTDIR"/usr/lib/libahb-wrapper.so.* 2>/dev/null | head -n1)
    [ -n "$real" ] && ln -sfn "$(basename "$real")" "$DESTDIR/usr/lib/libahb-wrapper.so"
  fi
  log "ahb-wrapper OK"
}

build_wsi() {
  log "build vulkan-wsi-layer"
  local bdir=$BUILD_ROOT/wsi
  rm -rf "$bdir"
  mkdir -p "$bdir"

  # Patch ja troca android → ahb-wrapper e adiciona /usr/include/android
  # Ajustar include android no CMakeLists gerado/patchado
  if grep -q '/usr/include/android' "$WSI_SRC/CMakeLists.txt" 2>/dev/null; then
    sed -i "s|/usr/include/android|${ANDROID_HDR_STAGE}/usr/include/android|g" "$WSI_SRC/CMakeLists.txt"
  fi

  local cflags cxxflags ldflags
  cflags="-I${ANDROID_HDR_STAGE}/usr/include -I${ANDROID_HDR_STAGE}/usr/include/android -I${HYBRIS_STAGE}/include/hybris -I${HYBRIS_STAGE}/include"
  cxxflags="$cflags"
  ldflags="-L${DESTDIR}/usr/lib -L${HYBRIS_STAGE}/lib -Wl,-rpath-link,${DESTDIR}/usr/lib -Wl,-rpath-link,${HYBRIS_STAGE}/lib"

  cmake -S "$WSI_SRC" -B "$bdir" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_PREFIX_PATH="${DESTDIR}/usr;${HYBRIS_STAGE}" \
    -DCMAKE_C_FLAGS="$cflags" \
    -DCMAKE_CXX_FLAGS="$cxxflags" \
    -DCMAKE_SHARED_LINKER_FLAGS="$ldflags" \
    -DCMAKE_EXE_LINKER_FLAGS="$ldflags" \
    -DCMAKE_LIBRARY_PATH="${DESTDIR}/usr/lib;${HYBRIS_STAGE}/lib" \
    -DBUILD_WSI_X11=ON \
    >"$LOGS_DIR/wsi-cmake.log" 2>&1 \
    || fail "wsi cmake falhou (ver $LOGS_DIR/wsi-cmake.log)"

  cmake --build "$bdir" -j"$JOBS" \
    >"$LOGS_DIR/wsi-build.log" 2>&1 \
    || fail "wsi build falhou (ver $LOGS_DIR/wsi-build.log)"

  DESTDIR="$DESTDIR" cmake --install "$bdir" \
    >"$LOGS_DIR/wsi-install.log" 2>&1 \
    || fail "wsi install falhou"

  # Garantir JSON WSI em explicit ou implicit layer.d
  local json
  json=$(find "$DESTDIR" -name 'VkLayer_window_system_integration.json' 2>/dev/null | head -n1 || true)
  [ -n "$json" ] || fail "VkLayer_window_system_integration.json ausente apos WSI install"

  if [ ! -f "$DESTDIR/usr/share/vulkan/explicit_layer.d/VkLayer_window_system_integration.json" ] \
     && [ ! -f "$DESTDIR/usr/share/vulkan/implicit_layer.d/VkLayer_window_system_integration.json" ]; then
    mkdir -p "$DESTDIR/usr/share/vulkan/explicit_layer.d"
    cp -a "$json" "$DESTDIR/usr/share/vulkan/explicit_layer.d/"
  fi

  # lib da layer
  if ! find "$DESTDIR/usr" -name 'libVkLayer_window_system_integration.so' | grep -q .; then
    fail "libVkLayer_window_system_integration.so ausente"
  fi
  log "vulkan-wsi-layer OK ($json)"
}

build_mesa_wrapper() {
  if [ "$SKIP_MESA" = "1" ]; then
    warn "SKIP_MESA=1 — skip mesa ICD wrapper"
    return 0
  fi
  log "build mesa-vulkan-icd-wrapper (demora)"
  local bdir=$BUILD_ROOT/mesa
  rm -rf "$bdir"
  mkdir -p "$bdir"

  # Paths /usr → staging ja reescritos em fetch_mesa(); nao re-sed substrings.
  local android_inc="$ANDROID_HDR_STAGE/usr/include"
  local hybris_inc="$HYBRIS_STAGE/include/hybris"
  local dest_lib="$DESTDIR/usr/lib"
  [ -d "$android_inc/android" ] || fail "android include staging ausente: $android_inc/android"
  [ -d "$hybris_inc" ] || fail "hybris include staging ausente: $hybris_inc"
  if grep -R --include='meson.build' -nE "['\"]/usr/include/android['\"]" "$MESA_SRC/src/vulkan" >/dev/null 2>&1; then
    warn "ainda ha literal /usr/include/android em meson.build — reaplicar sed unico"
    find "$MESA_SRC/src/vulkan" -type f -name 'meson.build' -print0 | xargs -0 sed -i \
      -e "s#'/usr/include/android'#'${android_inc}'#g" \
      -e "s#\"/usr/include/android\"#\"${android_inc}\"#g" \
      -e "s#'/usr/include/hybris'#'${hybris_inc}'#g" \
      -e "s#\"/usr/include/hybris\"#\"${hybris_inc}\"#g" \
      -e "s#'-L/lib'#'-L${dest_lib}'#g" \
      -e "s#dirs: \['/lib'\]#dirs: ['${dest_lib}']#g"
  fi
  # Actualizar -L/lib literal se ainda existir (DESTDIR fresco)
  find "$MESA_SRC/src/vulkan" -type f -name 'meson.build' -print0 | xargs -0 sed -i \
    -e "s#'-L/lib'#'-L${dest_lib}'#g" \
    -e "s#dirs: \['/lib'\]#dirs: ['${dest_lib}']#g" \
    2>/dev/null || true

  export PKG_CONFIG_LIBDIR=${PKG_CONFIG_LIBDIR:-/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig}
  export PKG_CONFIG_SYSROOT_DIR=${PKG_CONFIG_SYSROOT_DIR:-/}

  # -I usr/include  → <android/cutils/...>
  # -I usr/include/android → <android/hardware_buffer.h> (nested android/)
  #   e <vndk/...>, <cutils/...>
  local c_args cxx_args link_args
  c_args="-I${android_inc} -I${android_inc}/android -I${hybris_inc} -I${HYBRIS_STAGE}/include"
  cxx_args="$c_args"
  link_args="-L${dest_lib} -L${HYBRIS_STAGE}/lib -Wl,-rpath-link,${dest_lib} -Wl,-rpath-link,${HYBRIS_STAGE}/lib -lahb-wrapper -lhybris-common"

  meson setup "$bdir" "$MESA_SRC" \
    --cross-file "$MESON_CROSS" \
    --prefix=/usr \
    --libdir=lib \
    -Dbuildtype=release \
    -Dcpp_rtti=false \
    -Dgbm=disabled \
    -Dopengl=false \
    -Dllvm=disabled \
    -Dshared-llvm=disabled \
    -Dplatforms=x11,wayland \
    -Dgallium-drivers= \
    -Dxmlconfig=disabled \
    -Dvulkan-drivers=wrapper \
    -Db_ndebug=true \
    -Dandroid-stub=false \
    -Dglvnd=disabled \
    -Dlibunwind=disabled \
    -Dlmsensors=disabled \
    -Dmicrosoft-clc=disabled \
    -Dvalgrind=disabled \
    -Dc_args="$c_args" \
    -Dcpp_args="$cxx_args" \
    -Dc_link_args="$link_args" \
    -Dcpp_link_args="$link_args" \
    >"$LOGS_DIR/mesa-meson.log" 2>&1 \
    || fail "mesa meson setup falhou (ver $LOGS_DIR/mesa-meson.log)"

  meson compile -C "$bdir" -j "$JOBS" \
    >"$LOGS_DIR/mesa-build.log" 2>&1 \
    || fail "mesa compile falhou (ver $LOGS_DIR/mesa-build.log)"

  DESTDIR="$DESTDIR" meson install -C "$bdir" \
    >"$LOGS_DIR/mesa-install.log" 2>&1 \
    || fail "mesa install falhou (ver $LOGS_DIR/mesa-install.log)"

  log "mesa-vulkan-icd-wrapper OK"
}

# ---------------------------------------------------------------------------
# Package
# ---------------------------------------------------------------------------
package_sysvk_opt() {
  if [ "$SKIP_PACKAGE" = "1" ]; then
    warn "SKIP_PACKAGE=1 — tarball nao gerado"
    return 0
  fi

  log "empacotar $SYSVK_OPT_TAR_NAME"
  command -v tar >/dev/null 2>&1 || fail "tar ausente"
  command -v zstd >/dev/null 2>&1 || fail "zstd ausente"

  [ -d "$DESTDIR/usr" ] || fail "DESTDIR/usr ausente: $DESTDIR"

  # --- validacao layout ---
  local icd_json="" j
  for j in \
    "$DESTDIR"/usr/share/vulkan/icd.d/*.json \
    "$DESTDIR"/usr/local/share/vulkan/icd.d/*.json
  do
    [ -f "$j" ] || continue
    if grep -qiE 'sysvk|android|wrapper|mali' "$j"; then
      icd_json=$j
      break
    fi
  done
  [ -n "$icd_json" ] || fail "ICD JSON (wrapper/android/sysvk) ausente em $DESTDIR/usr/share/vulkan/icd.d/"

  local icd_lib
  icd_lib=$(sed -n 's/.*"library_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$icd_json" | head -n1 || true)
  [ -n "$icd_lib" ] || fail "library_path ausente em $icd_json"
  if [[ "$icd_lib" != /* ]]; then
    # relativo ao JSON ou so basename
    if [ -f "$(dirname "$icd_json")/$icd_lib" ]; then
      :
    elif [ -f "$DESTDIR/usr/lib/$icd_lib" ] || [ -f "$DESTDIR/usr/lib/$(basename "$icd_lib")" ]; then
      :
    else
      # procurar libvulkan_wrapper / wrapper
      if ! find "$DESTDIR/usr/lib" "$DESTDIR/usr/lib64" -name 'libvulkan_wrapper.so*' -o -name '*wrapper*.so*' 2>/dev/null | grep -q .; then
        fail "biblioteca ICD nao encontrada para library_path=$icd_lib"
      fi
    fi
  else
    [ -f "$DESTDIR$icd_lib" ] || [ -f "$icd_lib" ] || \
      fail "library_path absoluto ausente: $icd_lib"
  fi

  local wsi_ok=0
  for j in \
    "$DESTDIR/usr/share/vulkan/explicit_layer.d/VkLayer_window_system_integration.json" \
    "$DESTDIR/usr/share/vulkan/implicit_layer.d/VkLayer_window_system_integration.json"
  do
    [ -f "$j" ] && wsi_ok=1 && break
  done
  [ "$wsi_ok" = 1 ] || fail "JSON WSI ausente (VkLayer_window_system_integration.json)"

  ls "$DESTDIR"/usr/lib/libahb-wrapper.so* >/dev/null 2>&1 \
    || fail "libahb-wrapper.so ausente no DESTDIR"

  # ELF aarch64 spot-check
  local so
  so=$(find "$DESTDIR/usr/lib" -name 'libahb-wrapper.so*' -type f | head -n1)
  if [ -n "$so" ]; then
    file "$so" | grep -Eqi 'ARM aarch64|aarch64' \
      || fail "libahb-wrapper nao e AArch64: $(file "$so")"
  fi

  OPT_TARBALL="$ARTIFACTS_DIR/$SYSVK_OPT_TAR_NAME"
  mkdir -p "$ARTIFACTS_DIR"
  # so usr/ (prefixo /usr)
  tar -C "$DESTDIR" -I zstd -cf "$OPT_TARBALL" usr

  tar -I zstd -tf "$OPT_TARBALL" | grep -q 'usr/share/vulkan/icd.d/.*\.json' \
    || fail "tarball sem ICD json"
  tar -I zstd -tf "$OPT_TARBALL" | grep -q 'VkLayer_window_system_integration\.json' \
    || fail "tarball sem WSI json"
  tar -I zstd -tf "$OPT_TARBALL" | grep -q 'libahb-wrapper\.so' \
    || fail "tarball sem libahb-wrapper.so"

  log "tarball: $OPT_TARBALL ($(wc -c <"$OPT_TARBALL") bytes)"

  local out_deps pack_dest
  out_deps=${SYSVK_OPT_OUT:-}
  if [ -z "$out_deps" ] && [ -n "$DEPS_DIR_DEFAULT" ]; then
    out_deps=$DEPS_DIR_DEFAULT
  fi
  if [ -n "$out_deps" ]; then
    mkdir -p "$out_deps"
    pack_dest="$out_deps/$SYSVK_OPT_TAR_NAME"
    cp -f "$OPT_TARBALL" "$pack_dest"
    log "copiado → $pack_dest"
  else
    warn "SYSVK_OPT_OUT nao definido e rootfs/deps nao encontrado — tarball so em artifacts/"
  fi

  # manifest curto
  {
    echo "sysvk-opt-arm64"
    echo "built=$START_TS"
    echo "mesa_ref=$MESA_WRAPPER_REF"
    echo "mesa_git=$MESA_WRAPPER_GIT"
    echo "wsi_git=$WSI_GIT"
    echo "bridge_tar=$(basename "$BRIDGE_TAR")"
    echo "hybris_tar=$(basename "$LIBHYBRIS_OPT_TAR")"
    echo "icd_json=$(basename "$icd_json")"
  } >"$ARTIFACTS_DIR/sysvk-opt-manifest.txt"
}

print_summary() {
  cat <<EOF

========================================================================
 Build sysvk-opt concluido
========================================================================
 Staging:    $DESTDIR
 Artifacts:  $ARTIFACTS_DIR
 Tarball:    ${OPT_TARBALL:- (nao gerado)}
 Logs:       $LOGS_DIR

 Stack: ahb-wrapper + vulkan-wsi-layer + mesa-vulkan-icd-wrapper
 NÃO instalado no /usr do host WSL (so DESTDIR).
 Proximo no device: prepare.sh → run-setup-gpu-hybris.sh (Fase F)
========================================================================
EOF
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  guard_host
  check_tools
  setup_tree
  resolve_inputs
  extract_bridge
  stage_hybris
  fetch_android_headers_30
  fetch_wsi
  write_cmake_toolchain
  write_meson_cross
  # limpar DESTDIR fresco
  rm -rf "$DESTDIR"
  mkdir -p "$DESTDIR"
  build_ahb
  build_wsi
  fetch_mesa
  build_mesa_wrapper
  package_sysvk_opt
  print_summary
}

main "$@"
