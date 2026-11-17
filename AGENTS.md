# AGENTS.md

Guidance for agents working in this repo. HealthyPi Studio is a Flutter desktop
app (macOS, Windows, Linux) for HealthyPi 6 hardware. Mobile and web targets are
deleted; do not add them back.

## Git workflow

- Work on a `feature/...` branch. Never commit directly to `main`.
- `origin` is the personal fork: `mikekurni/healthypi_studio`.
- `upstream` is `Protocentral/healthypi_studio`. Use it to sync:
  `git fetch upstream && git rebase upstream/main`.
- Commits must be clean, modular, and ready for an upstream PR. One concern per
  commit, descriptive sentence-case subject (see `git log`), no WIP or fixup
  commits left behind.
- Check `git branch --show-current` and `git status` before committing.

## Build and checks

Requires Flutter 3.44+ stable and Dart `^3.10.0`.

```bash
flutter pub get
flutter run -d macos                  # or windows / linux
flutter build macos --release
flutter analyze --no-fatal-infos      # must stay at zero errors and warnings
flutter test
dart run tool/gen_protocol.dart       # regenerate lib/protocol/*.g.dart
```

- `flutter analyze` must report zero errors and zero warnings. `info` lints are
  pre-existing and not fatal.
- `flutter test` must pass. Report real failures; do not skip or delete tests to
  reach green.
- `lib/protocol/*.g.dart` is generated from the firmware catalog snapshots in
  `protocol/`. Regenerate with the command above and commit the output. CI fails
  on a diff, and hand edits are lost.
- Release builds pin Flutter 3.44.6 in `.github/workflows/release.yml`. Do not
  bump that pin casually.

## Code layout

| Path | Contents |
|---|---|
| `lib/screens/` | One file per screen |
| `lib/widgets/hpi/` | Canvas-painted waveforms and UI components |
| `lib/services/` | USB serial, Wi-Fi, BLE, recording, firmware update |
| `lib/protocol/` | Packet parsing and generated protocol surfaces |
| `lib/controllers/`, `lib/models/` | State and data types |
| `protocol/` | Firmware catalog snapshots (generator input) |
| `tool/` | Build and codegen scripts |

Read `docs/DEVELOPER_GUIDE.md` before touching the data pipeline, recording, or
firmware update. Read `docs/DESIGN_SYSTEM.md` before changing styling.

## Coding preferences

- Match surrounding style. No new abstraction, wrapper, or config unless the
  task needs it. No new dependency for something small.
- Charting is hand-rolled with `CustomPainter`. Do not add a chart package.
- Never render a value the device did not report. Empty states beat invented data.
- Keep the raw recording format on disk unchanged. Display-only transforms stay
  in the UI layer.
- Add tests in `test/`, one file per unit, mirroring the `lib/` name.

## Flutter engineering standards

- **Architecture:** layer-first, as laid out above. Do not restructure into
  feature-first or Clean Architecture without an explicit request.
- **State management:** `provider` with `ChangeNotifier` (`StudioSession`,
  `StudioSettings`, `StudioNavController`, `LiveDataPump`). Do not add BLoC,
  Riverpod, GetX, or a second state approach.
- **Null safety:** no `!` unless nullability is provably impossible from earlier
  checks. No unsafe casts; parse at the boundary, then use typed values.
- **Const:** use `const` constructors and sub-widgets wherever possible.
- **Lists:** dynamic or long lists use `ListView.builder` / `SliverList`, never a
  `Column` of children.
- **Widget size:** keep `build` methods readable. Split past roughly 50 lines into
  private widget classes in the same file, or into `lib/widgets/hpi/` if reused.
- **Async:** handle loading and error states explicitly. Do not leave unawaited
  futures or swallow exceptions. No `print` in production paths; use the existing
  logging/debug facilities.
- **Desktop only:** no mobile layout branches, no `Cupertino` widgets, no new
  platform folders.

## Agents

Custom OpenCode agents live in `.opencode/agents/`:

| Agent | Purpose |
|---|---|
| `flutter-planner` | Read-only. Plans widget trees, state transitions, tasks. |
| `flutter-coder` | Implements tasks in `lib/`, `test/`, `pubspec.yaml`. |
| `flutter-reviewer` | Runs `flutter analyze` / `flutter test`, reports findings. |

## Session modes

- **caveman** (terse chat replies) and **ponytail full** (smallest complete change)
  are auto-activated by global OpenCode plugins. No per-directory action needed.
- If a session starts without them, say so and load the `caveman` / `ponytail`
  skill instead of silently ignoring the preference.
- caveman styles chat only. Code, comments, commits, and docs stay normal prose.

