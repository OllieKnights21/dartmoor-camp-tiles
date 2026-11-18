"""Turn every GPX in routes/ into one small routes.json for the watch map app.
Each route: name, total metres, points as [lat*1e5, lon*1e5, ...] (simplified to ~10 m),
cumulative distance (m) and cumulative climb (m) per point. Stdlib only."""
import glob, json, math, os, sys, xml.etree.ElementTree as ET

def pts_of(path):
    root = ET.parse(path).getroot()
    ns = root.tag.split('}')[0] + '}' if root.tag.startswith('{') else ''
    name = root.findtext(f'{ns}trk/{ns}name') or root.findtext(f'{ns}rte/{ns}name') or root.findtext(f'{ns}metadata/{ns}name')
    pts = []
    for tag in (f'.//{ns}trkpt', f'.//{ns}rtept'):
        for p in root.iterfind(tag):
            e = p.findtext(f'{ns}ele')
            pts.append((float(p.get('lat')), float(p.get('lon')), float(e) if e else None))
        if pts: break
    return (name or os.path.splitext(os.path.basename(path))[0]), pts

def dist(a, b):
    dy = (b[0] - a[0]) * 111320; dx = (b[1] - a[1]) * 111320 * math.cos(math.radians(a[0]))
    return math.hypot(dx, dy)

def simplify(pts, tol):  # Douglas-Peucker in metres
    if len(pts) < 3: return pts
    keep = [False] * len(pts); keep[0] = keep[-1] = True; stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop(); a, b = pts[i], pts[j]; best, bk = 0, -1
        L = dist(a, b)
        for k in range(i + 1, j):
            if L == 0: d = dist(a, pts[k])
            else:
                ax = (pts[k][1] - a[1]) * math.cos(math.radians(a[0])) * 111320; ay = (pts[k][0] - a[0]) * 111320
                bx = (b[1] - a[1]) * math.cos(math.radians(a[0])) * 111320; by = (b[0] - a[0]) * 111320
                d = abs(ax * by - ay * bx) / L
            if d > best: best, bk = d, k
        if best > tol: keep[bk] = True; stack += [(i, bk), (bk, j)]
    return [p for p, k in zip(pts, keep) if k]

def main(src, out):
    res = []
    for f in sorted(glob.glob(os.path.join(src, '*.gpx'))):
        name, pts = pts_of(f)
        if len(pts) < 2: continue
        # climb from the full-resolution track (smoothed over 5 points to ignore GPS noise)
        ele = [p[2] for p in pts]
        tol = 10
        s = simplify(pts, tol)
        while len(s) > 500: tol *= 1.5; s = simplify(pts, tol)
        cumd, cuma, d, a = [0], [0], 0.0, 0.0
        for p, q in zip(s, s[1:]):
            d += dist(p, q)
            if p[2] is not None and q[2] is not None and q[2] > p[2]: a += q[2] - p[2]
            cumd.append(round(d)); cuma.append(round(a))
        flat = []
        for p in s: flat += [round(p[0] * 1e5), round(p[1] * 1e5)]
        res.append(dict(name=name[:24], dist=round(d), pts=flat, cumd=cumd, cuma=cuma))
        print(f"{name}: {len(pts)} -> {len(s)} points, {d/1000:.1f} km, climb {a:.0f} m")
    json.dump(dict(routes=res), open(out, 'w'), separators=(',', ':'))

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'routes', sys.argv[2] if len(sys.argv) > 2 else 'routes.json')
