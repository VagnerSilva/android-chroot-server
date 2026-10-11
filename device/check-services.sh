#!/system/bin/sh
# check-services.sh — diagnóstico de dinit/sshd/dbus/X11 dentro do chroot

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

if [ ! -f "$PIDF" ] || ! container_vivo "$(cat "$PIDF" 2>/dev/null || printf '')"; then
  exit 0
fi

run_in_chroot /bin/sh -c '
  for s in sshd dbus elogind; do
    if dinitctl is-started "$s" >/dev/null 2>&1; then
      echo "OK_$s=1"
      echo "  [ok]  $s"
    else
      echo "OK_$s=0"
      if [ -e "/etc/dinit.d/$s" ]; then
        echo "  [!!]  $s"
        if [ "$s" = "sshd" ]; then
          echo "  [--]  sshd diag: bin=$(command -v sshd 2>/dev/null || echo AUSENTE)"
          echo "  [--]  sshd diag: unit=$(head -n5 /etc/dinit.d/sshd 2>/dev/null | tr "\\n" "|")"
          ST=$(dinitctl status sshd 2>&1 | head -n4 | tr "\\n" ";")
          echo "  [--]  sshd diag: status=$ST"
          if [ -f /var/log/dinit/sshd.log ]; then
            echo "  [--]  sshd.log (ultimas):"
            tail -n 8 /var/log/dinit/sshd.log 2>/dev/null | sed "s/^/         /"
          else
            echo "  [--]  sshd.log ausente"
          fi
        fi
      fi
    fi
  done

  if [ -S /run/dbus/system_bus_socket ]; then
    echo "OK_dbus_sock=1"
    echo "  [ok]  dbus socket"
  else
    echo "OK_dbus_sock=0"
    echo "  [!!]  dbus socket"
  fi

  if [ -S /tmp/.X11-unix/X0 ]; then
    echo "OK_x11=1"
    echo "  [ok]  X11 socket :0"
    if dinitctl is-started xfce-x11 >/dev/null 2>&1; then
      echo "  [ok]  xfce-x11"
    elif [ -e /etc/dinit.d/xfce-x11 ]; then
      echo "  [!!]  xfce-x11"
    fi
  else
    echo "OK_x11=0"
    echo "  [--]  X11 socket :0 (Termux:X11 parado)"
  fi
'
