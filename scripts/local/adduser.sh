#!/usr/bin/env bash
# adduser.sh — завести XMPP-юзера на сервере (запускать ЛОКАЛЬНО).
# Использование: ./scripts/local/adduser.sh root@IP username [password]
# Без пароля — сгенерит и напечатает (в историю чата не постить, сразу в менеджер паролей).
set -euo pipefail

TARGET="${1:?использование: adduser.sh root@IP username [password]}"
USERNAME="${2:?нужно имя юзера}"
XMPP_DOMAIN="${XMPP_DOMAIN:-xmpp.sigpay.xyz}"
PASSWORD="${3:-$(head -c 18 /dev/urandom | base64 | tr -d '/+=')}"

ssh "$TARGET" "printf '%s\n%s\n' '$PASSWORD' '$PASSWORD' | prosodyctl adduser '$USERNAME@$XMPP_DOMAIN'"
echo "JID:    $USERNAME@$XMPP_DOMAIN"
echo "Пароль: $PASSWORD"
