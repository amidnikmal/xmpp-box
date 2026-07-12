# xmpp-box

Свой XMPP-сервер одним деплоем: Prosody + coturn + Let's Encrypt на VPS.
Стиль vpn-box: идемпотентные bootstrap'ы, запуск по SSH.

```text
клиент (Conversations / Dino / Gajim)
   │ 5222 c2s · STARTTLS
   ▼
VPS 78.40.194.160 (xmpp.sigpay.xyz)
   ├─ prosody   5222 c2s · 5269 s2s · 5281 https (файлы/голосовые)
   └─ coturn    3478 stun/turn · 5349 turns · 49152-65535/udp релей (звонки)
```

## Что умеет

- **Чаты** с историей на сервере (MAM, год), синком устройств (carbons),
  выживанием мобильных обрывов (smacks), OMEMO-шифрованием (PEP).
- **Звонки** аудио/видео 1:1 (Jingle + свой TURN; Conversations, Dino).
- **Голосовые сообщения / файлы / видео** — http_file_share, до 100 МБ,
  квота 1 ГБ/сутки, хранение 30 дней.
- **Групповые чаты** (MUC + история).
- Регистрация закрыта: юзеры только через `adduser.sh`.

«Сториес» как в IG в XMPP-клиентах нет; ближайший аналог — микроблог
XEP-0277 поверх PEP (клиент Movim). PEP включён, UI-сториес — не отсюда.

## Деплой

```bash
./scripts/local/deploy.sh root@78.40.194.160       # prosody + coturn + серты
./scripts/local/adduser.sh root@78.40.194.160 dima # завести юзера
./scripts/debug/check-xmpp.sh                      # проверить снаружи
```

DNS (Cloudflare, зона sigpay.xyz, все записи **DNS only** — серая тучка):

| Тип | Имя | Значение |
|-----|-----|----------|
| A | `xmpp` | 78.40.194.160 |
| A | `upload.xmpp` | 78.40.194.160 |
| A | `conference.xmpp` | 78.40.194.160 |

JID = `имя@xmpp.sigpay.xyz` (домен = хостнейм, SRV-записи не нужны).
`issue-certs.sh` сам ждёт DNS: пока записей нет — деплой ставит всё на
самоподписанных, после появления DNS перезапустить деплой (или только
`issue-certs.sh` на сервере).

## Структура

```text
scripts/
  vps/     запускаются НА VPS (deploy.sh довозит их сам)
    install-prosody.sh   prosody + конфиг (MAM/carbons/upload/MUC/turn_external)
    install-coturn.sh    TURN для звонков, секрет общий с prosody
    issue-certs.sh       Let's Encrypt (HTTP-01 :80) + deploy-hook на продление
  local/   запускаются ЛОКАЛЬНО
    deploy.sh            оркестратор: scp + запуск всех bootstrap'ов
    adduser.sh           завести юзера, напечатать креды
  debug/
    check-xmpp.sh        DNS/порты/TLS/STUN снаружи
out/       секрет-несущие артефакты (в .gitignore)
```

## Грабли

- Порт TURN-релея 49152–65535/udp выбран **вне** 20000–40000 (на узлах
  vpn-box тот диапазон REDIRECT'ится в Hysteria2).
- Записи в Cloudflare держать «DNS only»: проксирование ломает XMPP и TURN.
- coturn без TLS-серта не стартует — install-coturn.sh кладёт самоподписанную
  заглушку, issue-certs.sh заменяет её на LE и дальше продляет сам.
