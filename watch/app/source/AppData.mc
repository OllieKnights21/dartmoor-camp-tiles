import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Everything the pages share: position, breadcrumb track, synced data and settings.
class AppData {
    var lat = null;
    var lon = null;
    var heading = null;        // radians, from GPS
    var camp;
    var posFmt = 0;

    // breadcrumb of where we've been: flat [lat, lon, lat, lon ...], one point per 15 m
    var track = [];
    var trackDist = 0.0;       // metres
    var movingSecs = 0;        // seconds with speed > 0.3 m/s
    hidden var _lastFixTime = null;

    // synced data (dictionaries as downloaded) and when each arrived
    var weather = null;
    var warnings = null;
    var firing = null;
    var routes = null;
    var lastSync = null;       // Time.Moment value seconds

    // map state
    var zoom = 14;
    var follow = true;
    var showRoute = true;
    var showTrack = true;
    var routeIdx = 0;

    // sync progress: list of [label, state] where state 0 waiting, 1 busy, 2 done, 3 failed
    var syncItems = null;
    hidden var _syncStep = -1;
    hidden var _omFallback = false;

    var tiles;

    function initialize() {
        camp = new CampLocator();
        tiles = new TileCache();
        loadSettings();
        weather = Application.Storage.getValue("weather");
        warnings = Application.Storage.getValue("warnings");
        firing = Application.Storage.getValue("firing");
        routes = Application.Storage.getValue("routes");
        lastSync = Application.Storage.getValue("lastSync");
        var t = Application.Storage.getValue("track");
        if (t != null) { track = t; }
        var r = Application.Storage.getValue("routeIdx");
        if (r != null) { routeIdx = r; }
        var z = Application.Storage.getValue("zoom");
        if (z != null) { zoom = z; }
    }

    function loadSettings() {
        var f = Application.Properties.getValue("posFormat");
        posFmt = (f == null) ? 0 : f;
    }

    function save() {
        Application.Storage.setValue("track", track);
        Application.Storage.setValue("routeIdx", routeIdx);
        Application.Storage.setValue("zoom", zoom);
    }

    function onPosition(info as Position.Info) {
        if (info.position == null || info.accuracy == null || info.accuracy < Position.QUALITY_POOR) { return; }
        var d = info.position.toDegrees();
        lat = d[0]; lon = d[1];
        if (info.heading != null && info.speed != null && info.speed > 0.5) { heading = info.heading; }
        camp.update(lat, lon, 10);
        var now = Time.now().value();
        if (info.speed != null && info.speed > 0.3 && _lastFixTime != null) {
            movingSecs += now - _lastFixTime;
        }
        _lastFixTime = now;
        var n = track.size();
        if (n == 0) {
            track.add(lat); track.add(lon);
        } else {
            var m = metres(track[n - 2], track[n - 1], lat, lon);
            if (m >= 15) {
                track.add(lat); track.add(lon);
                trackDist += m;
                if (track.size() > 3000) { thinTrack(); }
            }
        }
    }

    function clearTrack() { track = []; trackDist = 0.0; movingSecs = 0; }

    hidden function thinTrack() {
        var t = [];
        for (var i = 0; i < track.size(); i += 4) { t.add(track[i]); t.add(track[i + 1]); }
        track = t;
    }

    function metres(la1, lo1, la2, lo2) {
        var dy = (la2 - la1) * 111320.0;
        var dx = (lo2 - lo1) * 111320.0 * Math.cos(Geo.rad(la1));
        return Math.sqrt(dx * dx + dy * dy);
    }

    function avgSpeed() {
        if (movingSecs < 60 || trackDist < 50) { return null; }
        return trackDist / movingSecs;
    }

    // ---- route maths ----
    function route() {
        if (routes == null || !(routes instanceof Dictionary)) { return null; }
        var list = routes["routes"];
        if (list == null || list.size() == 0) { return null; }
        if (routeIdx >= list.size()) { routeIdx = 0; }
        return list[routeIdx];
    }

    // [metres left, metres of climb left] from the route point nearest to us, or null
    function routeLeft() {
        var r = route();
        if (r == null || lat == null) { return null; }
        var p = r["pts"]; var cd = r["cumd"]; var ca = r["cuma"];
        var best = -1; var bd = 1.0e12;
        var la = lat * 100000.0; var lo = lon * 100000.0;
        var k = Math.cos(Geo.rad(lat));
        for (var i = 0; i < p.size(); i += 2) {
            var dy = p[i] - la; var dx = (p[i + 1] - lo) * k;
            var d = dx * dx + dy * dy;
            if (d < bd) { bd = d; best = i / 2; }
        }
        if (best < 0) { return null; }
        var n = cd.size() - 1;
        return [cd[n] - cd[best], ca[n] - ca[best]];
    }

    // ---- sync ----
    function startSync() {
        syncItems = [["Weather", 0], ["Warnings", 0], ["Firing times", 0], ["Routes", 0]];
        _syncStep = -1;
        _omFallback = (lat == null);
        nextSync();
    }

    function syncing() { return _syncStep >= 0 && _syncStep < 4; }

    hidden function nextSync() {
        _syncStep++;
        if (_syncStep >= 4) {
            lastSync = Time.now().value();
            Application.Storage.setValue("lastSync", lastSync);
            WatchUi.requestUpdate();
            return;
        }
        syncItems[_syncStep][1] = 1;
        WatchUi.requestUpdate();
        var opts = { :method => Communications.HTTP_REQUEST_METHOD_GET,
                     :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON };
        var url;
        if (_syncStep == 0) {
            if (lat != null) {
                url = "https://api.open-meteo.com/v1/forecast?latitude=" + lat.format("%.3f") + "&longitude=" + lon.format("%.3f")
                    + "&hourly=precipitation_probability,precipitation,wind_speed_10m,wind_direction_10m,wind_gusts_10m"
                    + "&wind_speed_unit=mph&forecast_hours=24&timezone=Europe%2FLondon";
            } else {
                url = TileInfo.BASE + "weather.json";
            }
        } else if (_syncStep == 1) {
            url = TileInfo.BASE + "warnings.json";
        } else if (_syncStep == 2) {
            url = TileInfo.BASE + "firing.json";
        } else {
            url = TileInfo.BASE + "routes.json";
        }
        Communications.makeWebRequest(url, null, opts, method(:onSyncReply));
    }

    function onSyncReply(code as Number, data as Dictionary or String or Null) as Void {
        var ok = (code == 200 && data instanceof Dictionary);
        if (ok) {
            if (_syncStep == 0) {
                if (data["hourly"] != null) {
                    var h = data["hourly"];
                    data = { "time" => h["time"], "prob" => h["precipitation_probability"], "mm" => h["precipitation"],
                             "wind_mph" => h["wind_speed_10m"], "gust_mph" => h["wind_gusts_10m"], "wind_from_deg" => h["wind_direction_10m"],
                             "source" => "Open-Meteo" };
                }
                weather = data; Application.Storage.setValue("weather", data);
            } else if (_syncStep == 1) {
                warnings = data; Application.Storage.setValue("warnings", data);
            } else if (_syncStep == 2) {
                firing = data; Application.Storage.setValue("firing", data);
            } else {
                routes = data; Application.Storage.setValue("routes", data);
            }
        } else if (_syncStep == 0 && !_omFallback) {
            // Open-Meteo failed: try the hourly GitHub copy instead
            _omFallback = true;
            Communications.makeWebRequest(TileInfo.BASE + "weather.json", null,
                { :method => Communications.HTTP_REQUEST_METHOD_GET, :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON },
                method(:onSyncReply));
            return;
        }
        syncItems[_syncStep][1] = ok ? 2 : 3;
        nextSync();
    }

    // hour index into the weather arrays for "now", or -1
    function weatherNow() {
        if (weather == null || weather["time"] == null) { return -1; }
        var ct = System.getClockTime();
        var t = weather["time"];
        var today = todayIso();
        var key = today + "T" + ct.hour.format("%02d") + ":00";
        for (var i = 0; i < t.size(); i++) {
            if (t[i].equals(key)) { return i; }
        }
        return t.size() > 0 && t[0].substring(0, 10).equals(today) ? 0 : -1;
    }

    function todayIso() {
        var g = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return g.year.format("%04d") + "-" + g.month.format("%02d") + "-" + g.day.format("%02d");
    }

    // Live warnings that mention Devon, as a list of dictionaries.
    function devonWarnings() {
        var out = [];
        if (warnings == null || warnings["warnings"] == null) { return out; }
        var w = warnings["warnings"];
        for (var i = 0; i < w.size(); i++) {
            if (w[i]["devon"] == true) { out.add(w[i]); }
        }
        return out;
    }

    // Firing codes for a date offset from today: string like "013" or null
    function firingFor(offsetDays) {
        if (firing == null || firing["start"] == null || firing["days"] == null) { return null; }
        var s = firing["start"];
        var start = Time.Gregorian.moment({ :year => s.substring(0, 4).toNumber(), :month => s.substring(5, 7).toNumber(),
                                            :day => s.substring(8, 10).toNumber(), :hour => 12 });
        var g = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var today = Time.Gregorian.moment({ :year => g.year, :month => g.month, :day => g.day, :hour => 12 });
        var idx = (today.subtract(start).value() / 86400) * (today.greaterThan(start) ? 1 : -1) + offsetDays;
        var days = firing["days"];
        if (idx < 0 || idx >= days.size()) { return null; }
        return days[idx];
    }
}
