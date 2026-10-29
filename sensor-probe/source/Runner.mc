import Toybox.Application;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Runs the test plan: inventory, then one probe phase at a time with a
// settle gap between phases. Driven by a 1 s timer.
class Runner {
    var steps as Array = [];
    var idx = -1;
    var probe = null;
    var phaseStart = 0;
    var settling = false;
    var settleStart = 0;
    var running = false;
    var done = false;
    var results as Array = [];
    var timer = null;

    function buildPlan() as Void {
        steps = [];
        var maxHz = (Sensor has :getMaxSampleRate) ? Sensor.getMaxSampleRate() : 25;
        var rates = [];
        for (var i = 0; i < Config.CANDIDATE_RATES.size(); i++) {
            if (Config.CANDIDATE_RATES[i] <= maxHz) {
                rates.add(Config.CANDIDATE_RATES[i]);
            }
        }
        if (rates.indexOf(maxHz) < 0) {
            rates.add(maxHz);
        }
        var motion = [:accelerometer, :gyroscope, :magnetometer];
        for (var c = 0; c < motion.size(); c++) {
            for (var r = 0; r < rates.size(); r++) {
                steps.add({ :kind => :hf, :ch => [motion[c]], :rate => rates[r], :secs => Config.HF_SECS });
            }
        }
        // Deliberately over the reported max: does it error, clamp, or comply?
        steps.add({ :kind => :hf, :ch => [:accelerometer], :rate => maxHz * 2, :secs => Config.HF_SECS });
        steps.add({ :kind => :hf, :ch => [:heartBeatIntervals], :rate => 0, :secs => Config.HBI_SECS });
        // Everything at once, at the lower of 25 Hz and max.
        var both = maxHz < 25 ? maxHz : 25;
        steps.add({ :kind => :hf, :ch => [:accelerometer, :gyroscope, :magnetometer, :heartBeatIntervals],
            :rate => both, :secs => Config.HF_SECS });
        steps.add({ :kind => :info, :secs => Config.INFO_SECS });
        steps.add({ :kind => :pos, :secs => Config.POS_SECS });
    }

    function start() as Void {
        if (running) {
            return;
        }
        var clock = System.getClockTime();
        Log.emit("META", ["sensor-probe", Config.VERSION, clock.hour + ":" + clock.min + ":" + clock.sec,
            Config.HF_SECS, Config.HBI_SECS, Config.INFO_SECS, Config.POS_SECS, Config.HF_PERIOD_S, Config.LOG_RAW]);
        results = ["-- history --"];
        results.addAll(Inventory.run());
        results.add("-- live --");
        buildPlan();
        Log.emit("PLAN", [steps.size()]);
        running = true;
        done = false;
        idx = -1;
        timer = new Timer.Timer();
        timer.start(method(:tick), 1000, true);
        nextStep();
    }

    function abort() as Void {
        if (!running) {
            return;
        }
        finishStep();
        Log.emit("ABORT", [idx]);
        end();
    }

    function end() as Void {
        running = false;
        if (timer != null) {
            timer.stop();
            timer = null;
        }
        Log.emit("END", [System.getSystemStats().battery]);
        try {
            Application.Storage.setValue("lastResults", results);
        } catch (e instanceof Lang.Exception) {
        }
        WatchUi.requestUpdate();
    }

    function tick() as Void {
        var now = System.getTimer();
        if (settling) {
            if (now - settleStart >= Config.SETTLE_MS) {
                settling = false;
                nextStep();
            }
        } else if (probe != null && now - phaseStart >= steps[idx][:secs] * 1000) {
            finishStep();
            settling = true;
            settleStart = now;
        }
        WatchUi.requestUpdate();
    }

    function nextStep() as Void {
        idx += 1;
        if (idx >= steps.size()) {
            done = true;
            end();
            return;
        }
        var s = steps[idx];
        if (s[:kind] == :hf) {
            probe = new HfProbe("p" + idx, s[:ch], s[:rate]);
        } else if (s[:kind] == :info) {
            probe = new InfoProbe();
        } else {
            probe = new PosProbe();
        }
        Log.emit("BATT", ["p" + idx, "start", System.getSystemStats().battery]);
        phaseStart = System.getTimer();
        probe.start();
    }

    function finishStep() as Void {
        if (probe == null) {
            return;
        }
        probe.stop();
        results.addAll(probe.report());
        Log.emit("BATT", ["p" + idx, "end", System.getSystemStats().battery]);
        probe = null;
    }

    function statusLine() as String {
        if (done) {
            return "Done. Log saved.";
        }
        if (!running) {
            return "Press START";
        }
        if (settling || probe == null) {
            return "Step " + (idx + 2) + "/" + steps.size() + " ...";
        }
        var s = steps[idx];
        var el = (System.getTimer() - phaseStart) / 1000;
        var what = s[:kind] == :hf ? probe.chanNames().toString() + "@" + s[:rate] : (s[:kind] == :info ? "1Hz info" : "gps");
        return (idx + 1) + "/" + steps.size() + " " + what + " " + el + "/" + s[:secs] + "s";
    }
}
