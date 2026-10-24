# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Deploy: `git clone`, set the domain on the first line of `Caddyfile`, `podman compose up -d` (compose builds `server/Dockerfile` itself; no just target for the server). Stack: `sked` (only `expose`d) + `sked-caddy` (TLS via Let's Encrypt, proxies to `sked:1984`). Data lives in the `sked-data` named volume, not a bind mount, because rootless podman can't map host UIDs; `/data` is chowned to 65532 in the image so a fresh volume is writable. Deployment steps and host prerequisites are in `docs/ARCHITECTURE.md` (Deployment). Keep `compose.yaml` compatible with podman-compose 1.0.x (Ubuntu's): no compose `healthcheck` (it is wrapped in `/bin/sh -c`, absent in distroless), and updates need `down` before `up` because it won't recreate existing containers. `just ios` → `dist/Sked.ipa` (release, unsigned; `xtool install` signs). `just android` → runs the Android unit tests and builds `dist/Sked.apk` (release, signed with the debug key).

**Sked** — schedule app for students of the VKSIT college: a Go server (`server/`) parses the college's schedule PDFs and serves JSON; an iOS 26 SwiftUI client (`ios/`, built on Linux with xtool) and an Android Jetpack Compose client (`android/`) consume it. The two clients mirror each other: same screens, rules, strings and tests — change both together. The client never touches the PDFs or rasp.vksit.ru. Full design, data model and API contract: `docs/ARCHITECTURE.md` — keep it in sync when the JSON shape or endpoints change.

App icon: `icon.png` at the repo root is the source; `python3 tools/make_icons.py icon.png . [preview.png]` (needs Pillow) regenerates `ios/AppResources/AppIcon.png` (`iconPath` in `xtool.yml`), the Android adaptive-icon foreground PNGs and the background color in `values/colors.xml` (sampled from the corners); the optional preview shows the Android icon under a circular mask.

## iOS commands (run in `ios/`)

```sh
SKED_CORE_ONLY=1 swift test                        # SkedCore tests on Linux (Swift Testing)
SKED_CORE_ONLY=1 swift test --filter NextSchoolDayTests
xtool dev build                                    # cross-compile the app → xtool/Sked.app
xtool dev                                          # build, install and launch on a connected iPhone
```

`SKED_CORE_ONLY` makes `Package.swift` drop the SwiftUI target; plain `swift test` fails on Linux because it builds every target. The manifest is evaluated on the Linux host even during xtool cross-compilation, so `#if os(...)` in the manifest cannot distinguish the two.

## Server commands (run in `server/`)

```sh
go test ./...                                  # parser tests on real PDFs + HTTP integration tests
go test ./internal/parser -run TestParseSPO -v # single test
go test -race ./...
go vet ./... && gofmt -l .
go run ./cmd/parsepdf testdata/spo.pdf         # PDF → JSON on stdout, parser warnings on stderr
go run ./cmd/skedd -addr 127.0.0.1:1984 -data /tmp/sked-data
```

Server listens on `0.0.0.0:1984` by default; the iOS client talks only to `https://rasp.relya.ru` (hard-coded `Server.production` in `SkedCore`; no user-facing server setting, no ATS exceptions), so production must sit behind a TLS reverse proxy. Env vars: `SKED_ADDR`, `SKED_DATA`, `SKED_NPO_URL`, `SKED_SPO_URL`, `SKED_DEBUG`. There is no admin/manual-refresh endpoint by design (it would let anyone make the server hammer rasp.vksit.ru); the 2-minute ticker is the only refresh. `skedd -healthcheck` probes `/health` and is the container health check (the distroless image has no shell or curl).

## Server architecture

Pipeline: `updater` (2-min ticker) → `source.Fetcher` (conditional GET, then sha256 of body decides "changed") → `pdfx.Read` → `parser.Parse` → `store.Update` → `api` serves `store.Views` (snapshots + overrides). On fetch/parse failure the last snapshot keeps being served; a failed parse calls `Fetcher.Forget()` so the same bytes are retried. Bump `parser.Version` whenever parser output changes: stored snapshots with another version are re-parsed on start even if the PDF is unchanged.

Facts about the source PDFs that drive the parser design (verified on `testdata/*.pdf`, 23.10.2026):
- Building number comes from the page header «N КОРПУС» ("building N"), not the file name: `npo.pdf` is building **2**, `spo.pdf` is building **1**.
- Groups move between buildings day to day (11 of 36 in the test PDFs), so building is per lesson (`Lesson.building`), never part of the student's profile. Clients query `/schedule?group=…` without `building`; the API merges both sources by date.
- One page = one day; the PDF is a rolling window of upcoming days, so `store` keeps days that dropped out for 14 days.
- Excel lets text overflow into empty neighbouring cells, so text alone can't distinguish a whole-group lesson (merged cell) from a subgroup-1-only lesson. `pdfx` is a custom content-stream interpreter (on top of `ledongthuc/pdf` for object/ToUnicode decoding only) that yields text runs with their **origin point** plus ruling-line segments; `parser` rebuilds the grid (pair rows × subgroup columns) and union-finds cells across missing borders — horizontally (merged subgroups/groups) and vertically (multi-pair cells → `Lesson.PairTo`).
- Content-stream order is not visual order (pair numbers appear 6→1); always sort by coordinates.
- Cell text is classified by shape in `parser/cell.go` (room, «Д» = remote, teacher «Фамилия И.О.» (surname + initials), lunch («Обед») / «Занятия начинаются с» ("classes start at") notes, rest = subject). Annotations split across runs are re-joined there.
- Some pages (remote Saturdays) have no bell times. `parser/times.go` fills them from the most common times of the same PDF (`timeSource: "bells"`); on Saturdays pairs last 60 minutes (college rule), keeping the weekday first start and breaks (`saturdayBells`) and, for in-person pairs with a «Занятия начинаются с» ("classes start at") note, shifts them to that start (`timeSource: "startsAt"`). The client shows them like any other time (no "≈", per product decision). Never invent data beyond this.
- A teacher cell may end with «с 8:30» ("from 8:30"); it becomes `Lesson.note`, but is dropped when it equals the lesson's start (`dropRedundantStartNotes`), e.g. a whole-day exam.
- Anything unrecognised goes into `Result.Warnings` (logged, persisted in the snapshot, counted in `/health`). `TestNoUnrecognisedCells` fails on any warning other than missing bell times — when a new PDF breaks it, add the new real PDF to `testdata/` and extend the classifier.

Manual overrides: `<data>/overrides/<npo|spo>.json` (`{"days":[{date, group, lessons, notes}]}`) replace a group's day wholesale, win over the parser, and are reread on every tick.

`/schedule`, `/groups`, `/buildings` responses carry a content-hash `ETag` and answer `If-None-Match` with 304; keep new cacheable endpoints on `writeCached`.

## iOS architecture

- `SkedCore` holds every rule worth testing (subgroup filtering, next lesson, next school day, Moscow "today", validation, JSON decoding). Keep it free of SwiftUI so it stays testable on Linux; `Sked` is views, `AppModel`, networking and the cache.
- SwiftData's `@Model` macro is unavailable with xtool on Linux (the SDK's macro server lacks `SwiftDataMacros`), so the offline cache is JSON files (`Storage/ScheduleCache.swift`). `@Observable` works.
- Strings live in `Bundle.module`, not the main bundle: always localize via `L("key \(arg)")` (`Shared/Localization.swift`) and add the key to both `Resources/ru.lproj` and `en.lproj`. Interpolated `Int` → `%lld`, `String` → `%@` in the key; plurals go in `.stringsdict`.
- Liquid Glass via iOS 26 APIs (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass/.glassProminent)`, `tabBarMinimizeBehavior`); deployment target is iOS 26, iPhone only (`Info.plist`).
- Format dates only through `Format` (`Format.locale` is derived from `Bundle.module.preferredLocalizations`, not `Locale.current`, so dates always match the UI language); the root view also sets `.environment(\.locale, Format.locale)`.
- The main bundle needs `AppResources/<lang>.lproj` (listed under `resources` in `xtool.yml`); without them iOS runs the app as English-only and `Locale.current`, dates and system controls ignore the Russian device language.
- `UITests/` is XCUITest for a Mac/Xcode run; it is not part of the SwiftPM package. Accessibility identifiers it relies on: `onboarding.*`, `retry`, `home.currentLesson`. The app honours `-uitest-reset` and the `SKED_SERVER_URL` launch environment (test-only override of the server URL).

## Android commands (run in `android/`, `ANDROID_HOME` defaults to `~/Android/Sdk` in the Justfile)

```sh
./gradlew :app:testDebugUnitTest                                   # core + JSON tests (JVM)
./gradlew :app:testDebugUnitTest --tests 'ru.sked.app.core.NextSchoolDayTest'
./gradlew :app:assembleDebug -PskedServerUrl=http://10.0.2.2:1984  # debug build against a local skedd from the emulator
```

## Android architecture

- Versions follow `gradle/libs.versions.toml` (AGP 9 with built-in Kotlin, Compose BOM, Material 3); no third-party libraries — networking is `HttpURLConnection` + `HttpResponseCache` (ETag/304), JSON is `org.json`, the profile is `SharedPreferences`, the offline cache is a JSON file.
- `ru.sked.app.core` is the Kotlin twin of `SkedCore` (pure Kotlin + `java.time`, no Android APIs) and `app/src/test` mirrors `ios/Tests/SkedCoreTests`; keep rules identical across the two.
- `BuildConfig.SERVER_URL` is `https://rasp.relya.ru`; only debug builds may override it (`-PskedServerUrl`), and only debug's `network_security_config` allows cleartext, for `10.0.2.2`/`localhost`.
- UI is Material 3 only: `NavigationBar` tabs, `TopAppBar`s, cards, `SegmentedButton`, `FilterChip`, `PullToRefreshBox`, dynamic color. Sub-screens (profile editor, group picker) are state-driven with `BackHandler`, no navigation library.
- Russian strings are the default `values/`, English is `values-en/` (per-app language via `locales_config`); format dates with the helpers in `ui/Format.kt`, which use the resources' locale.

## UI conventions (both clients)

- «Занятия начинаются с …» ("classes start at") is shown only when it adds information: `ScheduleQuery.startsAt` hides it when the first in-person class already starts at that time or when a day has no in-person class.
- iOS sub-screens (Edit profile, group picker) use the same `ScreenBackground` as the screen they are pushed from.
- No decorative icons in content: only lunch breaks and «Занятия начинаются с» ("classes start at") notes carry icons. Navigation chrome (tab icons, back arrows, chevrons, the selected-group checkmark) stays.
- Home shows only the current/next class card (plus the stale-data banner). Resetting the profile lives in the "Edit profile" screen behind the profile card.
