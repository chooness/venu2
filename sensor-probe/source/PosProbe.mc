import Toybox.Lang;
import Toybox.Position;
import Toybox.System;

// GNSS event phase: callback rate and fix quality. Coordinates are only
// logged when Config.LOG_COORDS is on.
class PosProbe {
    var callbacks = 0;
    var lastMs = null;
    var interval = new RunningStats();
    // Index = Position.QUALITY_* (0 not available .. 4 good).
    var quality = [0, 0, 0, 0, 0];
    var error = null;

    function start() as Void {
        Log.emit("POS_START", [Config.LOG_COORDS]);
        try {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPos));
        } catch (e instanceof Lang.Exception) {
            error = e.getErrorMessage();
            Log.emit("POS_ERR", [error]);
        }
    }

    function stop() as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPos));
    }

    function onPos(info as Position.Info) as Void {
        var t = System.getTimer();
        callbacks += 1;
        if (lastMs != null) {
            interval.add(t - lastMs);
        }
        lastMs = t;
        var q = info.accuracy;
        if (q != null && q >= 0 && q < quality.size()) {
            quality[q] += 1;
        }
        var lat = null;
        var lon = null;
        if (Config.LOG_COORDS && info.position != null) {
            var deg = info.position.toDegrees();
            lat = deg[0];
            lon = deg[1];
        }
        var when = (info.when != null) ? info.when.value() : null;
        Log.emit("POS", [t, q, when, info.altitude, info.speed, info.heading, lat, lon]);
    }

    function report() as Array {
        Log.emit("POS_RATE", [callbacks, interval.mean(), interval.std(), interval.min, interval.max,
            quality, error]);
        return ["gps: " + callbacks + " ev, good " + (quality[3] + quality[4])];
    }
}
