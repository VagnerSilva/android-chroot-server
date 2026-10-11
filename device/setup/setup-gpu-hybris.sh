#!/bin/bash
# ============================================================
# setup-gpu-hybris.sh — DENTRO do chroot Artix
# GLES-first: libhybris-opt (tarball) + /opt/android-mali + libGLES_mali.so
# Runtime-only — SEM makepkg / base-devel / compile no device.
# Vulkan (sysvk-opt tarball) apenas apos /etc/artix-gpu-gles.ok
#
# Prefixo runtime: /opt/libhybris + /opt/android-mali
# Mounts /mnt/{system,vendor,apex} so para EXTRAÇÃO.
# Sem Panfrost, sem renderD128, sem GLVND hybris global.
# ============================================================
set -Eeuo pipefail

HYBRIS_PREFIX=${HYBRIS_PREFIX:-/opt/libhybris}
ANDROID_MALI=${ANDROID_MALI:-/opt/android-mali}
LIBC_PATH=${LIBC_PATH:-/apex/com.android.runtime/lib64/bionic/libc.so}
LIBC_URL=${LIBC_URL:-https://github.com/Linux-on-droid/vendor_lindroid/raw/lindroid-22.1/prebuilt/arm64/libc.so}
# Vulkan: auto = so se sysvk-opt tarball + vulkan.mali.so existirem
GPU_BUILD_SYSVK=${GPU_BUILD_SYSVK:-auto}

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${HYBRIS_PREFIX}/bin:${HYBRIS_PREFIX}/usr/bin

fail() {
    echo "!! $*" >&2
    exit 1
}

trap 'echo "!! falha na linha $LINENO: $BASH_COMMAND" >&2' ERR

[ "$(id -u)" -eq 0 ] || fail "execute como root"
uname -m | grep -qx aarch64 || fail "arquitetura diferente de aarch64"

for x in pacman bash tar sed awk grep find ldconfig; do
    command -v "$x" >/dev/null 2>&1 || fail "comando ausente: $x"
done

echo ">> setup GPU GLES-first (libhybris + /opt/android-mali)"

# Fontes Android para EXTRAÇÃO (nao requisito runtime)
mkdir -p /mnt/apex /mnt/system /mnt/system_ext /mnt/vendor "$ANDROID_MALI" "$HYBRIS_PREFIX" /apex

VENDOR_SRC=/mnt/vendor
[ -d "$VENDOR_SRC/lib64" ] || VENDOR_SRC=/vendor
SYSTEM_SRC=/mnt/system
[ -d "$SYSTEM_SRC/lib64" ] || SYSTEM_SRC=/system
SYSTEM_EXT_SRC=/mnt/system_ext
[ -d "$SYSTEM_EXT_SRC/lib64" ] || SYSTEM_EXT_SRC=/system_ext
APEX_SRC=/mnt/apex
[ -d "$APEX_SRC/com.android.runtime" ] || APEX_SRC=/apex

# ---------- GATE 0: pacman sync + Qk ----------
echo "=== GATE 0: ARTIX RUNTIME ==="

require_libgcc() {
    local where=$1
    if [ -e /usr/lib/libgcc_s.so.1 ] || [ -e /usr/lib64/libgcc_s.so.1 ]; then
        return 0
    fi
    fail "libgcc_s.so.1 ausente ($where) — no host: /data/linux/repair-libgcc.sh (sem wipe)"
}

require_libgcc "antes do setup GPU"
# pacman/eglinfo precisam de libgcc_s; testar o binario, nao so -V
pacman -V >/dev/null 2>&1 || fail "pacman nao funciona — YES=1 /data/linux/wipe-chroot.sh && /data/linux/bootstrap.sh"

echo "=== GATE 0: CURL ABI ==="
if [ -e /usr/lib/libcurl.so.4 ]; then
    ldd /usr/lib/libcurl.so.4 2>/dev/null | grep -E 'ngtcp2|nghttp|ssl|crypto' || true
    if [ -e /usr/lib/libngtcp2.so ] || [ -e /usr/lib/libngtcp2.so.16 ]; then
        SO=/usr/lib/libngtcp2.so.16
        [ -e "$SO" ] || SO=/usr/lib/libngtcp2.so
        if ! (nm -D "$SO" 2>/dev/null || readelf -Ws "$SO" 2>/dev/null) | grep -q 'ngtcp2_conn_get_tls_early_data_rejected2'; then
            echo "!! aviso: libngtcp2 sem ngtcp2_conn_get_tls_early_data_rejected2"
            echo "   se pacman -Sy falhar: wipe-chroot + bootstrap (rootfs inconsistente)"
        fi
    fi
fi

# Chroot partilha o kernel do telefone — nunca actualizar linux/mkinitcpio.
if [ -f /etc/pacman.conf ]; then
    sed -i '/^IgnorePkg /d' /etc/pacman.conf
    sed -i '/^DisableHooks /d' /etc/pacman.conf
    if grep -q '^\[options\]' /etc/pacman.conf; then
        awk '
          BEGIN { done=0 }
          /^\[options\]/ && !done {
            print
            print "IgnorePkg = linux-aarch64 linux-aarch64-lts linux-aarch64-headers linux-firmware mkinitcpio mkinitcpio-busybox"
            done=1
            next
          }
          { print }
        ' /etc/pacman.conf > /etc/pacman.conf.tmp && mv /etc/pacman.conf.tmp /etc/pacman.conf
    fi
    echo ">> pacman: IgnorePkg kernel/mkinitcpio"
fi

echo "=== GATE 0: RUNTIME PKGS (pacman -Sy --needed — SEM -Syu / SEM kernel) ==="
# Arch/ARMtix: gcc-libs e meta; libgcc_s.so.1 / libstdc++.so.6 vem de libgcc + libstdc++.
# Instalar na MESMA transacao que o meta, senao o upgrade remove as .so sem as repor.
if ! pacman -Sy --noconfirm --needed libgcc libstdc++ gcc-libs; then
    fail "pacman -Sy libgcc/libstdc++/gcc-libs falhou — rootfs inconsistente: YES=1 /data/linux/wipe-chroot.sh && /data/linux/bootstrap.sh"
fi
require_libgcc "apos pacman -Sy libgcc"

if ! pacman -S --noconfirm --needed \
    curl \
    libngtcp2 \
    libnghttp2 \
    libnghttp3 \
    openssl \
    glibc \
    ca-certificates \
    binutils \
    tar \
    zstd \
    libx11 \
    libxcb \
    libxshmfence \
    libdrm \
    libxml2 \
    mesa-utils \
    libglvnd \
    xcb-util-wm \
    xcb-util-keysyms; then
    fail "pacman -S runtime falhou (rede, mirror ou pacote em falta) — reveja a mao"
fi
require_libgcc "apos pacman -S runtime"
ldconfig 2>/dev/null || true

# Vulkan loader so se houver tarball sysvk (Fase F); evita puxar stack Vulkan cedo.
# vulkan-tools: hooks/post-install no chroot sem init completo podem "parar" apos 100%.
pacman_noconfirm() {
    # stdin fechado: nunca bloquear em Proceed with installation? / hooks interactivos
    pacman "$@" </dev/null
}

# Corre comando com timeout; rc=124 = timeout (GNU timeout) ou 143 = SIGTERM.
run_with_timeout() {
    local secs=$1
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout -k 10 "$secs" "$@"
        return $?
    fi
    # Fallback sem coreutils timeout
    "$@" &
    local pid=$!
    local i=0
    while [ "$i" -lt "$secs" ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid"
            return $?
        fi
        sleep 1
        i=$((i + 1))
    done
    echo "!! timeout ${secs}s — a matar PID $pid ($*)" >&2
    kill -TERM "$pid" 2>/dev/null || true
    sleep 2
    kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 124
}

# Garante vulkaninfo para o teste Fase F. Decide sozinho: skip / install c/ timeout / seguir ou falhar.
# Sucesso = binario presente (nao "pacman saiu 0" — hooks podem mentir/travar).
ensure_vulkaninfo() {
    if command -v vulkaninfo >/dev/null 2>&1; then
        echo ">> vulkaninfo ja presente — skip pacman vulkan-tools"
        return 0
    fi
    local to="${PACMAN_VULKAN_TOOLS_TIMEOUT:-120}"
    local hooks
    hooks=$(mktemp -d /tmp/pacman-hooks-empty.XXXXXX 2>/dev/null || mktemp -d)
    echo ">> instalar vulkan-tools (timeout=${to}s, --hookdir vazio — evita hang pos-100%)"
    set +e
    run_with_timeout "$to" pacman -S --noconfirm --needed --hookdir "$hooks" vulkan-tools </dev/null
    local rc=$?
    set -e
    rmdir "$hooks" 2>/dev/null || true
    # Pacote pode ter ficado no disco mesmo com timeout nos hooks
    if command -v vulkaninfo >/dev/null 2>&1; then
        if [ "$rc" = 124 ] || [ "$rc" = 143 ]; then
            echo ">> vulkaninfo OK apesar de timeout/hooks (rc=$rc) — a continuar"
        else
            echo ">> vulkaninfo OK apos pacman (rc=$rc)"
        fi
        ldconfig 2>/dev/null || true
        return 0
    fi
    echo "!! vulkan-tools: sem vulkaninfo (pacman rc=$rc)"
    return 1
}

if ls /root/sysvk-opt-*.tar.zst >/dev/null 2>&1 || [ -n "${SYSVK_TAR:-}" ]; then
    echo "=== GATE 0: vulkan runtime (sysvk presente) ==="
    if pacman_noconfirm -S --noconfirm --needed vulkan-icd-loader; then
        echo ">> vulkan-icd-loader OK (vulkan-tools na Fase F)"
    else
        echo "!! aviso: vulkan-icd-loader falhou — GLES continua; Vulkan na Fase F pode falhar"
    fi
    require_libgcc "apos pacman vulkan"
fi

# Mesa 25.1.2 sob /opt/android-mali (evita Mesa >=26 — free(): invalid pointer)
echo "=== GATE 0: mesa25 overlay ==="
if [ -f /root/install-mesa25-android-mali.sh ]; then
    /bin/bash /root/install-mesa25-android-mali.sh || \
        fail "install-mesa25-android-mali falhou"
else
    fail "install-mesa25-android-mali.sh ausente em /root (deps/ + run-setup-gpu-hybris)"
fi

echo "=== GATE 0: ferramentas runtime ==="
for x in readelf tar zstd; do
    command -v "$x" >/dev/null 2>&1 || fail "comando ausente apos pacman -Sy: $x"
done

echo "=== GATE 0: pacman -Qk ==="
require_libgcc "antes de pacman -Qk"
set +e
pacman -Qk >/tmp/pacman-qk.txt 2>&1
QK_RC=$?
set -e
# rc=127 = loader/shared lib partido (ex. libgcc_s) — nunca continuar
if [ "$QK_RC" = 127 ] || grep -q 'libgcc_s\.so' /tmp/pacman-qk.txt 2>/dev/null; then
    cat /tmp/pacman-qk.txt 2>/dev/null || true
    fail "pacman quebrado (libgcc_s) — YES=1 /data/linux/wipe-chroot.sh && /data/linux/bootstrap.sh"
fi
if [ "$QK_RC" != 0 ]; then
    echo "!! pacman -Qk reportou problemas (rc=$QK_RC):"
    head -n 40 /tmp/pacman-qk.txt || true
    MISS=$(grep -c 'warning:.*file.*is missing' /tmp/pacman-qk.txt 2>/dev/null || true)
    MISS=${MISS:-0}
    if [ "$MISS" -gt 50 ] 2>/dev/null; then
        fail "pacman -Qk: demasiados ficheiros em falta ($MISS) — ABORT GPU"
    fi
    echo ">> pacman -Qk: $MISS avisos (continuando; revise se GPU falhar)"
else
    echo ">> pacman -Qk OK"
fi

chmod 644 /etc/pacman.conf 2>/dev/null || true
chmod 755 /etc /etc/pacman.d 2>/dev/null || true
chmod 644 /etc/pacman.d/* 2>/dev/null || true

curl --version >/dev/null 2>&1 || fail "curl quebrado apos sincronizacao"
require_libgcc "apos GATE 0"

# ---------- GATE 1: preflight ----------
echo "=== GATE 1: PREFLIGHT MALI ==="
[ -e /dev/mali0 ] || fail "/dev/mali0 ausente"
[ -e /sys/class/misc/mali0 ] || echo ">> aviso: /sys/class/misc/mali0 ausente"
[ -d /sys/bus/platform/drivers/mali ] || echo ">> aviso: /sys/bus/platform/drivers/mali ausente"
[ -e /dev/dri/card0 ] || echo ">> aviso: /dev/dri/card0 ausente (mediatek-drm)"

if [ -d /sys/class/drm ]; then
    if ls /sys/class/drm/renderD* >/dev/null 2>&1; then
        echo ">> render node presente: $(ls /sys/class/drm/renderD* 2>/dev/null | tr '\n' ' ')"
    else
        echo ">> info: sem /sys/class/drm/renderD* (esperado — nao criar renderD128; sem Panfrost)"
    fi
fi

GLES_SO=""
for c in \
    "$VENDOR_SRC/lib64/egl/mt6878/libGLES_mali.so" \
    "$VENDOR_SRC/lib64/egl/libGLES_mali.so" \
    /mnt/vendor/lib64/egl/mt6878/libGLES_mali.so \
    /vendor/lib64/egl/mt6878/libGLES_mali.so
do
    [ -f "$c" ] && GLES_SO=$c && break
done
[ -n "$GLES_SO" ] || fail "libGLES_mali.so ausente sob $VENDOR_SRC (monte /mnt/vendor)"

VULKAN_SO=""
for c in \
    "$VENDOR_SRC/lib64/hw/mt6878/vulkan.mali.so" \
    "$VENDOR_SRC/lib64/hw/vulkan.mali.so" \
    /mnt/vendor/lib64/hw/mt6878/vulkan.mali.so \
    /vendor/lib64/hw/vulkan.mali.so
do
    [ -f "$c" ] && VULKAN_SO=$c && break
done
[ -n "$VULKAN_SO" ] || echo ">> aviso: vulkan.mali.so ausente (Vulkan so na Fase F)"

readelf -h "$GLES_SO" | grep -q 'AArch64' || fail "libGLES_mali nao e AArch64: $GLES_SO"
echo ">> GLES_SO=$GLES_SO"
[ -n "$VULKAN_SO" ] && echo ">> VULKAN_SO=$VULKAN_SO"

# ---------- Bionic apex (copia para /opt e /apex staging) ----------
echo "=== APEX / BIONIC (staging) ==="
[ -d "$APEX_SRC/com.android.runtime" ] || [ -d /apex/com.android.runtime ] || \
    fail "com.android.runtime ausente em $APEX_SRC — monte /mnt/apex"

copy_apex() {
    local name=$1
    local src=""
    local d=""
    if [ -d "$APEX_SRC/$name" ]; then
        src=$APEX_SRC/$name
    else
        for d in "$APEX_SRC/$name"@*; do
            [ -d "$d" ] || continue
            src=$d
            break
        done
    fi
    [ -n "$src" ] || return 0
    mkdir -p "$ANDROID_MALI/apex" /apex
    local base
    base=$(basename "$src" | sed 's/@.*//')
    if [ ! -d "$ANDROID_MALI/apex/$(basename "$src")" ]; then
        echo ">> a copiar apex $(basename "$src") → $ANDROID_MALI/apex/"
        cp -a "$src" "$ANDROID_MALI/apex/$(basename "$src")"
    fi
    [ -e "$ANDROID_MALI/apex/$base" ] || \
        ln -sfn "$(basename "$src")" "$ANDROID_MALI/apex/$base"
    # staging /apex para patch Bionic libc (libhybris)
    if [ ! -d "/apex/$(basename "$src")" ]; then
        cp -a "$src" "/apex/$(basename "$src")"
    fi
    [ -e "/apex/$base" ] || ln -sfn "$(basename "$src")" "/apex/$base"
}

copy_apex com.android.runtime
copy_apex com.android.i18n
copy_apex com.android.art
copy_apex com.android.vndk.v34
copy_apex com.android.vndk.v33
copy_apex com.android.vndk.v31

[ -f "$LIBC_PATH" ] || fail "Bionic libc ausente: $LIBC_PATH"

if [ ! -f "${LIBC_PATH}.bak" ]; then
    cp -a "$LIBC_PATH" "${LIBC_PATH}.bak"
fi

if [ "${GPU_REPATCH_LIBC:-1}" = 1 ]; then
    echo "=== BIONIC libc patch (Lindroid) ==="
    tmp=$(mktemp)
    DL_OK=0
    if [ -f /root/libc-hybris.so ]; then
        cp /root/libc-hybris.so "$tmp" && DL_OK=1
    fi
    if [ "$DL_OK" != 1 ]; then
        curl -fL --retry 3 --connect-timeout 15 -o "$tmp" "$LIBC_URL" && DL_OK=1
    fi
    [ "$DL_OK" = 1 ] && [ -s "$tmp" ] || fail "download da Bionic falhou"
    readelf -h "$tmp" | grep -q 'AArch64' || fail "libc Bionic baixada nao e AArch64"
    cp -f "$tmp" "$LIBC_PATH"
    chmod 644 "$LIBC_PATH"
    # espelhar para /opt/android-mali
    mkdir -p "$ANDROID_MALI/apex/com.android.runtime/lib64/bionic"
    cp -f "$tmp" "$ANDROID_MALI/apex/com.android.runtime/lib64/bionic/libc.so"
    rm -f "$tmp"
fi

# ---------- GATE 2: libhybris-opt overlay (sem compile) ----------
echo "=== GATE 2: libhybris-opt (tarball offline) ==="
if [ -f /root/install-libhybris-opt.sh ]; then
    /bin/bash /root/install-libhybris-opt.sh || fail "install-libhybris-opt falhou"
else
    fail "install-libhybris-opt.sh ausente em /root (deps/ + run-setup-gpu-hybris)"
fi
[ -f /etc/artix-libhybris.ok ] || fail "marker /etc/artix-libhybris.ok ausente apos install"

# ---------- GATE 3: /opt/android-mali tree (deps ELF) ----------
echo "=== GATE 3: /opt/android-mali (deps ELF selectivas) ==="

mkdir -p \
    "$ANDROID_MALI/system/lib64" \
    "$ANDROID_MALI/system_ext/lib64" \
    "$ANDROID_MALI/vendor/lib64/egl/mt6878" \
    "$ANDROID_MALI/vendor/lib64/hw/mt6878" \
    "$ANDROID_MALI/bin" \
    "$ANDROID_MALI/properties"

# linker64 — copiar para bin isolado (NAO /usr/lib)
if [ -f "$SYSTEM_SRC/bin/linker64" ]; then
    cp -a "$SYSTEM_SRC/bin/linker64" "$ANDROID_MALI/bin/linker64"
elif [ -f /system/bin/linker64 ]; then
    cp -a /system/bin/linker64 "$ANDROID_MALI/bin/linker64"
fi

# Nunca sobrescrever estas no Artix
is_forbidden_artix_overwrite() {
    case "$1" in
        libc.so|libc.so.*|libm.so|libm.so.*|libdl.so|libdl.so.*|libc++.so|libc++.so.*)
            return 0
            ;;
    esac
    return 1
}

find_android_lib() {
    local name=$1
    local d
    for d in \
        "$VENDOR_SRC/lib64/egl/mt6878" \
        "$VENDOR_SRC/lib64/egl" \
        "$VENDOR_SRC/lib64/hw/mt6878" \
        "$VENDOR_SRC/lib64/hw" \
        "$VENDOR_SRC/lib64/mt6878" \
        "$VENDOR_SRC/lib64" \
        "$SYSTEM_SRC/lib64" \
        "$SYSTEM_EXT_SRC/lib64" \
        /vendor/lib64/mt6878 \
        /vendor/lib64 \
        /system_ext/lib64 \
        /mnt/system_ext/lib64 \
        /odm/lib64 \
        /apex/com.android.vndk.v34/lib64 \
        /apex/com.android.vndk.v34@1/lib64 \
        /apex/com.android.runtime/lib64/bionic \
        "$APEX_SRC/com.android.vndk.v34/lib64" \
        "$APEX_SRC/com.android.runtime/lib64/bionic"
    do
        [ -d "$d" ] || continue
        # Preferir ficheiro real (nao symlink partido para mt6878/...)
        if [ -f "$d/$name" ] && [ ! -L "$d/$name" ]; then
            echo "$d/$name"
            return 0
        fi
    done
    # symlinks ok se o alvo existir
    for d in \
        "$VENDOR_SRC/lib64/mt6878" \
        "$VENDOR_SRC/lib64" \
        "$VENDOR_SRC/lib64/egl/mt6878" \
        "$SYSTEM_SRC/lib64" \
        "$SYSTEM_EXT_SRC/lib64" \
        /vendor/lib64/mt6878 \
        /vendor/lib64 \
        /system_ext/lib64
    do
        [ -d "$d" ] || continue
        if [ -e "$d/$name" ]; then
            echo "$d/$name"
            return 0
        fi
    done
    # pesquisa ampla — ficheiro real primeiro
    local hit
    hit=$(find "$VENDOR_SRC/lib64" "$SYSTEM_SRC/lib64" "$SYSTEM_EXT_SRC/lib64" \
        /vendor/lib64 /system_ext/lib64 /mnt/system_ext/lib64 /odm/lib64 \
        -type f -name "$name" 2>/dev/null | head -n1) || true
    [ -n "$hit" ] && { echo "$hit"; return 0; }
    hit=$(find "$VENDOR_SRC/lib64" "$SYSTEM_SRC/lib64" "$SYSTEM_EXT_SRC/lib64" \
        /vendor/lib64 /system_ext/lib64 /mnt/system_ext/lib64 /odm/lib64 \
        -name "$name" 2>/dev/null | head -n1) || true
    [ -n "$hit" ] && [ -e "$hit" ] && { echo "$hit"; return 0; }
    return 1
}

dest_for_android_lib() {
    local src=$1
    local name
    name=$(basename "$src")
    case "$src" in
        */vendor/lib64/egl/*)
            echo "$ANDROID_MALI/vendor/lib64/egl/mt6878/$name"
            ;;
        */vendor/lib64/hw/*)
            echo "$ANDROID_MALI/vendor/lib64/hw/mt6878/$name"
            ;;
        */vendor/lib64/mt6878/*)
            echo "$ANDROID_MALI/vendor/lib64/$name"
            ;;
        */vendor/*)
            echo "$ANDROID_MALI/vendor/lib64/$name"
            ;;
        */system_ext/*)
            echo "$ANDROID_MALI/system_ext/lib64/$name"
            ;;
        */apex/*)
            # manter sob apex tree
            local rel
            rel=$(echo "$src" | sed -n 's|.*/apex/||p')
            if [ -n "$rel" ]; then
                echo "$ANDROID_MALI/apex/$rel"
            else
                echo "$ANDROID_MALI/system/lib64/$name"
            fi
            ;;
        *)
            echo "$ANDROID_MALI/system/lib64/$name"
            ;;
    esac
}

copy_lib_selective() {
    local src=$1
    local name dest real
    name=$(basename "$src")
    # Sempre materializar o ELF real (cp -a de symlink relativo parte no destino)
    if [ -L "$src" ]; then
        real=$(readlink -f "$src" 2>/dev/null || true)
        if [ -n "$real" ] && [ -f "$real" ]; then
            src=$real
        else
            echo "  ! symlink partido ignorado: $name"
            return 0
        fi
    fi
    dest=$(dest_for_android_lib "$src")
    mkdir -p "$(dirname "$dest")"
    if [ -f "$dest" ] && [ ! -L "$dest" ]; then
        return 0
    fi
    # Substituir symlink partido se existir
    rm -f "$dest"
    echo "  + $name → $dest"
    cp -a "$src" "$dest"
}

# Resolver NEEDED recursivamente a partir de seed
resolve_elf_deps() {
    local seed=$1
    local max=${2:-80}
    local queue=("$seed")
    local seen=""
    local count=0
    local cur name deps dep src

    copy_lib_selective "$seed"

    while [ ${#queue[@]} -gt 0 ] && [ "$count" -lt "$max" ]; do
        cur=${queue[0]}
        queue=("${queue[@]:1}")
        count=$((count + 1))
        name=$(basename "$cur")
        case " $seen " in
            *" $name "*) continue ;;
        esac
        seen="$seen $name"

        deps=$(readelf -d "$cur" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p') || true
        for dep in $deps; do
            case " $seen " in
                *" $dep "*) continue ;;
            esac
            # skip libs tipicamente fornecidas pelo loader/hybris de forma especial
            case "$dep" in
                ld-android.so|libdl.so|libm.so|libc.so) ;;
            esac
            src=$(find_android_lib "$dep") || {
                echo "  ? dep nao encontrada: $dep (de $name)"
                continue
            }
            copy_lib_selective "$src"
            queue+=("$src")
        done
    done
    echo ">> deps resolvidas (~$count seeds processados)"
}

# Seeds de runtime carregados dinamicamente (dlopen) pelo stack Mali —
# nao aparecem no DT_NEEDED directo do HAL (ex.: libgpud_sys.so).
# Cada seed e depois expandido recursivamente via DT_NEEDED.
# Origem /system_ext/lib64 e raiz valida; destino preserva arvore Android.
seed_mali_runtime_libs() {
    local name src
    local seeds=${MALI_RUNTIME_SEEDS:-libgpud_sys.so}
    echo ">> seeds runtime Mali (dinamicos): $seeds"
    for name in $seeds; do
        src=$(find_android_lib "$name") || {
            echo "  ? seed runtime nao encontrada: $name"
            continue
        }
        echo "  * seed $name ← $src"
        resolve_elf_deps "$src" 160
    done
}

resolve_elf_deps "$GLES_SO" 100

# Copiar tambem libGLES para path canónico egl
mkdir -p "$ANDROID_MALI/vendor/lib64/egl/mt6878"
cp -a "$GLES_SO" "$ANDROID_MALI/vendor/lib64/egl/mt6878/libGLES_mali.so"
# symlink comum
ln -sfn mt6878/libGLES_mali.so "$ANDROID_MALI/vendor/lib64/egl/libGLES_mali.so" 2>/dev/null || true

# Mali unificado: so existe libGLES_mali.so; o linker Android (hybris q.so)
# procura libEGL.so / libGLESv2.so — symlinks no mesmo dir do HYBRIS_LD path.
EGL_DIR="$ANDROID_MALI/vendor/lib64/egl/mt6878"
for name in libEGL.so libGLESv1_CM.so libGLESv2.so; do
    ln -sfn libGLES_mali.so "$EGL_DIR/$name"
done
ln -sfn mt6878/libEGL.so "$ANDROID_MALI/vendor/lib64/egl/libEGL.so" 2>/dev/null || true
ln -sfn mt6878/libGLESv2.so "$ANDROID_MALI/vendor/lib64/egl/libGLESv2.so" 2>/dev/null || true
echo ">> Mali unificado: symlinks libEGL/libGLESv* → libGLES_mali.so"

# gralloc: ro.hardware.gralloc=common → gralloc.common.so
# libhardware Android usa paths absolutos /vendor/lib64/hw e $ANDROID_ROOT/lib64/hw
GRALLOC_SRC=""
for g in \
    "$VENDOR_SRC/lib64/hw/gralloc.default.so" \
    /vendor/lib64/hw/gralloc.default.so
do
    [ -f "$g" ] && GRALLOC_SRC=$g && break
done
if [ -n "$GRALLOC_SRC" ]; then
    for d in \
        "$ANDROID_MALI/vendor/lib64/hw/mt6878" \
        "$ANDROID_MALI/vendor/lib64/hw" \
        "$ANDROID_MALI/system/lib64/hw"
    do
        mkdir -p "$d"
        cp -a "$GRALLOC_SRC" "$d/gralloc.default.so"
        ln -sfn gralloc.default.so "$d/gralloc.common.so"
    done
    # chroot /vendor (se nao for bind do Android) — fallback HAL search
    if [ ! -e /vendor/lib64/hw/gralloc.default.so ]; then
        mkdir -p /vendor/lib64/hw
        cp -a "$GRALLOC_SRC" /vendor/lib64/hw/gralloc.default.so
        ln -sfn gralloc.default.so /vendor/lib64/hw/gralloc.common.so
    fi
    echo ">> gralloc.common.so ← gralloc.default.so"
else
    echo "!! aviso: gralloc.default.so ausente — GLES pode falhar no gralloc"
fi

# mapper.mediatek.so — WSI/AHB (vkcube) precisa do gralloc mapper HAL
MAPPER_SRC=""
for m in \
    "$VENDOR_SRC/lib64/hw/mt6878/mapper.mediatek.so" \
    "$VENDOR_SRC/lib64/hw/mapper.mediatek.so" \
    /vendor/lib64/hw/mt6878/mapper.mediatek.so \
    /vendor/lib64/hw/mapper.mediatek.so
do
    [ -f "$m" ] && MAPPER_SRC=$m && break
done
if [ -n "$MAPPER_SRC" ]; then
    for d in \
        "$ANDROID_MALI/vendor/lib64/hw/mt6878" \
        "$ANDROID_MALI/vendor/lib64/hw"
    do
        mkdir -p "$d"
        cp -a "$MAPPER_SRC" "$d/mapper.mediatek.so"
    done
    resolve_elf_deps "$MAPPER_SRC" 80
    echo ">> mapper.mediatek.so ← $MAPPER_SRC"
else
    echo "!! aviso: mapper.mediatek.so ausente — vkcube/WSI pode falhar"
fi

# AHB shim: ahb-wrapper faz hybris_dlopen("libandroid.so"); o libandroid
# completo puxa libgui/hwui e rebenta TLS. libnativewindow exporta os
# AHardwareBuffer_* necessarios com grafo muito mais leve.
AHB_SHIM="$ANDROID_MALI/ahb-shim"
mkdir -p "$AHB_SHIM"
NW_SRC=""
for n in \
    "$SYSTEM_SRC/lib64/libnativewindow.so" \
    /system/lib64/libnativewindow.so \
    /mnt/system/lib64/libnativewindow.so
do
    [ -f "$n" ] && NW_SRC=$n && break
done
if [ -n "$NW_SRC" ]; then
    resolve_elf_deps "$NW_SRC" 60
    cp -a "$NW_SRC" "$AHB_SHIM/libnativewindow.so"
    cp -a "$NW_SRC" "$AHB_SHIM/libandroid.so"
    echo ">> AHB shim: libandroid.so → libnativewindow ($NW_SRC)"
else
    echo "!! aviso: libnativewindow.so ausente — AHB/WSI pode falhar"
fi

# Properties tipicas
cat > "$ANDROID_MALI/properties/default.prop" <<'EOF'
ro.hardware.vulkan=mali
ro.hardware.egl=mali
ro.hardware.gralloc=common
EOF

# HYBRIS search path
HYBRIS_LIB_PATH="$ANDROID_MALI/vendor/lib64/egl/mt6878:$ANDROID_MALI/vendor/lib64/hw/mt6878:$ANDROID_MALI/vendor/lib64:$ANDROID_MALI/system_ext/lib64:$ANDROID_MALI/system/lib64:$ANDROID_MALI/apex/com.android.vndk.v34/lib64:$ANDROID_MALI/apex/com.android.runtime/lib64/bionic:$ANDROID_MALI/apex/com.android.vndk.v34@1/lib64"

# Paths libhybris
HYBRIS_LIBS=""
for d in \
    "$HYBRIS_PREFIX/lib" \
    "$HYBRIS_PREFIX/lib64" \
    "$HYBRIS_PREFIX/lib/libhybris" \
    /usr/lib/libhybris
do
    [ -d "$d" ] && HYBRIS_LIBS="$HYBRIS_LIBS:$d"
done
HYBRIS_LIBS=${HYBRIS_LIBS#:}

# ---------- wrappers ----------
echo "=== WRAPPERS ==="

# Plugins hybris: builds com --prefix=staging WSL embutem paths errados.
# Overrides runtime (hooks.c / ws.c / vulkan ws.c):
HYBRIS_LINKER_DIR="${HYBRIS_LINKER_DIR:-$HYBRIS_PREFIX/lib/libhybris/linker}"
HYBRIS_EGLPLATFORM_DIR="${HYBRIS_EGLPLATFORM_DIR:-$HYBRIS_PREFIX/lib/libhybris}"
HYBRIS_EGLPLATFORM="${HYBRIS_EGLPLATFORM:-null}"
HYBRIS_VULKANPLATFORM_DIR="${HYBRIS_VULKANPLATFORM_DIR:-$HYBRIS_PREFIX/lib/libhybris}"
HYBRIS_VULKANPLATFORM="${HYBRIS_VULKANPLATFORM:-null}"
[ -e "$HYBRIS_LINKER_DIR/q.so" ] || fail "linker hybris ausente: $HYBRIS_LINKER_DIR/q.so"
[ -e "$HYBRIS_EGLPLATFORM_DIR/eglplatform_${HYBRIS_EGLPLATFORM}.so" ] || \
    fail "eglplatform ausente: $HYBRIS_EGLPLATFORM_DIR/eglplatform_${HYBRIS_EGLPLATFORM}.so"
[ -e "$HYBRIS_VULKANPLATFORM_DIR/vulkanplatform_${HYBRIS_VULKANPLATFORM}.so" ] || \
    fail "vulkanplatform ausente: $HYBRIS_VULKANPLATFORM_DIR/vulkanplatform_${HYBRIS_VULKANPLATFORM}.so"

cat > /etc/artix-gpu.conf <<EOF2
GPU_MODE=hybris-gles
GPU_VENDOR_LIB=$HYBRIS_LIB_PATH
ANDROID_ROOT=$ANDROID_MALI/system
ANDROID_MALI=$ANDROID_MALI
HYBRIS_PREFIX=$HYBRIS_PREFIX
HYBRIS_LINKER_DIR=$HYBRIS_LINKER_DIR
HYBRIS_EGLPLATFORM_DIR=$HYBRIS_EGLPLATFORM_DIR
HYBRIS_EGLPLATFORM=$HYBRIS_EGLPLATFORM
HYBRIS_VULKANPLATFORM_DIR=$HYBRIS_VULKANPLATFORM_DIR
HYBRIS_VULKANPLATFORM=$HYBRIS_VULKANPLATFORM
GPU_GLES_SO=$ANDROID_MALI/vendor/lib64/egl/mt6878/libGLES_mali.so
GPU_ICD_SO=${VULKAN_SO:-}
ANDROID_DATA=/data
EOF2

cat > /etc/profile.d/gpu-mediatek.sh <<'EOF2'
[ -f /etc/artix-gpu.conf ] && . /etc/artix-gpu.conf
export ANDROID_ROOT="${ANDROID_ROOT:-/opt/android-mali/system}"
export ANDROID_DATA="${ANDROID_DATA:-/data}"
export HYBRIS_PREFIX="${HYBRIS_PREFIX:-/opt/libhybris}"
export HYBRIS_LINKER_DIR="${HYBRIS_LINKER_DIR:-$HYBRIS_PREFIX/lib/libhybris/linker}"
export HYBRIS_EGLPLATFORM_DIR="${HYBRIS_EGLPLATFORM_DIR:-$HYBRIS_PREFIX/lib/libhybris}"
export HYBRIS_EGLPLATFORM="${HYBRIS_EGLPLATFORM:-null}"
export HYBRIS_VULKANPLATFORM_DIR="${HYBRIS_VULKANPLATFORM_DIR:-$HYBRIS_PREFIX/lib/libhybris}"
export HYBRIS_VULKANPLATFORM="${HYBRIS_VULKANPLATFORM:-null}"
# Path Android para hybris_dlopen (libgpud_sys.so, etc.). Necessario quando
# VK_ICD aponta ao wrapper Mali — fastfetch/apps Vulkan sem gpu-*-run.
ANDROID_MALI="${ANDROID_MALI:-/opt/android-mali}"
if [ -z "${HYBRIS_LD_LIBRARY_PATH:-}" ]; then
    if [ -n "${GPU_VENDOR_LIB:-}" ]; then
        export HYBRIS_LD_LIBRARY_PATH="$GPU_VENDOR_LIB"
    else
        export HYBRIS_LD_LIBRARY_PATH="$ANDROID_MALI/vendor/lib64/egl/mt6878:$ANDROID_MALI/vendor/lib64/hw/mt6878:$ANDROID_MALI/vendor/lib64:$ANDROID_MALI/system_ext/lib64:$ANDROID_MALI/system/lib64:$ANDROID_MALI/apex/com.android.vndk.v34/lib64:$ANDROID_MALI/apex/com.android.vndk.v34@1/lib64:$ANDROID_MALI/apex/com.android.runtime/lib64/bionic"
    fi
fi
# Vulkan ICD so se configurado (Fase F)
if [ -n "${GPU_ICD_FILE:-}" ] && [ -f "$GPU_ICD_FILE" ]; then
    export VK_DRIVER_FILES="$GPU_ICD_FILE"
    export VK_ICD_FILENAMES="$GPU_ICD_FILE"
fi
EOF2

cat > /usr/local/bin/gpu-egl-run <<'EOF2'
#!/bin/sh
# Wrapper controlado: GLES/EGL Mali via libhybris + /opt/android-mali
# NAO activa GLVND global / NAO mistura no startxfce4

[ -f /etc/artix-gpu.conf ] && . /etc/artix-gpu.conf

ANDROID_MALI="${ANDROID_MALI:-/opt/android-mali}"
HYBRIS_PREFIX="${HYBRIS_PREFIX:-/opt/libhybris}"
export ANDROID_ROOT="${ANDROID_ROOT:-$ANDROID_MALI/system}"
export ANDROID_DATA="${ANDROID_DATA:-/data}"
# Overrides de PKGLIBDIR / LINKER_PLUGIN_DIR embutidos no build (staging WSL)
export HYBRIS_LINKER_DIR="${HYBRIS_LINKER_DIR:-$HYBRIS_PREFIX/lib/libhybris/linker}"
export HYBRIS_EGLPLATFORM_DIR="${HYBRIS_EGLPLATFORM_DIR:-$HYBRIS_PREFIX/lib/libhybris}"
export HYBRIS_EGLPLATFORM="${HYBRIS_EGLPLATFORM:-null}"

HYBRIS_LD="$ANDROID_MALI/vendor/lib64/egl/mt6878"
HYBRIS_LD="$HYBRIS_LD:$ANDROID_MALI/vendor/lib64/hw/mt6878"
HYBRIS_LD="$HYBRIS_LD:$ANDROID_MALI/vendor/lib64"
HYBRIS_LD="$HYBRIS_LD:$ANDROID_MALI/system_ext/lib64"
HYBRIS_LD="$HYBRIS_LD:$ANDROID_MALI/system/lib64"
HYBRIS_LD="$HYBRIS_LD:$ANDROID_MALI/apex/com.android.vndk.v34/lib64"
HYBRIS_LD="$HYBRIS_LD:$ANDROID_MALI/apex/com.android.vndk.v34@1/lib64"
HYBRIS_LD="$HYBRIS_LD:$ANDROID_MALI/apex/com.android.runtime/lib64/bionic"

export HYBRIS_LD_LIBRARY_PATH="$HYBRIS_LD${HYBRIS_LD_LIBRARY_PATH:+:$HYBRIS_LD_LIBRARY_PATH}"

LD_EXTRA="$HYBRIS_PREFIX/lib:$HYBRIS_PREFIX/lib64:$HYBRIS_PREFIX/lib/libhybris:$HYBRIS_LINKER_DIR:$HYBRIS_EGLPLATFORM_DIR:/usr/lib/libhybris"
export LD_LIBRARY_PATH="$LD_EXTRA:/usr/lib:/usr/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

unset LIBGL_ALWAYS_SOFTWARE
# nao forcar Zink aqui

[ $# -gt 0 ] || {
    echo "uso: gpu-egl-run comando"
    exit 2
}
exec "$@"
EOF2
chmod 755 /usr/local/bin/gpu-egl-run

# ---------- GATE 3–6: testes GLES ----------
echo "=== GATES 3–6: TESTES GLES ==="

# D1 — loader hybris presente
echo "--- D1 loader ---"
FOUND_HYB=0
for f in \
    "$HYBRIS_PREFIX/lib/libhybris-common.so" \
    "$HYBRIS_PREFIX/lib64/libhybris-common.so" \
    /usr/lib/libhybris/libhybris-common.so \
    /usr/lib/libhybris-common.so
do
    [ -e "$f" ] && FOUND_HYB=1 && echo ">> hybris: $f" && break
done
[ "$FOUND_HYB" = 1 ] || fail "D1: libhybris-common nao encontrado sob $HYBRIS_PREFIX"

# D2 — libGLES_mali carrega (readelf + existencia na arvore)
echo "--- D2 libGLES_mali ---"
[ -f "$ANDROID_MALI/vendor/lib64/egl/mt6878/libGLES_mali.so" ] || \
    fail "D2: libGLES_mali.so ausente em $ANDROID_MALI"
readelf -h "$ANDROID_MALI/vendor/lib64/egl/mt6878/libGLES_mali.so" | grep -q AArch64 || \
    fail "D2: libGLES_mali invalido"

# D3–D6 — eglinfo/es2_info via gpu-egl-run (sem gcc no device)
echo "--- D3–D6 EGL/GLES test (mesa-utils, sem compile) ---"
command -v eglinfo >/dev/null 2>&1 || command -v es2_info >/dev/null 2>&1 || \
    fail "D3: eglinfo/es2_info ausentes (mesa-utils)"

rm -f /tmp/mali-egl-out.txt /tmp/mali-egl-err.txt
set +e
if command -v eglinfo >/dev/null 2>&1; then
    gpu-egl-run eglinfo > /tmp/mali-egl-out.txt 2> /tmp/mali-egl-err.txt
    EGL_RC=$?
elif command -v es2_info >/dev/null 2>&1; then
    gpu-egl-run es2_info > /tmp/mali-egl-out.txt 2> /tmp/mali-egl-err.txt
    EGL_RC=$?
else
    EGL_RC=127
fi
set -e
head -n 80 /tmp/mali-egl-out.txt || true
[ -s /tmp/mali-egl-err.txt ] && head -n 40 /tmp/mali-egl-err.txt || true

# D4: sucesso = Mali/ARM no stdout (eglinfo pode abortar depois em Wayland/XDG)
if grep -qiE 'Mali-G6|Mali-G7|Valhall|EGL vendor string:[[:space:]]*ARM' /tmp/mali-egl-out.txt; then
    echo ">> D4 EGL/GLES Mali OK (rc=$EGL_RC; ignore XDG/wayland no fim do eglinfo)"
elif [ -s /tmp/mali-egl-out.txt ] && ! grep -qiE 'Failed to load hybris linker|eglplatform_.*cannot open|Assertion' /tmp/mali-egl-err.txt 2>/dev/null; then
    echo ">> D4 EGL probe OK (rc=$EGL_RC)"
else
    fail "D4: EGL/GLES falhou (rc=$EGL_RC) — ver /tmp/mali-egl-err.txt"
fi

# D5: GLES version hint (opcional)
if grep -qiE 'OpenGL ES|GLES|EGL version|GL_VERSION' /tmp/mali-egl-out.txt; then
    echo ">> D5 GLES/EGL strings presentes"
else
    echo ">> D5 aviso: sem string GLES explicita (continuando)"
fi

# D6: renderer Mali (nao software)
RENDERER=$(
    grep -iE 'GL_RENDERER|GLES renderer|OpenGL ES profile renderer|OpenGL renderer string|Renderer string' /tmp/mali-egl-out.txt \
        | head -n1 | sed 's/.*[:=][[:space:]]*//' || true
)
[ -n "$RENDERER" ] || RENDERER=$(
    grep -iE 'Mali-G[0-9]+|Mali' /tmp/mali-egl-out.txt | head -n1 || true
)
echo ">> renderer: ${RENDERER:-"(nao parseado)"}"
if echo "${RENDERER:-}" | grep -qiE 'llvmpipe|softpipe|swrast|software'; then
    fail "D6: renderer software — nao e Mali"
fi
if ! echo "${RENDERER}$(cat /tmp/mali-egl-out.txt)" | grep -qiE 'Mali|G615|G6[0-9]'; then
    echo "!! D6: renderer nao identifica Mali explicitamente: ${RENDERER:-n/a}"
    if [ "${GPU_FORCE_GLES_OK:-0}" != 1 ]; then
        fail "D6: confirme Mali-G615 ou GPU_FORCE_GLES_OK=1"
    fi
    RENDERER=${RENDERER:-forced-ok}
fi

date > /etc/artix-gpu-gles.ok
printf '%s\n' \
    "MODE=hybris-gles" \
    "RENDERER=$RENDERER" \
    "GLES_SO=$ANDROID_MALI/vendor/lib64/egl/mt6878/libGLES_mali.so" \
    "ANDROID_MALI=$ANDROID_MALI" \
    "HYBRIS_PREFIX=$HYBRIS_PREFIX" \
    >> /etc/artix-gpu-gles.ok
echo "=== GATE 6 OK: /etc/artix-gpu-gles.ok ==="

# ---------- Fase F: Vulkan via sysvk-opt tarball (opcional) ----------
if [ -z "${SYSVK_TAR:-}" ] || [ ! -f "${SYSVK_TAR:-}" ]; then
    if [ -f /root/sysvk-opt-arm64.tar.zst ]; then
        SYSVK_TAR=/root/sysvk-opt-arm64.tar.zst
    else
        # shellcheck disable=SC2012
        SYSVK_TAR=$(ls -1 /root/sysvk-opt-*.tar.zst 2>/dev/null | head -n1 || true)
    fi
fi

DO_VULKAN=0
case "$GPU_BUILD_SYSVK" in
    1|yes|true)
        DO_VULKAN=1
        ;;
    0|no|false)
        DO_VULKAN=0
        ;;
    auto)
        if [ -f /etc/artix-gpu-gles.ok ] && [ -n "${VULKAN_SO:-}" ] && [ -n "$SYSVK_TAR" ] && [ -f "$SYSVK_TAR" ]; then
            DO_VULKAN=1
        fi
        ;;
esac

if [ "$DO_VULKAN" != 1 ]; then
    echo "=== Vulkan ADIADO (GPU_BUILD_SYSVK=$GPU_BUILD_SYSVK sysvk_tar=${SYSVK_TAR:-ausente}) ==="
    echo "OK — GLES Mali via libhybris (runtime-only)"
    echo "Teste: gpu-egl-run eglinfo"
    echo "Vulkan: coloque deps/sysvk-opt-arm64.tar.zst e re-corra run-setup-gpu-hybris"
    exit 0
fi

[ -f /etc/artix-gpu-gles.ok ] || fail "Vulkan exige /etc/artix-gpu-gles.ok"
[ -n "$VULKAN_SO" ] || fail "vulkan.mali.so ausente"
[ -n "$SYSVK_TAR" ] && [ -f "$SYSVK_TAR" ] || fail "sysvk-opt tarball obrigatorio para Fase F"

echo "=== FASE F: Vulkan (sysvk-opt overlay) ==="
# ICD Linux = mesa-vulkan-icd-wrapper (hybris_dlopen).
# WRAPPER_VULKAN_PATH = libvulkan.so Android (loader AOSP) no staging —
# nao o HAL vulkan.mali.so (stub sem vkEnumerate*; causa SIGSEGV no wrapper).
# Cadeia validada: wrapper → libvulkan.so (ANDROID_ROOT=staging) → HAL Mali.
if ! ensure_vulkaninfo; then
    echo "!! GLES OK (/etc/artix-gpu-gles.ok); Fase F adiada — sem vulkaninfo para validar Mali"
    echo "   corriga: pacman -S vulkan-tools  (ou re-corra setup apos install manual)"
    echo "OK — GLES Mali via libhybris (runtime-only); Vulkan pendente"
    exit 0
fi
require_libgcc "apos pacman vulkan-tools Fase F"

echo ">> HAL vulkan.mali.so + deps ELF (so a partir do HAL)"
resolve_elf_deps "$VULKAN_SO" 120
# B) deps dinamicas (dlopen) — ex. libgpud_sys.so em system_ext
seed_mali_runtime_libs
mkdir -p "$ANDROID_MALI/vendor/lib64/hw/mt6878"
cp -a "$VULKAN_SO" "$ANDROID_MALI/vendor/lib64/hw/mt6878/vulkan.mali.so"
ln -sfn mt6878/vulkan.mali.so "$ANDROID_MALI/vendor/lib64/hw/vulkan.mali.so" 2>/dev/null || true
[ -f "$ANDROID_MALI/vendor/lib64/hw/mt6878/vulkan.mali.so" ] || \
    fail "falta $ANDROID_MALI/vendor/lib64/hw/mt6878/vulkan.mali.so"

# Loader AOSP no staging — contrato do mesa-vulkan-icd-wrapper (hybris_dl*)
AOSP_LIBVULKAN=""
for c in \
    "$SYSTEM_SRC/lib64/libvulkan.so" \
    /mnt/system/lib64/libvulkan.so \
    /system/lib64/libvulkan.so
do
    [ -f "$c" ] && AOSP_LIBVULKAN=$c && break
done
[ -n "$AOSP_LIBVULKAN" ] || fail "libvulkan.so Android ausente (SYSTEM_SRC/system)"
mkdir -p "$ANDROID_MALI/system/lib64"
# deps NEEDED do loader AOSP no staging (HAL/runtime seeds ja cobrem a maior parte)
resolve_elf_deps "$AOSP_LIBVULKAN" 80
[ -f "$ANDROID_MALI/system/lib64/libvulkan.so" ] || \
    fail "falta $ANDROID_MALI/system/lib64/libvulkan.so"
WRAPPER_VULKAN_PATH=$ANDROID_MALI/system/lib64/libvulkan.so
echo ">> WRAPPER_VULKAN_PATH=$WRAPPER_VULKAN_PATH (AOSP loader; HAL=$ANDROID_MALI/vendor/lib64/hw/mt6878/vulkan.mali.so)"

if [ -f /root/install-sysvk-opt.sh ]; then
    SYSVK_TAR="$SYSVK_TAR" /bin/bash /root/install-sysvk-opt.sh || fail "install-sysvk-opt falhou"
else
    echo ">> install-sysvk-opt.sh ausente — extract directo"
    tar --use-compress-program=zstd -xf "$SYSVK_TAR" -C /
    ldconfig 2>/dev/null || true
fi

# VNDK graphics NDK → android-mali + /usr/lib/android-vndk (HAL/gralloc podem precisar)
mkdir -p /usr/lib/android-vndk "$ANDROID_MALI/system/lib64"
for base in \
    /apex/com.android.vndk.v34/lib64 \
    /apex/com.android.vndk.v34@1/lib64 \
    "$ANDROID_MALI/apex/com.android.vndk.v34/lib64"
do
    [ -d "$base" ] || continue
    find "$base" -maxdepth 1 -type f \
        -name 'android.hardware.graphics.common*-ndk*.so' \
        -exec sh -c 'cp -Lf "$1" "/usr/lib/android-vndk/$(basename "$1")"; cp -Lf "$1" "'"$ANDROID_MALI"'/system/lib64/$(basename "$1")"' _ {} \;
done

ICD_FILE=""
if [ -f /etc/artix-sysvk.ok ]; then
    # shellcheck disable=SC1091
    . /etc/artix-sysvk.ok
fi
for j in \
    ${ICD_FILE:-} \
    /usr/share/vulkan/icd.d/*.json \
    /usr/local/share/vulkan/icd.d/*.json \
    "$HYBRIS_PREFIX"/share/vulkan/icd.d/*.json
do
    [ -f "$j" ] || continue
    if grep -qiE 'sysvk|android|wrapper|mali' "$j"; then
        ICD_FILE=$j
        break
    fi
done
[ -n "$ICD_FILE" ] || fail "ICD Android/sysvk nao encontrado apos sysvk-opt"

ICD_LIB=$(sed -n 's/.*"library_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ICD_FILE" | head -n1 || true)
[ -n "$ICD_LIB" ] || fail "library_path ausente em $ICD_FILE"
if [[ "$ICD_LIB" != /* ]]; then
    ICD_LIB="$(dirname "$ICD_FILE")/$ICD_LIB"
fi
[ -f "$ICD_LIB" ] || fail "biblioteca do ICD ausente: $ICD_LIB"

if [ ! -f /usr/share/vulkan/explicit_layer.d/VkLayer_window_system_integration.json ] \
   && [ ! -f /usr/share/vulkan/implicit_layer.d/VkLayer_window_system_integration.json ]; then
    echo "!! aviso: JSON WSI layer ausente — continue se o tarball nao a incluir"
fi

# Actualizar conf
HYBRIS_LINKER_DIR="${HYBRIS_LINKER_DIR:-$HYBRIS_PREFIX/lib/libhybris/linker}"
HYBRIS_EGLPLATFORM_DIR="${HYBRIS_EGLPLATFORM_DIR:-$HYBRIS_PREFIX/lib/libhybris}"
HYBRIS_EGLPLATFORM="${HYBRIS_EGLPLATFORM:-null}"
HYBRIS_VULKANPLATFORM_DIR="${HYBRIS_VULKANPLATFORM_DIR:-$HYBRIS_PREFIX/lib/libhybris}"
HYBRIS_VULKANPLATFORM="${HYBRIS_VULKANPLATFORM:-null}"
WRAPPER_VULKAN_PATH=${WRAPPER_VULKAN_PATH:-$ANDROID_MALI/system/lib64/libvulkan.so}
cat > /etc/artix-gpu.conf <<EOF2
GPU_MODE=hybris
GPU_VENDOR_LIB=$HYBRIS_LIB_PATH
ANDROID_ROOT=$ANDROID_MALI/system
ANDROID_MALI=$ANDROID_MALI
HYBRIS_PREFIX=$HYBRIS_PREFIX
HYBRIS_LINKER_DIR=$HYBRIS_LINKER_DIR
HYBRIS_EGLPLATFORM_DIR=$HYBRIS_EGLPLATFORM_DIR
HYBRIS_EGLPLATFORM=$HYBRIS_EGLPLATFORM
HYBRIS_VULKANPLATFORM_DIR=$HYBRIS_VULKANPLATFORM_DIR
HYBRIS_VULKANPLATFORM=$HYBRIS_VULKANPLATFORM
GPU_GLES_SO=$ANDROID_MALI/vendor/lib64/egl/mt6878/libGLES_mali.so
GPU_ICD_FILE=$ICD_FILE
GPU_ICD_SO=$ANDROID_MALI/vendor/lib64/hw/mt6878/vulkan.mali.so
WRAPPER_VULKAN_PATH=$WRAPPER_VULKAN_PATH
ANDROID_DATA=/data
EOF2

cat > /usr/local/bin/gpu-vulkan-run <<'EOF2'
#!/bin/sh
[ -f /etc/artix-gpu.conf ] && . /etc/artix-gpu.conf

ANDROID_MALI="${ANDROID_MALI:-/opt/android-mali}"
HYBRIS_PREFIX="${HYBRIS_PREFIX:-/opt/libhybris}"
export ANDROID_ROOT="${ANDROID_ROOT:-$ANDROID_MALI/system}"
export ANDROID_DATA="${ANDROID_DATA:-/data}"
export HYBRIS_TLS_PATCH="${HYBRIS_TLS_PATCH:-vulkan.mali.so}"
export HYBRIS_LINKER_DIR="${HYBRIS_LINKER_DIR:-$HYBRIS_PREFIX/lib/libhybris/linker}"
export HYBRIS_EGLPLATFORM_DIR="${HYBRIS_EGLPLATFORM_DIR:-$HYBRIS_PREFIX/lib/libhybris}"
export HYBRIS_EGLPLATFORM="${HYBRIS_EGLPLATFORM:-null}"
# Overrides PKGLIBDIR embutido (builds antigos com /home/.../mali-runtime/...)
export HYBRIS_VULKANPLATFORM_DIR="${HYBRIS_VULKANPLATFORM_DIR:-$HYBRIS_PREFIX/lib/libhybris}"
export HYBRIS_VULKANPLATFORM="${HYBRIS_VULKANPLATFORM:-null}"

# ICD = mesa wrapper; WRAPPER = libvulkan.so AOSP no staging (nao HAL stub)
export WRAPPER_VULKAN_PATH="${WRAPPER_VULKAN_PATH:-$ANDROID_MALI/system/lib64/libvulkan.so}"

# WSI layer faz dlsym(RTLD_DEFAULT, AHardwareBuffer_*) — precisa ahb-wrapper
# no namespace global (PKGBUILD faz patchelf --add-needed; tarball pode nao).
if [ -f /usr/lib/libahb-wrapper.so ] || [ -f /usr/lib/libahb-wrapper.so.1 ]; then
    AHB_SO=/usr/lib/libahb-wrapper.so
    [ -f "$AHB_SO" ] || AHB_SO=/usr/lib/libahb-wrapper.so.1
    case ":${LD_PRELOAD:-}:" in
        *":$AHB_SO:"*) ;;
        *) export LD_PRELOAD="$AHB_SO${LD_PRELOAD:+:$LD_PRELOAD}" ;;
    esac
fi

# ahb-shim primeiro: hybris_dlopen("libandroid.so") → libnativewindow
HYBRIS_LD=""
if [ -d "$ANDROID_MALI/ahb-shim" ]; then
    HYBRIS_LD="$ANDROID_MALI/ahb-shim"
fi
HYBRIS_LD="${HYBRIS_LD:+$HYBRIS_LD:}$ANDROID_MALI/vendor/lib64/egl/mt6878:$ANDROID_MALI/vendor/lib64/hw/mt6878:$ANDROID_MALI/vendor/lib64:$ANDROID_MALI/system_ext/lib64:$ANDROID_MALI/system/lib64:$ANDROID_MALI/apex/com.android.vndk.v34/lib64:$ANDROID_MALI/apex/com.android.vndk.v34@1/lib64:$ANDROID_MALI/apex/com.android.runtime/lib64/bionic"
export HYBRIS_LD_LIBRARY_PATH="$HYBRIS_LD"

# CRITICO: /usr/lib ANTES de $HYBRIS_PREFIX/lib.
# Caso contrario vulkaninfo resolve libvulkan.so.1 para o do hybris
# em vez do loader Linux + ICD (libvulkan_wrapper.so).
# Mesa25 overlay (/opt/android-mali/lib) antes de /usr para GLX/EGL Mesa (Zink).
HYBRIS_EXTRA="$HYBRIS_PREFIX/lib/libhybris:$HYBRIS_LINKER_DIR:$HYBRIS_EGLPLATFORM_DIR:$HYBRIS_VULKANPLATFORM_DIR:/usr/lib/libhybris:/usr/lib/android-vndk:$HYBRIS_PREFIX/lib:$HYBRIS_PREFIX/lib64"
export LD_LIBRARY_PATH="$ANDROID_MALI/lib:/usr/lib:/usr/lib64:$HYBRIS_EXTRA${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if [ -n "${GPU_ICD_FILE:-}" ] && [ -f "$GPU_ICD_FILE" ]; then
    export VK_DRIVER_FILES="$GPU_ICD_FILE"
    export VK_ICD_FILENAMES="$GPU_ICD_FILE"
fi
unset DISABLE_WSI_LAYER
unset LIBGL_ALWAYS_SOFTWARE

[ $# -gt 0 ] || { echo "uso: gpu-vulkan-run comando"; exit 2; }
exec "$@"
EOF2
chmod 755 /usr/local/bin/gpu-vulkan-run

# Fase G: Zink = OpenGL/GLX via Mesa → Vulkan Mali (WSI ja validado)
# megadriver: garantir zink_dri.so
if [ -f "$ANDROID_MALI/lib/dri/libdril_dri.so" ]; then
    ln -sfn libdril_dri.so "$ANDROID_MALI/lib/dri/zink_dri.so"
fi

cat > /usr/local/bin/gpu-run <<'EOF2'
#!/bin/sh
# Default: Vulkan path. Zink com GPU_USE_ZINK=1 ou via zink-run.
if [ "${GPU_USE_ZINK:-0}" = 1 ]; then
    ANDROID_MALI="${ANDROID_MALI:-/opt/android-mali}"
    [ -f /etc/artix-gpu.conf ] && . /etc/artix-gpu.conf
    ANDROID_MALI="${ANDROID_MALI:-/opt/android-mali}"
    export MESA_LOADER_DRIVER_OVERRIDE=zink
    export GALLIUM_DRIVER=zink
    export LIBGL_DRIVERS_PATH="${LIBGL_DRIVERS_PATH:-$ANDROID_MALI/lib/dri}"
    export GBM_BACKENDS_PATH="${GBM_BACKENDS_PATH:-$ANDROID_MALI/lib/gbm}"
    if [ -d "$ANDROID_MALI/share/glvnd/egl_vendor.d" ]; then
        export __EGL_VENDOR_LIBRARY_DIRS="${__EGL_VENDOR_LIBRARY_DIRS:-$ANDROID_MALI/share/glvnd/egl_vendor.d}"
    fi
    export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-mesa}"
    # Termux:X11: sem DRI3/render node — forçar caminho kopper/DRI2
    export LIBGL_KOPPER_DRI2="${LIBGL_KOPPER_DRI2:-1}"
    # Garantir loader Vulkan Linux (ldconfig pode preferir hybris)
    if [ -f /usr/lib/libvulkan.so.1 ]; then
        case ":${LD_PRELOAD:-}:" in
            *:/usr/lib/libvulkan.so.1:*) ;;
            *) export LD_PRELOAD="/usr/lib/libvulkan.so.1${LD_PRELOAD:+:$LD_PRELOAD}" ;;
        esac
    fi
    unset LIBGL_ALWAYS_SOFTWARE
fi
exec /usr/local/bin/gpu-vulkan-run "$@"
EOF2
chmod 755 /usr/local/bin/gpu-run

cat > /usr/local/bin/zink-run <<'EOF2'
#!/bin/sh
export GPU_USE_ZINK=1
exec /usr/local/bin/gpu-run "$@"
EOF2
chmod 755 /usr/local/bin/zink-run

echo "=== VULKAN: minimo → (vkcube externo) → vulkaninfo por ultimo ==="
HAL_SO="$ANDROID_MALI/vendor/lib64/hw/mt6878/vulkan.mali.so"
AOSP_SO="$ANDROID_MALI/system/lib64/libvulkan.so"
if [ ! -f "$HAL_SO" ]; then
    fail "pre-teste: falta HAL $HAL_SO"
fi
if [ ! -f "$AOSP_SO" ]; then
    fail "pre-teste: falta AOSP loader $AOSP_SO"
fi
echo ">> teste WRAPPER_VULKAN_PATH=$WRAPPER_VULKAN_PATH HAL=$HAL_SO"
VK_TEST_TO="${VULKANINFO_TIMEOUT:-90}"
set +e
WRAPPER_DEBUG="${WRAPPER_DEBUG:-1}" \
run_with_timeout "$VK_TEST_TO" \
    gpu-vulkan-run vulkaninfo --summary > /tmp/vulkan-hybris-summary.txt 2> /tmp/vulkan-hybris-error.txt
VK_RC=$?
set -e
if [ "$VK_RC" = 124 ] || [ "$VK_RC" = 143 ]; then
    echo "!! vulkaninfo timeout (${VK_TEST_TO}s) — ver /tmp/vulkan-hybris-error.txt"
    cat /tmp/vulkan-hybris-error.txt 2>/dev/null || true
    fail "Vulkan teste excedeu timeout (rc=$VK_RC)"
fi
grep -E 'deviceName|driverName|Mali|G6[0-9]|MediaTek|MTK' /tmp/vulkan-hybris-summary.txt || true
if ! grep -qiE 'Mali|G6[0-9]|MTK|MediaTek' /tmp/vulkan-hybris-summary.txt; then
    echo "!! vulkaninfo stderr/stdout (rc=$VK_RC):"
    cat /tmp/vulkan-hybris-error.txt || true
    head -n 40 /tmp/vulkan-hybris-summary.txt || true
    echo "!! HAL: ls -l $HAL_SO"
    ls -l "$HAL_SO" 2>&1 || true
    # Se library \"X\" not found: X deve ser NEEDED do HAL — nao inventar soft-deps
    if grep -qo 'library "[^"]*" not found' /tmp/vulkan-hybris-error.txt 2>/dev/null; then
        echo "!! libs em falta (so aceitar se forem NEEDED do HAL):"
        grep -o 'library "[^"]*" not found' /tmp/vulkan-hybris-error.txt | sort -u || true
        echo "!! NEEDED do HAL:"
        readelf -d "$HAL_SO" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/  - \1/p' || true
    fi
    fail "Vulkan iniciou sem identificar Mali (rc=$VK_RC)"
fi

date > /etc/artix-gpu-hybris.ok
printf '%s\n' MODE=hybris ICD="$ICD_FILE" DRIVER="$HAL_SO" WSI=1 GLES=1 \
    WRAPPER_VULKAN_PATH="$WRAPPER_VULKAN_PATH" \
    >> /etc/artix-gpu-hybris.ok

# ---------- Fase G: Zink (GLX sobre Vulkan) — so se X11 + glxinfo ----------
echo "=== FASE G: Zink (Mesa → Vulkan Mali) ==="
ZINK_OK=0
GALLIUM_SO="$ANDROID_MALI/lib/libgallium-25.1.2.so"
[ -f "$GALLIUM_SO" ] || GALLIUM_SO=$(ls -1 "$ANDROID_MALI"/lib/libgallium-*.so 2>/dev/null | head -n1)
if [ ! -e "$ANDROID_MALI/lib/dri/zink_dri.so" ]; then
    echo "!! aviso: zink_dri.so ausente — a criar symlink se libdril existir"
    [ -f "$ANDROID_MALI/lib/dri/libdril_dri.so" ] && \
        ln -sfn libdril_dri.so "$ANDROID_MALI/lib/dri/zink_dri.so"
fi
# Gate: kopper_init_screen < 32B = stubs (Zink inutil no Termux:X11 sem DRM).
KOPPER_SZ=""
if [ -n "$GALLIUM_SO" ] && [ -f "$GALLIUM_SO" ] && command -v readelf >/dev/null 2>&1; then
    set +o pipefail
    KOPPER_SZ=$(readelf -Ws "$GALLIUM_SO" 2>/dev/null \
        | awk '/[[:space:]]kopper_init_screen([[:space:]]|$)/ { print $3; exit }')
    set -o pipefail
fi
if [ ! -e "$ANDROID_MALI/lib/dri/zink_dri.so" ]; then
    echo "!! Zink adiado: sem zink_dri.so"
elif [ -n "$KOPPER_SZ" ] && [ "$KOPPER_SZ" -lt 32 ] 2>/dev/null; then
    echo "!! Zink adiado: Mesa overlay tem kopper_stubs (kopper_init_screen=${KOPPER_SZ}B)"
    echo "   Precisa rebuild mesa25 com kopper/WSI GLX real (Termux:X11 sem DRM)."
    echo "   Vulkan permanece OK: DISPLAY=:0 gpu-vulkan-run vkcube"
    echo "   SoftGL (CPU): MESA_LOADER_DRIVER_OVERRIDE=softpipe glxinfo -B"
    if [ "${GPU_REQUIRE_ZINK:-0}" = 1 ]; then
        fail "Zink obrigatorio (GPU_REQUIRE_ZINK=1) mas kopper esta stubbed"
    fi
elif ! command -v glxinfo >/dev/null 2>&1; then
    echo "!! Zink adiado: glxinfo ausente (mesa-utils)"
elif [ ! -S /tmp/.X11-unix/X0 ] && [ ! -S /tmp/.X11-unix/X1 ]; then
    echo "!! Zink adiado: sem socket X11 — teste manual:"
    echo "   DISPLAY=:0 zink-run glxinfo -B"
else
    # linux-shell usa env -i — garantir DISPLAY para glxinfo
    export DISPLAY="${DISPLAY:-:0}"
    set +e
    GPU_USE_ZINK=1 run_with_timeout "${ZINK_TIMEOUT:-45}" \
        zink-run glxinfo -B > /tmp/zink-glxinfo.txt 2> /tmp/zink-glxinfo.err
    ZINK_RC=$?
    set -e
    grep -iE 'OpenGL (vendor|renderer|version|device)|zink|Mali|llvmpipe' \
        /tmp/zink-glxinfo.txt 2>/dev/null || true
    if [ "$ZINK_RC" = 0 ] && grep -qiE 'zink' /tmp/zink-glxinfo.txt \
        && grep -qiE 'Mali|G6[0-9]' /tmp/zink-glxinfo.txt; then
        ZINK_OK=1
        date > /etc/artix-gpu-zink.ok
        printf '%s\n' MODE=zink BACKEND=vulkan \
            WRAPPER_VULKAN_PATH="$WRAPPER_VULKAN_PATH" >> /etc/artix-gpu-zink.ok
        echo ">> Zink OK — marker /etc/artix-gpu-zink.ok"
    else
        echo "!! Zink glxinfo falhou (rc=$ZINK_RC) — Vulkan permanece OK"
        cat /tmp/zink-glxinfo.err 2>/dev/null | tail -n 30 || true
        head -n 40 /tmp/zink-glxinfo.txt 2>/dev/null || true
        if [ "${GPU_REQUIRE_ZINK:-0}" = 1 ]; then
            fail "Zink obrigatorio (GPU_REQUIRE_ZINK=1) mas falhou"
        fi
    fi
fi

echo "=== OK ==="
echo "GLES + Vulkan Mali via libhybris (wrapper → AOSP libvulkan → HAL)"
echo "GLES marker: /etc/artix-gpu-gles.ok"
echo "Vulkan marker: /etc/artix-gpu-hybris.ok"
[ "$ZINK_OK" = 1 ] && echo "Zink marker: /etc/artix-gpu-zink.ok"
echo "WRAPPER_VULKAN_PATH=$WRAPPER_VULKAN_PATH"
echo "Teste GLES: gpu-egl-run eglinfo"
echo "Teste Vulkan: DISPLAY=:0 gpu-vulkan-run vkcube"
echo "Teste Zink:   DISPLAY=:0 zink-run glxinfo -B"
echo "              DISPLAY=:0 zink-run glxgears"
