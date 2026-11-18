import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

module Col {
    const DIM = 0x969696;
    const AMBER = 0xFFB020;
    const BLUE = 0x50A0FF;
    const LBLUE = 0x285082;
    const GUST = 0x5A3C0A;
    const CYAN = 0x5ADCE6;
    const GRID = 0x282828;
}

function centreText(dc, y, font, s, col) {
    dc.setColor(col, Graphics.COLOR_TRANSPARENT);
    dc.drawText(dc.getWidth() / 2, y, font, s, Graphics.TEXT_JUSTIFY_CENTER);
}

function noData(dc, title) {
    var h = dc.getHeight();
    $.centreText(dc, h * 0.10, Graphics.FONT_XTINY, title, Col.DIM);
    $.centreText(dc, h * 0.42, Graphics.FONT_SMALL, "No data yet", Graphics.COLOR_WHITE);
    $.centreText(dc, h * 0.55, Graphics.FONT_XTINY, "Hold UP > Sync now", Col.DIM);
}

// Page 2: rain for the next 12 hours: muted bar = % chance, bright inner bar = mm.
class RainView extends WatchUi.View {
    function initialize() { View.initialize(); }
    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK); dc.clear();
        var d = $.gData; var w = dc.getWidth(); var h = dc.getHeight();
        var i0 = d.weatherNow();
        if (i0 < 0) { $.noData(dc, "RAIN"); return; }
        var t = d.weather["time"]; var prob = d.weather["prob"]; var mm = d.weather["mm"];
        var n = t.size() - i0; if (n > 12) { n = 12; }
        // headline
        var maxMm = 0.0; var maxI = i0; var total = 0.0; var firstWet = -1;
        for (var i = i0; i < i0 + n; i++) {
            var v = mm[i] == null ? 0.0 : mm[i];
            total += v;
            if (v > maxMm) { maxMm = v; maxI = i; }
            if (firstWet < 0 && (v >= 0.2 || (prob[i] != null && prob[i] >= 50))) { firstWet = i; }
        }
        var head = firstWet < 0 ? "Dry for 12 h" : (firstWet == i0 ? "Rain now" : "Rain from " + t[firstWet].substring(11, 16));
        $.centreText(dc, h * 0.08, Graphics.FONT_XTINY, "RAIN · NEXT " + n + " H", Col.DIM);
        $.centreText(dc, h * 0.15, Graphics.FONT_SMALL, head, Col.BLUE);
        $.centreText(dc, h * 0.25, Graphics.FONT_XTINY, maxMm >= 0.1 ? "Heaviest " + t[maxI].substring(11, 16) + " · " + maxMm.format("%.1f") + " mm" : total.format("%.1f") + " mm total", Graphics.COLOR_WHITE);
        var gx0 = w * 0.14; var gx1 = w * 0.86; var gy0 = h * 0.35; var gy1 = h * 0.70;
        var bw = (gx1 - gx0) / n;
        dc.setColor(Col.GRID, Graphics.COLOR_TRANSPARENT);
        for (var v = 25; v <= 100; v += 25) { var y = gy1 - (gy1 - gy0) * v / 100; dc.drawLine(gx0, y, gx1, y); }
        for (var k = 0; k < n; k++) {
            var i = i0 + k; var x = gx0 + k * bw;
            var p = prob[i] == null ? 0 : prob[i];
            var yp = gy1 - (gy1 - gy0) * p / 100.0;
            dc.setColor(Col.LBLUE, Graphics.COLOR_TRANSPARENT); dc.fillRectangle(x + 2, yp, bw - 4, gy1 - yp);
            var m = mm[i] == null ? 0.0 : mm[i]; if (m > 4) { m = 4.0; }
            var ym = gy1 - (gy1 - gy0) * m / 4.0;
            dc.setColor(Col.BLUE, Graphics.COLOR_TRANSPARENT); dc.fillRectangle(x + bw * 0.3, ym, bw * 0.4, gy1 - ym);
            if (k % 3 == 0) {
                dc.setColor(Col.DIM, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x + bw / 2, gy1 + 2, Graphics.FONT_XTINY, t[i].substring(11, 13), Graphics.TEXT_JUSTIFY_CENTER);
            }
        }
        dc.setColor(Col.DIM, Graphics.COLOR_TRANSPARENT); dc.drawLine(gx0, gy1, gx1, gy1);
        $.centreText(dc, h * 0.80, Graphics.FONT_XTINY, "chance · mm/h (0-4)", Col.DIM);
        $.centreText(dc, h * 0.87, Graphics.FONT_XTINY, "Open-Meteo", Col.DIM);
    }
}

// Page 3: wind for the next 12 hours: gust bar behind, mean bar in front, direction arrows above.
class WindView extends WatchUi.View {
    function initialize() { View.initialize(); }
    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK); dc.clear();
        var d = $.gData; var w = dc.getWidth(); var h = dc.getHeight();
        var i0 = d.weatherNow();
        if (i0 < 0 || d.weather["wind_mph"] == null) { $.noData(dc, "WIND"); return; }
        var t = d.weather["time"]; var ws = d.weather["wind_mph"]; var gs = d.weather["gust_mph"]; var wd = d.weather["wind_from_deg"];
        var n = t.size() - i0; if (n > 12) { n = 12; }
        var top = 20.0; var maxI = i0;
        for (var i = i0; i < i0 + n; i++) {
            if (gs[i] > top) { top = gs[i]; }
            if (ws[i] > ws[maxI]) { maxI = i; }
        }
        top = (Math.ceil(top / 10.0) * 10).toFloat();
        // overnight direction: mean of the last 6 hours shown
        var sx = 0.0; var sy = 0.0;
        for (var i = i0 + n - 6; i < i0 + n; i++) { if (i >= i0) { sx += Math.sin(Geo.rad(wd[i])); sy += Math.cos(Geo.rad(wd[i])); } }
        var from = Geo.fmod(Geo.deg(Math.atan2(sx, sy)), 360.0d);
        $.centreText(dc, h * 0.08, Graphics.FONT_XTINY, "WIND · NEXT " + n + " H", Col.DIM);
        $.centreText(dc, h * 0.15, Graphics.FONT_SMALL, "From " + Geo.compass(wd[i0]) + " · " + ws[i0].toNumber() + " mph", Graphics.COLOR_WHITE);
        $.centreText(dc, h * 0.25, Graphics.FONT_XTINY, "Strongest " + t[maxI].substring(11, 16) + " · " + ws[maxI].toNumber() + ", gusts " + gs[maxI].toNumber(), Col.AMBER);
        var gx0 = w * 0.14; var gx1 = w * 0.86; var gy0 = h * 0.40; var gy1 = h * 0.70;
        var bw = (gx1 - gx0) / n;
        for (var k = 0; k < n; k++) {
            var i = i0 + k; var x = gx0 + k * bw;
            var yg = gy1 - (gy1 - gy0) * gs[i] / top;
            dc.setColor(Col.GUST, Graphics.COLOR_TRANSPARENT); dc.fillRectangle(x + 2, yg, bw - 4, gy1 - yg);
            var ym = gy1 - (gy1 - gy0) * ws[i] / top;
            dc.setColor(Col.AMBER, Graphics.COLOR_TRANSPARENT); dc.fillRectangle(x + bw * 0.28, ym, bw * 0.44, gy1 - ym);
            arrow(dc, x + bw / 2, gy0 - 12, 9, Geo.rad(wd[i] + 180.0));
            if (k % 3 == 0) {
                dc.setColor(Col.DIM, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x + bw / 2, gy1 + 2, Graphics.FONT_XTINY, t[i].substring(11, 13), Graphics.TEXT_JUSTIFY_CENTER);
            }
        }
        dc.setColor(Col.DIM, Graphics.COLOR_TRANSPARENT); dc.drawLine(gx0, gy1, gx1, gy1);
        var lee = Geo.compass(Geo.fmod(from + 180.0, 360.0d));
        $.centreText(dc, h * 0.80, Graphics.FONT_XTINY, "Pitch on the " + lee + " side of slopes", Col.CYAN);
        $.centreText(dc, h * 0.87, Graphics.FONT_XTINY, "mph · top " + top.toNumber(), Col.DIM);
    }
    hidden function arrow(dc, cx, cy, L, to) {
        var dx = Math.sin(to); var dy = -Math.cos(to);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(cx - dx * L, cy - dy * L, cx + dx * L, cy + dy * L);
        dc.setPenWidth(1);
        var hx = cx + dx * L; var hy = cy + dy * L; var s = L * 0.6;
        dc.fillPolygon([[hx, hy], [hx - dx * s - dy * s * 0.6, hy - dy * s + dx * s * 0.6], [hx - dx * s + dy * s * 0.6, hy - dy * s - dx * s * 0.6]]);
    }
}

// Page 4: warnings, light and today's firing.
class CondView extends WatchUi.View {
    function initialize() { View.initialize(); }
    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK); dc.clear();
        var d = $.gData; var w = dc.getWidth(); var h = dc.getHeight();
        var fh = dc.getFontHeight(Graphics.FONT_XTINY);
        $.centreText(dc, h * 0.07, Graphics.FONT_XTINY, "CONDITIONS", Col.DIM);
        // warnings card
        var ws = d.devonWarnings();
        var y = h * 0.14;
        var col = ws.size() == 0 ? Tent.GREEN : (levelCol(ws[0]["level"]));
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2); dc.drawRoundedRectangle(w * 0.13, y, w * 0.74, fh * 2 + 8, 10); dc.setPenWidth(1);
        if (d.warnings == null) {
            $.centreText(dc, y + 4, Graphics.FONT_XTINY, "Warnings not synced", Col.DIM);
        } else if (ws.size() == 0) {
            $.centreText(dc, y + 4, Graphics.FONT_TINY, "No warnings", Tent.GREEN);
            $.centreText(dc, y + 4 + fh, Graphics.FONT_XTINY, "Met Office · Devon", Col.DIM);
        } else {
            var w0 = ws[0];
            $.centreText(dc, y + 4, Graphics.FONT_XTINY, cap(w0["level"]) + " · " + cap(w0["type"]) + (ws.size() > 1 ? " +" + (ws.size() - 1) : ""), col);
            var v = w0["valid"];
            $.centreText(dc, y + 4 + fh, Graphics.FONT_XTINY, v == null ? "" : short(v[0]) + " to " + short(v[1]), Graphics.COLOR_WHITE);
        }
        y += fh * 2 + 16;
        // light
        if (d.lat != null) {
            var doy = Geo.dayOfYear();
            var s = Geo.sun(d.lat, d.lon, doy, 90.833d);
            var c = Geo.sun(d.lat, d.lon, doy, 96.0d);
            var s2 = Geo.sun(d.lat, d.lon, doy + 1, 90.833d);
            if (s != null && c != null) {
                row(dc, w, y, "Sunset", Geo.hhmm(s[1]), Graphics.COLOR_WHITE); y += fh;
                var m = (c[1] - Geo.nowUtcHours()) * 60;
                row(dc, w, y, "Dark", Geo.hhmm(c[1]) + (m > 0 ? " (" + Geo.duration(m) + ")" : ""), Col.AMBER); y += fh;
                if (s2 != null) { row(dc, w, y, "Sunrise", Geo.hhmm(s2[0]), Graphics.COLOR_WHITE); y += fh; }
            }
        } else {
            $.centreText(dc, y, Graphics.FONT_XTINY, "Light: waiting for GPS", Col.DIM); y += fh;
        }
        y += 6;
        // firing today
        $.centreText(dc, y, Graphics.FONT_XTINY, "FIRING TODAY", Col.DIM); y += fh;
        var codes = d.firingFor(0);
        var names = (d.firing != null && d.firing["ranges"] != null) ? d.firing["ranges"] : ["Okehampton", "Willsworthy", "Merrivale"];
        if (codes == null) {
            $.centreText(dc, y, Graphics.FONT_XTINY, "Not synced", Col.DIM);
        } else {
            for (var i = 0; i < names.size() && i < codes.length(); i++) {
                var ch = codes.substring(i, i + 1);
                row(dc, w, y, names[i], firingText(ch), ch.equals("0") ? Tent.GREEN : (ch.equals("?") ? Col.DIM : Tent.RED));
                y += fh;
            }
        }
    }
    hidden function row(dc, w, y, label, value, col) {
        dc.setColor(Col.DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 0.18, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 0.82, y, Graphics.FONT_XTINY, value, Graphics.TEXT_JUSTIFY_RIGHT);
    }
    hidden function cap(s) { return s == null || s.length() == 0 ? "" : s.substring(0, 1).toUpper() + s.substring(1, s.length()); }
    hidden function short(s) { return s.length() > 18 ? s.substring(0, 18) : s; }
    hidden function levelCol(l) { return "red".equals(l) ? Tent.RED : ("amber".equals(l) ? Col.AMBER : 0xFFE100); }
}

function firingText(ch) {
    if (ch.equals("0")) { return "None"; }
    if (ch.equals("1")) { return "Day"; }
    if (ch.equals("2")) { return "Night"; }
    if (ch.equals("3")) { return "Day+night"; }
    return "?";
}
