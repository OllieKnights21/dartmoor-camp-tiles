"""Render dark picture tiles of Dartmoor for the Connect IQ map app.

Inputs (in DATA dir): Overture parquet extracts (water, land, land_use, segment,
infrastructure), dem.npy + dem_origin.txt (terrarium z13 mosaic), and the DNPA
camping GeoJSON. Output: tiles/{z}/{x}/{y}.png (256 px, fixed 64-colour palette).

Usage: python make_tiles.py DATA_DIR CAMP_GEOJSON OUT_DIR [zooms...]
"""
import json, math, os, sys
import numpy as np
import pyarrow.parquet as pq
import shapely.wkb as wkb
from shapely.geometry import box, shape, Point
from shapely.ops import unary_union
from shapely.strtree import STRtree
from scipy.ndimage import gaussian_filter
from skimage import measure
from PIL import Image, ImageDraw, ImageFont

DATA, CAMPF, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
ZOOMS = [int(z) for z in sys.argv[4:]] or [12, 13, 14]
FONT = "/usr/share/fonts/opentype/inter/Inter-%s.otf"
SS = 2            # supersample factor
TS = 256          # tile size
META = 4          # metatile = META x META tiles
BUF = 48          # buffer px (at 1x) around a metatile

# ---------------- palette (dark, AMOLED) ----------------
C = dict(bg=(10, 10, 9), agri=(18, 24, 15), resid=(34, 32, 30), rock=(38, 38, 38),
         forest=(26, 58, 28), forest_e=(60, 110, 60), water=(18, 46, 86), water_l=(80, 160, 255),
         contour=(105, 78, 50), contour_i=(165, 118, 70), path=(255, 110, 80), track=(205, 150, 90),
         road_c=(80, 80, 80), road=(190, 190, 190), road_y=(225, 175, 80), wall=(78, 76, 70),
         range=(255, 70, 60), camp=(60, 220, 110), peak=(235, 225, 210), marsh=(80, 150, 240),
         woodtext=(120, 200, 120), white=(255, 255, 255))
CAMP_A = 34 / 255
C["campfill"] = tuple(int(C["bg"][i] * (1 - CAMP_A) + C["camp"][i] * CAMP_A) for i in range(3))
SHADE_LEVELS = 6
HS_LIGHT = 0.55 * 0.35


def build_palette():
    cols = []
    for k in ("bg", "campfill", "agri", "forest", "water", "rock", "resid"):
        base = np.array(C[k], float)
        top = 255 * HS_LIGHT * (1 - math.sin(math.radians(45))) * 0.6  # brightest hillshade lift
        for i in range(SHADE_LEVELS):
            cols.append(tuple(np.clip(base + top * i / (SHADE_LEVELS - 1), 0, 255).astype(int)))
    for k in ("contour", "contour_i", "path", "track", "water_l", "road", "road_c", "road_y", "wall",
              "range", "camp", "peak", "marsh", "woodtext", "forest_e", "white"):
        cols.append(C[k])
    # half-tones so anti-aliased lines/text stay smooth on the dark ground
    for k in ("peak", "path", "water_l", "contour_i", "camp", "track"):
        cols.append(tuple(int(C[k][i] * 0.5 + C["bg"][i] * 0.5) for i in range(3)))
    cols = list(dict.fromkeys(cols))[:64]
    while len(cols) < 64:
        cols.append(cols[-1])
    pal = Image.new("P", (1, 1))
    pal.putpalette([v for c in cols for v in c] + [0] * (768 - 3 * len(cols)))
    return pal, cols


PAL, PAL_COLS = build_palette()


def font(w, s):
    return ImageFont.truetype(FONT % w, int(s))


# ---------------- projection ----------------
def merc(lon, lat, z):
    r = math.radians(lat)
    n = 2 ** z * TS
    return (lon + 180) / 360 * n, (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n


def unmerc(x, y, z):
    n = 2 ** z * TS
    return x / n * 360 - 180, math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n))))


# ---------------- data ----------------
def load(name):
    out = []
    for r in pq.read_table(os.path.join(DATA, name + ".parquet")).to_pylist():
        r["geom"] = wkb.loads(r["geometry"])
        r["name"] = (r.get("names") or {}).get("primary") if r.get("names") else None
        del r["geometry"]
        out.append(r)
    return out


water, land, lu, seg, inf = (load(n) for n in ("water", "land", "land_use", "segment", "infrastructure"))
park = [r["geom"] for r in lu if r["class"] == "national_park" and r["name"] == "Dartmoor National Park"][0]
CAMP = unary_union([shape(f["geometry"]) for f in json.load(open(CAMPF))["features"]])
ranges = [r for r in lu if r["subtype"] == "military" and r["class"] in ("training_area", "range")]
dem = np.load(os.path.join(DATA, "dem.npy"))
DZ, DX0, DY0 = map(int, open(os.path.join(DATA, "dem_origin.txt")).read().split())


def layer(rows):
    rows = [r for r in rows if not r["geom"].is_empty]
    return rows, STRtree([r["geom"] for r in rows])


L = {k: layer(v) for k, v in dict(water=water, land=land, lu=lu, seg=seg,
                                   inf=[r for r in inf if r["class"] in ("wall",)], ranges=ranges).items()}


def query(k, bb):
    rows, tree = L[k]
    return [rows[i] for i in tree.query(bb)]


def polys(g):
    if g.geom_type == "Polygon":
        return [g]
    if g.geom_type in ("MultiPolygon", "GeometryCollection"):
        return [p for p in g.geoms if p.geom_type == "Polygon"]
    return []


def lines(g):
    t = g.geom_type
    if t in ("LineString", "LinearRing"):
        return [g]
    if hasattr(g, "geoms"):
        return [x for x in g.geoms if x.geom_type in ("LineString", "LinearRing")]
    return []


# ---------------- zoom styles ----------------
STYLE = {
    12: dict(contours=(50, 100), walls=False, paths=True, minor_water=False, fs=11, peaks=True, woods=False, rivers=True),
    13: dict(contours=(20, 100), walls=False, paths=True, minor_water=True, fs=12, peaks=True, woods=True, rivers=True),
    14: dict(contours=(10, 50), walls=True, paths=True, minor_water=True, fs=13, peaks=True, woods=True, rivers=True),
}


# ---------------- global label placement (consistent across tiles) ----------------
def place_labels(z, st):
    placed, labels = [], []
    fs = st["fs"] * SS

    def free(r):
        return not any(not (r[2] < q[0] or r[0] > q[2] or r[3] < q[1] or r[1] > q[3]) for q in placed)

    if st["peaks"]:
        f = font("SemiBoldItalic", fs)
        pk = [r for r in land if r["class"] == "peak" and r["name"] and r["geom"].geom_type == "Point"
              and park.buffer(0.02).contains(r["geom"])]

        def elev(r):
            x, y = merc(r["geom"].x, r["geom"].y, DZ)
            yi, xi = int(y - DY0 * 256), int(x - DX0 * 256)
            return dem[yi, xi] if 0 <= yi < dem.shape[0] and 0 <= xi < dem.shape[1] else 0
        pk.sort(key=elev, reverse=True)
        tmp = Image.new("L", (1, 1)); d = ImageDraw.Draw(tmp)
        for r in pk:
            x, y = merc(r["geom"].x, r["geom"].y, z); x *= SS; y *= SS
            tw = d.textlength(r["name"], font=f)
            sym = (x - 7 * SS, y - 7 * SS, x + 7 * SS, y + 7 * SS)
            for tx in (x + 9 * SS, x - 9 * SS - tw):
                rect = (tx, y - 9 * SS, tx + tw, y - 9 * SS + fs * 1.2)
                if free(rect) and free(sym):
                    placed += [rect, sym]
                    labels.append(("peak", x, y, tx, y - 9 * SS, r["name"]))
                    break
            else:
                if z >= 14 and free(sym):  # still show the tor symbol
                    placed.append(sym); labels.append(("peak", x, y, None, None, None))
    if st["woods"]:
        f = font("MediumItalic", fs - SS)
        tmp = Image.new("L", (1, 1)); d = ImageDraw.Draw(tmp)
        for r in land:
            if r["subtype"] == "forest" and r["name"] and r["geom"].area > (2e-6 if z >= 14 else 1e-5):
                c = r["geom"].representative_point(); x, y = merc(c.x, c.y, z); x *= SS; y *= SS
                t = r["name"].replace(" (Nature Reserve)", "")
                tw = d.textlength(t, font=f); rect = (x - tw / 2, y, x + tw / 2, y + fs * 1.2)
                if free(rect):
                    placed.append(rect); labels.append(("wood", x, y, x - tw / 2, y, t))
    if st["rivers"]:
        f = font("MediumItalic", fs - SS)
        tmp = Image.new("L", (1, 1)); d = ImageDraw.Draw(tmp)
        for r in water:
            if r["class"] == "river" and r["name"] and r["geom"].geom_type == "LineString" and r["geom"].length > 0.01:
                for frac in (0.25, 0.75) if r["geom"].length > 0.05 else (0.5,):
                    m = r["geom"].interpolate(frac, normalized=True); x, y = merc(m.x, m.y, z); x *= SS; y *= SS
                    tw = d.textlength(r["name"], font=f); rect = (x + 6 * SS, y + 4 * SS, x + 6 * SS + tw, y + 4 * SS + fs * 1.2)
                    if free(rect):
                        placed.append(rect); labels.append(("river", x, y, x + 6 * SS, y + 4 * SS, r["name"]))
    return labels


# ---------------- metatile renderer ----------------
def render_meta(z, mx, my, st, labels, smooth_dem):
    W = (META * TS + 2 * BUF) * SS
    ox, oy = (mx * META * TS - BUF) * SS, (my * META * TS - BUF) * SS  # global SS px of top-left
    lonA, latA = unmerc(ox / SS, oy / SS, z); lonB, latB = unmerc((ox + W) / SS, (oy + W) / SS, z)
    view = box(lonA, latB, lonB, latA)

    def P(lon, lat):
        x, y = merc(lon, lat, z); return x * SS - ox, y * SS - oy

    def PL(g):
        return [P(*c[:2]) for c in g.coords]

    im = Image.new("RGB", (W, W), C["bg"]); d = ImageDraw.Draw(im)

    def fill(g, col, outline=None, w=0):
        for p in polys(g):
            if not p.intersects(view): continue
            d.polygon(PL(p.exterior), fill=col)
            for h in p.interiors: d.polygon(PL(h), fill=C["bg"])
            if outline: d.line(PL(p.exterior), fill=outline, width=w)

    def line(g, col, w, dash=None):
        for l in lines(g):
            if not l.intersects(view): continue
            pts = PL(l)
            if len(pts) < 2: continue
            if not dash:
                d.line(pts, fill=col, width=max(1, int(w)), joint="curve"); continue
            on, off = dash; acc = 0; draw = True
            for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
                Ln = math.hypot(x1 - x0, y1 - y0); t = 0
                while t < Ln:
                    step = min((on if draw else off) - acc, Ln - t)
                    if draw:
                        d.line([(x0 + (x1 - x0) * t / Ln, y0 + (y1 - y0) * t / Ln),
                                (x0 + (x1 - x0) * (t + step) / Ln, y0 + (y1 - y0) * (t + step) / Ln)], fill=col, width=max(1, int(w)))
                    t += step; acc += step
                    if acc >= (on if draw else off) - 1e-6: acc = 0; draw = not draw

    # land use / cover
    for r in query("lu", view):
        if r["subtype"] == "agriculture" or r["class"] in ("grass", "meadow"): fill(r["geom"], C["agri"])
        elif r["subtype"] == "residential": fill(r["geom"], C["resid"])
    for r in query("land", view):
        if r["subtype"] == "rock" and r["class"] in ("bare_rock", "scree"): fill(r["geom"], C["rock"])
    # camping areas
    for p in polys(CAMP.intersection(view.buffer(0.01))): fill(p, C["campfill"])
    # hillshade (light only, keeps the ground black)
    s = 2 ** (z - DZ) * SS
    dx0, dy0 = ox / s - DX0 * 256, oy / s - DY0 * 256
    i0, j0 = int(dy0) - 2, int(dx0) - 2
    sub = dem[max(i0, 0):int(dy0 + W / s) + 3, max(j0, 0):int(dx0 + W / s) + 3]
    if sub.size and i0 >= 0 and j0 >= 0:
        gy, gx = np.gradient(gaussian_filter(sub, 1.0))
        res = 156543.03 * math.cos(math.radians((latA + latB) / 2)) / 2 ** DZ
        slope = np.arctan(np.hypot(gx, gy) / res * 1.6); asp = np.arctan2(-gx, gy)
        az, alt = math.radians(315), math.radians(45)
        hs = np.clip(np.sin(alt) * np.cos(slope) + np.cos(alt) * np.sin(slope) * np.cos(az - asp - math.pi / 2), 0, 1)
        hsimg = Image.fromarray((hs * 255).astype(np.uint8)).resize((int(sub.shape[1] * s), int(sub.shape[0] * s)), Image.BILINEAR)
        offx, offy = int((dx0 - j0) * s), int((dy0 - i0) * s)
        a = np.asarray(hsimg.crop((offx, offy, offx + W, offy + W))).astype(np.float32) / 255
        light = np.clip((a - math.sin(alt)) * 0.6, 0, 1)
        base = np.asarray(im).astype(np.float32) + 255 * light[..., None] * HS_LIGHT
        im = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8)); d = ImageDraw.Draw(im)
    # woods + marsh
    for r in query("land", view):
        if r["subtype"] == "forest": fill(r["geom"], C["forest"], C["forest_e"], SS)
    for r in query("land", view):
        if r["subtype"] == "wetland":
            for p in polys(r["geom"]):
                if not p.intersects(view): continue
                mask = Image.new("L", (W, W), 0); ImageDraw.Draw(mask).polygon(PL(p.exterior), fill=255)
                pat = Image.new("RGB", (W, W), C["bg"]); pd = ImageDraw.Draw(pat)
                g = 14 * SS
                gx0 = int(-ox) % g; gy0 = int(-oy) % g  # global grid so patterns line up across tiles
                for yy in range(gy0, W, g):
                    row = ((yy + oy) // g) % 2
                    for xx in range(gx0 + row * g // 2, W, g):
                        pd.line([(xx, yy), (xx + 7 * SS, yy)], fill=C["marsh"], width=SS)
                        pd.line([(xx + 3.5 * SS, yy), (xx + 3.5 * SS, yy - 3 * SS)], fill=C["marsh"], width=SS)
                pm = Image.eval(pat.convert("L"), lambda v: 255 if v > 30 else 0)
                from PIL import ImageChops
                im.paste(pat, (0, 0), ImageChops.multiply(mask, pm)); d = ImageDraw.Draw(im)
    # contours (global smoothed DEM => seamless)
    minor, major = st["contours"]
    sub = smooth_dem[max(i0, 0):int(dy0 + W / s) + 3, max(j0, 0):int(dx0 + W / s) + 3]
    clabels = []
    if sub.size and i0 >= 0 and j0 >= 0:
        for lev in np.arange(math.ceil(sub.min() / minor) * minor, sub.max(), minor):
            idx = lev % major == 0
            for cnt in measure.find_contours(sub, lev):
                if len(cnt) < 6: continue
                pts = [((c[1] + j0 - dx0) * s, (c[0] + i0 - dy0) * s) for c in cnt]
                d.line(pts, fill=C["contour_i"] if idx else C["contour"], width=int((1.6 if idx else 0.8) * SS), joint="curve")
                if idx and len(pts) > 60: clabels.append((lev, pts))
    # water
    for r in query("water", view):
        g = r["geom"]
        if g.geom_type in ("Polygon", "MultiPolygon") and r["class"] != "ocean": fill(g, C["water"], C["water_l"], SS)
    for r in query("water", view):
        g = r["geom"]
        if g.geom_type in ("LineString", "MultiLineString"):
            if r["class"] in ("drain", "ditch") and not st["minor_water"]: continue
            if r["class"] == "stream" and z <= 12: continue
            line(g, C["water_l"], {"river": 3.2, "stream": 1.5}.get(r["class"], 1.0) * SS)
    if st["walls"]:
        for r in query("inf", view): line(r["geom"], C["wall"], 0.7 * SS)
    # firing ranges and camping edge
    for r in query("ranges", view):
        for p in polys(r["geom"]): line(p.exterior, C["range"], 2 * SS, (9 * SS, 6 * SS))
    for p in polys(CAMP.intersection(view.buffer(0.01))):
        line(p.exterior, C["camp"], 2.4 * SS)
        for h in p.interiors: line(h, C["camp"], 2.4 * SS)
    # roads and paths
    order = {"path": 1, "footway": 1, "bridleway": 1, "track": 2, "unclassified": 3, "service": 3, "residential": 3,
             "tertiary": 4, "secondary": 5, "primary": 6, "trunk": 7}
    rs = sorted([r for r in query("seg", view) if r["subtype"] == "road"], key=lambda r: order.get(r["class"], 0))
    for r in rs:
        c = r["class"]
        if c in ("path", "footway", "bridleway", "cycleway", "steps"): line(r["geom"], C["path"], 1.6 * SS, (6 * SS, 4 * SS))
        elif c == "track": line(r["geom"], C["track"], 2.0 * SS, (10 * SS, 4 * SS))
    big = ("unclassified", "residential", "tertiary", "secondary", "primary", "trunk")
    if z <= 12:  # overview: minor roads as thin grey lines only
        for r in rs:
            if r["class"] in ("unclassified", "residential"): line(r["geom"], C["road_c"], 1.4 * SS)
        big = ("tertiary", "secondary", "primary", "trunk")
    rw = {"secondary": 6.5, "primary": 7, "trunk": 7.5, "tertiary": 5.5}
    for r in rs:
        if r["class"] in big or (r["class"] == "service" and z >= 14): line(r["geom"], C["road_c"], (rw.get(r["class"], 4.2) + 1.6) * SS * (0.7 if z <= 12 else 1))
    for r in rs:
        c = r["class"]
        if c in big or (c == "service" and z >= 14):
            line(r["geom"], C["road_y"] if c in ("secondary", "primary", "trunk", "tertiary") else C["road"], rw.get(c, 4.2) * SS * (0.7 if z <= 12 else 1))
    # contour labels (local, kept away from metatile edges)
    used = []; f = font("Medium", 10 * SS)
    for lev, pts in clabels:
        x, y = pts[len(pts) // 2]
        if not (BUF * SS + 30 * SS < x < W - BUF * SS - 30 * SS and BUF * SS + 12 * SS < y < W - BUF * SS - 12 * SS): continue
        if any(math.hypot(x - a, y - b) < 160 * SS for a, b in used): continue
        used.append((x, y)); t = str(int(lev)); tw = d.textlength(t, font=f)
        d.text((x - tw / 2, y - 7 * SS), t, font=f, fill=C["contour_i"], stroke_width=2 * SS, stroke_fill=C["bg"])
    # global labels
    fs = st["fs"] * SS
    fp, fw = font("SemiBoldItalic", fs), font("MediumItalic", fs - SS)
    for kind, x, y, tx, ty, t in labels:
        x -= ox; y -= oy
        if not (-300 * SS < x < W + 300 * SS and -60 * SS < y < W + 60 * SS): continue
        if kind == "peak":
            ts = 6 * SS
            d.polygon([(x, y - ts), (x + ts * 0.9, y + ts * 0.6), (x - ts * 0.9, y + ts * 0.6)], fill=C["peak"], outline=C["bg"])
            if t: d.text((tx - ox, ty - oy), t, font=fp, fill=C["peak"], stroke_width=int(2.5 * SS), stroke_fill=C["bg"])
        elif kind == "wood":
            d.text((tx - ox, ty - oy), t, font=fw, fill=C["woodtext"], stroke_width=2 * SS, stroke_fill=C["bg"])
        elif kind == "river":
            d.text((tx - ox, ty - oy), t, font=fw, fill=C["water_l"], stroke_width=2 * SS, stroke_fill=C["bg"])
    # cut into tiles
    im = im.resize((W // SS, W // SS), Image.LANCZOS)
    n = 0
    for ty_ in range(META):
        for tx_ in range(META):
            x, y = mx * META + tx_, my * META + ty_
            lon0, lat1 = unmerc(x * TS, y * TS, z); lon1, lat0 = unmerc((x + 1) * TS, (y + 1) * TS, z)
            if not park.buffer(0.01).intersects(box(lon0, lat0, lon1, lat1)): continue
            t = im.crop((BUF + tx_ * TS, BUF + ty_ * TS, BUF + (tx_ + 1) * TS, BUF + (ty_ + 1) * TS))
            t = t.quantize(palette=PAL, dither=Image.Dither.NONE)
            os.makedirs(f"{OUT}/{z}/{x}", exist_ok=True)
            t.save(f"{OUT}/{z}/{x}/{y}.png", optimize=True); n += 1
    return n


def main():
    bx0, by0, bx1, by1 = park.buffer(0.01).bounds
    index = dict(name="Dartmoor wild camp tiles", tile_size=TS, zooms={}, bounds=[bx0, by0, bx1, by1],
                 palette=[[int(v) for v in c] for c in PAL_COLS],
                 attribution="© OpenStreetMap contributors (ODbL) via Overture Maps; camping areas © Dartmoor National Park Authority (OGL v3); elevation: AWS Terrain Tiles")
    for z in ZOOMS:
        st = STYLE[z]
        smooth = gaussian_filter(dem, {12: 2.0, 13: 1.6, 14: 1.2}[z])
        labels = place_labels(z, st)
        X0, Y0 = [int(v // TS) for v in merc(bx0, by1, z)]
        X1, Y1 = [int(v // TS) for v in merc(bx1, by0, z)]
        total = 0
        for my in range(Y0 // META, Y1 // META + 1):
            for mx in range(X0 // META, X1 // META + 1):
                total += render_meta(z, mx, my, st, labels, smooth)
                print(f"z{z} meta {mx},{my} tiles so far {total}", flush=True)
        index["zooms"][str(z)] = dict(x=[X0, X1], y=[Y0, Y1], tiles=total)
    os.makedirs(OUT, exist_ok=True)
    old = json.load(open(f"{OUT}/index.json")) if os.path.exists(f"{OUT}/index.json") else {}
    old.update({k: v for k, v in index.items() if k != "zooms"})
    old.setdefault("zooms", {}).update(index["zooms"])
    json.dump(old, open(f"{OUT}/index.json", "w"), indent=1, ensure_ascii=False)


main()
