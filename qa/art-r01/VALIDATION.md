# Robot art validation — 2026-11-09

Historical art review checks. The [R02 combat pass](../combat-pass/VALIDATION.md) uses the same GLBs and changes the default scene, viewport and shared HUD.

Windows, Blender 5.1.2, Godot 4.7.2.stable.official.ed1daf0bf, NVIDIA RTX 5070 Ti, Godot Compatibility renderer.

## Bulldozer v03 and the two-robot review

- The GLB contains 17,568 triangles, six meshes, eight materials and 27 surfaces in 1,039,372 bytes. Rest bounds are approximately 1.663 m wide × 0.837 m high × 2.268 m long. The ground, transforms and axle positions passed the validator. See `assets/robots/bulldozer/asset.json`.
- The drum cleared the chassis and wheels in all 72 poses sampled at 5° intervals on the GLB geometry. The spike sweep leaves 0.0841 m of ground clearance. Each wheel passed its own clearance sweep.
- Both GLBs passed Godot checks for rotation axes, stable pivots, hit flash, defeat tint and absence of asset colliders. A separate arena check confirmed that the drum advances around local X during actual playback. See `godot-asset-check.json` and `godot-bulldozer-check.json`.
- The arena review with both art models matched the complete original match reports for seeds 1, 7 and 10. The rendered seed-7 match finished in 20.9333 seconds. See `regression-results.json`, `bulldozer-v03-rendered-seed-7.json` and `godot-bulldozer-v03-arena.log`.
- The studio render and actual Godot close-up were inspected, along with a frame of both models in the arena. See `art/review/bulldozer`.

## Riptide v02

- Blender built the editable `.blend`, exported the GLB and rendered three 1500 × 1200 studio views. The front three-quarter view shows the 24-tooth profile and six cutouts.
- The GLB contains 23,676 triangles, 6 meshes, 7 materials and 31 surfaces in 1,394,584 bytes. The validator checked the internal buffer, root and assembly transforms, pivot positions, finite geometry and ground alignment. `assets/robots/riptide/asset.json` records the measurements.
- The v01 and v02 exports match for chassis and all four wheel assemblies, including topology, geometry and material values.
- The saved `.blend` re-export matches node transforms, materials and accessor structure. The maximum geometry difference is 1.1921e-7 from floating-point roundoff. `source-roundtrip.json`, `blender-reexport.log`, and `roundtrip-v02.glb` record this check.
- Imported actual GLB in Godot. Headless runtime check verifies four wheel pivots, rotor pivot, local X/Y rotation axes, stable origins during motion, stationary chassis, two cyan armor surfaces, white hit flash and darkened defeat tint. No collision nodes in art. `godot-asset-check.json`.
- Imported GLB into Blender and sampled the rotor every 5 degrees through a full revolution. No triangle intersections with chassis or any wheel in all 72 samples. `rotor-clearance.json`. This is a sampled geometric check, not continuous physics validation.
- Original and review matches run headlessly at fixed 60 fps for seeds **1, 7, 10**. The complete corresponding JSON reports are identical, including attack times, damage, health, recovery, speed, arena extent and winner. `regression-results.json` and individual reports/logs.
- Seed 7 rendered at 720 × 1280 on the RTX 5070 Ti and stopped normally. Riptide won with 16 health after 13 spinner hits and 3 ram hits in 20.9333 seconds. See `rendered-art-seed-7.json`, `godot-rendered-match.log` and `art/review/riptide/riptide_v02_arena.png`.
- The standalone Godot review rendered the saw, hub and existing spindle at 1200 × 900. See `art/review/riptide/riptide_v02_godot.png`.
- SHA-256 comparison confirms all eight protected original files are unchanged: `project.godot`, four existing GDScript files, `scenes/arena.tscn`, `config/match.json`, and `Record-Fight.ps1`. Original QA and R01 preview are retained. `original-file-hashes.json`.

## Limits

No Godot script, import or runtime errors occurred in the completed checks. Riptide's source-save log includes a factory brush-material path warning. Both GLBs use internal buffers and the Riptide source re-export succeeded.

The rendered match checks cover game playback. Movie recording uses the separate R01 launcher. The seed comparisons are specific to the tested Godot version and local configuration.

## Re-run

From the project folder:

```powershell
python tools/art/validate_riptide.py --godot 'C:\Users\aurim\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
python tools/art/validate_riptide.py --robot bulldozer
& 'C:\Users\aurim\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/art/verify_import.gd
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' --background --factory-startup --python tools/art/check_rotor_clearance.py
```
