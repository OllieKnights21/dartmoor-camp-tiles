"""Fetch the MOD Dartmoor six-week firing table from GOV.UK and write a compact firing.json.

Codes per range per day: 0 = no firing, 1 = day only, 2 = night only, 3 = day and night, ? = unknown.
Day = sunrise to sunset, night = sunset to sunrise (per the GOV.UK page).
Stdlib only, so it runs on a bare GitHub Actions runner.
"""
import json, re, sys, urllib.request
from datetime import datetime, timezone, timedelta
from html.parser import HTMLParser

API = "https://www.gov.uk/api/content"
PUB = "/government/publications/dartmoor-firing-times"
UA = {"User-Agent": "dartmoor-camp-tiles firing-times job"}


def get(path):
    with urllib.request.urlopen(urllib.request.Request(API + path, headers=UA), timeout=30) as r:
        return json.load(r)


class Tables(HTMLParser):
    def __init__(self):
        super().__init__(); self.rows = []; self.row = None; self.cell = None
    def handle_starttag(self, t, a):
        if t == "tr": self.row = []
        elif t in ("td", "th") and self.row is not None: self.cell = ""
    def handle_endtag(self, t):
        if t in ("td", "th") and self.cell is not None: self.row.append(" ".join(self.cell.split())); self.cell = None
        elif t == "tr" and self.row is not None: self.rows.append(self.row); self.row = None
    def handle_data(self, d):
        if self.cell is not None: self.cell += d


def code(s):
    s = s.lower()
    if "no firing" in s or s.strip() in ("", "nil", "-"): return "0"
    day, night = "day" in s, "night" in s
    return "3" if day and night else "2" if night else "1" if day or "firing" in s else "?"


def main(out):
    pub = get(PUB)
    html = " ".join(pub.get("details", {}).get("documents", [])) + json.dumps(pub.get("links", {}))
    hrefs = list(dict.fromkeys(re.findall(r"(/government/publications/dartmoor-firing-times/[a-z0-9\-]+)", html)))
    if not hrefs: sys.exit("no firing-times document linked from " + PUB)
    doc = get(hrefs[0])
    p = Tables(); p.feed(doc["details"]["body"])
    ranges, days, prev = None, {}, None
    for row in p.rows:
        if row and row[0].lower() == "date":
            ranges = row[1:]; continue
        if not ranges or len(row) < 2: continue
        try:
            d = datetime.strptime(row[0], "%d %B %Y").date()
        except ValueError:
            continue
        # Rows run in date order. Around New Year GOV.UK sometimes keeps the old
        # year on January rows ("01 January 2026" in a Nov 2026 - Jan 2027 table),
        # which stretched the output to a whole year of "???". Roll such dates on.
        while prev and d < prev - timedelta(days=180):
            d = d.replace(year=d.year + 1)
        prev = d
        days[d] = "".join(code(c) for c in row[1:1 + len(ranges)])
    if not days: sys.exit("no rows parsed from " + hrefs[0])
    start, end = min(days), max(days)
    if (end - start).days > 70:
        sys.exit(f"implausible table span {start}..{end} in " + hrefs[0])
    seq, d = [], start
    while d <= end:
        seq.append(days.get(d, "?" * len(ranges))); d += timedelta(days=1)
    res = dict(updated=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%MZ"), title=doc.get("title"),
               source="https://www.gov.uk" + hrefs[0], ranges=ranges, start=start.isoformat(), days=seq,
               codes={"0": "no firing", "1": "day", "2": "night", "3": "day and night"},
               note="Contains public sector information licensed under the Open Government Licence v3.0. Always obey red flags and lamps on the ground.")
    json.dump(res, open(out, "w"), separators=(",", ":"))
    print(f"{len(seq)} days {start}..{end} ranges={ranges}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "firing.json")
