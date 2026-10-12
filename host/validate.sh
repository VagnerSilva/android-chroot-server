#!/bin/sh
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
FAILURES=0
CHECKED=0
SHELLCHECK=$(command -v shellcheck 2>/dev/null || true)

validate_file() {
  file=$1
  [ -f "$file" ] || {
    printf '!! arquivo ausente: %s\n' "$file" >&2
    FAILURES=$((FAILURES + 1))
    return
  }

  first_line=$(sed -n '1p' "$file")
  CR=$(printf '\r')
  case "$first_line" in
    *bash*)
      if ! command -v bash >/dev/null 2>&1; then
        printf '!! bash indisponivel para validar: %s\n' "$file" >&2
        FAILURES=$((FAILURES + 1))
        return
      fi
      if ! tr -d "$CR" < "$file" | bash -n; then
        printf '!! erro de parse Bash: %s\n' "$file" >&2
        FAILURES=$((FAILURES + 1))
      fi
      ;;
    *)
      if ! tr -d "$CR" < "$file" | sh -n; then
        printf '!! erro de parse POSIX sh: %s\n' "$file" >&2
        FAILURES=$((FAILURES + 1))
      fi
      ;;
  esac

  if [ -n "$SHELLCHECK" ]; then
    if ! tr -d "$CR" < "$file" | "$SHELLCHECK" -S warning -; then
      printf '!! shellcheck falhou: %s\n' "$file" >&2
      FAILURES=$((FAILURES + 1))
    fi
  fi
  CHECKED=$((CHECKED + 1))
}

scan_tree() {
  for path in "$1"/*; do
    [ -e "$path" ] || continue
    if [ -d "$path" ]; then
      scan_tree "$path"
    elif [ "${path##*.}" = sh ]; then
      validate_file "$path"
    fi
  done
}

if [ "$#" -gt 0 ]; then
  for file do
    case "$file" in
      /*) validate_file "$file" ;;
      *) validate_file "$ROOT/$file" ;;
    esac
  done
else
  scan_tree "$ROOT/device"
  scan_tree "$ROOT/host"
fi

if [ "$FAILURES" -ne 0 ]; then
  printf '!! validacao falhou: %s erro(s), %s script(s) verificado(s)\n' "$FAILURES" "$CHECKED" >&2
  exit 1
fi

if [ -n "$SHELLCHECK" ]; then
  printf '>> validacao OK: %s script(s), parse e shellcheck\n' "$CHECKED"
else
  printf '>> validacao OK: %s script(s), parse (shellcheck nao instalado)\n' "$CHECKED"
fi