import Toybox.Lang;
import Toybox.System;

// Every record is one println line:
//   SP,<seq>,<timer_ms>,<KIND>,<field>,<field>,...
// Arrays are joined with ';'. Empty field = null. On a real watch println
// output goes to GARMIN/APPS/LOGS/<PRGNAME>.TXT if that file exists; in the
// simulator it goes to the console. tools/parse_log.py reads this format.
module Log {
    var seq = 0;

    function emit(kind as String, fields as Array) as Void {
        var s = "SP," + seq + "," + System.getTimer() + "," + kind;
        for (var i = 0; i < fields.size(); i++) {
            s += "," + fmt(fields[i]);
        }
        System.println(s);
        seq += 1;
    }

    function fmt(v) as String {
        if (v == null) {
            return "";
        }
        if (v instanceof Lang.Float || v instanceof Lang.Double) {
            return v.format("%.3f");
        }
        if (v instanceof Lang.Array) {
            var s = "";
            for (var i = 0; i < v.size(); i++) {
                if (i > 0) {
                    s += ";";
                }
                s += fmt(v[i]);
            }
            return s;
        }
        if (v instanceof Lang.String) {
            return clean(v);
        }
        return v.toString();
    }

    // Keep the CSV framing intact.
    function clean(s as String) as String {
        var out = "";
        var chars = s.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var c = chars[i];
            if (c == ',' || c == '\n' || c == '\r') {
                out += " ";
            } else if (c == ';') {
                out += ":";
            } else {
                out += c.toString();
            }
        }
        return out;
    }
}
