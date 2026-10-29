# Sensor Probe (Venu 2, Phase 1: supported access)

A Connect IQ **device app** that answers three questions using only documented
Connect IQ APIs:

1. **What does this watch expose?** Device/firmware identity, method-level API
   presence, a `Sensor.Info` and `ActivityMonitor.Info` snapshot, and every
   `SensorHistory` / `ActivityMonitor` history store with its background
   logging interval.
2. **Can we record it?** Every high-rate batch, 1 Hz event and GNSS event is
   written to the app log with the watch's millisecond timer.
3. **How fast, really?** For each channel and requested rate: observed Hz,
   callback jitter, batch sizes, estimated dropped samples, and (when the
   firmware supplies per-sample timestamps) true inter-sample jitter and gaps.

Nothing here is a claim about the watch yet. Every capability stays
*unverified* until a log from the real device says otherwise.

## What a run does

Press **START** (top button, or tap) to begin; press again to abort. A full run
takes about 10 minutes with the defaults in `source/Config.mc`.

| Step | API | What is measured |
|---|---|---|
| Inventory | `System`, `Sensor has :…`, `Sensor.getInfo`, `ActivityMonitor.getInfo` | Part number, firmware, API level, battery, memory, `getMaxSampleRate()`, which methods exist, current values |
| History | `SensorHistory.get*History`, `ActivityMonitor.getHeartRateHistory` | Samples available, nulls, spacing between stored samples |
| Accelerometer sweep | `registerSensorDataListener` | 10/25/50/100 Hz up to `getMaxSampleRate()`, plus the max itself |
| Gyroscope sweep | same | same rates |
| Magnetometer sweep | same | same rates |
| Over-max request | same | Accelerometer at 2× max: error, clamp, or comply? |
| Heart beat intervals | same, `:heartBeatIntervals` | Beat count and IBI range (60 s) |
| Everything at once | same | acc + gyro + mag + HBI at min(25, max) Hz |
| 1 Hz events | `enableSensorEvents` + `setEnabledSensors(onboard HR, Pulse Ox)` | Event interval, which `Sensor.Info` fields are ever non-null |
| GNSS | `Position.enableLocationEvents(LOCATION_CONTINUOUS)` | Event interval, fix quality counts (coordinates off by default) |

Battery percentage is logged at the start and end of every phase.

The watch shows live progress and a one-line result per phase; swipe or use
the buttons to scroll.

### What it cannot tell you

* Raw optical PPG, LED/photodiode control and raw pressure/magnetic ADC
  values are not exposed by any documented API, so this app cannot test them.
  A "no" from this app is a statement about the supported API, not about the
  hardware.
* Motion arrays are "API samples": the SDK does not say what filtering or
  calibration was applied.
* Per-sample timestamps (`:includeTimestamps`) need API level 5.1.1. On older
  firmware the timing numbers come from callback arrival times only, which
  measure batch delivery, not sample spacing.
* A simulator run proves the code works, not what the watch does.

## Build (macOS)

1. Install the Connect IQ SDK Manager from
   <https://developer.garmin.com/connect-iq/sdk/>, sign in with your Garmin
   account, and download the latest SDK and the **Venu 2**, **Venu 2S** and
   **Venu 2 Plus** device files.
2. Java 17: `brew install openjdk@17` (the build script finds it there).
3. Build:

   ```sh
   tools/build.sh venu2      # or venu2s / venu2plus
   ```

   The first run creates a developer key in `~/.garmin/`. Keep that key: later
   sideloads must be signed with the same one.

If the compiler's type checker complains, build with `-l 0` added to the
`monkeyc` line, or set *Type Check Level: Off* in the VS Code extension, and
tell us what it flagged.

### Simulator

```sh
"$SDK_BIN/connectiq" &                       # start the simulator
"$SDK_BIN/monkeydo" bin/SensorProbe.prg venu2 # log lines appear in the terminal
```

The simulator's sensor data is synthetic; use it only to check that the app
runs end to end.

## Run on the watch

The Venu 2 connects over USB as an MTP device, which macOS does not mount on
its own. Use [OpenMTP](https://openmtp.ganeshrvel.com/) (`brew install --cask openmtp`).
Garmin Express is not needed.

1. Connect the watch with a **data** cable directly to the Mac.
2. Copy `bin/SensorProbe.prg` into `GARMIN/APPS/` on the watch.
3. Create an **empty** file `GARMIN/APPS/LOGS/SENSORPROBE.TXT` (the log is only
   written if this file exists; the name must match the `.prg` name).
4. Unplug, open *Sensor Probe* from the apps list, wear the watch, press START.
   Keep the watch still for a clean baseline, or follow the handoff
   measurement protocol (stationary, scripted wrist rotations, outdoor walk for
   GNSS).
5. Plug back in and copy `GARMIN/APPS/LOGS/SENSORPROBE.TXT` off the watch.

## Turn the log into a report

```sh
python3 tools/parse_log.py SENSORPROBE.TXT > report.md
python3 tools/parse_log.py SENSORPROBE.TXT --csv results   # + results_rates.csv, results_history.csv
```

The report has one row per channel and requested rate with a verdict:
*met* (within 5%), *partial*, *clamped/low*, *faster than asked*, *no data*
or *error*.

## Log format

One line per record: `SP,<seq>,<timer_ms>,<KIND>,<fields…>`. Arrays are
`;`-joined, empty means null, `NA` means the field does not exist on this
firmware.

| Kind | Fields |
|---|---|
| META | app, version, watch clock, phase durations, listener period, raw logging |
| INV | key, value |
| API | method/class name, present |
| SNAP | field, value |
| HIST | store, count, nulls, oldest epoch s, newest epoch s, spacing s, min, max, mean |
| PLAN | number of phases |
| HF_START / HF_ERR | phase, channels, rate, period / phase, error message |
| RAW | phase, channel, callback ms, n, x[], y[], z[], timestamps[] (HBI: phase, hbi, ms, n, intervals[]) |
| RATE | per channel summary, see `RATE_COLS` in `tools/parse_log.py` |
| INFO_START / EVT / INFO_RATE / INFO_FIELD | 1 Hz event phase |
| POS_START / POS / POS_RATE | GNSS phase |
| BATT | phase, start/end, battery % |
| END / ABORT | battery % / phase index |

Settings that change behaviour are in `source/Config.mc`
(durations, candidate rates, `LOG_RAW`, `LOG_COORDS`).
