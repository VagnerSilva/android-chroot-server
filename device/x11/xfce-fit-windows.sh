#!/bin/sh
# Purpose: clamp visible XFCE windows to the current X11 work area.
# Prerequisites: run in an active X11 session with xprop, xdotool, and xdpyinfo available.
# Inputs: DISPLAY from the session environment (defaults to :0).
# Outputs: adjusts eligible window geometry through xdotool; no files are written.
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

  windows=$(xdotool search --onlyvisible --name '.*' 2>/dev/null) || windows=
  for wid in $windows; do
    [ -n "$wid" ] || continue
    geometry=$(xdotool getwindowgeometry --shell "$wid" 2>/dev/null) || continue
    # shellcheck disable=SC2086
    set -- $(printf '%s\n' "$geometry" | awk -F= '/^(X|Y|WIDTH|HEIGHT)=/{print $2}')
    [ "$#" -eq 4 ] || continue
    wx=$1 wy=$2 ww=$3 wh=$4
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
    xdotool windowmove "$wid" "$nx" "$ny" 2>/dev/null || true
    xdotool windowsize "$wid" "$nw" "$nh" 2>/dev/null || true
  done
}

if ! command -v xdotool >/dev/null 2>&1; then
  echo "!! xfce-fit-windows: xdotool ausente" >&2
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
