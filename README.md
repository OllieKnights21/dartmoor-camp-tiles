# Dartmoor camp tiles

Dark picture tiles of Dartmoor and a daily firing-times file for a personal Garmin Connect IQ wild camping app (Instinct 3 AMOLED).

Published with GitHub Pages:

- `tiles/{z}/{x}/{y}.png`: 256 px web-mercator tiles, fixed 64-colour palette, zooms 12 (overview), 13 (about 1 km on screen) and 14 (about 500 m on screen). Covers the Dartmoor National Park plus a small margin.
- `tiles/index.json`: zoom ranges, bounds, palette and attribution.
- `warnings.json`: Met Office weather warnings for South West England (from the RSS feed), with a `devon` flag.
- `weather.json`: hourly rain chance (%) and amount (mm), wind speed and gusts (mph) and the direction the wind comes from (degrees) for the next 24 h in central Dartmoor, from Open-Meteo (CC BY 4.0). The watch normally asks Open-Meteo directly for its own position; this is the fallback.
- `firing.json`: the MOD six-week Dartmoor firing table from GOV.UK, refreshed hourly by the workflow. Per day, one character per range (in `ranges` order): `0` no firing, `1` day, `2` night, `3` day and night, `?` unknown. Always obey red flags and lamps on the ground.

## Sources and licences

- Map features: © OpenStreetMap contributors, available under the Open Database Licence (ODbL), via Overture Maps.
- Permitted backpack camping areas: Dartmoor National Park Authority, Open Government Licence v3.0.
- Firing times: Ministry of Defence via GOV.UK, Open Government Licence v3.0.
- Rain forecast: Open-Meteo (CC BY 4.0). Weather warnings: Met Office, Open Government Licence v3.0.
- Elevation (contours, hill shading): AWS Terrain Tiles (Mapzen terrarium).

## Rebuilding

`tools/make_tiles.py` renders the tiles from Overture extracts, an elevation mosaic and the DNPA GeoJSON. `tools/firing_times.py` builds `firing.json` (stdlib Python only).
