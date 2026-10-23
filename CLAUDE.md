# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Schedule app for VKSIT college students: a Go server (`server/`) parses the college's schedule PDFs and serves JSON; an iOS 26 SwiftUI client (`ios/`, built on Linux with xtool) consumes it. The client never touches the PDFs or rasp.vksit.ru. Full design, data model and API contract: `docs/ARCHITECTURE.md` — keep it in sync when the JSON shape or endpoints change.

## iOS commands (run in `ios/`)

```sh
VKSIT_CORE_ONLY=1 swift test                       # VKSITCore tests on Linux (Swift Testing)
VKSIT_CORE_ONLY=1 swift test --filter NextSchoolDayTests
xtool dev build                                    # cross-compile the app → xtool/VKSIT.app
xtool dev                                          # build, install and launch on a connected iPhone
```

`VKSIT_CORE_ONLY` makes `Package.swift` drop the SwiftUI target; plain `swift test` fails on Linux because it builds every target. The manifest is evaluated on the Linux host even during xtool cross-compilation, so `#if os(...)` in the manifest cannot distinguish the two.

## Server commands (run in `server/`)

```sh
go test ./...                                  # parser tests on real PDFs + HTTP integration tests
go test ./internal/parser -run TestParseSPO -v # single test
go test -race ./...
go vet ./... && gofmt -l .
go run ./cmd/parsepdf testdata/spo.pdf         # PDF → JSON on stdout, parser warnings on stderr
VKSIT_ADMIN_SECRET=x go run ./cmd/vksitd -addr 127.0.0.1:1984 -data /tmp/vksit-data
```

Server listens on `0.0.0.0:1984` by default; the iOS client defaults to `http://192.168.1.246:1984`. Env vars: `VKSIT_ADDR`, `VKSIT_DATA`, `VKSIT_NPO_URL`, `VKSIT_SPO_URL`, `VKSIT_ADMIN_SECRET` (empty disables `POST /admin/refresh`), `VKSIT_DEBUG`.

## Server architecture

Pipeline: `updater` (2-min ticker) → `source.Fetcher` (conditional GET, then sha256 of body decides "changed") → `pdfx.Read` → `parser.Parse` → `store.Update` → `api` serves `store.View` (snapshot + overrides). On fetch/parse failure the last snapshot keeps being served; a failed parse calls `Fetcher.Forget()` so the same bytes are retried.

Facts about the source PDFs that drive the parser design (verified on `testdata/*.pdf`, 23.10.2026):
- Building number comes from the page header «N КОРПУС», not the file name: `npo.pdf` is building **2**, `spo.pdf` is building **1**. The API's `building=` uses that number.
- One page = one day; the PDF is a rolling window of upcoming days, so `store` keeps days that dropped out for 14 days.
- Excel lets text overflow into empty neighbouring cells, so text alone can't distinguish a whole-group lesson (merged cell) from a subgroup-1-only lesson. `pdfx` is a custom content-stream interpreter (on top of `ledongthuc/pdf` for object/ToUnicode decoding only) that yields text runs with their **origin point** plus ruling-line segments; `parser` rebuilds the grid (pair rows × subgroup columns) and union-finds cells across missing borders — horizontally (merged subgroups/groups) and vertically (multi-pair cells → `Lesson.PairTo`).
- Content-stream order is not visual order (pair numbers appear 6→1); always sort by coordinates.
- Cell text is classified by shape in `parser/cell.go` (room, «Д» = remote, teacher «Фамилия И.О.», lunch / «Занятия начинаются с» notes, rest = subject). Annotations split across runs are re-joined there.
- Some pages (remote Saturdays) have no bell times. `parser/times.go` fills them from the most common times of the same PDF (`timeSource: "bells"`) and, for in-person pairs with a «Занятия начинаются с» note, shifts them to that start (`timeSource: "startsAt"`). The client must show these as approximate (≈). Never invent data beyond this.
- Anything unrecognised goes into `Result.Warnings` (logged, persisted in the snapshot, counted in `/health`). `TestNoUnrecognisedCells` fails on any warning other than missing bell times — when a new PDF breaks it, add the new real PDF to `testdata/` and extend the classifier.

Manual overrides: `<data>/overrides/<npo|spo>.json` (`{"days":[{date, group, lessons, notes}]}`) replace a group's day wholesale, win over the parser, and are reread on every tick.

`/schedule`, `/groups`, `/buildings` responses carry a content-hash `ETag` and answer `If-None-Match` with 304; keep new cacheable endpoints on `writeCached`.

## iOS architecture

- `VKSITCore` holds every rule worth testing (subgroup filtering, next lesson, next school day, Moscow "today", validation, JSON decoding). Keep it free of SwiftUI so it stays testable on Linux; `VKSIT` is views, `AppModel`, networking and the cache.
- SwiftData's `@Model` macro is unavailable with xtool on Linux (the SDK's macro server lacks `SwiftDataMacros`), so the offline cache is JSON files (`Storage/ScheduleCache.swift`). `@Observable` works.
- Strings live in `Bundle.module`, not the main bundle: always localize via `L("key \(arg)")` (`Shared/Localization.swift`) and add the key to both `Resources/ru.lproj` and `en.lproj`. Interpolated `Int` → `%lld`, `String` → `%@` in the key; plurals go in `.stringsdict`.
- Liquid Glass via iOS 26 APIs (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass/.glassProminent)`, `tabBarMinimizeBehavior`); deployment target is iOS 26, iPhone only (`Info.plist`).
- Lessons with `timeSource` set must render with "≈" (`Format.timeRange`).
- `UITests/` is XCUITest for a Mac/Xcode run; it is not part of the SwiftPM package. Accessibility identifiers it relies on: `onboarding.*`, `retry`, `home.currentLesson`. The app honours `-uitest-reset` and `VKSIT_SERVER_HOST`/`VKSIT_SERVER_PORT`.
