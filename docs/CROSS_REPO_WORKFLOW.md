# Cross-Repo Workflow: Studio App + Firmware

HealthyPi Studio (Flutter, this repo) and the HealthyPi 6 firmware (Zephyr RTOS,
separate repo) are two codebases linked by one wire protocol. This document is
the working agreement for changing them together.

## 1. Layout

Keep the repos as siblings. Do not merge them and do not use submodules.

```
~/Projects/hpi6/
├── healthypi_studio/      # app (this repo)
└── healthypi_fw/          # firmware (clone from Protocentral)
```

```bash
git clone https://github.com/Protocentral/healthypi-6-fw.git \
  ~/Projects/hpi6/healthypi_fw
```

## 2. Shared contract

The protocol lives in **this app repo** and is the single source of truth:

- `docs/PROTOCOL_REFERENCE.md`
- `lib/protocol/hp6_formats.dart` and `lib/protocol/*.g.dart`

Firmware is a producer that must match. When a wire change is needed:

1. Update `PROTOCOL_REFERENCE.md` in this repo.
2. Regenerate `lib/protocol/*.g.dart` with `dart run tool/gen_protocol.dart`.
3. Mirror the change in firmware.
4. Tag both commits with the same protocol version and issue number.

Add a protocol version line to `PROTOCOL_REFERENCE.md` so drift is visible.

## 3. Graphify across both repos

Build one merged graph that links app parsing code to firmware producers:

```bash
/graphify /Users/mikekurniawan/Projects/hpi6/healthypi_studio /Users/mikekurniawan/Projects/hpi6/healthypi_fw
```

Run the command from the common parent (`~/Projects/hpi6`), not from inside
either repo. Graphify writes `graphify-out/` into the current working
directory, so running from the parent keeps the merged graph out of both
repositories and avoids polluting either git tree.

Re-run with `--update` after either repo changes, or full rebuild after
protocol changes. Add `graphify-out/` to `.gitignore` in the firmware repo too.

## 4. Branch and commit strategy

Each repo keeps its own `main` and `feature/<slug>` branches. A cross-repo
change is two branches, one per repo, linked by protocol version and issue
number. Never try to make one commit span both repos.

Before merging in either repo:

```bash
flutter analyze --no-fatal-infos   # app
flutter test                      # app
# firmware: west build for the target board
```

## 5. Working on firmware without hardware

Doable now:

- Read firmware source: protocol constants, sensor drivers, BLE/Wi-Fi config,
  Kconfig, DTS overlays.
- Build with `west build` for `native_posix` or `qemu` where drivers allow.
- Use the app's decoders as the oracle: feed firmware-emitted bytes into
  `test/dblk_decode_test.dart` and `test/openview_decode_test.dart`.
- Replay recorded captures if available; otherwise generate synthetic bytes
  from the app's writer.
- Mock the radio: firmware sends OpenView v2 over TCP:5000; point it at a
  local echo server and observe.

Not doable without hardware:

- Sensor calibration and real data ranges
- BLE pairing and connection behavior
- RF range and throughput
- Power and thermal behavior
- Real timing under load

## 6. Suggested sequence before the device arrives

1. Clone firmware; add `graphify-out/` and `.DS_Store` to its `.gitignore`.
2. Build firmware for `native_posix` to confirm the toolchain works.
3. Audit: diff `PROTOCOL_REFERENCE.md` against firmware wire-format constants.
   Find drift.
4. Write contract tests on the app side for any message the audit flags.
5. Defer all hardware-only work until the Healthy Pi 6 arrives.

## 7. Risks

- Firmware may have moved ahead of the app's protocol doc. Verify before
  assuming parity.
- Zephyr toolchain setup is the main cost; budget time for it.
- The merged graph is only as fresh as the last run. Re-run after protocol
  changes or you will reason against stale code.
- `assets/.DS_Store` is tracked in this repo despite being gitignored. Remove
  it with `git rm --cached assets/.DS_Store` before the next clean commit.
