import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

var gMapView = null;

function pageView(i) {
    if (i == 0) {
        if ($.gMapView == null) { $.gMapView = new MapView(); }
        return $.gMapView;
    }
    if (i == 1) { return new RainView(); }
    if (i == 2) { return new WindView(); }
    return new CondView();
}

// START: next page. BACK: previous page (exits from the map). UP/DOWN: zoom on the map.
// Hold UP: menu. In pan mode UP/DOWN pan, START swaps N/S for E/W, BACK leaves pan mode.
class PageDelegate extends WatchUi.BehaviorDelegate {
    hidden var _page;
    function initialize(page) { BehaviorDelegate.initialize(); _page = page; }

    hidden function map() { return $.gMapView; }

    function onSelect() {
        if (_page == 0 && map() != null && map().panMode) {
            map().panAxisEW = !map().panAxisEW; WatchUi.requestUpdate(); return true;
        }
        var n = (_page + 1) % 4;
        WatchUi.switchToView($.pageView(n), new PageDelegate(n), WatchUi.SLIDE_LEFT);
        return true;
    }

    function onBack() {
        if (_page == 0) {
            if (map() != null && map().panMode) { map().recentre(); return true; }
            return false;   // exit app
        }
        var n = _page - 1;
        WatchUi.switchToView($.pageView(n), new PageDelegate(n), WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onPreviousPage() {   // UP
        if (_page == 0 && map() != null) {
            if (map().panMode) { map().pan(1); } else { map().zoomBy(1); }
        }
        return true;
    }

    function onNextPage() {       // DOWN
        if (_page == 0 && map() != null) {
            if (map().panMode) { map().pan(-1); } else { map().zoomBy(-1); }
        }
        return true;
    }

    function onMenu() {           // hold UP
        WatchUi.pushView(MainMenu.build(), new MainMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }
}

module MainMenu {
    function build() {
        var d = $.gData;
        var m = new WatchUi.Menu2({ :title => "Menu" });
        m.addItem(new WatchUi.MenuItem("Sync now", d.lastSync == null ? "Never synced" : "Last " + timeOf(d.lastSync), :sync, null));
        m.addItem(new WatchUi.MenuItem("Zoom", zoomName(d.zoom), :zoom, null));
        m.addItem(new WatchUi.MenuItem("Pan mode", "UP/DOWN move, START swaps", :pan, null));
        m.addItem(new WatchUi.MenuItem("Layers", null, :layers, null));
        m.addItem(new WatchUi.MenuItem("Firing times", "6 weeks", :firing, null));
        m.addItem(new WatchUi.MenuItem("Download area", "Map tiles for offline", :download, null));
        m.addItem(new WatchUi.ToggleMenuItem("Follow position", null, :follow, d.follow, null));
        m.addItem(new WatchUi.MenuItem("Position format", ["OS grid ref", "Lat/long", "Deg, min"][d.posFmt], :pos, null));
        m.addItem(new WatchUi.MenuItem("Route", routeName(), :route, null));
        m.addItem(new WatchUi.MenuItem("Clear track", (d.trackDist / 1000.0).format("%.1f") + " km recorded", :cleartrack, null));
        m.addItem(new WatchUi.MenuItem("About", null, :about, null));
        return m;
    }
    function zoomName(z) { return z == 14 ? "500 m" : (z == 13 ? "1 km" : "2 km"); }
    function timeOf(v) {
        var g = Time.Gregorian.info(new Time.Moment(v), Time.FORMAT_SHORT);
        return g.hour.format("%02d") + ":" + g.min.format("%02d");
    }
    function routeName() {
        var r = $.gData.route();
        if (r == null) { return "None synced"; }
        return r["name"];
    }
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() { Menu2InputDelegate.initialize(); }

    function onSelect(item) {
        var id = item.getId(); var d = $.gData;
        if (id == :sync) {
            d.startSync();
            WatchUi.pushView(new SyncView(), new InfoDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :zoom) {
            var z = d.zoom - 1; if (z < TileInfo.MINZ) { z = TileInfo.MAXZ; }
            if ($.gMapView != null) { $.gMapView.zoomBy(z - d.zoom); } else { d.zoom = z; }
            item.setSubLabel(MainMenu.zoomName(d.zoom));
        } else if (id == :pan) {
            if ($.gMapView != null) { $.gMapView.panMode = true; $.gMapView.panAxisEW = false; }
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :layers) {
            var m = new WatchUi.Menu2({ :title => "Layers" });
            m.addItem(new WatchUi.ToggleMenuItem("Route", null, :showRoute, d.showRoute, null));
            m.addItem(new WatchUi.ToggleMenuItem("Recorded track", null, :showTrack, d.showTrack, null));
            m.addItem(new WatchUi.MenuItem("Shelter dots", "Coming later", :shelter, null));
            WatchUi.pushView(m, new LayersDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :firing) {
            WatchUi.pushView(new FiringView(), new InfoDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :download) {
            WatchUi.pushView(new DownloadView(), new DownloadDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :follow) {
            d.follow = item.isEnabled();
            if (d.follow && $.gMapView != null) { $.gMapView.recentre(); }
        } else if (id == :pos) {
            d.posFmt = (d.posFmt + 1) % 3;
            Application.Properties.setValue("posFormat", d.posFmt);
            item.setSubLabel(["OS grid ref", "Lat/long", "Deg, min"][d.posFmt]);
        } else if (id == :route) {
            if (d.routes != null && d.routes["routes"] != null && d.routes["routes"].size() > 0) {
                d.routeIdx = (d.routeIdx + 1) % d.routes["routes"].size();
            }
            item.setSubLabel(MainMenu.routeName());
        } else if (id == :cleartrack) {
            d.clearTrack();
            item.setSubLabel("0.0 km recorded");
        } else if (id == :about) {
            WatchUi.pushView(new AboutView(), new InfoDelegate(), WatchUi.SLIDE_LEFT);
        }
        WatchUi.requestUpdate();
    }
}

class LayersDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() { Menu2InputDelegate.initialize(); }
    function onSelect(item) {
        var id = item.getId();
        if (id == :showRoute) { $.gData.showRoute = item.isEnabled(); }
        else if (id == :showTrack) { $.gData.showTrack = item.isEnabled(); }
    }
}

class InfoDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    function onBack() { WatchUi.popView(WatchUi.SLIDE_RIGHT); return true; }
}

// Sync progress: a tick per item as it lands.
class SyncView extends WatchUi.View {
    function initialize() { View.initialize(); }
    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK); dc.clear();
        var d = $.gData; var w = dc.getWidth(); var h = dc.getHeight();
        var fh = dc.getFontHeight(Graphics.FONT_TINY) + 4;
        $.centreText(dc, h * 0.08, Graphics.FONT_XTINY, "SYNC", Col.DIM);
        if (!System.getDeviceSettings().phoneConnected) {
            $.centreText(dc, h * 0.40, Graphics.FONT_TINY, "Phone not connected", Tent.RED);
            $.centreText(dc, h * 0.52, Graphics.FONT_XTINY, "Keeping the data you have", Col.DIM);
        }
        var items = d.syncItems;
        if (items == null) { return; }
        var y = h * 0.20;
        for (var i = 0; i < items.size(); i++) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w * 0.22, y, Graphics.FONT_TINY, items[i][0], Graphics.TEXT_JUSTIFY_LEFT);
            var s = items[i][1];
            var t = s == 2 ? "OK" : (s == 3 ? "failed" : (s == 1 ? "..." : ""));
            dc.setColor(s == 2 ? Tent.GREEN : (s == 3 ? Tent.RED : Col.AMBER), Graphics.COLOR_TRANSPARENT);
            dc.drawText(w * 0.80, y, Graphics.FONT_TINY, t, Graphics.TEXT_JUSTIFY_RIGHT);
            y += fh;
        }
        var p = d.tiles.pending();
        if (p > 0) { $.centreText(dc, y + 4, Graphics.FONT_XTINY, "Tiles left: " + p, Col.AMBER); }
        if (!d.syncing() && d.lastSync != null) {
            $.centreText(dc, h * 0.82, Graphics.FONT_XTINY, "Last synced " + MainMenu.timeOf(d.lastSync), Col.DIM);
        }
    }
}

// 6-week firing list, scroll with UP/DOWN.
class FiringView extends WatchUi.View {
    var first = 0;
    function initialize() { View.initialize(); }
    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK); dc.clear();
        var d = $.gData; var w = dc.getWidth(); var h = dc.getHeight();
        $.centreText(dc, h * 0.07, Graphics.FONT_XTINY, "FIRING TIMES", Col.DIM);
        if (d.firing == null || d.firing["days"] == null) { $.noData(dc, ""); return; }
        var fh = dc.getFontHeight(Graphics.FONT_XTINY) + 2;
        var cols = [w * 0.56, w * 0.66, w * 0.76];
        dc.setColor(Col.DIM, Graphics.COLOR_TRANSPARENT);
        var lab = ["O", "W", "M"];
        for (var c = 0; c < 3; c++) { dc.drawText(cols[c], h * 0.14, Graphics.FONT_XTINY, lab[c], Graphics.TEXT_JUSTIFY_CENTER); }
        var y = h * 0.14 + fh;
        var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        for (var k = first; k < first + 8; k++) {
            var codes = d.firingFor(k);
            if (codes == null) { break; }
            var m = Time.now().add(new Time.Duration(k * 86400));
            var g = Time.Gregorian.info(m, Time.FORMAT_SHORT);
            dc.setColor(k == 0 ? Graphics.COLOR_WHITE : 0xC8C8C8, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w * 0.20, y, Graphics.FONT_XTINY, names[g.day_of_week - 1] + " " + g.day, Graphics.TEXT_JUSTIFY_LEFT);
            for (var c = 0; c < 3 && c < codes.length(); c++) {
                var ch = codes.substring(c, c + 1);
                var col = ch.equals("0") ? 0x2A2A2A : (ch.equals("1") ? Col.AMBER : (ch.equals("?") ? 0x555555 : Tent.RED));
                dc.setColor(col, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(cols[c] - w * 0.04, y + 2, w * 0.08, fh - 5, 4);
            }
            y += fh;
        }
        $.centreText(dc, h * 0.86, Graphics.FONT_XTINY, "amber day · red night", Col.DIM);
    }
}

class DownloadView extends WatchUi.View {
    var km = 10;
    var queued = 0;
    function initialize() { View.initialize(); }
    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK); dc.clear();
        var d = $.gData; var h = dc.getHeight();
        $.centreText(dc, h * 0.08, Graphics.FONT_XTINY, "DOWNLOAD AREA", Col.DIM);
        $.centreText(dc, h * 0.20, Graphics.FONT_TINY, "Around my position", Graphics.COLOR_WHITE);
        $.centreText(dc, h * 0.32, Graphics.FONT_SMALL, km + " km square", Graphics.COLOR_WHITE);
        $.centreText(dc, h * 0.44, Graphics.FONT_XTINY, "UP/DOWN size · START download", Col.DIM);
        var p = d.tiles.pending();
        if (queued > 0) {
            $.centreText(dc, h * 0.56, Graphics.FONT_TINY, (queued - p) + " / " + queued + " tiles", p > 0 ? Col.AMBER : Tent.GREEN);
            if (d.tiles.failed > 0) { $.centreText(dc, h * 0.66, Graphics.FONT_XTINY, d.tiles.failed + " failed", Tent.RED); }
            if (!d.tiles.storageOk) { $.centreText(dc, h * 0.72, Graphics.FONT_XTINY, "Watch storage full", Tent.RED); }
        }
        $.centreText(dc, h * 0.80, Graphics.FONT_XTINY, "Hold UP: clear cached tiles", Tent.RED);
    }
}

class DownloadDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    hidden function view() { return WatchUi.getCurrentView()[0]; }
    function onPreviousPage() { var v = view(); if (v.km < 20) { v.km += 5; } WatchUi.requestUpdate(); return true; }
    function onNextPage() { var v = view(); if (v.km > 5) { v.km -= 5; } WatchUi.requestUpdate(); return true; }
    function onSelect() {
        var d = $.gData; var v = view();
        var lat = d.lat == null ? 50.58 : d.lat; var lon = d.lon == null ? -3.93 : d.lon;
        d.tiles.listener = method(:onTile);
        v.queued = d.tiles.queueArea(lat, lon, v.km, 14) + d.tiles.queueArea(lat, lon, v.km * 2, 13);
        WatchUi.requestUpdate();
        return true;
    }
    function onTile() as Void { WatchUi.requestUpdate(); }
    function onMenu() { $.gData.tiles.clearAll(); view().queued = 0; WatchUi.requestUpdate(); return true; }
    function onBack() { WatchUi.popView(WatchUi.SLIDE_RIGHT); return true; }
}

class AboutView extends WatchUi.View {
    function initialize() { View.initialize(); }
    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK); dc.clear();
        var h = dc.getHeight(); var w = dc.getWidth();
        Tent.draw(dc, w / 2, h * 0.17, h * 0.12, Tent.GREEN, Graphics.COLOR_BLACK);
        $.centreText(dc, h * 0.26, Graphics.FONT_TINY, "Dartmoor Map 0.1", Graphics.COLOR_WHITE);
        var lines = ["Camping layer 22 Mar 2024", "Tiles built 17 Nov 2026", "", "© OpenStreetMap contributors", "DNPA · Met Office · MOD", "(OGL v3)", "Open-Meteo (CC BY 4.0)"];
        var fh = dc.getFontHeight(Graphics.FONT_XTINY);
        for (var i = 0; i < lines.size(); i++) {
            $.centreText(dc, h * 0.38 + i * fh, Graphics.FONT_XTINY, lines[i], i < 2 ? Graphics.COLOR_WHITE : Col.DIM);
        }
    }
}
