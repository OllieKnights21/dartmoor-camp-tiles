import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.WatchUi;

var gData = null;     // AppData, shared by every page

class CampMapApp extends Application.AppBase {
    function initialize() { AppBase.initialize(); }

    function onStart(state) {
        $.gData = new AppData();
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
    }

    function onStop(state) {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        if ($.gData != null) { $.gData.save(); }
    }

    function onPosition(info as Position.Info) as Void {
        $.gData.onPosition(info);
        WatchUi.requestUpdate();
    }

    function getInitialView() {
        return [$.pageView(0), new PageDelegate(0)];
    }

    function onSettingsChanged() {
        $.gData.loadSettings();
        WatchUi.requestUpdate();
    }
}
