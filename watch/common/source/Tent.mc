import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

module Tent {
    const GREEN = 0x34C759;
    const RED = 0xEB4034;
    // Tent symbol centred on (cx, cy), s = overall height.
    function draw(dc, cx, cy, s, colour, bg) {
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pt(cx, cy - s * 0.55), pt(cx + s * 0.62, cy + s * 0.42), pt(cx - s * 0.62, cy + s * 0.42)]);
        dc.setColor(bg, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pt(cx, cy - s * 0.10), pt(cx + s * 0.20, cy + s * 0.42), pt(cx - s * 0.20, cy + s * 0.42)]);
    }
    function pt(x, y) {
        return [Math.round(x).toNumber(), Math.round(y).toNumber()];
    }
}
