#!/bin/sh
# test-dinit-network.sh — instancia dinit de teste (user/container)
set -eu

RUN=/tmp/dinit-test-vp
SERVICES=$RUN/services
SOCKET=$RUN/dinitctl
LOG=$RUN/dinit.log

rm -rf "$RUN"
mkdir -p "$SERVICES" "$RUN"

# scripts (evitar '>' no campo command do dinit — parte o parse)
cat > "$RUN/network.sh" <<'EOF'
#!/bin/sh
echo NETWORK_UP > /tmp/dinit-test-vp/network.state
exec sleep 300
EOF

cat > "$RUN/test-network.sh" <<'EOF'
#!/bin/sh
echo TEST_NETWORK_UP > /tmp/dinit-test-vp/test-network.state
exec sleep 300
EOF
chmod 755 "$RUN/network.sh" "$RUN/test-network.sh"

# boot e obrigatorio quando arrancas o dinit sem outro alvo explicito
cat > "$SERVICES/boot" <<'SERVICE'
type = internal
depends-on = test-network
SERVICE

cat > "$SERVICES/network" <<'SERVICE'
type = process
command = /tmp/dinit-test-vp/network.sh
restart = false
SERVICE

cat > "$SERVICES/test-network" <<'SERVICE'
type = process
depends-on = network
command = /tmp/dinit-test-vp/test-network.sh
restart = false
SERVICE

echo "=== USUARIO ==="
id

echo "=== VALIDACAO ==="
command -v dinit
command -v dinitctl

echo "=== INICIANDO DINIT (user+container) ==="
rm -f "$SOCKET"

# --user/--container: nao gerir sistema
# --cgroup-path: chroot Android tem cgroup duplicado
dinit \
  --user \
  --container \
  --cgroup-path /sys/fs/cgroup \
  --services-dir "$SERVICES" \
  --socket-path "$SOCKET" \
  --log-file "$LOG" \
  boot \
  >>"$LOG" 2>&1 &
DINIT_PID=$!

cleanup() {
  dinitctl --socket-path "$SOCKET" shutdown 2>/dev/null || true
  kill "$DINIT_PID" 2>/dev/null || true
  wait "$DINIT_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

i=0
while [ ! -S "$SOCKET" ] && [ "$i" -lt 50 ]; do
  sleep 0.1
  i=$((i + 1))
done

if [ ! -S "$SOCKET" ]; then
  echo "FAIL: socket do dinit nao foi criado"
  echo "=== log ==="
  cat "$LOG" 2>/dev/null || true
  exit 1
fi

echo "=== SOCKET ==="
ls -l "$SOCKET"

sleep 1
echo "=== STATUS ==="
dinitctl --socket-path "$SOCKET" list || true

echo "=== ESTADO ==="
cat "$RUN/network.state" 2>/dev/null || echo "(sem network.state)"
cat "$RUN/test-network.state" 2>/dev/null || echo "(sem test-network.state)"

echo "=== RESULTADO ==="
grep -qx NETWORK_UP "$RUN/network.state" &&
grep -qx TEST_NETWORK_UP "$RUN/test-network.state" &&
echo "PASS: dependencia network -> test-network funcionou" ||
{
  echo "FAIL: dependencia nao funcionou"
  echo "=== log ==="
  cat "$LOG" 2>/dev/null || true
  exit 1
}
