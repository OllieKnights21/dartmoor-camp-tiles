import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Page 1: picture-tile map, north up, with route, track, position, tent, wind and info band.
class MapView extends WatchUi.View {
    const MAGENTA = 0xE150FF;
    const YELLOW = 0xFFE100;
    const BLUE = 0x006EEB;
    const AMBER = 0xFFB020;
    const DIM = 0x969696;
    const PANEL = 0x101010;

    // pan offset in pixels at the current zoom (when not following)
    var panX = 0.0;
    var panY = 0.0;
    var panMode = false;
    var panAxisEW = false;

    hidden var _buf = null;        // screen-sized palette bitmap holding the tiles
    hidden var _bufCx = null;      // world pixel centre the buffer was drawn for
    hidden var _bufCy = null;
    hidden var _bufZ = null;
    hidden var _dirty = true;
    hidden var _w = 0;
    hidden var _h = 0;
    // last known centre, used when there is no GPS yet (centre of the park)
    hidden var _cLat = 50.58d;
    hidden var _cLon = -3.93d;

    function initialize() {
        View.initialize();
    }

    function onShow() {
        $.gData.tiles.listener = method(:onTile);
        _dirty = true;
    }

    function onHide() {
        $.gData.tiles.listener = null;
        _buf = null;                // give the memory back to other pages
    }

    function onTile() as Void { _dirty = true; WatchUi.requestUpdate(); }

    function zoomBy(d) {
        var z = $.gData.zoom + d;
        if (z < TileInfo.MINZ || z > TileInfo.MAXZ) { return; }
        // keep the same place in the middle when panned
        panX = d > 0 ? panX * 2 : panX / 2;
        panY = d > 0 ? panY * 2 : panY / 2;
        $.gData.zoom = z;
        $.gData.tiles.clearQueue();
        _dirty = true;
        WatchUi.requestUpdate();
    }

    function pan(dir) {
        var step = _w / 3.0;
        if (panAxisEW) { panX += dir * step; } else { panY -= dir * step; }
        $.gData.follow = false;
        WatchUi.requestUpdate();
    }

    function recentre() { panX = 0.0; panY = 0.0; $.gData.follow = true; panMode = false; WatchUi.requestUpdate(); }

    // world pixel centre of the screen
    hidden function centre(z) {
        var d = $.gData;
        if (d.lat != null) { _cLat = d.lat; _cLon = d.lon; }
        var c = Merc.toPixel(_cLat, _cLon, z);
        return [c[0] + panX, c[1] + panY];
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        _w = dc.getWidth(); _h = dc.getHeight();
        var d = $.gData;
        var z = d.zoom;
        var c = centre(z);
        var cx = c[0]; var cy = c[1];

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // re-draw the tile buffer when we've moved more than a few pixels
        if (_buf == null || _bufZ != z || _dirty || (cx - _bufCx).abs() > 6 || (cy - _bufCy).abs() > 6) {
            renderTiles(cx, cy, z);
        }
        if (_buf != null) {
            dc.drawBitmap(Math.round(_bufCx - cx).toNumber(), Math.round(_bufCy - cy).toNumber(), _buf);
        }
        var x0 = cx - _w / 2.0; var y0 = cy - _h / 2.0;

        if (d.showRoute) { drawRoute(dc, x0, y0, z); }
        if (d.showTrack) { drawTrack(dc, x0, y0, z); }
        drawMe(dc, x0, y0, z);
        drawTop(dc);
        drawWind(dc);
        drawBand(dc);
        drawScale(dc, z);
        if (panMode) {
            dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_w / 2, _h * 0.20, Graphics.FONT_XTINY, panAxisEW ? "PAN  E / W" : "PAN  N / S", Graphics.TEXT_JUSTIFY_CENTER);
        }
        var p = d.tiles.pending();
        if (p > 0) {
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_w * 0.82, _h * 0.30, Graphics.FONT_XTINY, p.format("%d"), Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    hidden function renderTiles(cx, cy, z) {
        if (_buf == null) {
            var opts = { :width => _w, :height => _h };   // full colour: tiles won't draw into a palette buffer
            if (Graphics has :createBufferedBitmap) {
                _buf = Graphics.createBufferedBitmap(opts).get();
            } else {
                _buf = new Graphics.BufferedBitmap(opts);
            }
        }
        var bdc = _buf.getDc();
        bdc.setColor(TileInfo.PALETTE[0], TileInfo.PALETTE[0]);
        bdc.clear();
        var x0 = cx - _w / 2.0; var y0 = cy - _h / 2.0;
        var tx0 = (x0 / 256).toNumber(); var ty0 = (y0 / 256).toNumber();
        var tx1 = ((x0 + _w) / 256).toNumber(); var ty1 = ((y0 + _h) / 256).toNumber();
        var tiles = $.gData.tiles;
        for (var tx = tx0; tx <= tx1; tx++) {
            for (var ty = ty0; ty <= ty1; ty++) {
                var b = tiles.get(z, tx, ty);
                if (b == null) {
                    if (inPark(z, tx, ty)) { tiles.request(z, tx, ty); }
                } else if (b != :none) {
                    bdc.drawBitmap(Math.round(tx * 256 - x0).toNumber(), Math.round(ty * 256 - y0).toNumber(), b);
                }
                b = null;
            }
        }
        _bufCx = cx; _bufCy = cy; _bufZ = z; _dirty = false;
    }

    hidden function inPark(z, tx, ty) {
        var a = Merc.toPixel(TileInfo.BOUNDS[3], TileInfo.BOUNDS[0], z);
        var b = Merc.toPixel(TileInfo.BOUNDS[1], TileInfo.BOUNDS[2], z);
        return tx >= (a[0] / 256).toNumber() && tx <= (b[0] / 256).toNumber() && ty >= (a[1] / 256).toNumber() && ty <= (b[1] / 256).toNumber();
    }

    hidden function toScreen(lat, lon, x0, y0, z) {
        var p = Merc.toPixel(lat, lon, z);
        return [(p[0] - x0).toNumber(), (p[1] - y0).toNumber()];
    }

    hidden function drawRoute(dc, x0, y0, z) {
        var r = $.gData.route();
        if (r == null) { return; }
        var p = r["pts"];
        var pts = [];
        for (var i = 0; i < p.size(); i += 2) { pts.add(toScreen(p[i] / 100000.0d, p[i + 1] / 100000.0d, x0, y0, z)); }
        polyline(dc, pts, 0x781E8C, 7);
        polyline(dc, pts, MAGENTA, 4);
    }

    hidden function drawTrack(dc, x0, y0, z) {
        var t = $.gData.track;
        if (t.size() < 4) { return; }
        var pts = [] as Array;
        for (var i = 0; i < t.size(); i += 2) { pts.add(toScreen(t[i], t[i + 1], x0, y0, z)); }
        var d = $.gData;
        if (d.lat != null) { pts.add(toScreen(d.lat, d.lon, x0, y0, z)); }
        polyline(dc, pts, YELLOW, 3);
        dc.setColor(YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(pts[0][0], pts[0][1], 5);
    }

    hidden function polyline(dc, pts, col, width) {
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(width);
        var lim = 2000;
        for (var i = 1; i < pts.size(); i++) {
            var a = pts[i - 1]; var b = pts[i];
            if ((a[0] < 0 && b[0] < 0) || (a[1] < 0 && b[1] < 0) || (a[0] > _w && b[0] > _w) || (a[1] > _h && b[1] > _h)) { continue; }
            if (a[0].abs() > lim || a[1].abs() > lim || b[0].abs() > lim || b[1].abs() > lim) { continue; }
            dc.drawLine(a[0], a[1], b[0], b[1]);
        }
        dc.setPenWidth(1);
    }

    // Garmin-style arrowhead: blue with a white edge and black outline, pointing where we're heading.
    hidden function drawMe(dc, x0, y0, z) {
        var d = $.gData;
        if (d.lat == null) { return; }
        var p = toScreen(d.lat, d.lon, x0, y0, z);
        var a = d.heading == null ? 0.0 : d.heading;
        chevron(dc, p[0], p[1], a, 24, Graphics.COLOR_BLACK);
        chevron(dc, p[0], p[1], a, 21, Graphics.COLOR_WHITE);
        chevron(dc, p[0], p[1], a, 16, BLUE);
    }

    hidden function chevron(dc, cx, cy, a, s, col) {
        var ca = Math.cos(a); var sa = Math.sin(a);
        var shape = [[0.0, -1.0], [0.72, 0.78], [0.0, 0.40], [-0.72, 0.78]];
        var pts = [];
        for (var i = 0; i < 4; i++) {
            var x = shape[i][0]; var y = shape[i][1];
            pts.add([(cx + s * (x * ca - y * sa)).toNumber(), (cy + s * (x * sa + y * ca)).toNumber()]);
        }
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);
    }

    // Top: green tent alone inside an area, red tent + distance outside. Warning triangle when live.
    hidden function drawTop(dc) {
        var d = $.gData;
        var cy = (_h * 0.09).toNumber();
        if (d.lat == null) {
            pill(dc, _w / 2, cy, _w * 0.36, "No GPS", DIM, Tent.RED);
            return;
        }
        if (d.camp.inside) {
            var r = (_h * 0.06).toNumber();
            dc.setColor(PANEL, Graphics.COLOR_TRANSPARENT); dc.fillCircle(_w / 2, cy, r);
            dc.setColor(0x5A5A5A, Graphics.COLOR_TRANSPARENT); dc.drawCircle(_w / 2, cy, r);
            Tent.draw(dc, _w / 2, cy + 2, r * 1.2, Tent.GREEN, PANEL);
        } else {
            var t = d.camp.distM == null ? "--" : Geo.dist(d.camp.distM);
            pill(dc, _w / 2, cy, _w * 0.36, t, Graphics.COLOR_WHITE, Tent.RED);
        }
        if (d.devonWarnings().size() > 0) {
            var x = _w * 0.72; var y = cy;
            dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[x, y - 12], [x + 13, y + 10], [x - 13, y + 10]]);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y - 1, Graphics.FONT_XTINY, "!", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    hidden function pill(dc, cx, cy, w, text, tcol, tentCol) {
        var h = _h * 0.10;
        dc.setColor(PANEL, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - w / 2, cy - h / 2, w, h, h / 2);
        dc.setColor(0x5A5A5A, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(cx - w / 2, cy - h / 2, w, h, h / 2);
        Tent.draw(dc, cx - w / 2 + h * 0.6, cy + 1, h * 0.62, tentCol, PANEL);
        dc.setColor(tcol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + h * 0.35, cy, Graphics.FONT_TINY, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Left: wind arrow (where it blows to), mean and gust in mph for this hour.
    hidden function drawWind(dc) {
        var d = $.gData;
        var i = d.weatherNow();
        if (i < 0 || d.weather["wind_mph"] == null) { return; }
        var bx = _w * 0.15; var by = _h / 2; var r = _w * 0.085;
        dc.setColor(PANEL, Graphics.COLOR_TRANSPARENT); dc.fillCircle(bx, by, r);
        dc.setColor(0x5A5A5A, Graphics.COLOR_TRANSPARENT); dc.drawCircle(bx, by, r);
        var to = Geo.rad(d.weather["wind_from_deg"][i] + 180.0);
        var L = r * 0.8; var ax = bx; var ay = by - r * 0.35;
        var dx = Math.sin(to); var dy = -Math.cos(to);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(ax - dx * L / 2, ay - dy * L / 2, ax + dx * L / 2, ay + dy * L / 2);
        dc.setPenWidth(1);
        var hx = ax + dx * L / 2; var hy = ay + dy * L / 2; var s = L * 0.35;
        dc.fillPolygon([[hx + dx * 2, hy + dy * 2], [hx - dx * s - dy * s * 0.6, hy - dy * s + dx * s * 0.6], [hx - dx * s + dy * s * 0.6, hy - dy * s - dx * s * 0.6]]);
        dc.drawText(bx, by + r * 0.15, Graphics.FONT_XTINY, d.weather["wind_mph"][i].toNumber().format("%d"), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
        dc.drawText(bx, by + r * 0.62, Graphics.FONT_XTINY, "G" + d.weather["gust_mph"][i].toNumber().format("%d"), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Bottom band: position, then route left + ETA, then margin before dark.
    hidden function drawBand(dc) {
        var d = $.gData;
        var fh = dc.getFontHeight(Graphics.FONT_XTINY);
        var lines = [];
        lines.add([d.lat == null ? "Waiting for GPS" : Geo.position(d.lat, d.lon, d.posFmt), Graphics.COLOR_WHITE]);
        var dusk = null;
        if (d.lat != null) {
            var s = Geo.sun(d.lat, d.lon, Geo.dayOfYear(), 96.0d);
            if (s != null) { dusk = s[1]; }
        }
        var now = Geo.nowUtcHours();
        var left = d.lat == null ? null : d.routeLeft();
        var spd = d.avgSpeed();
        if (left != null && left[0] > 30 && dusk != null) {
            var eta = null;
            if (spd != null) {
                var mins = left[0] / spd / 60.0 + left[1] / 100.0 * 10.0;   // Naismith: +10 min per 100 m climb
                eta = now + mins / 60.0;
            }
            lines.add([Geo.dist(left[0]) + " left  ·  ETA " + (eta == null ? "--:--" : Geo.hhmm(eta)), Graphics.COLOR_WHITE]);
            if (eta != null) {
                var m = (dusk - eta) * 60.0;
                var col = m >= 30 ? Tent.GREEN : (m >= 0 ? AMBER : Tent.RED);
                lines.add([Geo.duration(m) + (m >= 0 ? " before dark (" : " after dark (") + Geo.hhmm(dusk) + ")", col]);
            } else {
                lines.add(["Dark " + Geo.hhmm(dusk), AMBER]);
            }
        } else if (dusk != null) {
            var m = (dusk - now) * 60.0;
            lines.add([m > 0 ? "Dark " + Geo.hhmm(dusk) + "  ·  " + Geo.duration(m) : "Dark since " + Geo.hhmm(dusk), AMBER]);
        }
        var bh = lines.size() * fh + 6;
        var y = _h * 0.86 - bh;
        dc.setColor(PANEL, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(_w * 0.13, y, _w * 0.74, bh);
        for (var i = 0; i < lines.size(); i++) {
            dc.setColor(lines[i][1], Graphics.COLOR_TRANSPARENT);
            dc.drawText(_w / 2, y + 3 + i * fh, Graphics.FONT_XTINY, lines[i][0], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    hidden function drawScale(dc, z) {
        var lat = $.gData.lat == null ? _cLat : $.gData.lat;
        var mpp = Merc.metresPerPixel(lat, z);
        var m = z >= 14 ? 500 : (z == 13 ? 1000 : 2000);
        var L = m / mpp;
        var y = _h * 0.93;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(_w / 2 - L / 2, y - 3, L, 6);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(_w / 2 - L / 2 + 1, y - 2, L / 2 - 1, 4);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_w / 2, y - 6 - dc.getFontHeight(Graphics.FONT_XTINY) / 2, Graphics.FONT_XTINY, m >= 1000 ? (m / 1000).format("%d") + " km" : m.format("%d") + " m", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
