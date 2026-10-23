# ВКСИТ Расписание — архитектура

## Слои

```
┌──────────────────────┐   HTTP/JSON (ETag, 304)   ┌──────────────────────────┐   conditional GET   ┌────────────────────┐
│ iOS-клиент (SwiftUI) │ ────────────────────────▶ │ vksitd (Go)              │ ──────────────────▶ │ rasp.vksit.ru      │
│  • профиль (локально)│                           │  updater: тик 2 мин      │   ETag / IMS /      │  npo.pdf, spo.pdf  │
│  • кэш снимков       │ ◀──────────────────────── │  pdfx → parser → store   │   sha256 тела       └────────────────────┘
│  • «ближайшая пара»  │                           │  api: /health /schedule… │
└──────────────────────┘                           │  data/*.json + overrides │
                                                   └──────────────────────────┘
```

PDF разбирает только сервер. Клиент к rasp.vksit.ru не обращается.

## Что показал анализ реальных PDF (23.10.2026)

| Факт | Следствие |
|---|---|
| `npo.pdf` в заголовке «2 КОРПУС», `spo.pdf` — «1 КОРПУС» | номер корпуса берётся **из заголовка страницы**, а не из имени файла |
| 1 страница = 1 день, в файле окно ближайших дней (23, 24, 26) | сервер хранит прошедшие дни ещё 14 дней, а дни из нового PDF заменяют сохранённые |
| Excel → ABBYY, текстовый слой с ToUnicode | OCR не нужен |
| Текст вылезает в соседние пустые ячейки, общая пара — объединённая ячейка | сетку восстанавливаем **по линиям таблицы**, текст относим к ячейке по точке начала (`Tm`) |
| Ячейки объединяются и по вертикали (экзамен на весь день) | `Lesson.pairTo` |
| Дистант = «Д» в колонке «Ауд.» | `isRemote: true`, `room` пустой |
| В субботу 24.10 время пар **не указано** | время берётся из сетки звонков других дней того же PDF, `timeSource: "bells"` (клиент показывает ≈); очные пары сдвигаются по «Занятия начинаются с …», `timeSource: "startsAt"` |
| «Занятия начинаются с 11:10», «Обед 10:55-11:20», «Обед с 11:25 до 11:50» относятся к ячейке группы, часто разбиты на фрагменты | `notes[]` у `GroupDay` |
| У НПО своя сетка звонков (9:00-10:30, 10:40-12:40, …) | время пары всегда берём из строки PDF |
| Группа `ИСП-324а`: первая цифра номера — курс | `course = 3` |

## Парсер

1. `internal/pdfx` — собственный интерпретатор content stream поверх `ledongthuc/pdf` (из неё берём только чтение объектов и ToUnicode). Возвращает фрагменты текста `{x, y, size, text}` (один `Tj`/`TJ`) и отрезки линий (`m/l/S` и тонкие `re f`), ось Y направлена вниз.
2. `internal/parser`:
   - заголовок `на DD.MM.YYYY г. (день) N КОРПУС` → дата и корпус;
   - блоки начинаются строкой «Группа:», у каждой группы две колонки подгрупп;
   - строки пар: номер пары в левой колонке, границы — горизонтальные линии;
   - сетка «пары × колонки подгрупп» объединяется (union-find) там, где граница отсутствует (≥60 % длины). Если ячейка накрывает обе подгруппы, это пара всей группы; если одну — пара подгруппы;
   - классификация текста ячейки: аудитория (`23/1`, `СЗ/1`, `ауд.114/1`, `11 цех`), «Д», преподаватель (`Фамилия И.О.` с возможным хвостом «с 8:30»), примечания, предмет (всё остальное).
3. Нераспознанное попадает в `Result.Warnings`: логируется, отдаётся в `/health` (`warnings`) и сохраняется в снимке.
4. Ручной оверрайд `data/overrides/<npo|spo>.json` целиком заменяет день группы и имеет приоритет над парсером. Перечитывается на каждом тике.

## Структура репозитория

```
server/
  cmd/vksitd/        HTTP-сервер (флаги/env)
  cmd/parsepdf/      отладка: PDF → JSON + предупреждения
  internal/pdfx/     геометрия PDF
  internal/parser/   восстановление таблицы, разбор ячеек (+тесты на testdata/*.pdf)
  internal/schedule/ модель данных
  internal/source/   условный GET + sha256
  internal/store/    снимки (память + диск, атомарная запись), история, оверрайды
  internal/updater/  тикер, статусы источников
  internal/api/      эндпоинты (+интеграционные тесты с фейковым origin)
  testdata/          реальные PDF от 23.10.2026
ios/                 (следующий шаг) SwiftPM + xtool.yml
  Sources/VKSIT/
    App/             VKSITApp, RootView (онбординг ↔ TabView)
    Model/           DTO (Codable), Profile, ScheduleQuery (ближайшая пара, следующий день)
    Network/         APIClient (async/await, ретраи, ETag), ServerSettings
    Storage/         SwiftData: CachedSnapshot
    Features/        Onboarding, Home, Schedule, Profile
    Resources/       Localizable.xcstrings (ru, en)
  Tests/VKSITTests/  ScheduleQuery: ближайшая пара, следующий учебный день
```

## Модель данных

```jsonc
// Lesson
{ "pair": 1, "pairTo": 6,            // pairTo — только для объединённых по вертикали ячеек
  "start": "08:30", "end": "10:00",  // Europe/Moscow
  "subject": "ОСиС", "teacher": "Петров С.И.", "room": "17/1",
  "isRemote": false,
  "subgroup": 1,                     // 1 | 2; поле отсутствует — пара всей группы
  "note": "с 8:30",
  "timeSource": "bells" }            // нет в PDF: "bells" | "startsAt"; поле отсутствует — время из PDF

// Note
{ "kind": "startsAt" | "lunch" | "other", "text": "Обед 10:55-11:20",
  "time": "10:55", "endTime": "11:20", "pair": 3, "subgroup": 1 }

// GroupDay
{ "group": "ИСП-225а", "lessons": [Lesson], "notes": [Note] }

// Day
{ "date": "2026-10-23", "weekday": "пятница", "building": 1, "groups": [GroupDay] }
```

Как клиент склеивает подгруппы: для подгруппы N показываются пары без `subgroup` и с `subgroup == N`. Если подгруппа «не указана», показываются все пары с бейджами.

## API

Все ответы — JSON. Для `/schedule`, `/groups` и `/buildings` сервер отдаёт `ETag` (хэш тела), `Last-Modified` (время парса) и `Cache-Control: no-cache`, а на `If-None-Match` отвечает `304`. Ошибки приходят в виде `{"error": "..."}`.

| Метод | Путь | Ответ |
|---|---|---|
| GET | `/health` | `200 {status: ok\|degraded, version, lastParse, sources: [{source, building, lastCheck, lastSuccess, lastChange, lastError, days, warnings}]}` |
| GET | `/buildings` | `{buildings: [{building, source, parsedAt, sourceModified}]}` |
| GET | `/schedule?building=1[&date=YYYY-MM-DD][&group=ИСП-225а]` | `{building, source, parsedAt, sourceModified, days: [Day]}`. При `group` день остаётся в ответе с `groups: []`, если у группы в этот день пар нет |
| GET | `/groups?building=1` | `{building, groups: [{name, course, building}]}` (сортировка: курс, затем имя) |
| POST | `/admin/refresh` | заголовок `X-Admin-Secret`; `200`/`502 {sources, error?}`; без секрета или с неверным — `403` |

Коды ответов: `400` — неверный `building`/`date`; `404` — неизвестный корпус; `503` + `Retry-After` — ещё ничего не распарсено.

## Запуск

```sh
cd server
VKSIT_ADMIN_SECRET=… go run ./cmd/vksitd            # слушает 0.0.0.0:1984, данные в ./data
go run ./cmd/vksitd -addr 192.168.1.246:1984 -interval 2m -data /var/lib/vksit
go test ./...                                       # парсер на реальных PDF + интеграционные
go run ./cmd/parsepdf testdata/spo.pdf              # отладка парсера
```

Env: `VKSIT_ADDR`, `VKSIT_DATA`, `VKSIT_NPO_URL`, `VKSIT_SPO_URL`, `VKSIT_ADMIN_SECRET`, `VKSIT_DEBUG`.
