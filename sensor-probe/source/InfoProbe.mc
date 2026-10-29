import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;

// Sensor.Info snapshot fields, shared by the inventory and the 1 Hz event
// phase. "NA" = the field does not exist on this firmware's Sensor.Info,
// which is different from a field that exists but is null.
module InfoFields {
    const NAMES = ["heartRate", "oxygenSaturation", "temperature", "pressure",
        "altitude", "heading", "cadence", "power", "speed", "accel", "mag"];

    function values(info as Sensor.Info) as Array {
        return [
            (info has :heartRate) ? info.heartRate : "NA",
            (info has :oxygenSaturation) ? info.oxygenSaturation : "NA",
            (info has :temperature) ? info.temperature : "NA",
            (info has :pressure) ? info.pressure : "NA",
            (info has :altitude) ? info.altitude : "NA",
            (info has :heading) ? info.heading : "NA",
            (info has :cadence) ? info.cadence : "NA",
            (info has :power) ? info.power : "NA",
            (info has :speed) ? info.speed : "NA",
            (info has :accel) ? info.accel : "NA",
            (info has :mag) ? info.mag : "NA"
        ];
    }
}

// enableSensorEvents phase (documented as 1 Hz). Turns on the onboard HR and
// Pulse Ox sensors via setEnabledSensors where that API exists, then counts
// how often each Sensor.Info field is populated.
class InfoProbe {
    var callbacks = 0;
    var lastMs = null;
    var interval = new RunningStats();
    var present as Array;
    var nonNull as Array;
    var enabled as Array = [];
    var error = null;

    function initialize() {
        var n = InfoFields.NAMES.size();
        present = new [n];
        nonNull = new [n];
        for (var i = 0; i < n; i++) {
            present[i] = false;
            nonNull[i] = 0;
        }
    }

    function start() as Void {
        if (Sensor has :setEnabledSensors) {
            var list = [];
            if (Sensor has :SENSOR_ONBOARD_HEARTRATE) {
                list.add(Sensor.SENSOR_ONBOARD_HEARTRATE);
                enabled.add("onboard_hr");
            }
            if (Sensor has :SENSOR_ONBOARD_PULSE_OXIMETRY) {
                list.add(Sensor.SENSOR_ONBOARD_PULSE_OXIMETRY);
                enabled.add("onboard_spo2");
            }
            try {
                Sensor.setEnabledSensors(list);
            } catch (e instanceof Lang.Exception) {
                error = "setEnabledSensors: " + e.getErrorMessage();
            }
        }
        Log.emit("INFO_START", [enabled, error]);
        Sensor.enableSensorEvents(method(:onInfo));
    }

    function stop() as Void {
        Sensor.enableSensorEvents(null);
        if (Sensor has :setEnabledSensors) {
            try {
                Sensor.setEnabledSensors([]);
            } catch (e instanceof Lang.Exception) {
            }
        }
    }

    function onInfo(info as Sensor.Info) as Void {
        var t = System.getTimer();
        callbacks += 1;
        if (lastMs != null) {
            interval.add(t - lastMs);
        }
        lastMs = t;
        var v = InfoFields.values(info);
        for (var i = 0; i < v.size(); i++) {
            if (!"NA".equals(v[i])) {
                present[i] = true;
                if (v[i] != null) {
                    nonNull[i] += 1;
                }
            }
        }
        if (Config.LOG_RAW) {
            var line = [t];
            line.addAll(v);
            Log.emit("EVT", line);
        }
    }

    function report() as Array {
        Log.emit("INFO_RATE", [callbacks, interval.mean(), interval.std(), interval.min, interval.max, error]);
        var out = ["info: " + callbacks + " ev, " +
            (interval.mean() != null ? interval.mean().format("%.0f") : "?") + " ms"];
        for (var i = 0; i < InfoFields.NAMES.size(); i++) {
            Log.emit("INFO_FIELD", [InfoFields.NAMES[i], present[i], nonNull[i], callbacks]);
            if (nonNull[i] > 0) {
                out.add("  " + InfoFields.NAMES[i] + " " + nonNull[i] + "/" + callbacks);
            }
        }
        return out;
    }
}
