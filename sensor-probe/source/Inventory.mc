import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;

// One-shot capability snapshot. Everything is written as INV / API / SNAP /
// HIST lines; nothing here assumes a capability exists before checking.
module Inventory {

    function run() as Array {
        device();
        apis();
        snapshot();
        activity();
        var out = [];
        history(out);
        return out;
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
        api("Toybox.Communications", Toybox has :Communications);
        api("Toybox.ActivityRecording", Toybox has :ActivityRecording);
        api("Toybox.FitContributor", Toybox has :FitContributor);
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

    // History stores: sample count, time span and median-ish spacing tell us
    // the background logging rate of each store.
    function history(out as Array) as Void {
        if (Toybox has :SensorHistory) {
            var opts = { :period => Config.HISTORY_MAX, :order => SensorHistory.ORDER_NEWEST_FIRST };
            if (SensorHistory has :getHeartRateHistory) { hist("heart_rate", SensorHistory.getHeartRateHistory(opts), out); }
            if (SensorHistory has :getTemperatureHistory) { hist("temperature", SensorHistory.getTemperatureHistory(opts), out); }
            if (SensorHistory has :getPressureHistory) { hist("pressure", SensorHistory.getPressureHistory(opts), out); }
            if (SensorHistory has :getElevationHistory) { hist("elevation", SensorHistory.getElevationHistory(opts), out); }
            if (SensorHistory has :getOxygenSaturationHistory) { hist("spo2", SensorHistory.getOxygenSaturationHistory(opts), out); }
            if (SensorHistory has :getBodyBatteryHistory) { hist("body_battery", SensorHistory.getBodyBatteryHistory(opts), out); }
            if (SensorHistory has :getStressHistory) { hist("stress", SensorHistory.getStressHistory(opts), out); }
        }
        if (ActivityMonitor has :getHeartRateHistory) {
            amHrHistory(out);
        }
    }

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
                if (newest == null) {
                    newest = w;
                }
                oldest = w;
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
                if (newest == null) {
                    newest = s.when.value();
                }
                oldest = s.when.value();
            }
            s = it.next();
        }
        var spacing = (count > 1 && newest != null) ? (newest - oldest).toFloat() / (count - 1) : null;
        Log.emit("HIST", ["ActivityMonitor.heart_rate", count, invalid, oldest, newest, spacing]);
        out.add("am_hr: " + count + (spacing != null ? " @" + spacing.format("%.0f") + "s" : ""));
    }
}
