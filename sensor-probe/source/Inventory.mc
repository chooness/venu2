import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;

// One-shot capability snapshot. Everything is written as INV / API / SNAP /
// HIST lines; nothing here assumes a capability exists before checking.
module Inventory {

    // History stores are read later, one per Runner step (HistProbe):
    // reading them all in one call trips the watchdog.
    function run() as Void {
        device();
        apis();
        snapshot();
        activity();
    }

    function historyStores() as Array {
        var a = [];
        if (Toybox has :SensorHistory) {
            if (SensorHistory has :getHeartRateHistory) { a.add("heart_rate"); }
            if (SensorHistory has :getTemperatureHistory) { a.add("temperature"); }
            if (SensorHistory has :getPressureHistory) { a.add("pressure"); }
            if (SensorHistory has :getElevationHistory) { a.add("elevation"); }
            if (SensorHistory has :getOxygenSaturationHistory) { a.add("spo2"); }
            if (SensorHistory has :getBodyBatteryHistory) { a.add("body_battery"); }
            if (SensorHistory has :getStressHistory) { a.add("stress"); }
        }
        if (ActivityMonitor has :getHeartRateHistory) {
            a.add("am_heart_rate");
        }
        return a;
    }

    function readHistory(name as String, out as Array) as Void {
        if (name.equals("am_heart_rate")) {
            amHrHistory(out);
            return;
        }
        var opts = { :period => Config.HISTORY_MAX, :order => SensorHistory.ORDER_NEWEST_FIRST };
        var it = null;
        if (name.equals("heart_rate")) { it = SensorHistory.getHeartRateHistory(opts); }
        else if (name.equals("temperature")) { it = SensorHistory.getTemperatureHistory(opts); }
        else if (name.equals("pressure")) { it = SensorHistory.getPressureHistory(opts); }
        else if (name.equals("elevation")) { it = SensorHistory.getElevationHistory(opts); }
        else if (name.equals("spo2")) { it = SensorHistory.getOxygenSaturationHistory(opts); }
        else if (name.equals("body_battery")) { it = SensorHistory.getBodyBatteryHistory(opts); }
        else if (name.equals("stress")) { it = SensorHistory.getStressHistory(opts); }
        hist(name, it, out);
    }

    function device() as Void {
        var ds = System.getDeviceSettings();
        var ss = System.getSystemStats();
        Log.emit("INV", ["app_version", Config.VERSION]);
        Log.emit("INV", ["part_number", (ds has :partNumber) ? ds.partNumber : "NA"]);
        Log.emit("INV", ["firmware", (ds has :firmwareVersion) ? ds.firmwareVersion : "NA"]);
        Log.emit("INV", ["monkey_version", (ds has :monkeyVersion) ? ds.monkeyVersion : "NA"]);
        Log.emit("INV", ["screen", [ds.screenWidth, ds.screenHeight]]);
        Log.emit("INV", ["battery_pct", ss.battery]);
        Log.emit("INV", ["memory_total_free", [ss.totalMemory, ss.freeMemory]]);
        if (Sensor has :getMaxSampleRate) {
            Log.emit("INV", ["max_sample_rate", Sensor.getMaxSampleRate()]);
        }
    }

    // Method-level presence on this firmware. True only means the symbol
    // exists, not that the hardware delivers data.
    function apis() as Void {
        api("Sensor.registerSensorDataListener", Sensor has :registerSensorDataListener);
        api("Sensor.getMaxSampleRate", Sensor has :getMaxSampleRate);
        api("Sensor.enableSensorEvents", Sensor has :enableSensorEvents);
        api("Sensor.setEnabledSensors", Sensor has :setEnabledSensors);
        api("Sensor.getInfo", Sensor has :getInfo);
        api("Sensor.SENSOR_ONBOARD_HEARTRATE", Sensor has :SENSOR_ONBOARD_HEARTRATE);
        api("Sensor.SENSOR_ONBOARD_PULSE_OXIMETRY", Sensor has :SENSOR_ONBOARD_PULSE_OXIMETRY);
        api("Sensor.GyroscopeData", Sensor has :GyroscopeData);
        api("Sensor.MagnetometerData", Sensor has :MagnetometerData);
        api("Toybox.SensorHistory", Toybox has :SensorHistory);
        if (Toybox has :SensorHistory) {
            api("SensorHistory.getHeartRateHistory", SensorHistory has :getHeartRateHistory);
            api("SensorHistory.getTemperatureHistory", SensorHistory has :getTemperatureHistory);
            api("SensorHistory.getPressureHistory", SensorHistory has :getPressureHistory);
            api("SensorHistory.getElevationHistory", SensorHistory has :getElevationHistory);
            api("SensorHistory.getOxygenSaturationHistory", SensorHistory has :getOxygenSaturationHistory);
            api("SensorHistory.getBodyBatteryHistory", SensorHistory has :getBodyBatteryHistory);
            api("SensorHistory.getStressHistory", SensorHistory has :getStressHistory);
        }
        api("ActivityMonitor.getHeartRateHistory", ActivityMonitor has :getHeartRateHistory);
        api("Toybox.Position", Toybox has :Position);
        // Communications, ActivityRecording and FitContributor are not
        // probed: even a `has` check on them crashes without their manifest
        // permission (seen in the simulator).
        api("Toybox.Attention", Toybox has :Attention);
    }

    function api(name as String, ok as Boolean) as Void {
        Log.emit("API", [name, ok]);
    }

    function snapshot() as Void {
        if (!(Sensor has :getInfo)) {
            return;
        }
        var v = InfoFields.values(Sensor.getInfo());
        for (var i = 0; i < v.size(); i++) {
            Log.emit("SNAP", ["Sensor.Info." + InfoFields.NAMES[i], v[i]]);
        }
    }

    function activity() as Void {
        var a = ActivityMonitor.getInfo();
        am("steps", (a has :steps) ? a.steps : "NA");
        am("calories", (a has :calories) ? a.calories : "NA");
        am("distance_cm", (a has :distance) ? a.distance : "NA");
        am("floorsClimbed", (a has :floorsClimbed) ? a.floorsClimbed : "NA");
        am("metersClimbed", (a has :metersClimbed) ? a.metersClimbed : "NA");
        am("activeMinutesDay", (a has :activeMinutesDay) ? a.activeMinutesDay.total : "NA");
        am("moveBarLevel", (a has :moveBarLevel) ? a.moveBarLevel : "NA");
        am("stressScore", (a has :stressScore) ? a.stressScore : "NA");
        am("respirationRate", (a has :respirationRate) ? a.respirationRate : "NA");
        am("timeToRecovery", (a has :timeToRecovery) ? a.timeToRecovery : "NA");
    }

    function am(name as String, v) as Void {
        Log.emit("SNAP", ["ActivityMonitor.Info." + name, v]);
    }

    // Sample count, time span and average spacing give the background
    // logging rate of each store. Spacing uses min/max time because not every
    // store honours ORDER_NEWEST_FIRST.
    function hist(name as String, it, out as Array) as Void {
        if (it == null) {
            Log.emit("HIST", ["SensorHistory." + name, 0]);
            return;
        }
        var count = 0;
        var nulls = 0;
        var newest = null;
        var oldest = null;
        var vals = new RunningStats();
        var s = it.next();
        while (s != null && count < Config.HISTORY_MAX) {
            count += 1;
            if (s.data == null) {
                nulls += 1;
            } else {
                vals.add(s.data);
            }
            if (s.when != null) {
                var w = s.when.value();
                if (newest == null || w > newest) {
                    newest = w;
                }
                if (oldest == null || w < oldest) {
                    oldest = w;
                }
            }
            s = it.next();
        }
        var spacing = (count > 1 && newest != null && oldest != null) ?
            (newest - oldest).toFloat() / (count - 1) : null;
        Log.emit("HIST", ["SensorHistory." + name, count, nulls, oldest, newest, spacing,
            vals.min, vals.max, vals.mean()]);
        out.add(name + ": " + count + (spacing != null ? " @" + spacing.format("%.0f") + "s" : ""));
    }

    function amHrHistory(out as Array) as Void {
        var it = ActivityMonitor.getHeartRateHistory(Config.HISTORY_MAX, true);
        var count = 0;
        var invalid = 0;
        var newest = null;
        var oldest = null;
        var s = (it != null) ? it.next() : null;
        while (s != null && count < Config.HISTORY_MAX) {
            count += 1;
            if (s.heartRate == null || s.heartRate == ActivityMonitor.INVALID_HR_SAMPLE) {
                invalid += 1;
            }
            if (s.when != null) {
                var w = s.when.value();
                if (newest == null || w > newest) {
                    newest = w;
                }
                if (oldest == null || w < oldest) {
                    oldest = w;
                }
            }
            s = it.next();
        }
        var spacing = (count > 1 && newest != null) ? (newest - oldest).toFloat() / (count - 1) : null;
        Log.emit("HIST", ["ActivityMonitor.heart_rate", count, invalid, oldest, newest, spacing]);
        out.add("am_hr: " + count + (spacing != null ? " @" + spacing.format("%.0f") + "s" : ""));
    }
}
