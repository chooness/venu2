import Toybox.Lang;

// Test-plan knobs. Edit these and rebuild; nothing here is read at runtime
// from settings so a run is fully described by the build + the META line.
module Config {
    const VERSION = "0.1.0";

    // Seconds per high-rate listener phase (one channel at one rate).
    const HF_SECS = 30;
    // Heart beat intervals arrive about once per beat, so give them longer.
    const HBI_SECS = 60;
    // 1 Hz Sensor.Info events (enableSensorEvents).
    const INFO_SECS = 30;
    // GNSS events. Needs open sky for a fix; indoors this mostly measures "no fix".
    const POS_SECS = 90;
    // Pause between phases so one listener is fully torn down before the next.
    const SETTLE_MS = 2000;
    // :period for registerSensorDataListener, seconds (documented max 4).
    const HF_PERIOD_S = 1;

    // Candidate rates for the sweep. Anything above Sensor.getMaxSampleRate()
    // is dropped, the max itself is always added, and one deliberate
    // over-max request is made for the accelerometer to see what happens.
    const CANDIDATE_RATES = [10, 25, 50, 100];

    // Write every high-rate batch to the log (RAW lines). Turn off if the
    // log write itself turns out to disturb timing.
    const LOG_RAW = true;
    // Write latitude/longitude in POS lines. Off by default: rate testing does
    // not need coordinates and the log may be copied around.
    const LOG_COORDS = false;
    // Max samples read from each SensorHistory / ActivityMonitor history.
    const HISTORY_MAX = 600;
}
