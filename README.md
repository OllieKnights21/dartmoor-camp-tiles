# Dartmoor camp tiles

Dark picture tiles of Dartmoor and a daily firing-times file for a personal Garmin Connect IQ wild camping app (Instinct 3 AMOLED).

Published with GitHub Pages:

- `tiles/{z}/{x}/{y}.png`: 256 px web-mercator tiles, fixed 64-colour palette, zooms 12 (overview), 13 (about 1 km on screen) and 14 (about 500 m on screen). Covers the Dartmoor National Park plus a small margin.
- `tiles/index.json`: zoom ranges, bounds, palette and attribution.
- `firing.json`: the MOD six-week Dartmoor firing table from GOV.UK, refreshed daily by the workflow. Per day, one character per range (in `ranges` order): `0` no firing, `1` day, `2` night, `3` day and night, `?` unknown. Always obey red flags and lamps on the ground.

## Sources and licences

- Map features: © OpenStreetMap contributors, available under the Open Database Licence (ODbL), via Overture Maps.
- Permitted backpack camping areas: Dartmoor National Park Authority, Open Government Licence v3.0.
- Firing times: Ministry of Defence via GOV.UK, Open Government Licence v3.0.
- Elevation (contours, hill shading): AWS Terrain Tiles (Mapzen terrarium).

## Rebuilding

`tools/make_tiles.py` renders the tiles from Overture extracts, an elevation mosaic and the DNPA GeoJSON. `tools/firing_times.py` builds `firing.json` (stdlib Python only).
