import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class CampFieldApp extends Application.AppBase {
    var view;
    function initialize() { AppBase.initialize(); }
    function getInitialView() {
        view = new CampFieldView();
        return [view];
    }
    function onSettingsChanged() {
        if (view != null) { view.loadSettings(); }
        WatchUi.requestUpdate();
    }
}
