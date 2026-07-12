#!/usr/bin/env bash
# deploy.sh — раскатать xmpp-box на VPS по SSH (запускать ЛОКАЛЬНО).
# Использование: ./scripts/local/deploy.sh root@78.40.194.160
# Env-переменные (XMPP_DOMAIN, ADMIN_USER, ...) пробрасываются на сервер.
set -euo pipefail

TARGET="${1:?использование: deploy.sh root@IP}"
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FWD="XMPP_DOMAIN=${XMPP_DOMAIN:-xmpp.sigpay.xyz} ADMIN_USER=${ADMIN_USER:-dima}"

echo "==> Deploy xmpp-box → $TARGET ($ENV_FWD)"
ssh "$TARGET" 'mkdir -p /opt/xmpp-box'
scp -q "$HERE"/scripts/vps/*.sh "$TARGET":/opt/xmpp-box/

for s in install-prosody.sh install-coturn.sh issue-certs.sh; do
  echo "──── $s ────"
  # issue-certs падает кодом 2, пока нет DNS — это ок, не валим деплой
  ssh "$TARGET" "chmod +x /opt/xmpp-box/*.sh; $ENV_FWD /opt/xmpp-box/$s" || {
    rc=$?
    [[ "$s" == issue-certs.sh && $rc -eq 2 ]] && continue
    exit $rc
  }
done

echo "──── статус ────"
ssh "$TARGET" 'systemctl is-active prosody coturn; ss -tulnp | grep -E ":(5222|5269|5281|3478|5349)\s" | awk "{print \$1, \$5}"'
