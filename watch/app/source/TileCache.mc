import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// Picture tiles from GitHub Pages, fetched through the phone and kept in app storage.
// Missing tiles are queued and fetched one at a time.
class TileCache {
    hidden var _queue = [];
    hidden var _busy = null;
    hidden var _mem = {};          // fallback in-memory cache if storage refuses bitmaps
    hidden var _memKeys = [];
    var storageOk = true;
    var fetched = 0;
    var failed = 0;
    var listener = null;           // method(:onTile) to call when a tile lands

    function key(z, x, y) { return "t" + z + "/" + x + "/" + y; }

    // Returns a bitmap, :none (tile doesn't exist, e.g. outside the park) or null (not here yet).
    function get(z, x, y) {
        var k = key(z, x, y);
        var v = _mem[k];
        if (v != null) { return v; }
        v = Application.Storage.getValue(k);
        if (v != null) {
            if (v instanceof Number) { return :none; }
            return v;
        }
        return null;
    }

    function request(z, x, y) {
        var k = key(z, x, y);
        if (_busy != null && _busy.equals(k)) { return; }
        for (var i = 0; i < _queue.size(); i++) { if (_queue[i][0].equals(k)) { return; } }
        _queue.add([k, z, x, y]);
        if (_busy == null) { next(); }
    }

    function pending() { return _queue.size() + (_busy == null ? 0 : 1); }

    function clearQueue() { _queue = []; }

    hidden function next() {
        if (_queue.size() == 0) { _busy = null; return; }
        var q = _queue[0];
        _queue = _queue.slice(1, null);
        _busy = q[0];
        var url = TileInfo.BASE + "tiles/" + q[1] + "/" + q[2] + "/" + q[3] + ".png";
        Communications.makeImageRequest(url, null,
            { :palette => TileInfo.PALETTE, :dithering => Communications.IMAGE_DITHERING_NONE },
            method(:onImage));
    }

    function onImage(code as Number, data as WatchUi.BitmapResource or Graphics.BitmapReference or Null) as Void {
        var k = _busy;
        if (code == 200 && data != null) {
            fetched++;
            var stored = false;
            if (storageOk) {
                try {
                    Application.Storage.setValue(k, data);
                    stored = true;
                } catch (e) {
                    storageOk = false;
                }
            }
            if (!stored) {
                _mem[k] = data; _memKeys.add(k);
                if (_memKeys.size() > 6) { _mem.remove(_memKeys[0]); _memKeys = _memKeys.slice(1, null); }
            }
        } else if (code == 404) {
            Application.Storage.setValue(k, 0);   // remember that this tile doesn't exist
        } else {
            failed++;
        }
        _busy = null;
        if (listener != null) { listener.invoke(); }
        next();
    }

    // Tiles needed to cover a square of side km around lat/lon at zoom z.
    function queueArea(lat, lon, km, z) {
        var c = Merc.toPixel(lat, lon, z);
        var mpp = Merc.metresPerPixel(lat, z);
        var half = km * 500.0 / mpp;
        var x0 = ((c[0] - half) / 256).toNumber(); var x1 = ((c[0] + half) / 256).toNumber();
        var y0 = ((c[1] - half) / 256).toNumber(); var y1 = ((c[1] + half) / 256).toNumber();
        var n = 0;
        for (var x = x0; x <= x1; x++) {
            for (var y = y0; y <= y1; y++) {
                if (get(z, x, y) == null) { request(z, x, y); n++; }
            }
        }
        return n;
    }

    // Delete every cached tile (keeps weather, routes and settings).
    function clearAll() {
        _mem = {}; _memKeys = []; _queue = [];
        for (var z = TileInfo.MINZ; z <= TileInfo.MAXZ; z++) {
            var a = Merc.toPixel(TileInfo.BOUNDS[3], TileInfo.BOUNDS[0], z);
            var b = Merc.toPixel(TileInfo.BOUNDS[1], TileInfo.BOUNDS[2], z);
            for (var x = (a[0] / 256).toNumber(); x <= (b[0] / 256).toNumber(); x++) {
                for (var y = (a[1] / 256).toNumber(); y <= (b[1] / 256).toNumber(); y++) {
                    Application.Storage.deleteValue(key(z, x, y));
                }
            }
        }
    }
}

// Web mercator helpers (256 px tiles).
module Merc {
    function toPixel(lat, lon, z) {
        var n = 256.0d * (1 << z);
        var r = Geo.rad(lat.toDouble());
        var x = (lon + 180.0d) / 360.0d * n;
        var y = (1.0d - Math.ln(Math.tan(r) + 1.0d / Math.cos(r)) / Math.PI) / 2.0d * n;
        return [x, y];
    }
    function metresPerPixel(lat, z) {
        return 156543.03d * Math.cos(Geo.rad(lat)) / (1 << z);
    }
}
