# Dartmoor Camp watch apps (Instinct 3 AMOLED, sideload)

- `field/` tent data field: in/out of DNPA camping areas, distance and direction to the nearest, distance left, average pace, ETA vs dark, position (OS grid or lat/long).
- `common/` shared code and the baked camping polygons (`tools/bake_camp.py`).

Build (Windows, SDK 9.2.0):

    monkeyc -f field\monkey.jungle -d instinct3amoled50mm -o build\DartmoorCampField.prg -y <developer_key.der> -w
