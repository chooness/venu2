import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;

// One registerSensorDataListener phase: a set of channels at one requested
// rate. Only one listener can be active system-wide, so phases run one at
// a time and stop() must be called before the next start().
class HfProbe {
    static const SHORT = {
        :accelerometer => "acc",
        :gyroscope => "gyr",
        :magnetometer => "mag",
        :heartBeatIntervals => "hbi"
    };

    var label as String;
    var channels as Array;
    var rate as Number;
    var stats as Dictionary = {};
    var error = null;
    var registered = false;

    function initialize(lbl as String, chans as Array, hz as Number) {
        label = lbl;
        channels = chans;
        rate = hz;
        for (var i = 0; i < chans.size(); i++) {
            var hzFor = chans[i] == :heartBeatIntervals ? 0 : hz;
            stats[chans[i]] = new ChannelStats(SHORT[chans[i]], hzFor);
        }
    }

    function start() as Void {
        var opts = { :period => Config.HF_PERIOD_S };
        for (var i = 0; i < channels.size(); i++) {
            var ch = channels[i];
            if (ch == :heartBeatIntervals) {
                opts[ch] = { :enabled => true };
            } else {
                // :includeTimestamps is API 5.1.1+; older firmware ignores it
                // and the timestamp arrays stay null.
                opts[ch] = { :enabled => true, :sampleRate => rate, :includeTimestamps => true };
            }
        }
        Log.emit("HF_START", [label, chanNames(), rate, Config.HF_PERIOD_S]);
        if (!(Sensor has :registerSensorDataListener)) {
            error = "registerSensorDataListener not available";
            Log.emit("HF_ERR", [label, error]);
            return;
        }
        try {
            Sensor.registerSensorDataListener(method(:onData), opts);
            registered = true;
        } catch (e instanceof Lang.Exception) {
            error = e.getErrorMessage();
            if (error == null) {
                error = "exception";
            }
            Log.emit("HF_ERR", [label, error]);
        }
    }

    function stop() as Void {
        if (registered) {
            Sensor.unregisterSensorDataListener();
            registered = false;
        }
    }

    function onData(data as Sensor.SensorData) as Void {
        var t = System.getTimer();
        for (var i = 0; i < channels.size(); i++) {
            var ch = channels[i];
            var st = stats[ch];
            if (ch == :heartBeatIntervals) {
                var hr = (data has :heartRateData) ? data.heartRateData : null;
                var ibi = (hr != null) ? hr.heartBeatIntervals : null;
                var n = (ibi != null) ? ibi.size() : 0;
                st.addBatch(t, n, null);
                st.addValues(ibi);
                if (Config.LOG_RAW) {
                    Log.emit("RAW", [label, st.name, t, n, ibi]);
                }
            } else {
                var d = null;
                if (ch == :accelerometer && (data has :accelerometerData)) {
                    d = data.accelerometerData;
                } else if (ch == :gyroscope && (data has :gyroscopeData)) {
                    d = data.gyroscopeData;
                } else if (ch == :magnetometer && (data has :magnetometerData)) {
                    d = data.magnetometerData;
                }
                var x = (d != null) ? d.x : null;
                var n = (x != null) ? x.size() : 0;
                var ts = (d != null && (d has :timestamp)) ? d.timestamp : null;
                st.addBatch(t, n, ts);
                st.addValues(x);
                if (Config.LOG_RAW) {
                    Log.emit("RAW", [label, st.name, t, n,
                        x, (d != null) ? d.y : null, (d != null) ? d.z : null, ts]);
                }
            }
        }
    }

    // One RATE line per channel; returns short strings for the on-watch list.
    function report() as Array {
        var out = [];
        for (var i = 0; i < channels.size(); i++) {
            var st = stats[channels[i]];
            var hzCb = st.observedHzByCallback();
            var hzTs = st.observedHzByTimestamp();
            Log.emit("RATE", [
                label, st.name, st.requestedHz, error,
                st.callbacks, st.emptyCallbacks, st.samples, st.firstBatch,
                hzCb, hzTs, st.droppedEstimate(),
                st.cbInterval.mean(), st.cbInterval.std(), st.cbInterval.min, st.cbInterval.max,
                st.batchSize.min, st.batchSize.max,
                st.tsCount, st.tsInterval.mean(), st.tsInterval.std(),
                st.tsInterval.min, st.tsInterval.max,
                st.tsGaps, st.tsMissing, st.tsBackwards,
                st.values.min, st.values.max, st.values.mean()
            ]);
            var s = st.name + "@" + st.requestedHz + ": ";
            if (error != null) {
                s += "ERR";
            } else if (st.samples == 0) {
                s += "no data";
            } else {
                var hz = hzTs != null ? hzTs : hzCb;
                s += (hz != null ? hz.format("%.1f") : "?") + " Hz";
                if (hzTs != null) {
                    s += " gaps " + st.tsGaps;
                } else if (st.droppedEstimate() != null) {
                    s += " drop~" + st.droppedEstimate();
                }
            }
            out.add(s);
        }
        return out;
    }

    function chanNames() as Array {
        var a = [];
        for (var i = 0; i < channels.size(); i++) {
            a.add(SHORT[channels[i]]);
        }
        return a;
    }
}
