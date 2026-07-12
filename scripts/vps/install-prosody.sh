#!/usr/bin/env bash
# install-prosody.sh — идемпотентный bootstrap XMPP-сервера Prosody (запускать НА VPS от root).
#
# Что поднимает:
#   - Prosody 0.12 (из репо Ubuntu 24.04)
#   - VirtualHost $XMPP_DOMAIN: MAM (история), carbons, smacks, CSI, PEP/pubsub,
#     blocklist, bookmarks — полный «современный» набор для Conversations/Dino
#   - Component upload.$XMPP_DOMAIN (http_file_share) — файлы, голосовые, видео
#   - Component conference.$XMPP_DOMAIN (MUC + MAM) — групповые чаты
#   - mod_turn_external — раздаёт клиентам креды нашего coturn (звонки, XEP-0215)
#
# Env:
#   XMPP_DOMAIN   (default: xmpp.sigpay.xyz)
#   ADMIN_USER    (default: dima) — JID админа = $ADMIN_USER@$XMPP_DOMAIN
#   UPLOAD_LIMIT_MB (default: 104857600 = 100 MiB на файл)
#
# TURN-секрет — общий с install-coturn.sh, живёт в /etc/xmpp-box/turn.secret
# (генерится здесь, если нет). Сертификаты — отдельным issue-certs.sh; до них
# prosody работает на самоподписанных (prosodyctl cert generate).
set -euo pipefail

XMPP_DOMAIN="${XMPP_DOMAIN:-xmpp.sigpay.xyz}"
ADMIN_USER="${ADMIN_USER:-dima}"
UPLOAD_LIMIT="${UPLOAD_LIMIT_MB:-100}"

echo "==> Prosody bootstrap: домен $XMPP_DOMAIN, админ $ADMIN_USER@$XMPP_DOMAIN"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq prosody lua-dbi-sqlite3 >/dev/null

# --- общий TURN-секрет ---
mkdir -p /etc/xmpp-box
if [[ ! -s /etc/xmpp-box/turn.secret ]]; then
  head -c 32 /dev/urandom | base64 | tr -d '/+=' > /etc/xmpp-box/turn.secret
  chmod 600 /etc/xmpp-box/turn.secret
  echo "==> Сгенерирован новый TURN-секрет"
fi
TURN_SECRET="$(cat /etc/xmpp-box/turn.secret)"

# --- конфиг целиком (мы владеем боксом, override проще merge) ---
cat > /etc/prosody/prosody.cfg.lua <<EOF
-- xmpp-box: генерится install-prosody.sh, руками не править (правки — в репо)

admins = { "${ADMIN_USER}@${XMPP_DOMAIN}" }

pidfile = "/run/prosody/prosody.pid"

modules_enabled = {
    -- ядро
    "roster"; "saslauth"; "tls"; "dialback"; "disco"; "posix";
    -- полезное
    "private"; "vcard4"; "vcard_legacy"; "version"; "uptime"; "time"; "ping";
    -- современный мобильный стек
    "carbons";      -- синк между устройствами
    "mam";          -- история на сервере
    "smacks";       -- stream management (мобильные обрывы)
    "csi_simple";   -- экономия батареи
    "blocklist";
    "bookmarks";
    "pep";          -- PubSub-per-user: аватары, OMEMO-ключи, микроблог XEP-0277
    -- звонки: выдача TURN-кредов клиентам (XEP-0215)
    "turn_external";
    -- админка
    "admin_shell";
}

allow_registration = false          -- юзеров заводим только prosodyctl adduser

c2s_require_encryption = true
s2s_require_encryption = true
s2s_secure_auth = true

authentication = "internal_hashed"

storage = "internal"

archive_expires_after = "1y"        -- MAM: хранить историю год

-- TURN для звонков (coturn на этом же хосте)
turn_external_host = "${XMPP_DOMAIN}"
turn_external_secret = "${TURN_SECRET}"
turn_external_port = 3478

-- HTTPS (http_file_share) на 5281
http_ports = { }
https_ports = { 5281 }
http_external_url = "https://upload.${XMPP_DOMAIN}:5281/"

certificates = "certs"

log = {
    info = "/var/log/prosody/prosody.log";
    error = "/var/log/prosody/prosody.err";
}

VirtualHost "${XMPP_DOMAIN}"

Component "upload.${XMPP_DOMAIN}" "http_file_share"
    http_file_share_size_limit = ${UPLOAD_LIMIT} * 1024 * 1024
    http_file_share_daily_quota = 1024 * 1024 * 1024   -- 1 GiB/сутки на юзера
    http_file_share_expires_after = 60 * 60 * 24 * 30  -- хранить 30 дней

Component "conference.${XMPP_DOMAIN}" "muc"
    modules_enabled = { "muc_mam"; "vcard_muc" }
    muc_room_default_public = false
EOF

# --- самоподписанные серты, пока нет Let's Encrypt (issue-certs.sh заменит) ---
for d in "$XMPP_DOMAIN" "upload.$XMPP_DOMAIN" "conference.$XMPP_DOMAIN"; do
  if [[ ! -e "/etc/prosody/certs/$d.crt" && ! -e "/etc/letsencrypt/live/$XMPP_DOMAIN/fullchain.pem" ]]; then
    yes '' | prosodyctl cert generate "$d" >/dev/null 2>&1 || true
  fi
done

prosodyctl check config
systemctl enable --now prosody
systemctl restart prosody

echo "==> Prosody поднят. Юзеров заводить: prosodyctl adduser имя@${XMPP_DOMAIN}"
