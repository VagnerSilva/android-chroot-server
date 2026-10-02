#!/system/bin/sh
# ============================================================
# 99-linux.sh -> /data/adb/service.d/99-linux.sh (chmod 755)
# KernelSU late_start: sobe o container apos o boot.
# ============================================================

i=0
until [ "$(getprop sys.boot_completed)" = "1" ] || [ $i -ge 120 ]; do
  sleep 2
  i=$((i + 1))
done
sleep 15

i=0
until ip -4 addr show 2>/dev/null | grep -qE 'inet .*(wlan|eth|rndis|rmnet)' || [ $i -ge 20 ]; do
  sleep 2
  i=$((i + 1))
done

/data/linux/linux-start.sh >> /data/linux/boot.log 2>&1

(
  while true; do
    sleep 60
    PIDF=/data/linux/run/init.pid
    [ -f /data/linux/run/stopped ] && continue
    if [ ! -f "$PIDF" ] || ! kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; then
      echo "=== watchdog: reiniciando $(date) ===" >> /data/linux/boot.log
      /data/linux/linux-start.sh >> /data/linux/boot.log 2>&1
    fi
  done
) &
