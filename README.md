# Sked

Расписание колледжа ВКСИТ на iPhone. Go-сервер `skedd` разбирает PDF с
rasp.vksit.ru и отдаёт JSON, а iOS-приложение показывает ближайшую пару,
следующий учебный день и расписание на день или неделю. Подробности в
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Развёртывание сервера

```sh
git clone https://github.com/relyay/sked.git
cd sked
# в первой строке Caddyfile укажи свой домен (сейчас там lunars.ru)
podman compose up -d     # или: docker compose up -d
```

Compose сам соберёт образ сервера и поднимет два контейнера: `sked`
(сервер) и `sked-caddy` (HTTPS с автоматическим сертификатом Let's Encrypt).
Проверка:

```sh
curl https://<домен>/health
```

Если домен поменялся, в iOS-приложении нужно поправить `Server.production`
в `ios/Sources/SkedCore/Profile.swift`.

### Что нужно один раз настроить на сервере

- **DNS:** A-запись домена указывает на публичный IP сервера.
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

### Логи, обновление, данные

```sh
podman compose logs -f sked
git pull && podman compose down && podman compose up -d --build   # обновление
```

`down` перед `up` обязателен для podman-compose 1.0.x: он не пересоздаёт
существующие контейнеры, а запускает старые. Тома (данные и сертификаты)
`down` не трогает.

Снимки расписания лежат в томе `sked-data`, сертификаты — в `caddy-data`
(этот том не удаляй, иначе сертификат придётся получать заново). Ручные
исправления расписания (оверрайды) кладутся в том:

```sh
podman cp spo.json sked:/data/overrides/spo.json   # подхватятся в течение 2 минут
```

Формат оверрайдов описан в [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Разработка

```sh
cd server && go test ./...                    # сервер
cd ios && SKED_CORE_ONLY=1 swift test         # логика iOS-клиента (на Linux)
just ios                                      # dist/Sked.ipa (xtool)
```

## Лицензия

[MIT](LICENSE)
