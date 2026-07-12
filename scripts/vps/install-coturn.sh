#!/usr/bin/env bash
# install-coturn.sh — идемпотентный bootstrap TURN/STUN-сервера (запускать НА VPS от root).
# Нужен для звонков: релеит медиа, когда оба клиента за NAT (мобильные сети — почти всегда).
#
# Секрет — общий с prosody (mod_turn_external), из /etc/xmpp-box/turn.secret.
# Порты: 3478 tcp+udp (STUN/TURN), 5349 tcp (TURNS/TLS, после issue-certs.sh),
#        49152–65535 udp (релей; НЕ пересекается с HY2-hop 20000–40000).
#
# Env: XMPP_DOMAIN (default: xmpp.sigpay.xyz) — realm и имя для TLS.
set -euo pipefail

XMPP_DOMAIN="${XMPP_DOMAIN:-xmpp.sigpay.xyz}"

[[ -s /etc/xmpp-box/turn.secret ]] || { echo "Нет /etc/xmpp-box/turn.secret — сначала install-prosody.sh"; exit 1; }
TURN_SECRET="$(cat /etc/xmpp-box/turn.secret)"
PUBLIC_IP="$(curl -fsS4 --max-time 10 https://ifconfig.me || hostname -I | awk '{print $1}')"

echo "==> coturn bootstrap: realm $XMPP_DOMAIN, external IP $PUBLIC_IP"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq coturn >/dev/null

cat > /etc/turnserver.conf <<EOF
# xmpp-box: генерится install-coturn.sh, руками не править
listening-port=3478
tls-listening-port=5349
listening-ip=0.0.0.0
external-ip=${PUBLIC_IP}
relay-ip=${PUBLIC_IP}

min-port=49152
max-port=65535

fingerprint
use-auth-secret
static-auth-secret=${TURN_SECRET}
realm=${XMPP_DOMAIN}

# TLS-серты подложит issue-certs.sh (deploy-hook копирует из letsencrypt)
cert=/etc/xmpp-box/turn-cert.pem
pkey=/etc/xmpp-box/turn-key.pem

# hardening: не даём релеить внутрь и в приватные сети
no-cli
no-multicast-peers
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=100.64.0.0-100.127.255.255
denied-peer-ip=169.254.0.0-169.254.255.255

no-software-attribute
EOF

# без сертов coturn на 5349 не стартует — заглушки, если LE ещё нет
if [[ ! -s /etc/xmpp-box/turn-cert.pem ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -subj "/CN=${XMPP_DOMAIN}" \
    -keyout /etc/xmpp-box/turn-key.pem -out /etc/xmpp-box/turn-cert.pem >/dev/null 2>&1
  chown turnserver:turnserver /etc/xmpp-box/turn-*.pem
fi

# на Ubuntu coturn выключен по умолчанию
sed -i 's/^#\?TURNSERVER_ENABLED=.*/TURNSERVER_ENABLED=1/' /etc/default/coturn 2>/dev/null || true
systemctl enable --now coturn
systemctl restart coturn

echo "==> coturn поднят: 3478 (tcp/udp), 5349 (tls), релей 49152-65535/udp"
