import Toybox.Activity;
import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// Tent data field: green tent inside a DNPA camping area, red tent + distance outside.
// Full-screen layout adds distance left, average pace, ETA vs dark and position.
class CampFieldView extends WatchUi.DataField {
    const AMBER = 0xFFB020;
    const DIM = 0x969696;

    hidden var _camp;
    hidden var _lat = null;
    hidden var _lon = null;
    hidden var _posFmt = 0;
    hidden var _alerts = true;
    hidden var _wasInside = null;
    hidden var _left = null;       // metres to end of navigated course
    hidden var _speed = null;      // average speed m/s
    hidden var _duskUtc = null;    // civil dusk today, UTC hours
    hidden var _sunKey = null;
    hidden var _margin = null;     // minutes between ETA and dusk (+ before, - after)
    hidden var _marginLevel = 0;   // 0 green, 1 amber, 2 red
    hidden var _posText = "";

    function initialize() {
        DataField.initialize();
        _camp = new CampLocator();
        loadSettings();
    }

    function loadSettings() {
        var f = Application.Properties.getValue("posFormat");
        _posFmt = (f == null) ? 0 : f;
        var a = Application.Properties.getValue("alerts");
        _alerts = (a == null) ? true : a;
        if (_lat != null) { _posText = Geo.position(_lat, _lon, _posFmt); }
    }

    function compute(info as Activity.Info) as Void {
        if (info.currentLocation != null) {
            var d = info.currentLocation.toDegrees();
            _lat = d[0]; _lon = d[1];
            _camp.update(_lat, _lon, 10);
            _posText = Geo.position(_lat, _lon, _posFmt);
            updateSun();
        }
        _left = (info has :distanceToDestination) ? info.distanceToDestination : null;
        _speed = info.averageSpeed;
        updateMargin();
        checkAlerts();
    }

    hidden function updateSun() {
        var doy = Geo.dayOfYear();
        var key = doy * 1000 + (_lat * 10).toNumber();
        if (key == _sunKey) { return; }
        _sunKey = key;
        var s = Geo.sun(_lat, _lon, doy, 96.0d);
        _duskUtc = (s == null) ? null : s[1];
    }

    hidden function updateMargin() {
        _margin = null;
        if (_duskUtc == null) { return; }
        var now = Geo.nowUtcHours();
        var eta = now;
        if (_left != null && _left > 0) {
            if (_speed == null || _speed < 0.3) { return; }
            eta = now + _left / _speed / 3600.0;
        }
        _margin = (_duskUtc - eta) * 60.0;
        _marginLevel = _margin >= 30 ? 0 : (_margin >= 0 ? 1 : 2);
    }

    hidden function checkAlerts() {
        if (_lat == null) { return; }
        var ins = _camp.inside;
        if (_wasInside != null && ins != _wasInside && _alerts) {
            buzz(ins ? 1 : 2);
        }
        _wasInside = ins;
        if (_margin != null) {
            if (_marginLevel > _lastAlertLevel && _alerts && _left != null) { buzz(3); }
            _lastAlertLevel = _marginLevel;
        }
    }
    hidden var _lastAlertLevel = 0;

    hidden function buzz(n) {
        if (!(Attention has :vibrate)) { return; }
        var p = [];
        for (var i = 0; i < n; i++) {
            p.add(new Attention.VibeProfile(80, 250));
            p.add(new Attention.VibeProfile(0, 150));
        }
        Attention.vibrate(p);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var bg = getBackgroundColor();
        var fg = (bg == Graphics.COLOR_BLACK) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        dc.setColor(fg, bg);
        dc.clear();
        var w = dc.getWidth(); var h = dc.getHeight();
        var sh = System.getDeviceSettings().screenHeight;
        if (_lat == null) {
            Tent.draw(dc, w / 2, h / 2 - h * 0.12, h * 0.3, DIM, bg);
            text(dc, w / 2, h / 2 + h * 0.12, Graphics.FONT_XTINY, "Waiting for GPS", DIM);
            return;
        }
        if (h > sh * 0.7) { drawFull(dc, w, h, fg, bg); }
        else if (h > sh * 0.3) { drawHalf(dc, w, h, fg, bg); }
        else { drawSmall(dc, w, h, fg, bg); }
    }

    hidden function campText() {
        if (_camp.inside) { return ""; }
        if (_camp.distM == null) { return "--"; }
        if (_camp.distM > 50000) { return "far"; }
        return Geo.dist(_camp.distM) + " " + Geo.compass(_camp.bearing);
    }

    hidden function tentColour() { return _camp.inside ? Tent.GREEN : Tent.RED; }

    hidden function marginColour() {
        return _marginLevel == 0 ? Tent.GREEN : (_marginLevel == 1 ? AMBER : Tent.RED);
    }

    hidden function marginText() {
        if (_margin == null) { return "Dark --:--"; }
        if (_left != null && _left > 0) {
            return Geo.duration(_margin) + (_margin >= 0 ? " before dark" : " after dark");
        }
        if (_margin < 0) { return "Dark since " + Geo.hhmm(_duskUtc); }
        return "Dark in " + Geo.duration(_margin);
    }

    hidden function drawFull(dc, w, h, fg, bg) {
        var y = h * 0.17;
        Tent.draw(dc, w / 2, y, h * 0.15, tentColour(), bg);
        y += h * 0.11;
        var ct = campText();
        if (!ct.equals("")) {
            text(dc, w / 2, y, Graphics.FONT_SMALL, ct, fg);
        }
        y += h * 0.09;
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(w * 0.15, y, w * 0.85, y);
        y += h * 0.02;
        var navigating = (_left != null && _left > 0);
        var rowH = dc.getFontHeight(Graphics.FONT_XTINY) + 2;
        if (navigating) {
            row(dc, w, y, "Left", Geo.dist(_left), fg); y += rowH;
            row(dc, w, y, "Avg pace", Geo.pace(_speed), fg); y += rowH;
            var eta = (_speed != null && _speed >= 0.3) ? Geo.hhmm(Geo.nowUtcHours() + _left / _speed / 3600.0) : "--:--";
            row(dc, w, y, "ETA", eta, fg); y += rowH;
        } else {
            y += rowH;
        }
        // margin box
        var bh = dc.getFontHeight(Graphics.FONT_TINY) + 6;
        var col = marginColour();
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(w * 0.14, y + 2, w * 0.72, bh, 8);
        dc.setPenWidth(1);
        text(dc, w / 2, y + 2 + bh / 2, Graphics.FONT_TINY, marginText(), col);
        y += bh + h * 0.04;
        text(dc, w / 2, y, Graphics.FONT_XTINY, _posText, fg);
        y += dc.getFontHeight(Graphics.FONT_XTINY);
        if (_duskUtc != null) {
            text(dc, w / 2, y, Graphics.FONT_XTINY, "dark " + Geo.hhmm(_duskUtc), DIM);
        }
    }

    hidden function drawHalf(dc, w, h, fg, bg) {
        var ct = campText();
        var font = Graphics.FONT_MEDIUM;
        var ts = h * 0.32;
        var tw = ct.equals("") ? 0 : dc.getTextWidthInPixels(ct, font) + 8;
        var total = ts * 1.3 + tw;
        var x0 = (w - total) / 2;
        var cy = h * 0.38;
        Tent.draw(dc, x0 + ts * 0.65, cy, ts, tentColour(), bg);
        if (tw > 0) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x0 + ts * 1.3 + 4, cy, font, ct, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        text(dc, w / 2, h * 0.72, Graphics.FONT_XTINY, _posText, fg);
    }

    hidden function drawSmall(dc, w, h, fg, bg) {
        var ct = campText();
        var font = Graphics.FONT_SMALL;
        var ts = h * 0.55;
        var tw = ct.equals("") ? 0 : dc.getTextWidthInPixels(ct, font) + 6;
        var total = ts * 1.3 + tw;
        var x0 = (w - total) / 2;
        Tent.draw(dc, x0 + ts * 0.65, h / 2, ts, tentColour(), bg);
        if (tw > 0) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x0 + ts * 1.3 + 3, h / 2, font, ct, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    hidden function row(dc, w, y, label, value, fg) {
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 0.18, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 0.82, y, Graphics.FONT_XTINY, value, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    hidden function text(dc, x, y, font, s, col) {
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, s, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
