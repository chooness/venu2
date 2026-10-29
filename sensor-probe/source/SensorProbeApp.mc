import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class SensorProbeApp extends Application.AppBase {
    var runner as Runner;

    function initialize() {
        AppBase.initialize();
        runner = new Runner();
    }

    function onStop(state as Dictionary?) as Void {
        // Never leave a listener or GPS on after the app exits.
        runner.abort();
    }

    function getInitialView() {
        var v = new ProbeView(runner);
        return [v, new ProbeDelegate(runner, v)];
    }
}

class ProbeView extends WatchUi.View {
    var runner as Runner;
    var scroll = 0;

    function initialize(r as Runner) {
        View.initialize();
        runner = r;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var font = Graphics.FONT_XTINY;
        var lh = dc.getFontHeight(font);
        var y = h / 8;

        dc.drawText(w / 2, y, Graphics.FONT_SMALL, "Sensor Probe", Graphics.TEXT_JUSTIFY_CENTER);
        y += dc.getFontHeight(Graphics.FONT_SMALL);
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y, font, runner.statusLine(), Graphics.TEXT_JUSTIFY_CENTER);
        y += lh + 4;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var lines = runner.results;
        var maxLines = (h - y - h / 10) / lh;
        if (scroll > lines.size() - 1) {
            scroll = lines.size() > 0 ? lines.size() - 1 : 0;
        }
        for (var i = scroll; i < lines.size() && i < scroll + maxLines; i++) {
            dc.drawText(w / 2, y, font, lines[i], Graphics.TEXT_JUSTIFY_CENTER);
            y += lh;
        }
    }
}

// START/select: start the run, or abort it. Up/down or swipe: scroll results.
class ProbeDelegate extends WatchUi.BehaviorDelegate {
    var runner as Runner;
    var probeView as ProbeView;

    function initialize(r as Runner, v as ProbeView) {
        BehaviorDelegate.initialize();
        runner = r;
        probeView = v;
    }

    function onSelect() as Boolean {
        if (runner.running) {
            runner.abort();
        } else {
            runner.start();
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() as Boolean {
        probeView.scroll += 3;
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        probeView.scroll = probeView.scroll > 3 ? probeView.scroll - 3 : 0;
        WatchUi.requestUpdate();
        return true;
    }
}
