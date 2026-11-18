import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.System;

// Shared maths: OS grid refs, lat/long text, sun times, compass words.
module Geo {

    function rad(d) { return d * Math.PI / 180.0d; }
    function deg(r) { return r * 180.0d / Math.PI; }

    // WGS84 lat/lon (degrees) -> OS grid ref "SX 5634 8725" (Helmert, about 5 m accuracy).
    function osGrid(lat, lon, digits) {
        var a = 6378137.0d; var b = 6356752.3141d; var e2 = 1.0d - (b * b) / (a * a);
        var p = rad(lat.toDouble()); var l = rad(lon.toDouble());
        var sp = Math.sin(p);
        var nu = a / Math.sqrt(1.0d - e2 * sp * sp);
        var x = nu * Math.cos(p) * Math.cos(l);
        var y = nu * Math.cos(p) * Math.sin(l);
        var z = (1.0d - e2) * nu * sp;
        var tx = -446.448d; var ty = 125.157d; var tz = -542.060d; var s = 20.4894e-6;
        var rx = rad(-0.1502d / 3600.0d); var ry = rad(-0.2470d / 3600.0d); var rz = rad(-0.8421d / 3600.0d);
        var x2 = tx + (1 + s) * x - rz * y + ry * z;
        var y2 = ty + rz * x + (1 + s) * y - rx * z;
        var z2 = tz - ry * x + rx * y + (1 + s) * z;
        a = 6377563.396d; b = 6356256.909d; e2 = 1.0d - (b * b) / (a * a);
        var pp = Math.sqrt(x2 * x2 + y2 * y2);
        p = Math.atan2(z2, pp * (1.0d - e2));
        for (var i = 0; i < 10; i++) {
            sp = Math.sin(p);
            nu = a / Math.sqrt(1.0d - e2 * sp * sp);
            p = Math.atan2(z2 + e2 * nu * sp, pp);
        }
        l = Math.atan2(y2, x2);
        var F0 = 0.9996012717d; var p0 = rad(49.0d); var l0 = rad(-2.0d); var N0 = -100000.0d; var E0 = 400000.0d;
        var n = (a - b) / (a + b);
        sp = Math.sin(p);
        nu = a * F0 / Math.sqrt(1.0d - e2 * sp * sp);
        var rho = a * F0 * (1.0d - e2) / Math.pow(1.0d - e2 * sp * sp, 1.5d);
        var eta2 = nu / rho - 1.0d;
        var n2 = n * n; var n3 = n2 * n;
        var M = b * F0 * ((1 + n + 1.25d * n2 + 1.25d * n3) * (p - p0)
            - (3 * n + 3 * n2 + 21.0d / 8 * n3) * Math.sin(p - p0) * Math.cos(p + p0)
            + (15.0d / 8 * n2 + 15.0d / 8 * n3) * Math.sin(2 * (p - p0)) * Math.cos(2 * (p + p0))
            - 35.0d / 24 * n3 * Math.sin(3 * (p - p0)) * Math.cos(3 * (p + p0)));
        var c = Math.cos(p); var t = Math.tan(p); var t2 = t * t;
        var I = M + N0;
        var II = nu / 2 * sp * c;
        var III = nu / 24 * sp * c * c * c * (5 - t2 + 9 * eta2);
        var IIIA = nu / 720 * sp * Math.pow(c, 5) * (61 - 58 * t2 + t2 * t2);
        var IV = nu * c;
        var V = nu / 6 * c * c * c * (nu / rho - t2);
        var VI = nu / 120 * Math.pow(c, 5) * (5 - 18 * t2 + t2 * t2 + 14 * eta2 - 58 * t2 * eta2);
        var dl = l - l0; var dl2 = dl * dl;
        var N = I + II * dl2 + III * dl2 * dl2 + IIIA * dl2 * dl2 * dl2;
        var E = E0 + IV * dl + V * dl2 * dl + VI * dl2 * dl2 * dl;
        if (E < 0 || N < 0 || E >= 700000 || N >= 1300000) { return "Outside GB"; }
        var e100k = (E / 100000).toNumber(); var n100k = (N / 100000).toNumber();
        var l1 = (19 - n100k) - (19 - n100k) % 5 + (e100k + 10) / 5;
        var l2 = (19 - n100k) * 5 % 25 + e100k % 5;
        if (l1 > 7) { l1 += 1; }
        if (l2 > 7) { l2 += 1; }
        var letters = (l1 + 65).toChar().toString() + (l2 + 65).toChar().toString();
        var k = digits / 2;
        var div = Math.pow(10, 5 - k).toNumber();
        var fmt = "%0" + k + "d";
        var ee = (E.toNumber() % 100000) / div;
        var nn = (N.toNumber() % 100000) / div;
        return letters + " " + ee.format(fmt) + " " + nn.format(fmt);
    }

    // fmt: 0 = OS grid, 1 = decimal degrees, 2 = degrees and decimal minutes
    function position(lat, lon, fmt) {
        if (fmt == 1) {
            return lat.format("%.5f") + ", " + lon.format("%.5f");
        } else if (fmt == 2) {
            return dm(lat, "N", "S") + " " + dm(lon, "E", "W");
        }
        return osGrid(lat, lon, 8);
    }

    function dm(v, pos, neg) {
        var h = v < 0 ? neg : pos;
        var a = v.abs();
        var d = a.toNumber();
        var m = (a - d) * 60.0;
        return d.format("%d") + "°" + m.format("%06.3f") + "'" + h;
    }

    // NOAA sunrise / sunset in UTC hours for a date. zen 90.833 = sunset, 96 = civil dusk.
    // Returns [rise, set] or null when the sun doesn't cross that zenith.
    function sun(lat, lon, dayOfYear, zen) {
        var out = [];
        for (var k = 0; k < 2; k++) {
            var rising = (k == 0);
            var lh = lon / 15.0d;
            var t = dayOfYear + ((rising ? 6 : 18) - lh) / 24.0d;
            var M = 0.9856d * t - 3.289d;
            var L = M + 1.916d * Math.sin(rad(M)) + 0.020d * Math.sin(rad(2 * M)) + 282.634d;
            L = fmod(L, 360.0d);
            var RA = fmod(deg(Math.atan(0.91764d * Math.tan(rad(L)))), 360.0d);
            RA += Math.floor(L / 90.0d) * 90.0d - Math.floor(RA / 90.0d) * 90.0d;
            RA /= 15.0d;
            var sd = 0.39782d * Math.sin(rad(L));
            var cd = Math.cos(Math.asin(sd));
            var cH = (Math.cos(rad(zen)) - sd * Math.sin(rad(lat))) / (cd * Math.cos(rad(lat)));
            if (cH > 1 || cH < -1) { return null; }
            var H = rising ? (360.0d - deg(Math.acos(cH))) : deg(Math.acos(cH));
            H /= 15.0d;
            var T = H + RA - 0.06571d * t - 6.622d;
            out.add(fmod(T - lh, 24.0d));
        }
        return out;
    }

    function fmod(a, m) {
        var r = a - Math.floor(a / m) * m;
        return r;
    }

    // Day of year (1..366) for today in UTC.
    function dayOfYear() {
        var now = Time.now();
        var g = Gregorian.utcInfo(now, Time.FORMAT_SHORT);
        var jan1 = Gregorian.moment({ :year => g.year, :month => 1, :day => 1, :hour => 0 });
        return (now.subtract(jan1).value() / 86400) + 1;
    }

    // Local time "17:04" from UTC hours.
    function hhmm(utcHours) {
        var off = System.getClockTime().timeZoneOffset / 3600.0d;
        var h = fmod(utcHours + off, 24.0d);
        var mins = Math.round(h * 60).toNumber() % 1440;
        return (mins / 60).format("%02d") + ":" + (mins % 60).format("%02d");
    }

    // Hours since UTC midnight now.
    function nowUtcHours() {
        var g = Gregorian.utcInfo(Time.now(), Time.FORMAT_SHORT);
        return g.hour + g.min / 60.0d + g.sec / 3600.0d;
    }

    function duration(mins) {
        var m = mins.abs().toNumber();
        if (m < 60) { return m.format("%d") + " min"; }
        return (m / 60).format("%d") + "h " + (m % 60).format("%02d") + "m";
    }

    const COMPASS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
    function compass(bearingDeg) {
        var i = ((fmod(bearingDeg + 22.5d, 360.0d)) / 45.0d).toNumber() % 8;
        return COMPASS[i];
    }

    // Distance text in the watch's own units.
    function dist(m) {
        var metric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
        if (metric) {
            if (m < 1000) { return (Math.round(m / 10.0) * 10).toNumber().format("%d") + " m"; }
            return (m / 1000.0).format(m < 10000 ? "%.1f" : "%.0f") + " km";
        }
        var mi = m / 1609.344;
        if (mi < 0.2) { return (m * 1.0936).toNumber().format("%d") + " yd"; }
        return mi.format("%.1f") + " mi";
    }

    function pace(mps) {
        if (mps == null || mps < 0.1) { return "--"; }
        var metric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
        var secs = (metric ? 1000.0 : 1609.344) / mps;
        var s = secs.toNumber();
        return (s / 60).format("%d") + ":" + (s % 60).format("%02d") + (metric ? " /km" : " /mi");
    }
}
