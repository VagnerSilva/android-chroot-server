#!/bin/sh
# Servico de teste dinit — heartbeat simples
LOG=/var/log/dinit-test.log
OK=/run/dinit-test.ok
mkdir -p /var/log /run
echo "dinit-test start pid=$$ $(date -Iseconds 2>/dev/null || date)" >> "$LOG"
i=0
while true; do
  i=$((i + 1))
  echo "ok tick=$i pid=$$ $(date -Iseconds 2>/dev/null || date)" > "$OK"
  echo "tick=$i $(date -Iseconds 2>/dev/null || date)" >> "$LOG"
  sleep 5
done
