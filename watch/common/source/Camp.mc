import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// Finds whether a position is inside a DNPA camping area, and if not the distance and
// bearing to the nearest one. Only polygons whose bounding box could beat the best answer
// so far are loaded, so memory stays small.
class CampLocator {
    var inside = false;
    var distM = null;      // metres to nearest area (0 when inside)
    var bearing = null;    // degrees true to nearest point
    hidden var _index;
    hidden var _ids;
    hidden var _lastLat = null;
    hidden var _lastLon = null;

    function initialize() {
        _index = WatchUi.loadResource(Rez.JsonData.campIndex);
        _ids = CampData.ids();
    }

    // Recompute when moved more than minMove metres since last time.
    function update(lat, lon, minMove) {
        if (_lastLat != null) {
            var dy = (lat - _lastLat) * 111320.0;
            var dx = (lon - _lastLon) * 111320.0 * Math.cos(Geo.rad(lat));
            if (dx * dx + dy * dy < minMove * minMove) { return false; }
        }
        _lastLat = lat; _lastLon = lon;
        var px = (lon - CampData.LON0) * CampData.Q;
        var py = (lat - CampData.LAT0) * CampData.Q;
        var my = 111320.0 / CampData.Q;                 // metres per unit north
        var mx = my * Math.cos(Geo.rad(lat));           // metres per unit east

        // candidate boxes ordered by distance
        var n = _index.size();
        var bd = new [n];
        for (var i = 0; i < n; i++) {
            var b = _index[i];
            var ex = 0.0; var ey = 0.0;
            if (px < b[0]) { ex = b[0] - px; } else if (px > b[2]) { ex = px - b[2]; }
            if (py < b[1]) { ey = b[1] - py; } else if (py > b[3]) { ey = py - b[3]; }
            ex *= mx; ey *= my;
            bd[i] = Math.sqrt(ex * ex + ey * ey);
        }
        var best = 1.0e12; var bx = 0.0; var by = 0.0; var isIn = false;
        var done = new [n];
        while (true) {
            var k = -1; var kd = best;
            for (var i = 0; i < n; i++) {
                if (done[i] == null && bd[i] < kd) { k = i; kd = bd[i]; }
            }
            if (k < 0) { break; }
            done[k] = true;
            var rings = WatchUi.loadResource(_ids[k]);
            var crossings = 0;
            for (var r = 0; r < rings.size(); r++) {
                var ring = rings[r];
                var m = ring.size();
                var x1 = ring[m - 2]; var y1 = ring[m - 1];
                for (var j = 0; j < m; j += 2) {
                    var x2 = ring[j]; var y2 = ring[j + 1];
                    if ((y1 > py) != (y2 > py)) {
                        var xi = x1 + (py - y1) * (x2 - x1).toFloat() / (y2 - y1);
                        if (px < xi) { crossings++; }
                    }
                    // nearest point on segment, in metres
                    var ax = (x1 - px) * mx; var ay = (y1 - py) * my;
                    var sx = (x2 - x1) * mx; var sy = (y2 - y1) * my;
                    var l2 = sx * sx + sy * sy;
                    var t = 0.0;
                    if (l2 > 0) {
                        t = -(ax * sx + ay * sy) / l2;
                        if (t < 0) { t = 0.0; } else if (t > 1) { t = 1.0; }
                    }
                    var qx = ax + t * sx; var qy = ay + t * sy;
                    var d = Math.sqrt(qx * qx + qy * qy);
                    if (d < best) { best = d; bx = qx; by = qy; }
                    x1 = x2; y1 = y2;
                }
            }
            if (crossings % 2 == 1) { isIn = true; break; }
        }
        inside = isIn;
        distM = isIn ? 0 : best;
        bearing = isIn ? null : Geo.fmod(Geo.deg(Math.atan2(bx, by)), 360.0d);
        return true;
    }
}
