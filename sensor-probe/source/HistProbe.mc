import Toybox.Lang;

// Reads one history store as its own Runner step so no single callback
// does enough work to trip the watchdog.
class HistProbe {
    var store as String;
    var out as Array = [];

    function initialize(name as String) {
        store = name;
    }

    function start() as Void {
        Inventory.readHistory(store, out);
    }

    function stop() as Void {
    }

    function report() as Array {
        return out;
    }
}
