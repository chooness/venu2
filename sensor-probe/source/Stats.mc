import Toybox.Lang;
import Toybox.Math;

// Running mean / stddev / min / max without keeping samples.
class RunningStats {
    var n = 0;
    var sum = 0.0d;
    var sumSq = 0.0d;
    var min = null;
    var max = null;

    function add(v) as Void {
        var d = v.toDouble();
        n += 1;
        sum += d;
        sumSq += d * d;
        if (min == null || d < min) {
            min = d;
        }
        if (max == null || d > max) {
            max = d;
        }
    }

    function mean() {
        return n > 0 ? sum / n : null;
    }

    function std() {
        if (n < 2) {
            return null;
        }
        var m = sum / n;
        var v = (sumSq - n * m * m) / (n - 1);
        return v > 0 ? Math.sqrt(v) : 0.0d;
    }
}

// Rate bookkeeping for one channel of a registerSensorDataListener phase.
//
// Two independent clocks are used and reported separately:
//  - callback arrival time (System.getTimer at callback), always available;
//  - per-sample timestamps from :includeTimestamps (API 5.1.1+), if the
//    firmware fills them in. Only these give true inter-sample timing.
class ChannelStats {
    var name as String;
    var requestedHz as Number;
    var callbacks = 0;
    var emptyCallbacks = 0;
    var samples = 0;
    var firstBatch = 0;
    var firstCbMs = null;
    var lastCbMs = null;
    var cbInterval = new RunningStats();
    var batchSize = new RunningStats();
    var values = new RunningStats();

    var tsCount = 0;
    var tsFirst = null;
    var tsLast = null;
    var tsInterval = new RunningStats();
    var tsBackwards = 0;
    var tsGaps = 0;
    var tsMissing = 0;

    function initialize(n as String, hz as Number) {
        name = n;
        requestedHz = hz;
    }

    function addBatch(cbMs as Number, count as Number, ts) as Void {
        callbacks += 1;
        if (count == 0) {
            emptyCallbacks += 1;
        }
        if (firstCbMs == null) {
            firstCbMs = cbMs;
            firstBatch = count;
        } else {
            cbInterval.add(cbMs - lastCbMs);
        }
        lastCbMs = cbMs;
        samples += count;
        batchSize.add(count);

        if (ts != null) {
            var nominal = requestedHz > 0 ? 1000.0 / requestedHz : null;
            for (var i = 0; i < ts.size(); i++) {
                var t = ts[i];
                if (tsLast != null) {
                    var dt = t - tsLast;
                    if (dt <= 0) {
                        tsBackwards += 1;
                    } else {
                        tsInterval.add(dt);
                        if (nominal != null && dt > 1.5 * nominal) {
                            tsGaps += 1;
                            tsMissing += (dt / nominal + 0.5).toNumber() - 1;
                        }
                    }
                }
                if (tsFirst == null) {
                    tsFirst = t;
                }
                tsLast = t;
                tsCount += 1;
            }
        }
    }

    function addValues(arr) as Void {
        if (arr == null) {
            return;
        }
        for (var i = 0; i < arr.size(); i++) {
            if (arr[i] != null) {
                values.add(arr[i]);
            }
        }
    }

    // Samples per second judged by callback arrival. The first batch is
    // excluded because its start time is unknown.
    function observedHzByCallback() {
        if (callbacks < 2 || lastCbMs == firstCbMs) {
            return null;
        }
        return (samples - firstBatch) * 1000.0 / (lastCbMs - firstCbMs);
    }

    function observedHzByTimestamp() {
        if (tsCount < 2 || tsLast == tsFirst) {
            return null;
        }
        return (tsCount - 1) * 1000.0 / (tsLast - tsFirst);
    }

    // Shortfall versus the requested rate over the callback window.
    function droppedEstimate() {
        if (requestedHz <= 0 || callbacks < 2) {
            return null;
        }
        var expected = requestedHz * (lastCbMs - firstCbMs) / 1000.0;
        var got = samples - firstBatch;
        var d = (expected - got + 0.5).toNumber();
        return d;
    }
}
