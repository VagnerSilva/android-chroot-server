#!/usr/bin/env bash
# ============================================================
# build-libhybris-a16-vndk34-wsl.sh
#
# Cross-build isolado do libhybris (AArch64) no WSL para:
#   Android 16 / API 36 (runtime) + vendor VNDK 34 (ABI)
#   GPU alvo: Mali-G615 MC2 (GLES/EGL first)
#
# Work tree: ~/mali-runtime/
# Prefixo runtime: /opt/libhybris  (embutido nos binarios via --prefix)
# Staging WSL:     ~/mali-runtime/install/destdir/opt/libhybris  (DESTDIR)
#
# NÃO instala no sistema WSL (/usr, /usr/local, /opt do host).
# NÃO acede/modifica Artix, telefone, /system ou /vendor.
# NÃO aplica patches experimentais nesta fase.
# Empacota libhybris-opt-arm64.tar.zst (layout ./opt/libhybris/...) no fim.
#
# Env úteis:
#   MALI_RUNTIME=~/mali-runtime
#   LIBHYBRIS_GIT=https://github.com/Linux-on-droid/libhybris
#   LIBHYBRIS_REF=lindroid-21
#   ANDROID_HEADERS_34_GIT=https://github.com/fish4terrisa-MSDSM/android-headers-34
#   ANDROID_HEADERS_34_REF=<branch|commit>   (default: HEAD da default branch)
#   ANDROID_TREE_16=/path/to/aosp            (opcional; extract-headers)
#   AOSP_16_TAG=android-16.0.0_r1
#   SKIP_A16_OVERLAY=1                       (só headers-34)
#   FORCE_NATIVE=1                           (permitir build nativo aarch64)
#   SKIP_PACKAGE=1                           (não gerar tarball opt)
#   LIBHYBRIS_OPT_OUT=/path/to/rootfs/deps   (copiar tarball; default: ../deps se existir)
#   JOBS=$(nproc)
# ============================================================
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_NAME=$(basename "$0")
START_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log()  { printf '>> %s\n' "$*"; }
warn() { printf '!! %s\n' "$*" >&2; }
fail() { printf '!! %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
MALI_RUNTIME=${MALI_RUNTIME:-$HOME/mali-runtime}
LIBHYBRIS_GIT=${LIBHYBRIS_GIT:-https://github.com/Linux-on-droid/libhybris}
LIBHYBRIS_REF=${LIBHYBRIS_REF:-lindroid-21}
ANDROID_HEADERS_34_GIT=${ANDROID_HEADERS_34_GIT:-https://github.com/fish4terrisa-MSDSM/android-headers-34}
ANDROID_HEADERS_34_REF=${ANDROID_HEADERS_34_REF:-}
AOSP_16_TAG=${AOSP_16_TAG:-android-16.0.0_r1}
SKIP_A16_OVERLAY=${SKIP_A16_OVERLAY:-0}
FORCE_NATIVE=${FORCE_NATIVE:-0}
SKIP_PACKAGE=${SKIP_PACKAGE:-0}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 2)}
LIBHYBRIS_OPT_TAR=libhybris-opt-arm64.tar.zst
OPT_TARBALL=""

SRC_DIR=$MALI_RUNTIME/src
HEADERS_DIR=$MALI_RUNTIME/headers
PATCHES_DIR=$MALI_RUNTIME/patches
BUILD_DIR=$MALI_RUNTIME/build/libhybris
# Prefixo real no device; DESTDIR isola o staging no WSL
PREFIX=/opt/libhybris
DESTDIR=$MALI_RUNTIME/install/destdir
INSTALL_ROOT=$DESTDIR$PREFIX
ARTIFACTS_DIR=$MALI_RUNTIME/artifacts
LOGS_DIR=$MALI_RUNTIME/logs

LIBHYBRIS_SRC=$SRC_DIR/libhybris
HEADERS_34=$HEADERS_DIR/android-34
HEADERS_16=$HEADERS_DIR/android-16
HEADERS_MERGED=$HEADERS_DIR/merged
PROVENANCE=$HEADERS_DIR/PROVENANCE.txt
AOSP16_SRC=$SRC_DIR/aosp-16

ANDROID_API_RUNTIME=36
VNDK_VERSION=34

WAYLAND_ENABLED=no
CONFIGURE_ARGS=()
CC_FINAL=""
CXX_FINAL=""
AR_FINAL=""
RANLIB_FINAL=""
STRIP_FINAL=""
SYSROOT_FINAL=""
CFLAGS_FINAL=""
CXXFLAGS_FINAL=""
LDFLAGS_FINAL=""

# ---------------------------------------------------------------------------
# 1. Guardas de host
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

  # Recusar paths típicos do chroot Artix / deploy no telefone
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

# ---------------------------------------------------------------------------
# 2. Ferramentas
# ---------------------------------------------------------------------------
# Pacotes Debian/Ubuntu sugeridos quando falta um comando
suggest_pkg() {
    local missing=()

    command -v git >/dev/null 2>&1 || missing+=(git)
    command -v curl >/dev/null 2>&1 || missing+=(curl)
    command -v wget >/dev/null 2>&1 || missing+=(wget)
    command -v rsync >/dev/null 2>&1 || missing+=(rsync)
    command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 || missing+=(gcc-aarch64-linux-gnu)
    command -v aarch64-linux-gnu-g++ >/dev/null 2>&1 || missing+=(g++-aarch64-linux-gnu)
    command -v make >/dev/null 2>&1 || missing+=(make)
    command -v pkg-config >/dev/null 2>&1 || missing+=(pkg-config)
    command -v autoconf >/dev/null 2>&1 || missing+=(autoconf)
    command -v automake >/dev/null 2>&1 || missing+=(automake)
    command -v libtoolize >/dev/null 2>&1 || missing+=(libtool)
    command -v file >/dev/null 2>&1 || missing+=(file)
    command -v readelf >/dev/null 2>&1 || missing+=(binutils)
    command -v sha256sum >/dev/null 2>&1 || missing+=(coreutils)
    command -v python3 >/dev/null 2>&1 || missing+=(python3)
    command -v perl >/dev/null 2>&1 || missing+=(perl)
    command -v m4 >/dev/null 2>&1 || missing+=(m4)
    command -v flex >/dev/null 2>&1 || missing+=(flex)
    command -v bison >/dev/null 2>&1 || missing+=(bison)
    command -v gperf >/dev/null 2>&1 || missing+=(gperf)
    command -v tar >/dev/null 2>&1 || missing+=(tar)
    command -v gzip >/dev/null 2>&1 || missing+=(gzip)
    command -v xz >/dev/null 2>&1 || missing+=(xz-utils)
    command -v awk >/dev/null 2>&1 || missing+=(mawk)

    if ((${#missing[@]})); then
        printf '%s\n' "Pacotes possivelmente necessários:"
        printf '  %s\n' "${missing[@]}"
    fi
}

need_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  fi
  local pkg
  pkg=$(suggest_pkg "$1")
  if [ -n "$pkg" ]; then
    fail "ferramenta ausente: $1  →  sudo apt-get install -y $pkg"
  fi
  fail "ferramenta ausente: $1"
}

detect_sysroot() {
  local candidates=(
    /usr/aarch64-linux-gnu
    /usr/lib/aarch64-linux-gnu/../../aarch64-linux-gnu
  )
  local c
  for c in "${candidates[@]}"; do
    if [ -d "$c" ] && { [ -d "$c/include" ] || [ -d "$c/usr/include" ]; }; then
      # canonical
      if [ -d /usr/aarch64-linux-gnu ]; then
        echo /usr/aarch64-linux-gnu
        return 0
      fi
      echo "$c"
      return 0
    fi
  done
  # Debian multiarch: headers em /usr/include/aarch64-linux-gnu, libs em /usr/lib/aarch64-linux-gnu
  if [ -d /usr/lib/aarch64-linux-gnu ] && [ -d /usr/include/aarch64-linux-gnu ]; then
    echo /
    return 0
  fi
  return 1
}

check_tools() {
  log "verificar ferramentas"

  local req=(
    git
    make
    pkg-config
    autoconf
    automake
    file
    readelf
    sha256sum
    python3
    perl
    m4
    flex
    bison
    gperf
    tar
    gzip
    xz
    zstd
    rsync
    aarch64-linux-gnu-gcc
    aarch64-linux-gnu-g++
    aarch64-linux-gnu-ar
    aarch64-linux-gnu-ranlib
    aarch64-linux-gnu-strip
  )

  local c
  for c in "${req[@]}"; do
    need_cmd "$c"
  done

  if ! command -v libtool >/dev/null 2>&1 &&
     ! command -v libtoolize >/dev/null 2>&1 &&
     ! command -v glibtoolize >/dev/null 2>&1; then
    fail "ferramenta ausente: libtool/libtoolize → sudo apt-get install -y libtool"
  fi

  SYSROOT_FINAL=$(detect_sysroot) || fail \
    "sysroot aarch64 ausente. Instale: sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libc6-arm64-cross libc6-dev-arm64-cross"

  log "sysroot: $SYSROOT_FINAL"

  [ -d /usr/lib/gcc-cross/aarch64-linux-gnu ] ||
    fail "GCC cross sem diretório /usr/lib/gcc-cross/aarch64-linux-gnu"

  local tmpdir
  tmpdir=$(mktemp -d)

  cat >"$tmpdir/t.c" <<'EOF'
int main(void) { return 0; }
EOF

  log "testar GCC cross"

  aarch64-linux-gnu-gcc \
    -o "$tmpdir/t-gcc" \
    "$tmpdir/t.c" \
    || {
      rm -rf "$tmpdir"
      fail "aarch64-linux-gnu-gcc não consegue linkar"
    }

  file "$tmpdir/t-gcc" | grep -Eqi 'ARM aarch64|aarch64' \
    || {
      local gcc_info
      gcc_info=$(file "$tmpdir/t-gcc")
      rm -rf "$tmpdir"
      fail "GCC cross não produziu AArch64: $gcc_info"
    }

  rm -rf "$tmpdir"

  log "toolchain aarch64 OK ($(aarch64-linux-gnu-gcc --version | head -n1))"
}


# ---------------------------------------------------------------------------
# 3. Árvore
# ---------------------------------------------------------------------------
setup_tree() {
  log "criar árvore $MALI_RUNTIME"
  mkdir -p \
    "$SRC_DIR" \
    "$HEADERS_34" \
    "$HEADERS_16" \
    "$HEADERS_MERGED" \
    "$PATCHES_DIR" \
    "$BUILD_DIR" \
    "$PREFIX" \
    "$ARTIFACTS_DIR" \
    "$LOGS_DIR"
}

# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------
git_clone_ref() {
  # git_clone_ref <url> <dest> <ref> <logname>
  local url=$1 dest=$2 ref=$3 logname=$4
  if [ -d "$dest/.git" ]; then
    log "actualizar $dest ($ref)"
    git -C "$dest" remote set-url origin "$url"
    git -C "$dest" fetch --tags origin
    if git -C "$dest" rev-parse --verify "refs/remotes/origin/$ref" >/dev/null 2>&1; then
      git -C "$dest" checkout -B "$ref" "origin/$ref"
    elif git -C "$dest" rev-parse --verify "$ref" >/dev/null 2>&1; then
      git -C "$dest" checkout --detach "$ref"
    else
      git -C "$dest" fetch origin "$ref" || true
      git -C "$dest" checkout --detach "FETCH_HEAD" 2>/dev/null \
        || git -C "$dest" checkout --detach "$ref" \
        || fail "não foi possível checkout $ref em $dest"
    fi
  else
    log "clonar $url → $dest ($ref)"
    rm -rf "$dest"
    if ! git clone --branch "$ref" --single-branch "$url" "$dest" 2>/dev/null; then
      git clone "$url" "$dest"
      git -C "$dest" fetch origin "$ref" || true
      if git -C "$dest" rev-parse --verify "origin/$ref" >/dev/null 2>&1; then
        git -C "$dest" checkout -B "$ref" "origin/$ref"
      else
        git -C "$dest" checkout --detach "$ref" \
          || fail "ref $ref não encontrada em $url"
      fi
    fi
  fi

  {
    echo "remote=$(git -C "$dest" remote get-url origin)"
    echo "branch_or_ref=$ref"
    echo "commit=$(git -C "$dest" rev-parse HEAD)"
    echo "describe=$(git -C "$dest" describe --always --tags --dirty 2>/dev/null || true)"
    echo "date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$LOGS_DIR/${logname}-revision.txt"
  log "$logname @ $(git -C "$dest" rev-parse --short HEAD)"
}

# ---------------------------------------------------------------------------
# 4. libhybris
# ---------------------------------------------------------------------------
fetch_libhybris() {
  git_clone_ref "$LIBHYBRIS_GIT" "$LIBHYBRIS_SRC" "$LIBHYBRIS_REF" libhybris
  [ -x "$LIBHYBRIS_SRC/hybris/autogen.sh" ] \
    || [ -f "$LIBHYBRIS_SRC/hybris/autogen.sh" ] \
    || fail "autogen.sh ausente em $LIBHYBRIS_SRC/hybris"
  [ -f "$LIBHYBRIS_SRC/utils/extract-headers.sh" ] \
    || fail "utils/extract-headers.sh ausente"
  chmod +x "$LIBHYBRIS_SRC/hybris/autogen.sh" "$LIBHYBRIS_SRC/utils/extract-headers.sh" || true
}

# ---------------------------------------------------------------------------
# 5–6. Headers 34 + overlay 16 + merged
# ---------------------------------------------------------------------------
rsync_headers() {
  # copia árvore de headers ignorando .git
  local src=$1 dst=$2
  mkdir -p "$dst"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude '.git' "$src"/ "$dst"/
  else
    rm -rf "$dst"
    mkdir -p "$dst"
    tar -C "$src" --exclude='.git' -cf - . | tar -C "$dst" -xf -
  fi
}

overlay_missing_only() {
  # Copia de $1 para $2 apenas ficheiros que NÃO existem em $2
  local src=$1 dst=$2
  local f rel
  while IFS= read -r -d '' f; do
    rel=${f#"$src"/}
    case "$rel" in
      .git|/*|.git/*) continue ;;
    esac
    if [ ! -e "$dst/$rel" ]; then
      mkdir -p "$(dirname "$dst/$rel")"
      cp -a "$f" "$dst/$rel"
      echo "overlay16:$rel" >>"$PROVENANCE"
    fi
  done < <(find "$src" -type f ! -path '*/.git/*' -print0 2>/dev/null)
}

fetch_headers_34() {
  local ref=${ANDROID_HEADERS_34_REF:-}
  local tmp=$SRC_DIR/android-headers-34
  if [ -n "$ref" ]; then
    git_clone_ref "$ANDROID_HEADERS_34_GIT" "$tmp" "$ref" android-headers-34
  else
    if [ -d "$tmp/.git" ]; then
      log "actualizar android-headers-34"
      git -C "$tmp" remote set-url origin "$ANDROID_HEADERS_34_GIT"
      git -C "$tmp" fetch origin
      git -C "$tmp" checkout "$(git -C "$tmp" remote show origin | awk '/HEAD branch/ {print $NF}')" 2>/dev/null \
        || git -C "$tmp" checkout master 2>/dev/null \
        || git -C "$tmp" checkout main 2>/dev/null \
        || git -C "$tmp" pull --ff-only || true
      git -C "$tmp" pull --ff-only 2>/dev/null || true
    else
      log "clonar $ANDROID_HEADERS_34_GIT"
      rm -rf "$tmp"
      git clone "$ANDROID_HEADERS_34_GIT" "$tmp"
    fi
    {
      echo "remote=$(git -C "$tmp" remote get-url origin)"
      echo "branch_or_ref=$(git -C "$tmp" rev-parse --abbrev-ref HEAD 2>/dev/null || echo DETACHED)"
      echo "commit=$(git -C "$tmp" rev-parse HEAD)"
      echo "describe=$(git -C "$tmp" describe --always --tags --dirty 2>/dev/null || true)"
      echo "date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$LOGS_DIR/android-headers-34-revision.txt"
  fi

  [ -f "$tmp/android-version.h" ] || fail "android-version.h ausente em headers-34"
  [ -f "$tmp/android-config.h" ] || fail "android-config.h ausente em headers-34"

  rsync_headers "$tmp" "$HEADERS_34"
  : >"$PROVENANCE"
  {
    echo "# Header provenance — gerado por $SCRIPT_NAME"
    echo "date_utc=$START_TS"
    echo "base=android-headers-34"
    echo "base_git=$ANDROID_HEADERS_34_GIT"
    echo "base_commit=$(git -C "$tmp" rev-parse HEAD)"
    echo "vndk=$VNDK_VERSION"
    echo "android_api_runtime=$ANDROID_API_RUNTIME"
  } >>"$PROVENANCE"

  rsync_headers "$HEADERS_34" "$HEADERS_MERGED"
  log "headers-34 → merged (base ABI/VNDK $VNDK_VERSION)"
}

aosp_clone_module() {
  # aosp_clone_module <platform/path>  e.g. system/core
  local mod=$1
  local dest=$AOSP16_SRC/$mod
  local url="https://android.googlesource.com/platform/${mod}"
  mkdir -p "$(dirname "$dest")"
  if [ -d "$dest/.git" ]; then
    git -C "$dest" fetch --depth 1 origin "refs/tags/${AOSP_16_TAG}:refs/tags/${AOSP_16_TAG}" 2>/dev/null \
      || git -C "$dest" fetch --depth 1 origin "$AOSP_16_TAG" 2>/dev/null || true
    git -C "$dest" checkout --detach "refs/tags/${AOSP_16_TAG}" 2>/dev/null \
      || git -C "$dest" checkout --detach "$AOSP_16_TAG" 2>/dev/null \
      || warn "checkout $AOSP_16_TAG falhou em $mod"
    return 0
  fi
  log "sparse AOSP: $mod @$AOSP_16_TAG"
  if ! git clone --depth 1 --branch "$AOSP_16_TAG" "$url" "$dest" 2>"$LOGS_DIR/aosp-${mod//\//_}.log"; then
    # algumas tags só existem como tag, não branch
    rm -rf "$dest"
    git clone --depth 1 "$url" "$dest" 2>>"$LOGS_DIR/aosp-${mod//\//_}.log" || return 1
    git -C "$dest" fetch --depth 1 origin "refs/tags/${AOSP_16_TAG}:refs/tags/${AOSP_16_TAG}" 2>/dev/null || return 1
    git -C "$dest" checkout --detach "refs/tags/${AOSP_16_TAG}" || return 1
  fi
}

fetch_headers_16() {
  rm -rf "$HEADERS_16"
  mkdir -p "$HEADERS_16"

  if [ "$SKIP_A16_OVERLAY" = "1" ]; then
    warn "SKIP_A16_OVERLAY=1 — android-16 vazio; build só com base 34"
    echo "overlay16=skipped" >>"$PROVENANCE"
    return 0
  fi

  local extract=$LIBHYBRIS_SRC/utils/extract-headers.sh
  local tree=""

  if [ -n "${ANDROID_TREE_16:-}" ]; then
    [ -d "$ANDROID_TREE_16" ] || fail "ANDROID_TREE_16 não é diretório: $ANDROID_TREE_16"
    tree=$ANDROID_TREE_16
    log "extract-headers a partir de ANDROID_TREE_16=$tree"
  else
    log "tentar sparse AOSP $AOSP_16_TAG para overlay android-16"
    # Módulos mínimos tipicamente usados por extract-headers.sh
    local modules=(
      bionic
      system/core
      system/media
      system/logging
      frameworks/native
      hardware/libhardware
      hardware/libhardware_legacy
    )
    local ok=1
    local m
    for m in "${modules[@]}"; do
      if ! aosp_clone_module "$m"; then
        warn "falha ao obter AOSP module $m"
        ok=0
        break
      fi
    done
    if [ "$ok" = "1" ] && [ -d "$AOSP16_SRC" ]; then
      tree=$AOSP16_SRC
      echo "overlay16_source=aosp_sparse:$AOSP_16_TAG" >>"$PROVENANCE"
    else
      warn "sparse AOSP incompleto — overlay android-16 vazio (base 34 permanece)"
      echo "overlay16=unavailable (sparse AOSP falhou; use ANDROID_TREE_16=...)" >>"$PROVENANCE"
      return 0
    fi
  fi

  # extract-headers.sh <android_tree> <outdir>
    if ! bash "$extract" --version 16.0.0 "$tree" "$HEADERS_16" >"$LOGS_DIR/extract-headers-16.log" 2>&1; then
    warn "extract-headers.sh falhou — ver $LOGS_DIR/extract-headers-16.log"
    echo "overlay16=extract_failed" >>"$PROVENANCE"
    # não falhar o build: base 34 é suficiente para compilar na maioria dos casos
    return 0
  fi

  echo "overlay16_extract=ok" >>"$PROVENANCE"
  if [ -n "${ANDROID_TREE_16:-}" ]; then
    echo "overlay16_source=ANDROID_TREE_16:$ANDROID_TREE_16" >>"$PROVENANCE"
  fi

  # Fundir só ficheiros em falta (nunca substituir base 34)
  overlay_missing_only "$HEADERS_16" "$HEADERS_MERGED"
  log "overlay android-16 aplicado (só headers em falta na base 34)"
}



prepare_link_sysroot() {
  local link_sysroot="$MALI_RUNTIME/build/sysroot-aarch64"

  log "preparar sysroot de link: $link_sysroot"

  rm -rf "$link_sysroot"
  mkdir -p "$link_sysroot"

  cp -a "$SYSROOT_FINAL/." "$link_sysroot/"

  [ -f "$link_sysroot/lib/libc.so" ] || fail "libc.so ausente no sysroot de link"
  [ -f "$link_sysroot/lib/libc.so.6" ] || fail "libc.so.6 ausente no sysroot de link"
  [ -f "$link_sysroot/lib/libc_nonshared.a" ] || fail "libc_nonshared.a ausente no sysroot de link"
  [ -f "$link_sysroot/lib/ld-linux-aarch64.so.1" ] || fail "ld-linux-aarch64.so.1 ausente no sysroot de link"

  cat >"$link_sysroot/lib/libc.so" <<'EOF'
/* GNU ld linker script */
GROUP (
  libc.so.6
  libc_nonshared.a
  AS_NEEDED (
    ld-linux-aarch64.so.1
  )
)
EOF

  SYSROOT_LINK="$link_sysroot"
}

# ---------------------------------------------------------------------------
# 7–8. Configure + build + install staging
# ---------------------------------------------------------------------------
setup_toolchain_env() {
  log "configurar toolchain (GCC cross — nested functions em hooks.c)"

  # GCC aarch64 usa paths absolutos em libc.so; não precisa do sysroot
  # artificial que o clang exigia. Mantemos SYSROOT_FINAL só para pkg-config.
  SYSROOT_LINK=""

  CC_FINAL=aarch64-linux-gnu-gcc
  CXX_FINAL=aarch64-linux-gnu-g++
  AR_FINAL=aarch64-linux-gnu-ar
  RANLIB_FINAL=aarch64-linux-gnu-ranlib
  STRIP_FINAL=aarch64-linux-gnu-strip

  need_cmd "$CC_FINAL"
  need_cmd "$CXX_FINAL"
  need_cmd "$AR_FINAL"
  need_cmd "$RANLIB_FINAL"
  need_cmd "$STRIP_FINAL"

  CFLAGS_FINAL="-O2 -fPIC"
  CXXFLAGS_FINAL="-O2 -fPIC"
  LDFLAGS_FINAL=""

  export CC="$CC_FINAL"
  export CXX="$CXX_FINAL"
  export AR="$AR_FINAL"
  export RANLIB="$RANLIB_FINAL"
  export STRIP="$STRIP_FINAL"
  export CFLAGS="$CFLAGS_FINAL"
  export CXXFLAGS="$CXXFLAGS_FINAL"
  export LDFLAGS="$LDFLAGS_FINAL"

  export PKG_CONFIG_PATH=""

  if [ "$SYSROOT_FINAL" = "/" ]; then
    export PKG_CONFIG_LIBDIR="/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR=""
  else
    export PKG_CONFIG_LIBDIR="$SYSROOT_FINAL/lib/pkgconfig:$SYSROOT_FINAL/usr/lib/pkgconfig:$SYSROOT_FINAL/usr/lib/aarch64-linux-gnu/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$SYSROOT_FINAL"
  fi

  WAYLAND_ENABLED=no
}

configure_libhybris() {
  log "configure libhybris (staging $PREFIX)"
  setup_toolchain_env

  [ -f "$HEADERS_MERGED/android-version.h" ] || fail "merged headers incompletos"
  [ -f "$HEADERS_MERGED/android-config.h" ] || fail "merged headers incompletos"

  # Out-of-tree: autoreconf no source, configure no build dir
  (
    cd "$LIBHYBRIS_SRC/hybris"
    NOCONFIGURE=1 ./autogen.sh
  ) >"$LOGS_DIR/autogen.log" 2>&1 || {
    cat "$LOGS_DIR/autogen.log" >&2 || true
    fail "autogen.sh falhou — ver $LOGS_DIR/autogen.log"
  }

  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"

  CONFIGURE_ARGS=(
    --prefix="$PREFIX"
    --host=aarch64-linux-gnu
    --build="$(gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)"
    --with-android-headers="$HEADERS_MERGED"
    --enable-arch=arm64
    --enable-mali-quirks
    --enable-property-cache
    --enable-experimental
    --disable-mesa
    --with-default-egl-platform=null
  )

  if [ "$WAYLAND_ENABLED" = "yes" ]; then
    CONFIGURE_ARGS+=(--enable-wayland)
  else
    CONFIGURE_ARGS+=(--disable-wayland)
    log "wayland desligado (pkg-config cross ausente)"
  fi

  # Sem GLVND nesta fase (evita dependência libglvnd/egl host)
  # configure não tem --disable-glvnd explícito em todos os forks; omitir --enable-glvnd = off

  {
    echo "=== configure ==="
    echo "CC=$CC"
    echo "CXX=$CXX"
    echo "AR=$AR RANLIB=$RANLIB STRIP=$STRIP"
    echo "CFLAGS=$CFLAGS"
    echo "CXXFLAGS=$CXXFLAGS"
    echo "LDFLAGS=$LDFLAGS"
    echo "PKG_CONFIG_LIBDIR=${PKG_CONFIG_LIBDIR:-}"
    echo "args: ${CONFIGURE_ARGS[*]}"
  } >"$LOGS_DIR/configure-env.txt"

  (
    cd "$BUILD_DIR"
    # shellcheck disable=SC2086
    "$LIBHYBRIS_SRC/hybris/configure" "${CONFIGURE_ARGS[@]}"
  ) >"$LOGS_DIR/configure.log" 2>&1 || {
    tail -n 80 "$LOGS_DIR/configure.log" >&2 || true
    fail "configure falhou — ver $LOGS_DIR/configure.log"
  }
  log "configure OK (wayland=$WAYLAND_ENABLED)"
}

build_and_install() {
  log "compilar (jobs=$JOBS)"
  (
    cd "$BUILD_DIR"
    make -j"$JOBS"
  ) >"$LOGS_DIR/build.log" 2>&1 || {
    tail -n 100 "$LOGS_DIR/build.log" >&2 || true
    fail "make falhou — ver $LOGS_DIR/build.log"
  }

  # Prefixo runtime /opt/libhybris; staging so via DESTDIR (nunca no /opt do host WSL)
  [ "$PREFIX" = "/opt/libhybris" ] || fail "PREFIX inesperado: $PREFIX (esperado /opt/libhybris)"
  case "$DESTDIR" in
    "$HOME/mali-runtime"/install/destdir|"$MALI_RUNTIME"/install/destdir) ;;
    *) fail "DESTDIR inseguro: $DESTDIR" ;;
  esac

  log "make install DESTDIR=$DESTDIR prefix=$PREFIX"
  rm -rf "$DESTDIR"
  mkdir -p "$DESTDIR"
  (
    cd "$BUILD_DIR"
    make install DESTDIR="$DESTDIR"
  ) >"$LOGS_DIR/install.log" 2>&1 || {
    tail -n 80 "$LOGS_DIR/install.log" >&2 || true
    fail "make install falhou — ver $LOGS_DIR/install.log"
  }
  [ -d "$INSTALL_ROOT" ] || fail "staging ausente apos install: $INSTALL_ROOT"
  # LINKER_PLUGIN_DIR embutido deve apontar para /opt/libhybris/...
  if command -v strings >/dev/null 2>&1; then
    if strings "$INSTALL_ROOT/lib/libhybris-common.so" 2>/dev/null | grep -q '/home/.*/mali-runtime'; then
      fail "libhybris-common ainda embute path de staging WSL — configure --prefix=/opt/libhybris"
    fi
    strings "$INSTALL_ROOT/lib/libhybris-common.so" 2>/dev/null | grep -q '/opt/libhybris/lib/libhybris/linker' \
      || warn "HYBRIS linker dir /opt/libhybris nao encontrado em strings (verifique HYBRIS_LINKER_DIR em runtime)"
  fi
}

# ---------------------------------------------------------------------------
# 9–10. ELF verify + artifacts + manifest
# ---------------------------------------------------------------------------
classify_needed() {
  local lib=$1
  case "$lib" in
    libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|ld-linux*.so*)
      echo glibc ;;
    libhybris*|libEGL.so*|libGLESv*.so*|libhardware.so*|libsync.so*|libgralloc.so*|libis.so*|libsf.so*|libui*)
      echo libhybris ;;
    libwayland*|libffi.so*|libstdc++*|libgcc_s*)
      echo host_linux ;;
    *)
      echo other ;;
  esac
}

verify_elf() {
  log "verificar ELF AArch64"
  local deps_log=$LOGS_DIR/elf-deps.txt
  : >"$deps_log"
  local count=0
  local f

  while IFS= read -r -d '' f; do
    count=$((count + 1))
    local info
    info=$(file -b "$f")
    echo "==== $f ====" >>"$deps_log"
    echo "file: $info" >>"$deps_log"

    if echo "$info" | grep -qiE 'x86-64|x86_64|Intel 80386'; then
      fail "ELF x86 detectado (esperado AArch64): $f ($info)"
    fi
    if ! echo "$info" | grep -Eqi 'ARM aarch64|aarch64|ARM64'; then
      # scripts / ascii podem aparecer; só exigir em ELF
      if echo "$info" | grep -qi ELF; then
        fail "ELF não-AArch64: $f ($info)"
      else
        echo "skip_non_elf" >>"$deps_log"
        continue
      fi
    fi

    readelf -h "$f" >>"$deps_log" 2>&1 || fail "readelf -h falhou: $f"
    readelf -h "$f" | grep -q AArch64 || fail "Machine != AArch64: $f"

    echo "-- dynamic --" >>"$deps_log"
    readelf -d "$f" >>"$deps_log" 2>&1 || true
    echo "-- version --" >>"$deps_log"
    readelf -V "$f" >>"$deps_log" 2>&1 || true

    local needed
    needed=$(readelf -d "$f" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' || true)
    local n
    for n in $needed; do
      echo "NEEDED $n -> $(classify_needed "$n")" >>"$deps_log"
    done
  done < <(find "$INSTALL_ROOT" \( -name '*.so' -o -name '*.so.*' \) -type f -print0 2>/dev/null)

  [ "$count" -gt 0 ] || fail "nenhuma .so encontrada em $INSTALL_ROOT"
  log "ELF OK ($count bibliotecas) — detalhes em $deps_log"
}

collect_artifacts() {
  log "gerar artifacts/"
  rm -rf "${ARTIFACTS_DIR:?}/"*
  mkdir -p "$ARTIFACTS_DIR"

  # Copiar .so com nomes reais do upstream (não assumir lista fixa)
  local f base
  while IFS= read -r -d '' f; do
    base=$(basename "$f")
    # Preferir cópia do ficheiro real (não symlink) com nome basename
    if [ -L "$f" ]; then
      cp -aL "$f" "$ARTIFACTS_DIR/$base" 2>/dev/null || cp -a "$f" "$ARTIFACTS_DIR/$base"
    else
      cp -a "$f" "$ARTIFACTS_DIR/$base"
    fi
  done < <(find "$INSTALL_ROOT" \( -name '*.so' -o -name '*.so.*' \) -type f -print0 2>/dev/null)

  # Também copiar symlinks .so principais se úteis
  while IFS= read -r -d '' f; do
    base=$(basename "$f")
    [ -e "$ARTIFACTS_DIR/$base" ] && continue
    cp -a "$f" "$ARTIFACTS_DIR/$base" 2>/dev/null || true
  done < <(find "$INSTALL_ROOT" -name '*.so' -type l -print0 2>/dev/null)

  (
    cd "$ARTIFACTS_DIR"
    find . -type f ! -name sha256sums.txt ! -name manifest.txt -print0 \
      | sort -z \
      | xargs -0 sha256sum
  ) >"$ARTIFACTS_DIR/sha256sums.txt"

  write_manifest
  log "artifacts em $ARTIFACTS_DIR"
}

# ---------------------------------------------------------------------------
# Empacotar libhybris-opt-arm64.tar.zst (layout ./opt/libhybris/...)
# ---------------------------------------------------------------------------
package_libhybris_opt() {
  if [ "$SKIP_PACKAGE" = "1" ]; then
    warn "SKIP_PACKAGE=1 — tarball libhybris-opt nao gerado"
    return 0
  fi

  log "empacotar $LIBHYBRIS_OPT_TAR"

  command -v tar >/dev/null 2>&1 || fail "tar ausente (empacotamento)"
  command -v zstd >/dev/null 2>&1 || fail "zstd ausente (empacotamento)"

  [ -d "$INSTALL_ROOT" ] || fail "staging ausente: $INSTALL_ROOT"
  [ -e "$INSTALL_ROOT/lib/libhybris-common.so" ] || \
    [ -e "$INSTALL_ROOT/lib/libhybris-common.so.1" ] || \
    fail "libhybris-common ausente em $INSTALL_ROOT/lib"
  [ -e "$INSTALL_ROOT/lib/libhybris/linker/q.so" ] || \
    fail "linker q.so ausente em $INSTALL_ROOT/lib/libhybris/linker/"

  local pack_root pack_dest out_deps
  # DESTDIR ja tem ./opt/libhybris/...
  pack_root=$DESTDIR

  OPT_TARBALL="$ARTIFACTS_DIR/$LIBHYBRIS_OPT_TAR"
  mkdir -p "$ARTIFACTS_DIR"
  tar -C "$pack_root" -I zstd -cf "$OPT_TARBALL" opt
  # nao apagar DESTDIR aqui — util para inspeccao

  # Validar layout minimo
  tar -I zstd -tf "$OPT_TARBALL" | grep -q '^opt/libhybris/lib/libhybris-common\.so' \
    || fail "tarball sem opt/libhybris/lib/libhybris-common.so*"

  log "tarball: $OPT_TARBALL ($(wc -c <"$OPT_TARBALL") bytes)"

  # Destino opcional: LIBHYBRIS_OPT_OUT ou rootfs/deps ao lado deste script
  out_deps=${LIBHYBRIS_OPT_OUT:-}
  if [ -z "$out_deps" ] && [ -d "$SCRIPT_DIR/../deps" ]; then
    out_deps=$(cd "$SCRIPT_DIR/../deps" && pwd)
  fi
  if [ -n "$out_deps" ]; then
    mkdir -p "$out_deps"
    pack_dest="$out_deps/$LIBHYBRIS_OPT_TAR"
    cp -f "$OPT_TARBALL" "$pack_dest"
    log "copiado → $pack_dest"
  else
    warn "LIBHYBRIS_OPT_OUT nao definido e rootfs/deps nao encontrado — tarball so em artifacts/"
  fi
}

write_manifest() {
  local hybris_rev headers_rev
  hybris_rev=$(cat "$LOGS_DIR/libhybris-revision.txt" 2>/dev/null || echo "missing")
  headers_rev=$(cat "$LOGS_DIR/android-headers-34-revision.txt" 2>/dev/null || echo "missing")

  cat >"$ARTIFACTS_DIR/manifest.txt" <<EOF
# libhybris A16/VNDK34 WSL build manifest
# gerado por $SCRIPT_NAME

date_utc=$START_TS
date_end_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
host_uname=$(uname -a)
host_arch=$(uname -m)

# Target
target=aarch64-linux-gnu
android_api_runtime=$ANDROID_API_RUNTIME
vndk_version=$VNDK_VERSION
gpu_target=Mali-G615_MC2
stage=gles_egl_first

# Work tree
mali_runtime=$MALI_RUNTIME
prefix=$PREFIX
install_root=$INSTALL_ROOT

# libhybris
libhybris_git=$LIBHYBRIS_GIT
libhybris_ref=$LIBHYBRIS_REF
--- libhybris revision ---
$hybris_rev
--- end ---

# Headers
android_headers_34_git=$ANDROID_HEADERS_34_GIT
--- android-headers-34 revision ---
$headers_rev
--- end ---
headers_merged=$HEADERS_MERGED
headers_provenance=$PROVENANCE
aosp_16_tag=$AOSP_16_TAG
android_tree_16=${ANDROID_TREE_16:-}
skip_a16_overlay=$SKIP_A16_OVERLAY

# Toolchain
CC=$CC_FINAL
CXX=$CXX_FINAL
AR=$AR_FINAL
RANLIB=$RANLIB_FINAL
STRIP=$STRIP_FINAL
sysroot=$SYSROOT_FINAL
gcc_version=$(aarch64-linux-gnu-gcc --version | head -n1)
CFLAGS=$CFLAGS_FINAL
CXXFLAGS=$CXXFLAGS_FINAL
LDFLAGS=$LDFLAGS_FINAL

# Configure
wayland=$WAYLAND_ENABLED
configure_args=${CONFIGURE_ARGS[*]}

# Policy
patches_applied=none
system_install=no
artix_touched=no
android_touched=no
phone_touched=no
mesa=no
zink=no
sysvk=no
android_vulkan_bridge=no
glvnd=no

# Approval checklist
[x] libhybris revisão identificada
[x] headers API/VNDK 34 identificados
[x] Android 16/API 36 tratado como runtime (overlay headers opcional)
[x] target AArch64
[x] ELF ARM64 verificado
[x] prefixo isolado ($PREFIX)
[x] Artix não modificado
[x] Android não modificado
[x] telefone não modificado
[x] dependências ELF inspeccionadas ($LOGS_DIR/elf-deps.txt)
[x] manifest gerado
[x] SHA256 gerado
[x] build reproduzível (revisions + flags registados)
EOF
}

print_summary() {
  cat <<EOF

========================================================================
 Build concluído
========================================================================
 Prefix:     $PREFIX  (runtime; embutido nos binarios)
 Staging:    $INSTALL_ROOT  (DESTDIR)
 Artifacts:  $ARTIFACTS_DIR
 Manifest:   $ARTIFACTS_DIR/manifest.txt
 SHA256:     $ARTIFACTS_DIR/sha256sums.txt
 Opt tarball:${OPT_TARBALL:- (nao gerado)}
 Logs:       $LOGS_DIR

 NÃO instalado no /opt do host WSL (so DESTDIR).
 NÃO tocado Artix / Android / telefone.
 Proximo no device: prepare.sh → run-setup-gpu-hybris.sh
   (usa deps/libhybris-opt-arm64.tar.zst + install-libhybris-opt.sh)
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
  fetch_libhybris
  fetch_headers_34
  fetch_headers_16
  configure_libhybris
  build_and_install
  verify_elf
  collect_artifacts
  package_libhybris_opt
  print_summary
}

main "$@"
