#!/usr/bin/env bash
# issue-certs.sh — Let's Encrypt для XMPP-домена (запускать НА VPS от root).
# Идемпотентен; безопасно гонять до появления DNS — сам проверит и откажется.
#
# HTTP-01 standalone на :80 (порт на этом узле свободен).
# После выпуска: prosodyctl cert import + копия для coturn + рестарты.
# Продление — штатный certbot.timer, deploy-hook делает то же самое.
#
# Env: XMPP_DOMAIN (default: xmpp.sigpay.xyz)
set -euo pipefail

XMPP_DOMAIN="${XMPP_DOMAIN:-xmpp.sigpay.xyz}"
DOMAINS=("$XMPP_DOMAIN" "upload.$XMPP_DOMAIN" "conference.$XMPP_DOMAIN")

MY_IP="$(curl -fsS4 --max-time 10 https://ifconfig.me)"
for d in "${DOMAINS[@]}"; do
  got="$(dig +short A "$d" @1.1.1.1 | tail -1)"
  if [[ "$got" != "$MY_IP" ]]; then
    echo "✗ DNS не готов: $d → '${got:-ничего}' (жду $MY_IP). Добавь A-записи (DNS only, серая тучка) и перезапусти."
    exit 2
  fi
done
echo "==> DNS ок для: ${DOMAINS[*]}"

export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq certbot dnsutils >/dev/null

# deploy-hook: прокидывает свежий серт в prosody и coturn при каждом продлении
cat > /etc/letsencrypt/renewal-hooks/deploy/xmpp-box.sh <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
LIVE="/etc/letsencrypt/live"
DOMAIN_DIR="$(ls -d $LIVE/*/ | head -1)"
prosodyctl --root cert import "$LIVE" >/dev/null 2>&1 || true
install -o turnserver -g turnserver -m 600 "$DOMAIN_DIR/fullchain.pem" /etc/xmpp-box/turn-cert.pem
install -o turnserver -g turnserver -m 600 "$DOMAIN_DIR/privkey.pem"   /etc/xmpp-box/turn-key.pem
systemctl restart prosody coturn
HOOK
chmod +x /etc/letsencrypt/renewal-hooks/deploy/xmpp-box.sh

certbot certonly --standalone --non-interactive --agree-tos \
  --register-unsafely-without-email --expand \
  $(printf -- '-d %s ' "${DOMAINS[@]}")

/etc/letsencrypt/renewal-hooks/deploy/xmpp-box.sh
echo "==> Сертификаты выпущены и подключены (prosody + coturn перезапущены)"
