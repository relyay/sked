# Sked

Расписание колледжа ВКСИТ на iPhone. Go-сервер `skedd` разбирает PDF с
rasp.vksit.ru и отдаёт JSON, а iOS-приложение показывает ближайшую пару,
следующий учебный день и расписание на день или неделю. Подробности в
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Развёртывание сервера

```sh
git clone https://github.com/relyay/sked.git
cd sked
just server              # собирает образ localhost/sked-server:latest
podman compose up -d     # или: docker compose up -d
```

Поднимаются два контейнера: `sked` (сервер) и `sked-caddy` (HTTPS для
`lunars.ru` с автоматическим сертификатом Let's Encrypt). Проверка:

```sh
curl https://lunars.ru/health
```

### Что нужно один раз настроить на сервере

- **DNS:** A-запись `lunars.ru` указывает на публичный IP сервера.
- **Порты 80 и 443** открыты из интернета (файрвол, проброс на роутере).
  Порт 80 нужен Let's Encrypt для выдачи сертификата.
- **Compose-провайдер для podman:** `sudo pacman -S podman-compose`
  (или `docker-compose`).
- **Rootless podman и порты ниже 1024:**
  ```sh
  echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-unprivileged-ports.conf
  sudo sysctl --system
  ```
- **Автозапуск после перезагрузки (rootless podman):**
  ```sh
  systemctl --user enable --now podman-restart.service
  sudo loginctl enable-linger $USER
  ```

### Настройки (переменные окружения или файл `.env` рядом с `compose.yaml`)

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `SKED_DOMAIN` | `lunars.ru` | домен для Caddy; `localhost` — локальная проверка с внутренним CA |
| `SKED_HTTP_PORT` / `SKED_HTTPS_PORT` | `80` / `443` | порты на хосте |
| `SKED_DEBUG` | — | подробные логи сервера |

### Логи, обновление, данные

```sh
podman compose logs -f sked
git pull && just server && podman compose up -d   # обновление
```

Снимки расписания лежат в томе `sked_sked-data`, сертификаты — в
`sked_caddy-data` (этот том не удаляй, иначе сертификат придётся получать
заново). Ручные исправления расписания (оверрайды) кладутся в том:

```sh
podman cp spo.json sked:/data/overrides/spo.json   # подхватятся в течение 2 минут
```

Формат оверрайдов описан в [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Разработка

```sh
cd server && go test ./...                    # сервер
cd ios && SKED_CORE_ONLY=1 swift test         # логика iOS-клиента (на Linux)
just server-bin                               # бинарник dist/skedd без контейнеров
just ios                                      # dist/Sked.ipa (xtool)
```

## Лицензия

[MIT](LICENSE)
