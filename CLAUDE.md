# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

oXs (openXsensor) firmware for RP2040 boards (Pico / RP2040-Zero / RP2040-TINY). A single binary that
sits between one or two RC receivers and the model, and can simultaneously do: telemetry (11 RC
protocols), up to 16 PWM servo outputs, SBUS output, gyro stabilization, servo sequencers, data
logging over UART, and a LORA "locator" link. C++ on the Raspberry Pi Pico SDK, bare metal, no RTOS.

The user-facing manual is `README.md` — it is the authoritative description of behavior, wiring,
USB commands and the calibration/learning procedures. Read the relevant section before changing
behavior in those areas.

## Build

This branch targets **Pico SDK 2.1.0** with ARM toolchain **13.3.Rel1** and **picotool 2.1.0** — the
header block in `CMakeLists.txt` and `.vscode/settings.json` pin those versions and expect the
Raspberry Pi Pico VS Code extension layout under `%USERPROFILE%\.pico-sdk\`.

That layout is installed on this machine (self-contained, nothing on the global PATH):

```
~/.pico-sdk/
  sdk/2.1.0/                  pico-sdk (shallow clone, tag 2.1.0, lib/tinyusb submodule)
  toolchain/13_3_Rel1/        arm-none-eabi-gcc 13.3.1
  tools/2.1.0/pioasm/         prebuilt pioasm  -> no host C++ compiler needed
  picotool/2.1.0/picotool/    prebuilt picotool (required by pico_add_extra_outputs)
  cmake/v3.29.9/  ninja/v1.12.1/
  pico-env.ps1                dot-source this to put it all in the environment
```

```powershell
. "$env:USERPROFILE\.pico-sdk\pico-env.ps1"
cmake -S . -B build -G Ninja
cmake --build build              # -> build\oXs_<branch>.uf2
```

A build writes only into `build/`. Artifacts are named after the checked out branch
(`oXs_rk-main.uf2`) so it stays obvious which build ended up on a board; CMake re-configures itself
when `.git/HEAD` changes. `-DOXS_UF2_NAME=oXs` gives the plain name back, which is what refreshing
the `oXs.uf2` committed in the repo root needs. To also copy the artifact somewhere, pass
`-DOXS_COPY_UF2_TO=<dir>` — a drive letter flashes a mounted RPI-RP2 directly, and
`"-DOXS_UF2_NAME=oXs" "-DOXS_COPY_UF2_TO=."` is the release refresh. A relative destination
resolves against the repo root. **Quote these arguments in PowerShell**: it drops the trailing `.`
of an unquoted `-DOXS_COPY_UF2_TO=.`, which leaves the value empty, and the build then copies
nothing and still exits 0. (Upstream and `main` do both copies
unconditionally, which dirties the working tree on every build and, on `main`, fails the build
outright when drive `E:` does not exist.)

### Version string

`VERSION` is **generated**, not maintained by hand. `tools/gen_version.cmake` composes
`VERSION_BASE` from `config.h` with the branch, the short commit and a `-dirty` marker into
`build/generated/oxs_version.h`, e.g. `3.0.11-rk-main-b25351d`. It runs on every build (not at
configure time, so a fresh commit cannot leave a stale hash) and rewrites the header only when the
string changed, since everything includes `config.h`. `printConfigAndSequencers()` prints it, so what
a board reports over USB names the exact commit it was built from — and says so when that build had
uncommitted changes. Bump `VERSION_BASE` only when tracking a new upstream release.

The linked artifact keeps the stable branch name so ninja can track it. **The file to hand to other
people is `build/dist/oXs_<version>.uf2`**, staged by `tools/stage_release.cmake` under the exact
string the firmware prints, so a file on someone's disk and a board's reported version can always be
matched up. `dist/` is wiped of UF2s on each build and therefore holds exactly the current one. A
build from an uncommitted tree lands there as `...-dirty.uf2` — that name is the signal not to
publish it. GitHub has no per-branch assets: attach that file to a *release* (which hangs off a tag,
and the tag may point at a commit on a topic branch).

### The 256 KiB flash ceiling

`param.cpp` stores its blobs at fixed offsets from `XIP_BASE` starting at `FLASH_CONFIG_OFFSET`
= 256 KiB, and **the linker does not reserve that area**. A firmware that grows past it still links,
still boots, reads its parameters out of program code (so every setting looks reset) and then wipes
a sector of itself on the first `SAVE` — the board goes dead until it is re-flashed over BOOTSEL.
This has happened once, in September 2026.

Two things keep it from happening again:
- `CMAKE_CXX_FLAGS_RELEASE` is pinned to **`-O2`**. The SDK default `-O3` builds this firmware at
  ~260 KiB, i.e. straight through the ceiling; `-O2` builds it at ~245 KiB. Do not raise it back
  without checking the image size.
- `tools/check_flash_layout.cmake` runs POST_BUILD, compares `oXs_<branch>.bin` (which is exactly the
  flash footprint) against the offset and **fails the build** on overlap, warning below 8 KiB of
  headroom. `OXS_FLASH_CONFIG_OFFSET` in `CMakeLists.txt` must be kept in sync with `param.cpp`.

Keeping the offset at 256 KiB is deliberate: moving it would buy megabytes of room but break
compatibility with upstream and with every config already stored on a board.

Build gotchas:
- The `sdkVersion` / `toolchainVersion` / `picotoolVersion` block at the top of `CMakeLists.txt` is
  generated by the VS Code extension. Editing it silently changes which SDK is used.
- Sources are picked up with `file(GLOB ... "src/*.h" "src/*.cpp")`, so new files need no CMake edit,
  but every `src/*.pio` that is used must be added explicitly with `pico_generate_pio_header`.
- `src/mpu - mahony for vario.cpp` and `src/mpu_bu.cpp` are dead alternates: they are globbed into the
  build but their whole body is inside `#ifdef MAHONY_USED_INITIALLY_FOR_VARIO` / `#ifdef USE_MPU_BU`,
  which are never defined. `*.bak` and `crsf - Copie_*.txt` are not compiled at all.

Flashing: hold BOOT while plugging USB, drag `build\oXs_<branch>.uf2` onto the RPI-RP2 drive, or use
`picotool load -x build\oXs_<branch>.uf2`. `doc/flash_nuke.uf2` erases flash (and therefore the
stored config); it is also the way back from a board bricked by the flash ceiling above, since the
bootloader lives in ROM and survives.

## Branches

This is a fork. Upstream (`mstrens/oXs_on_RP2040`) develops on `test`, not `main`, and has not moved
since February 2025.

| branch | role |
|---|---|
| `main` | untouched mirror of `upstream/main` — never commit here |
| `test` | untouched mirror of `upstream/test` — the base for any pull request |
| `rk-main` | our trunk; all work lands here |
| `rk-<topic>` | short-lived topic branches, cut from `rk-main` |

Keeping the two mirrors pristine is what makes a clean PR cheap later:

```bash
git fetch upstream
git checkout main && git merge --ff-only upstream/main
git checkout test && git merge --ff-only upstream/test

# a PR takes only the upstreamable commits, never the local ones
git checkout -b fix-<topic> upstream/test
git cherry-pick <sha>...
```

Our commits split into two kinds, and they must not be mixed in a PR:
- **upstreamable** — fixes and features that help anyone: the negative-`OFFSET2` guards in `esc.cpp`
  (`c4bef56` for HW5, `127aa91` for HW4), the opt-in UF2 copy (`a65ec5a`), `GPSBAUD` with its v8 -> v9
  config migration (`39f2022`) and the output fix on top of it (`b25351d`)
- **local only** — the generated version string (`c8171c3`) and the UF2 staging built on it
  (`f8b3dcb`), machine-local paths in `.vscode/settings.json`, rebuilt `oXs.uf2` binaries, and this file

`fe674ec` is the one commit that mixes both: the flash-ceiling check in
`tools/check_flash_layout.cmake` guards against bricking a board and belongs upstream, while the
branch-named artifacts in the same commit do not. Split it before offering it.

`oXs.uf2` is a committed binary that git cannot merge, so every branch that rebuilds it creates a
conflict. Branch-named artifacts keep it out of the way by default; refresh it only on `rk-main`,
with `-DOXS_UF2_NAME=oXs -DOXS_COPY_UF2_TO=.`, when marking a state as released.

## Tests

There is no host compiler and no test framework on this machine, so there is no runtime test suite.
What exists instead is `test/test_config_and_gps.cpp`: compile-time tests (`constexpr` +
`static_assert`) built by the ARM toolchain, where **the build is the test run** and a failed test is
a compile error.

```powershell
cmake --build build --target oXs_tests
```

It is also part of the default `cmake --build build`, so a regression cannot slip through. It pins
down what cannot be checked on hardware without losing data: that `CONFIG` still fits in one flash
page, that no field moved relative to the v8 layout (which is what makes the migration in
`setupConfig()` safe), and the UBX-CFG-PRT baudrate patching including its checksum. When adding
tests, mutate the code once to confirm the new assert actually fires — a `static_assert` over a typo
passes silently.

Note what that file does *not* cover: it guards the struct against the flash page, not the image
against the parameter area. That second boundary is the 256 KiB ceiling above, checked by
`tools/check_flash_layout.cmake` instead. Both are needed; the struct assert passing says nothing
about the image fitting.

The cmake helpers in `tools/` are build tooling and therefore outside the compile-time tests. They
have their own runnable tests, which build throwaway git repos and fake binaries in the temp
directory and never touch the working tree:

```powershell
.\test\run_cmake_script_tests.ps1     # 16 checks, exits non-zero on failure
```

`lib/` and `include/README` are still leftovers from a PlatformIO scaffold and contain only
boilerplate. Everything behavioural is verified on hardware over the USB serial console
(115200 8N1, terminal must send CR+LF).

## Configuration: two distinct layers

Keep these apart — confusing them is the most common source of wrong advice here.

1. **Runtime parameters** (`struct CONFIG` in `src/param.h`) — pin assignments, protocol, scales,
   failsafe, gyro PIDs, MPU calibration, sequencers, gyro mixer. Set by the user over USB serial
   (`KEY=value`, `;`-separated, then `SAVE`, then power cycle). **No recompile needed.**
   Stored in flash by `param.cpp` at fixed offsets from `XIP_BASE`:
   `FLASH_CONFIG_OFFSET` = 256 KiB, sequencers at +4 KiB, gyro mixer at +8 KiB.
   Each blob is version-tagged (`CONFIG_VERSION`, `SEQUENCER_VERSION`, `GYROMIXER_VERSION`).
   **Changing a struct layout means bumping its version** — on mismatch `setupConfig()` silently
   falls back to the `_xxx` defaults in `config.h`; without a bump, stale flash is memcpy'd into the
   new layout and the device misbehaves.
   A bump normally costs the user every stored setting. `setupConfig()` therefore carries a migration
   for v8 -> v9: `gpsBaudrate` was **appended** to `CONFIG`, so a v8 blob is a byte-exact prefix
   (`CONFIG_V8_SIZE`) and gets reused with the new field defaulted. Keep new fields at the end and
   extend that path rather than resetting people's configs. The whole struct is memcpy'd into one
   256-byte flash page (`saveConfig()`), currently 248 bytes — a `static_assert` guards the rest.
2. **Compile-time parameters** (`src/config.h`, ~26 KB) — telemetry field priorities for
   Sport/Fbus/Exbus, SBUS2 slot assignment, MPX field/alarm table, I2C addresses, sensor variants
   (`KX134_IS_USED`, `USE_RFM95`, `USEDS18B20`), LORA radio settings, and the `_xxx` default values
   for every runtime parameter. Changing these requires a rebuild and reflash.

## Architecture

### Dual-core split (`src/main.cpp`)

- **core1** = sensors only: `setupSensors()` probes every I2C/serial sensor and `getSensors()` polls
  them in a tight loop. It pushes results to core0 through `queue_t qSensorData` as
  `{uint8_t type; int32_t data}` via `sent2Core0()`. `type` is a `fieldIdx` enum value, or one of the
  `0xFA..0xFF` pseudo-types (save-config request, camera pitch/roll, gyro X/Y/Z).
  core0 sends calibration requests back over `qSendCmdToCore1`.
- **core0** = everything real-time-facing: drain the sensor queue, run the protocol handler, apply
  failsafe, gyro corrections, PWM/SBUS output, sequencers, logger, USB command parsing, LED, button.
- A watchdog is armed at 3500 ms and kicked several times per `loop()`. Any blocking code added to
  core0 (or a long `sleep_ms`) will reboot the board. Long operations (`saveConfig`) explicitly
  re-arm the watchdog with a larger timeout first.
- `printf` goes to USB CDC (`pico_enable_stdio_usb`). `#define DEBUG` in `config.h` is **active**,
  here and upstream: `setup()` waits up to 1 s for `tud_cdc_connected()` and then sleeps another
  2 s, so every power-on costs ~3 s before anything else runs. It is still not enough to see the
  early output — the config is loaded at `main.cpp:440` and a terminal opened after that window
  misses `Clean boot`, the watchdog notice and the config migration message. Do not conclude from a
  missing line that the code did not run.

### Protocol dispatch

`config.protocol` is a single char, and both `setup()` and `loop()` in `main.cpp` are an if/else
chain over it. Each protocol is one `src/<name>.cpp` exposing `setupXxx()` + `handleXxx...()`:

| char | protocol | file |
|---|---|---|
| `C` | CRSF / ELRS | `crsf_in.cpp`, `crsf_out.cpp` |
| `S` | FrSky Sport | `sport.cpp` |
| `F` | FrSky Fbus | `fbus.cpp` |
| `B` | FrSky Hub | `frsky_hub.cpp` |
| `J` | Jeti EX | `jeti.cpp` |
| `E` | Jeti EXBUS | `exbus.cpp` |
| `H` | Graupner HoTT | `hott.cpp` |
| `M` | Multiplex | `mpx.cpp` |
| `I` | Flysky IBUS | `ibus.cpp`, `ibus_in.cpp` |
| `L` | Spektrum SRXL2 | `srxl2.cpp` |
| `2` | Futaba SBUS2 | `sbus2_tlm.cpp` |

Adding a protocol means touching both chains in `main.cpp` plus the `PROTOCOL=` validation in
`param.cpp`.

### PIO / UART budget (hard constraint)

Pins are user-configurable, so almost every serial link is bit-banged in PIO rather than using the
hardware UARTs. The allocation is fixed and documented at the top of `main.cpp`:

- pio0 sm0 = protocol TX (CRSF/Sport/Jeti/HoTT/MPX/SRXL2/Ibus), sm1 = protocol RX, sm2 = SBUS out, sm3 = ESC RX
- pio1 sm0 = GPS TX then reused for GPS RX, sm1 = RPM, sm2 = logger UART TX, sm3 = WS2812 RGB LED
- UART0 = secondary CRSF/SBUS in, UART1 = primary CRSF/SBUS in

There are no free state machines. Any new serial peripheral has to share or replace one of these.

### Telemetry field model

All measurements live in one flat array `field fields[NUMBER_MAX_IDX]` (`src/tools.h`), indexed by the
`fieldIdx` enum (`VSPEED`, `MVOLT`, `LATITUDE`, ...), each with `value` / `available` / `onceAvailable`.
Sensors fill it via core1; protocol modules read it and map it into their own wire format.

Adding a telemetry field requires edits in many places — `src/tools.h` carries the authoritative
checklist next to the enum (tools.cpp FVP/FVN values, param.cpp `printFieldValues()`, sport.cpp
tables + `calculateSportMaxBandwidth()`, ibus.cpp `ibusTypes[]`, sbus2_tlm.cpp slot, config.h slot +
priority `#define`, exbus.cpp `sensorsParam[]`, mpx.cpp `oXsToMpxUnits[]`, srxl2, and
`doc/fields per protocol.txt`). Follow that list.

### RC channel pipeline (core0 `loop()`)

```
receiver frame -> sbusFrame -> (failsafe if stale) -> rcChannelsUs     -> logger, sequencers
                                                   -> rcChannelsUsCorr -> gyro corrections -> PWM out, SBUS out
```

`setRcChannels()` (`sbus_out_pwm.cpp`) produces both arrays; gyro only ever writes the `...Corr` copy.
The `rcChannelsUsChanged` / `rcChannelsUsCorrChanged` / `newRcChannelsFrameReceived` flags gate the
downstream updates and are reset at the end of every loop iteration.

### USB command handling

`handleUSBCmd()` -> `handleOneCmd()` in `param.cpp` is a long `strcmp(key, ...)` chain (~180 commands).
A new parameter needs: the field in `struct CONFIG`, a `_default` in `config.h`, the parse branch in
`handleOneCmd()`, output in `printConfig...()` and in `dumpConfig()`, validation in
`checkConfigAndSequencers()`, and a `CONFIG_VERSION` bump.

### Other subsystems

- `gyro.cpp` — PID stabilization plus the "learning process" (mixer calibration) that discovers the
  handset's mixers, servo limits and MPU orientation from stick movements. State is `gyroMixer_t`,
  saved to its own flash page. README documents the LED-driven user procedure in detail.
- `sequencer.cpp` — up to 16 sequencers (one per GPIO 0-15), each with sequences selected by RC
  channel value and steps with smooth/value/keep. Parsed from a single `SEQ=[...](...){...}` command.
- `logger.cpp` — stuffed, delta-compressed byte stream over a PIO UART to a separate oXs_logger board.
- `rfm95.cpp` / `sx126x_driver.cpp` — LORA locator over SPI; the RFM95 path is deprecated and only
  built with `#define USE_RFM95` (default is the Ebyte E220-900M22S).
- Sensor drivers are auto-probing: baro tries MS5611 -> SPL06 -> BMP280, airspeed tries MS4525 ->
  SDP3X -> XGZP, and each sets its own `...Installed` flag. Never assume a sensor is present.

## Conventions

The code is a long-running hobby project with its own style: commented-out debug blocks, `//xxxxx`
markers and `to do` lists left in place (a large one at the top of `main.cpp`). Match the surrounding
style rather than reformatting, and leave existing commented-out code alone unless the task is about it.
