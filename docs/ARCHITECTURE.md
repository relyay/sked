# Sked — architecture

## Layers

```
┌──────────────────────┐   HTTP/JSON (ETag, 304)   ┌──────────────────────────┐   conditional GET   ┌────────────────────┐
│ iOS client (SwiftUI) │ ────────────────────────▶ │ skedd (Go)               │ ──────────────────▶ │ rasp.vksit.ru      │
│  • profile (local)   │                           │  updater: 2-min tick     │   ETag / IMS /      │  npo.pdf, spo.pdf  │
│  • snapshot cache    │ ◀──────────────────────── │  pdfx → parser → store   │   body sha256       └────────────────────┘
│  • "next class"      │                           │  api: /health /schedule… │
└──────────────────────┘                           │  data/*.json + overrides │
                                                   └──────────────────────────┘
```

Only the server parses PDFs. The client never talks to rasp.vksit.ru.

## What the real PDFs showed (23.10.2026)

| Fact | Consequence |
|---|---|
| `npo.pdf` says «2 КОРПУС» ("building 2") in its header, `spo.pdf` says «1 КОРПУС» | the building number comes **from the page header**, not the file name |
| 11 of 36 groups attend both buildings on different days (ИСП-225ис: Fri/Mon building 1, Sat building 2) | the building is stored per lesson (`Lesson.building`), not in the profile; the client asks for a group's schedule across both PDFs |
| 1 page = 1 day; the file is a window of upcoming days (23, 24, 26) | the server keeps past days for 14 more days; days from a new PDF replace stored ones |
| Excel → ABBYY, text layer with ToUnicode | no OCR needed |
| Text overflows into empty neighbouring cells; a whole-group class is a merged cell | the grid is rebuilt **from the table's ruling lines**; text is assigned to a cell by its origin point (`Tm`) |
| Cells are also merged vertically (an exam for the whole day) | `Lesson.pairTo` |
| Remote = «Д» in the room («Ауд.») column | `isRemote: true`, empty `room` |
| On Saturday 24.10 class times are **missing** | times come from the bell schedule of other days of the same PDF (`timeSource: "bells"`); in-person classes are shifted by «Занятия начинаются с …» ("classes start at …"), `timeSource: "startsAt"` |
| «Занятия начинаются с 11:10», «Обед 10:55-11:20», «Обед с 11:25 до 11:50» (start time and lunch notes) belong to a group's cell and are often split into fragments | `notes[]` on `GroupDay` |
| NPO has its own bell schedule (9:00-10:30, 10:40-12:40, …) | a class's time is always taken from its PDF row |
| Group `ИСП-324а`: the first digit of the number is the course (year) | `course = 3` |

## Parser

1. `internal/pdfx` — a custom content-stream interpreter on top of `ledongthuc/pdf` (used only for reading objects and ToUnicode). It returns text runs `{x, y, size, text}` (one `Tj`/`TJ` each) and ruling segments (`m/l/S` and thin `re f`), with Y pointing down.
2. `internal/parser`:
   - header `на DD.MM.YYYY г. (weekday) N КОРПУС` → date and building;
   - blocks start with a «Группа:» ("Group:") row; each group has two subgroup columns;
   - class rows: the pair number is in the left column, bounds are horizontal lines;
   - the "pairs × subgroup columns" grid is merged (union-find) wherever a border is missing (≥60 % of its length). A cell covering both subgroups is a whole-group class; covering one, a subgroup class;
   - cell text is classified: room (`23/1`, `СЗ/1`, `ауд.114/1`, `11 цех`), «Д» (remote), teacher (`Фамилия И.О.`, optionally followed by «с 8:30»), notes, subject (everything else).
3. Anything unrecognised goes to `Result.Warnings`: it is logged, reported by `/health` (`warnings`) and stored in the snapshot.
4. A manual override `data/overrides/<npo|spo>.json` replaces a group's day entirely and wins over the parser. It is reread on every tick.

## Repository layout

```
server/
  cmd/skedd/         HTTP server (flags/env, `-healthcheck`)
  Dockerfile         multi-stage build → distroless static
  cmd/parsepdf/      debugging: PDF → JSON + warnings
  internal/pdfx/     PDF geometry
  internal/parser/   table reconstruction, cell parsing (+tests on testdata/*.pdf)
  internal/schedule/ data model
  internal/source/   conditional GET + sha256
  internal/store/    snapshots (memory + disk, atomic writes), history, overrides
  internal/updater/  ticker, source statuses
  internal/api/      endpoints (+integration tests with a fake origin)
  testdata/          real PDFs from 23.10.2026
ios/                 SwiftPM package + xtool.yml + Info.plist
  Sources/SkedCore/  pure logic without SwiftUI: API models, Profile + validation, Server (https://rasp.relya.ru),
                     ScheduleQuery (next class, next school day, subgroups), CollegeClock (Europe/Moscow)
  Sources/Sked/
    App/             SkedApp, RootView (onboarding ↔ TabView), AppModel (@Observable)
    Network/         APIClient: async/await, timeouts, 3 attempts with exponential backoff, URLCache (ETag → 304)
    Storage/         ScheduleCache: last successful /schedule in Application Support (JSON)
    Features/        Onboarding, Home, Schedule, Profile
    Shared/          GlassCard and lesson rows, Format, L() for strings from Bundle.module
    Resources/       ru.lproj, en.lproj (Localizable.strings + .stringsdict for "N classes")
  Tests/SkedCoreTests/   Swift Testing, runs on Linux
  UITests/           onboarding XCUITest (needs a Mac with Xcode)
Caddyfile, compose.yaml  deployment (see below)
```

## Data model

```jsonc
// Lesson
{ "pair": 1, "building": 2, "pairTo": 6,  // pairTo only for vertically merged cells
  "start": "08:30", "end": "10:00",       // Europe/Moscow
  "subject": "ОСиС", "teacher": "Петров С.И.", "room": "17/1",
  "isRemote": false,
  "subgroup": 1,                          // 1 | 2; absent = whole group
  "note": "с 8:30",
  "timeSource": "bells" }                 // not in the PDF: "bells" | "startsAt"; absent = time from the PDF

// Note
{ "kind": "startsAt" | "lunch" | "other", "text": "Обед 10:55-11:20",
  "time": "10:55", "endTime": "11:20", "pair": 3, "subgroup": 1 }

// GroupDay
{ "group": "ИСП-225а", "lessons": [Lesson], "notes": [Note] }

// Day
{ "date": "2026-10-23", "weekday": "пятница", "building": 1, "groups": [GroupDay] }
```

Values such as subjects, teachers, rooms, note texts and weekdays are copied from the Russian PDFs as is.

Subgroup merging on the client: subgroup N sees classes without `subgroup` and with `subgroup == N`. With the subgroup "not set", all classes are shown.

## API

All responses are JSON. `/schedule`, `/groups` and `/buildings` send an `ETag` (body hash), `Last-Modified` (parse time) and `Cache-Control: no-cache`, and answer `If-None-Match` with `304`. Errors look like `{"error": "..."}`.

| Method | Path | Response |
|---|---|---|
| GET | `/health` | `200 {status: ok\|degraded, version, lastParse, sources: [{source, building, lastCheck, lastSuccess, lastChange, lastError, days, warnings}]}` |
| GET | `/buildings` | `{buildings: [{building, source, parsedAt, sourceModified}]}` |
| GET | `/schedule?group=ИСП-225а[&building=1][&date=YYYY-MM-DD]` | `{group?, building?, parsedAt, sourceModified, days: [Day]}`. Without `building`, days from both buildings are merged by date and each lesson carries its building. At least one of `group` or `building` is required. A day stays in the response with `groups: []` if the group has no classes that day |
| GET | `/groups[?building=1]` | `{groups: [{name, course, buildings: [1, 2]}]}` (sorted by course, then name) |

Status codes: `400` — invalid `building`/`date`; `404` — unknown building; `503` + `Retry-After` — nothing parsed yet.

## iOS client: decisions

- **SwiftData is replaced by JSON files.** xtool builds on Linux lack the `SwiftDataMacros` plugin (`@Model`), so the offline snapshot is stored as JSON in Application Support. The profile lives in UserDefaults.
- "Today" uses `Calendar.current` with an explicit `TimeZone(identifier: "Europe/Moscow")`.
- Times with `timeSource` are shown like any other time. The Home "first at …" is the start of the first in-person class; on an all-remote day it is omitted.
- The main bundle contains `AppResources/ru.lproj` and `en.lproj` (`resources` in `xtool.yml`). Without them iOS treats the app as English-only, and dates and system controls come out in English.
- Data refreshes on launch, on return to the foreground, every 5 minutes, on pull-to-refresh and with the "Refresh now" button. On a network error the cache is shown with a "Showing data from …" banner. Without a cache, an error screen with "Retry" is shown.
- The server address is hard-coded: `https://rasp.relya.ru` (`Server.production`). There is no server setting in the app and no ATS exceptions. Only UI tests override the address through the `SKED_SERVER_URL` environment variable. In production the server sits behind a TLS reverse proxy (Caddy → `skedd` on :1984).

## Acceptance checklist

**Server**
- [x] `go test ./...` passes; `testdata/*.pdf` contain no unrecognised cells.
- [x] Re-checking an unchanged PDF does not re-parse it (304 / same sha256).
- [x] When a source is unavailable, the last snapshot is served and `/health` reports `degraded` with the error text.
- [x] `If-None-Match` → 304.
- [x] There is no manual refresh (`/admin/refresh`): the schedule is refreshed only by the 2-minute ticker.

**Onboarding**
- [ ] First launch opens a single screen: full name → group (searchable list by course) → subgroup. Building and course are not asked.
- [ ] "Save" is disabled without a group; with an empty name a hint appears and focus moves to the field.
- [ ] Groups come from `/groups`.
- [ ] If the server is unreachable, a clear message and a "Retry" button are shown.
- [ ] Saving opens Home immediately.

**Home**
- [ ] "Next class" card as "Class N · subject · time · building, room" with a "starts in …" countdown that updates every minute.
- [ ] During a class it says "in progress"; after the last one, "No more classes today — take a rest 🎉".
- [ ] Next school day card as "Tomorrow (Sat) · N classes · building · first at …", with the building taken from that day's classes; if tomorrow is free, a "No classes tomorrow" line.
- [ ] Skeletons while loading; offline with a cache, a "Showing data from …" banner; without a cache, "Retry".

**Schedule**
- [ ] Day/Week switch.
- [ ] Date chips start today and run to the end of the PDF; header "Friday, October 23 · today · building 2".
- [ ] On today, a "Next · Class N · in …" hint.
- [ ] The other subgroup's classes are hidden, the user's subgroup is not highlighted, lessons have no subgroup badge; remote classes read "remote · teacher" without a room; times have no "≈".
- [ ] Under the day header (and in each day's header in the week view) "Classes start at …" and lunch breaks from the PDF are shown for the user's subgroup.
- [ ] In the day view the subject comes first, then the time; in the week view the class number is in a circle, followed by the subject, the "start – end" time and the room.
- [ ] An empty day shows "No classes" with an icon.

**Profile**
- [ ] A user card at the top (initials, full name, group · course, subgroup as plain text); its chevron opens a screen with the name, group and subgroup.
- [ ] Below, "Data" and "About" sections, and "Reset profile" with confirmation at the very bottom. No server setting.
- [ ] "Data updated: …", a "Refresh now" button and the app version are visible.

**General**
- [ ] Light and dark themes, Dynamic Type up to AX5 without clipped text, VoiceOver reads cards as a whole.
- [ ] Switching the device language between ru and en switches every string.

## Running locally

```sh
cd server
go run ./cmd/skedd                                  # listens on 0.0.0.0:1984, data in ./data
go run ./cmd/skedd -addr 127.0.0.1:1984 -interval 2m -data /var/lib/sked
go test ./...                                       # parser on real PDFs + integration tests
go run ./cmd/parsepdf testdata/spo.pdf              # parser debugging
```

```sh
just ios                       # → dist/Sked.ipa
cd ios
SKED_CORE_ONLY=1 swift test    # client logic on Linux
xtool dev build                # build the .app
xtool dev                      # build and install on a connected iPhone
```

Env: `SKED_ADDR`, `SKED_DATA`, `SKED_NPO_URL`, `SKED_SPO_URL`, `SKED_DEBUG`.

## Deployment

```sh
git clone https://github.com/relyay/sked.git
cd sked
# put your domain on the first line of Caddyfile (currently rasp.relya.ru)
podman compose up -d     # or: docker compose up -d
curl https://<domain>/health
```

Compose builds `server/Dockerfile` itself and starts `sked` (not published, only `expose: 1984`) and `sked-caddy`. Caddy obtains a Let's Encrypt certificate for the domain in `Caddyfile` and proxies to `sked:1984`. If the domain changes, update `Server.production` in `ios/Sources/SkedCore/Profile.swift` too.

Data lives in the `sked-data` named volume: a bind-mounted `./data` does not work with rootless podman because of UID mapping. In the image `/data` is owned by user 65532, so a fresh volume is writable under both podman and docker. Certificates live in `caddy-data`; keep that volume, or the certificate has to be obtained again (Let's Encrypt rate limits).

### One-time host setup

- **DNS:** an A record for the domain points to the server's public IP, served by the DNS provider the domain is delegated to (its NS records).
- **Ports 80 and 443** are reachable from the internet (firewall, router forwarding). Let's Encrypt needs port 80 to issue the certificate.
- **A compose provider for podman:** `podman-compose` (or `docker-compose`).
- **Rootless podman and ports below 1024:**
  ```sh
  echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-unprivileged-ports.conf
  sudo sysctl --system
  ```
- **Restart after reboot:** `systemctl enable --now podman-restart.service` (rootful), or for rootless podman `systemctl --user enable --now podman-restart.service` plus `sudo loginctl enable-linger $USER`.

### Logs, updates, overrides

```sh
podman compose logs -f sked
git pull && podman compose down && podman compose up -d --build   # update
podman cp spo.json sked:/data/overrides/spo.json                   # override, picked up within 2 minutes
```

`down` before `up` is required with podman-compose 1.0.x: it does not recreate existing containers and starts the old ones instead. `down` keeps the volumes (data and certificates).
