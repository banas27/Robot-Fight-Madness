# Robot art review

## Bulldozer tracked review

The tracked variant has 36 moving shoes per side around three road wheels, with the existing orange upper hull and spiked drum. Open [the tracked review scene](../scenes/review/bulldozer_tracks_review.tscn) in Godot and press **F6** for the turntable. The [tracked test arena](../scenes/review/arena_tracked_bulldozer_test.tscn) uses the tracked rig in the introduction, fight and showcase. The default arena loads wheeled Bulldozer v04.

The test arena converts the original AI's speed and steering requests into forces at the left and right belts. Each belt uses a convex hull for contact. Its shoes animate with the measured motion of that side. The original wheel wear thresholds now apply independently to each belt. A failed motor leaves a passive belt that supports the chassis. A thrown belt releases a short strip and transfers support to the surviving road wheels. Road wheel hubs can take separate damage, and losing an end wheel throws the corresponding belt.

The solver treats each attached belt as one rigid shape and each exposed road wheel as part of the chassis. Lateral grip uses the existing chassis controller, and loose belts use a rigid strip of shoes. The showcase retains the damage and missing parts from the end of the fight. Run the isolated checks with `& $godot --headless --path . --fixed-fps 60 --script res://tools/verify_tracks.gd`.

In standard seed 25, the visual-only test ended in a Bulldozer knockout at 18.68 seconds with 179 HP. The functional test ran to 25 seconds, with Bulldozer winning on health at 156 HP to Riptide's 6. The functional run scored two saw hits on weapon supports. The isolated fixtures exercised track and road-wheel strikes, motor failures, thrown belts and the damaged showcase. The recorded and headless combat reports agree.

- [Editable Blender source](source/robots/bulldozer/bulldozer_v05_tracks.blend) · [Runtime review GLB](../assets/robots/bulldozer/bulldozer_v05_tracks.glb)
- [Godot motion review](../renders/bulldozer-tracks/bulldozer-tracks.mp4) · [Close-up still](../renders/bulldozer-tracks/bulldozer-tracks.png)

To reproduce the variant from the wheeled source, use the same Blender binary as the wheel-support builds below.

```powershell
& $blender -b art/source/robots/bulldozer/bulldozer_v04.blend --python-exit-code 1 --python tools/art/build_bulldozer_tracks.py
```

## Wheel-support revisions

Riptide v03 and Bulldozer v04 retain the same root, wheel pivots and weapon pivot. The chassis mesh includes the bearing carriers, collars, shafts, crossmembers and skids. Each wheel pivot owns its tire and rotating hub. See the [wheel-support validation](../qa/wheel-support/VALIDATION.md) for intact and detached views.

| Robot | Editable Blender source | Runtime asset |
| --- | --- | --- |
| Riptide | [riptide_v03.blend](source/robots/riptide/riptide_v03.blend) | [riptide_v03.glb](../assets/robots/riptide/riptide_v03.glb) |
| Bulldozer | [bulldozer_v04.blend](source/robots/bulldozer/bulldozer_v04.blend) | [bulldozer_v04.glb](../assets/robots/bulldozer/bulldozer_v04.glb) |

Use `export_robot.py` with the current versioned Blender file to export hand edits. To reproduce the added hardware from the preceding sources, use Blender 5.1.2 and run these commands from the project folder.

```powershell
& $blender -b art/source/robots/riptide/riptide_v02.blend --python-exit-code 1 --python tools/art/add_wheel_support.py -- --robot riptide
& $blender -b art/source/robots/bulldozer/bulldozer_v03.blend --python-exit-code 1 --python tools/art/add_wheel_support.py -- --robot bulldozer
py tools/art/validate_riptide.py --asset-only --robot riptide
py tools/art/validate_riptide.py --asset-only --robot bulldozer
```

## Bulldozer v03

Bulldozer has broad orange armor, recessed wheels and a steel cylinder with 15 staggered spikes. The drum spins around local X at (0, -0.021, -1.125) in Godot coordinates. The bearing forks belong to the chassis and the four wheels have individual axle pivots. In the R02 arena the drum spins up to attack speed and its spikes can strike the other robot. The R01 art review displays the same drum with the earlier ram rules.

- [Studio render](review/bulldozer/bulldozer_v03_hero.png) · [Top](review/bulldozer/bulldozer_v03_top.png) · [Rear](review/bulldozer/bulldozer_v03_rear.png)
- [Godot close-up](review/bulldozer/bulldozer_v03_godot.png) · [Both robots in the arena](review/bulldozer/riptide_vs_bulldozer_v03_arena.png)
- [Editable Blender source](source/robots/bulldozer/bulldozer_v03.blend) · [Runtime GLB](../assets/robots/bulldozer/bulldozer_v03.glb) · [Measured metadata](../assets/robots/bulldozer/asset.json)

In Godot, open `scenes/review/bulldozer_review.tscn` and press **F6** for a moving close-up. Press **F5** for the R02 match, or open `scenes/review/arena_art_review.tscn` and press **F6** to compare the R01 art review.

To regenerate Bulldozer, run `tools/art/build_bulldozer.py` in background Blender with `art/source/robots/riptide/riptide_v02.blend` loaded as the studio template. The builder overwrites the Bulldozer v03 source, GLB and studio stills. To export hand edits, run `tools/art/export_robot.py` with the saved Bulldozer source open and pass `--root Robot_Bulldozer --output assets/robots/bulldozer/bulldozer_v03.glb` after `--`.

## Riptide v02

The front weapon is a horizontal steel circular saw with 24 swept teeth, six cutouts and a cyan hub. It spins around the existing spindle.

### Look at the model

- [Blender studio render](review/riptide/riptide_v02_hero.png)
- [GLB rendered in Godot](review/riptide/riptide_v02_godot.png)
- [R01 match camera](review/riptide/riptide_v02_arena.png)
- [Top](review/riptide/riptide_v02_top.png) and [rear](review/riptide/riptide_v02_rear.png)

Blender's studio lighting and AgX tone mapping produce a softer finish. Godot's Compatibility renderer and original arena lighting show the in-game result. Judge team-color readability in the Godot images. Small fasteners and text are for closeups; the swept cyan shoulders and rotor carry the identity at match distance.

In Godot, open `scenes/review/riptide_review.tscn` and press **F6** for a moving close-up. In either close-up scene, Space pauses motion, Left/Right turn the robot, 1/2/3 select three-quarter, top and front views, and Escape closes.

### Source and runtime asset

- [Editable Blender source](source/robots/riptide/riptide_v02.blend)
- [Runtime GLB](../assets/robots/riptide/riptide_v02.glb)
- Measured metadata: `assets/robots/riptide/asset.json`
- Shared style, scale, naming, and proposed ten-robot roster: [STYLE_GUIDE.md](STYLE_GUIDE.md)

The model has 23,676 triangles, six rigid assemblies, seven PBR materials and 31 material surfaces. The GLB is 1.39 MB. Rest-pose size is approximately **1.785 wide × 0.843 high × 2.216 long** in meters. Place the root at Y = 0.4 for ground contact. Godot forward is -Z at unit scale. The chassis, four wheels and saw are separate assemblies with pivots centered on their axles or spindle.

Blender **5.1.2** is installed and its background Python/glTF exporter work. No dedicated Blender connector is exposed in this chat. Godot **4.7.2** imports and renders the GLB on the local RTX 5070 Ti. No plugins or software were installed.

### Continue editing and exporting

Edit the objects inside `RIPTIDE_EDITABLE` in Blender; keep root and assembly names stable. The `STUDIO_NOT_EXPORTED` collection contains the lighting, ground and camera. Save your source edits normally.

From the project folder, export your saved source without regenerating it:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' --background 'art/source/robots/riptide/riptide_v02.blend' --python 'tools/art/export_robot.py' -- --root Robot_Riptide --output 'assets/robots/riptide/riptide_v02.glb'
```

The exporter works on evaluated temporary copies and merges details within each rigid assembly. It does not save over the Blender source. Reimport the changed GLB in Godot and run the validator to refresh `asset.json`:

```powershell
python tools/art/validate_riptide.py --godot 'C:\Users\aurim\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
```

`tools/art/build_riptide.py` is the procedural construction recipe. Running it **rebuilds and overwrites the v02 Blender source, GLB and studio stills**. Use the exporter above to preserve hand edits. For a new art revision, first save under a new versioned filename and export that revision separately.

### Saw review

Use the top and studio views to inspect the saw profile. The Godot review scene shows how the blade reads in motion.

Validation evidence: [qa/art-r01/VALIDATION.md](../qa/art-r01/VALIDATION.md).
