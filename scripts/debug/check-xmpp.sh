#!/usr/bin/env bash
# check-xmpp.sh — быстрая проверка XMPP-сервера снаружи (запускать ЛОКАЛЬНО).
# Использование: ./scripts/debug/check-xmpp.sh [xmpp.sigpay.xyz]
set -uo pipefail

D="${1:-xmpp.sigpay.xyz}"

echo "── DNS ──"
for h in "$D" "upload.$D" "conference.$D"; do
  printf '%-25s → %s\n' "$h" "$(dig +short A "$h" @1.1.1.1 | tail -1)"
done

echo "── порты ──"
for p in 5222 5269 5281 5349; do
  timeout 4 bash -c "</dev/tcp/$D/$p" 2>/dev/null && echo "tcp/$p открыт" || echo "tcp/$p ЗАКРЫТ"
done

echo "── TLS (c2s, STARTTLS) ──"
openssl s_client -connect "$D:5222" -starttls xmpp -xmpphost "$D" -brief </dev/null 2>&1 | grep -E "Verification|subject|issuer" || true

echo "── STUN ──"
command -v stunclient >/dev/null && stunclient "$D" 3478 || echo "(stunclient не стоит — пропущено)"
