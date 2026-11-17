"""Build warnings.json (Met Office, South West England) and weather.json (Open-Meteo hourly rain, central Dartmoor).

The watch fetches Open-Meteo itself for its own position when the phone is connected; weather.json is a
fallback. Met Office warnings come as RSS (XML), which the watch can't parse, so this job turns them into
a small JSON file. Stdlib only.
"""
import json, re, sys, urllib.request, xml.etree.ElementTree as ET
from datetime import datetime, timezone

UA = {"User-Agent": "dartmoor-camp-tiles weather job"}
RSS = "https://www.metoffice.gov.uk/public/data/PWSCache/WarningsRSS/Region/sw"
OM = ("https://api.open-meteo.com/v1/forecast?latitude=50.58&longitude=-3.96"
      "&hourly=precipitation_probability,precipitation&forecast_hours=24&timezone=Europe%2FLondon")


def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
        return r.read()


def warnings(out):
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
    try:
        root = ET.fromstring(fetch(RSS))
    except Exception as e:
        json.dump(dict(updated=now, error=str(e)[:200], warnings=[]), open(out, "w")); print("warnings failed", e); return
    items = []
    for it in root.iter("item"):
        title = (it.findtext("title") or "").strip()
        desc = " ".join(re.sub(r"<[^>]+>", " ", it.findtext("description") or "").split())
        m = re.match(r"(Yellow|Amber|Red)\s+warning of\s+(.+?)\s+affecting", title, re.I)
        level, kind = (m.group(1).lower(), m.group(2).lower()) if m else ("unknown", title.lower())
        times = re.findall(r"valid from (.+?) to (.+?)(?:\.|$)", desc, re.I)
        items.append(dict(level=level, type=kind, title=title, valid=(list(times[0]) if times else None),
                          devon=("devon" in (title + desc).lower()), link=it.findtext("link")))
    json.dump(dict(updated=now, region="South West England", source=RSS, warnings=items,
                   note="Contains public sector information licensed under the Open Government Licence v3.0 (Met Office)."),
              open(out, "w"), separators=(",", ":"))
    print(f"{len(items)} warnings", [w["title"] for w in items])


def weather(out):
    try:
        h = json.loads(fetch(OM))["hourly"]
        res = dict(updated=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%MZ"), place="central Dartmoor",
                   time=h["time"], prob=h["precipitation_probability"], mm=h["precipitation"], source="Open-Meteo (CC BY 4.0)")
    except Exception as e:
        res = dict(error=str(e)[:200])
    json.dump(res, open(out, "w"), separators=(",", ":"))
    print(json.dumps(res)[:900])


if __name__ == "__main__":
    site = sys.argv[1] if len(sys.argv) > 1 else "."
    warnings(f"{site}/warnings.json"); weather(f"{site}/weather.json")
