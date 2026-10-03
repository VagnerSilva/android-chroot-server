#!/bin/bash
# check-mesa25.sh — validar overlay Mesa 25.1.2 no chroot
set -u
export DISPLAY="${DISPLAY:-:0}" XDG_RUNTIME_DIR=/tmp TMPDIR=/tmp
export LD_LIBRARY_PATH=/opt/android-mali/lib
export LIBGL_DRIVERS_PATH=/opt/android-mali/lib/dri
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=softpipe
unset MESA_LOADER_DRIVER_OVERRIDE || true

ok=0
fail=0
pass() { echo "PASS $1"; ok=$((ok + 1)); }
failm() { echo "FAIL $1"; fail=$((fail + 1)); }

echo "=== Mesa 25 environment check ==="
[ -f /etc/artix-mesa25.ok ] && pass marker || failm marker
[ -f /opt/android-mali/lib/libgallium-25.1.2.so ] && pass libgallium || failm libgallium
[ -f /etc/ld.so.conf.d/android-mali-mesa25.conf ] && pass ld_conf || failm ld_conf
[ ! -f /etc/ld.so.conf.d/android-mali-mesa25.conf.exp-bak ] && pass ld_bak_clean || failm ld_bak_present
[ -S /tmp/.X11-unix/X0 ] && pass x11_socket || failm x11_socket

timeout 20 glxinfo -B >/tmp/c-t1.out 2>/tmp/c-t1.err
rc=$?
if [ "$rc" = 0 ] && grep -q 'Mesa 25.1.2' /tmp/c-t1.out && grep -qi softpipe /tmp/c-t1.out; then
  pass softGL_glxinfo
else
  failm softGL_glxinfo
fi
if grep -Eiq 'free\(\): invalid|malloc\(\):|corrupted size' /tmp/c-t1.out /tmp/c-t1.err; then
  failm softGL_heap
else
  pass softGL_heap
fi

timeout 15 glxgears -info >/tmp/c-t2.out 2>/tmp/c-t2.err
rc=$?
if { [ "$rc" = 0 ] || [ "$rc" = 124 ]; } && grep -qiE 'FPS:|GL_RENDERER|frames' /tmp/c-t2.out /tmp/c-t2.err; then
  pass softGL_gears
else
  failm softGL_gears
fi
if grep -Eiq 'free\(\): invalid|malloc\(\):|corrupted size' /tmp/c-t2.out /tmp/c-t2.err; then
  failm softGL_gears_heap
else
  pass softGL_gears_heap
fi

if [ -x /usr/local/bin/zink-run ] && [ -f /etc/artix-gpu-zink.ok ]; then
  timeout 20 /usr/local/bin/zink-run glxinfo -B >/tmp/c-t5.out 2>/tmp/c-t5.err
  rc=$?
  if [ "$rc" = 0 ] && grep -qi zink /tmp/c-t5.out && grep -qi Mali /tmp/c-t5.out && grep -q 'Mesa 25.1.2' /tmp/c-t5.out; then
    pass zink_glxinfo
  else
    failm zink_glxinfo
  fi
  if grep -Eiq 'free\(\): invalid|malloc\(\):|corrupted size' /tmp/c-t5.out /tmp/c-t5.err; then
    failm zink_heap
  else
    pass zink_heap
  fi
else
  echo "SKIP zink"
fi

if pgrep -x xfce4-session >/dev/null 2>&1; then
  pass xfce_session
else
  failm xfce_session
fi

echo
echo "SoftGL:"
grep -E 'OpenGL (renderer|version)' /tmp/c-t1.out || true
echo "Zink:"
grep -E 'OpenGL (renderer|version)' /tmp/c-t5.out 2>/dev/null || true
echo
echo "pacman mesa: $(pacman -Qi mesa 2>/dev/null | awk -F': ' '/^Version/{print $2; exit}' || echo ausente) (inerte se overlay ativo)"
echo "RESULT ok=$ok fail=$fail"
if [ "$fail" = 0 ]; then
  echo ENV_OK
  exit 0
fi
echo ENV_NOT_OK
exit 1
