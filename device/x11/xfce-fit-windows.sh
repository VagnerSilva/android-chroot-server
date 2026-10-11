#!/bin/sh
# ============================================================
# xfce-fit-windows.sh — limita janelas ao workarea (Termux:X11)
# Autostart XFCE; DISPLAY do ambiente da sessao.
# ============================================================
: "${DISPLAY:=:0}"
export DISPLAY

SKIP_TYPES='DESKTOP|DOCK|TOOLBAR|MENU|SPLASH|NOTIFICATION|COMBO|DND'

workarea() {
  wa=$(xprop -root _NET_WORKAREA 2>/dev/null) || wa=""
  nums=$(printf '%s\n' "$wa" | sed -n 's/.*=[[:space:]]*//p' | tr ',' ' ')
  # shellcheck disable=SC2086
  set -- $nums
  if [ -n "${1:-}" ] && [ -n "${4:-}" ]; then
    printf '%s %s %s %s\n' "$1" "$2" "$3" "$4"
    return 0
  fi
  dim=$(xdpyinfo 2>/dev/null | awk '/dimensions:/{print $2; exit}')
  [ -n "$dim" ] || return 1
  sw=${dim%x*}
  sh=${dim#*x}
  printf '%s %s %s %s\n' 0 0 "$sw" "$sh"
}

skip_window() {
  id="$1"
  types=$(xprop -id "$id" _NET_WM_WINDOW_TYPE 2>/dev/null) || return 0
  printf '%s\n' "$types" | grep -qE "$SKIP_TYPES" && return 0
  return 1
}

is_maximized() {
  id="$1"
  st=$(xprop -id "$id" _NET_WM_STATE 2>/dev/null) || return 1
  printf '%s\n' "$st" | grep -q 'MAXIMIZED'
}

fit_once() {
  wa=$(workarea) || return 0
  # shellcheck disable=SC2086
  set -- $wa
  ax=$1 ay=$2 aw=$3 ah=$4
  [ "$aw" -gt 0 ] 2>/dev/null && [ "$ah" -gt 0 ] 2>/dev/null || return 0

  wmctrl -lG 2>/dev/null | while read -r wid _desk wx wy ww wh _rest; do
    [ -n "$wid" ] && [ -n "$wh" ] || continue
    [ "$ww" -gt 0 ] 2>/dev/null || continue
    [ "$wh" -gt 0 ] 2>/dev/null || continue
    skip_window "$wid" && continue
    is_maximized "$wid" && continue

    nw=$ww nh=$wh nx=$wx ny=$wy
    [ "$nw" -gt "$aw" ] && nw=$aw
    [ "$nh" -gt "$ah" ] && nh=$ah
    [ "$nx" -lt "$ax" ] 2>/dev/null && nx=$ax
    [ "$ny" -lt "$ay" ] 2>/dev/null && ny=$ay
    right=$((ax + aw))
    bottom=$((ay + ah))
    [ $((nx + nw)) -gt "$right" ] && nx=$((right - nw))
    [ $((ny + nh)) -gt "$bottom" ] && ny=$((bottom - nh))
    [ "$nx" -lt "$ax" ] && nx=$ax
    [ "$ny" -lt "$ay" ] && ny=$ay

    if [ "$nx" -eq "$wx" ] && [ "$ny" -eq "$wy" ] && [ "$nw" -eq "$ww" ] && [ "$nh" -eq "$wh" ]; then
      continue
    fi
    wmctrl -i -r "$wid" -e "0,$nx,$ny,$nw,$nh" 2>/dev/null || true
  done
}

if ! command -v wmctrl >/dev/null 2>&1; then
  echo "!! xfce-fit-windows: wmctrl ausente" >&2
  exit 1
fi

fit_once
while :; do
  if command -v timeout >/dev/null 2>&1 && command -v xprop >/dev/null 2>&1; then
    timeout 2 sh -c 'xprop -root -spy _NET_CLIENT_LIST 2>/dev/null | { read _; read _; }' >/dev/null 2>&1 || true
  else
    sleep 1
  fi
  fit_once
done
