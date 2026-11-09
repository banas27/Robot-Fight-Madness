# Wheel-loss support experiment

The branch starts from `547a052`, which contains the validated convex Riptide hub correction in `cf80747`. Both robots keep their weapon pivots and four independent wheel pivots. The tire, outer hub and tread/hub colliders leave together. Bearing carriers, collars, stub shafts, crossmembers and skids remain on the chassis. The skids and carriers use fitted boxes. The small collars, shaft keys and crossmembers are visual details inside the support envelope.

The first physical detachment releases pitch and roll. Gravity and the surviving solids determine posture. An attached failed motor still supports the chassis. The drive force and yaw controller use the fraction of usable wheels reporting upward deck contact and apply forces parallel to the deck. Debris starts at the wheel's exact visible pose, inherits axle-point movement and roll, and gets a 0.50–0.68 m/s outward release to clear the shaft. Loose wheels collide with the deck and rails. The showcase rotates a copy of the finish tilt and seats the lowest surviving solid on the pedestal. The introduction and combat rules use their existing timing and settings.

## Isolated checks

Godot 4.7.2 at 180 physics ticks/s passed 20 deterministic support cases, the moving-release and airborne controls, and damaged showcase checks for both robots. All 15 existing combat checks and all three original wheel–drum same-pose regressions also passed. Four representative episode/headless pairs had identical combat reports and traces. Untraced and detailed-contact variants agreed in eight further comparisons. Both rendered episodes match their headless combat reports.

Every isolated case was allowed to settle, driven straight and through a turn with the rotor off, then exercised with a spinning rotor and an off-centre impulse. All single-wheel fixtures settled within 0.02° of level on three wheels. A failed attached wheel held the level stance with four supports and 76% available drive. Same-side loss rested on the skids at 6.92° roll for Riptide and 5.98° for Bulldozer. Front/rear loss produced 7.98°/8.19° pitch for Riptide and 3.73°/5.62° for Bulldozer. The drum itself can support the nose after front loss, and steering slows while it scrapes. [Support JSON](fixtures.json), [wheel–drum regression JSON](wheel-drum.json), [parity JSON](parity/summary.json)

## Same 20 development seeds and both starts

| Metric | Corrected baseline | Wheel-support branch |
| --- | ---: | ---: |
| Riptide wins / Bulldozer wins / draws | 6 / 34 / 0 | 10 / 30 / 0 |
| Mean HP damage dealt by Riptide / Bulldozer | 53.80 / 108.18 | 59.23 / 106.85 |
| Mean Riptide rail pin / stall | 0.520 / 6.246 s | 0.413 / 6.288 s |
| Mean Bulldozer rail pin / stall | 0.000 / 2.232 s | 0.006 / 2.164 s |
| Wheel detachments | 26 | 20 |
| Peak weapon contact witness projection | 139.5 mm | 127.0 mm |
| Longest weapon projection above 25 mm | 13 ticks | 7 ticks |
| Peak lift above spawn / speed | 57.0 mm / 4.00 m/s | 80.7 mm / 4.00 m/s |
| Fights flagged for post-detachment deck penetration over 25 mm | — | 3 |

Rail pin means simultaneous rail and opponent contact. Stall uses the existing close-range low-speed test with a minimum 0.35 s run. After wheel loss, Riptide recorded 0.061 s total below 0.25 m/s with no supported drive. Bulldozer recorded zero. No overturned or permanently immobilized robot was observed in this sample. The branch uses the same baseline AI, stats and damage thresholds.

Three fights showed transient deck penetration at a surviving wheel after detachment. The worst was standard seed 3 at 13.028 s of combat. A drum tooth contacted Riptide’s convex rear hub at a steep angle. The solver’s positional correction put the opposite edge of the supporting tread 101.6 mm below the deck plane for one tick. It was 27.8 mm deep the next tick and under 25 mm on the third. Swapped seed 25 and standard seed 4 also crossed 25 mm. A 6 mm bevel moved the largest outlier to another replay and made it deeper, so the validated hub fit was retained. The existing match verifier checks the duration of post-detachment penetration because root height alone can drop legitimately. The evaluator still flags every peak above 25 mm. The showcase reflects the finish pose on its pedestal and does not run a second settlement simulation. [Corrected baseline raw matches](../wheel-drum/baseline-after), [branch raw matches and comparison](development), [bevel diagnostic](bevel-diagnostic/summary.json)

## Reproduce and review

Run these commands in the project folder with the same Godot executable as `Record-Fight.ps1`. Reproduce the before batch at `547a052` with the same evaluator command and a different output directory. The historical wheel–drum captures used by the isolated replay are described in the [wheel–drum investigation](../wheel-drum/VALIDATION.md).

```powershell
& $godot --headless --editor --path . --import
& $godot --headless --path . --fixed-fps 180 --script res://tools/verify_wheel_support.gd
& $godot --headless --path . --fixed-fps 60 --script res://tools/verify_combat.gd
& $godot --headless --path . --fixed-fps 180 --script res://tools/verify_wheel_drum.gd -- --fixture-report=res://qa/wheel-support/wheel-drum.json
py tools/evaluate_riptide.py --godot $godot --split development --variants baseline --output qa/wheel-support/development
py tools/evaluate_riptide.py --godot $godot --split parity --variants baseline --output qa/wheel-support/parity
py tools/verify_matches.py --godot $godot --seeds 3 4 13 25 --output qa/wheel-support/verified-matches.json
New-Item -ItemType Directory -Force renders/wheel-support | Out-Null
foreach ($robot in 'saw','drum') {
    & $godot --path . --resolution 720x1280 --write-movie "renders/wheel-support/$robot.avi" --fixed-fps 30 --quit-after 420 --script res://tools/verify_wheel_support.gd -- "--wheel-review=$robot"
    & $ffmpeg -i "renders/wheel-support/$robot.avi" -an -c:v libx264 -pix_fmt yuv420p -movflags +faststart "renders/wheel-support/$robot.mp4"
}
foreach ($seed in 25,13) {
    .\Record-Fight.ps1 -Godot $godot -Seed $seed -RiptideAI baseline -FFmpeg $ffmpeg
}
```

- [Riptide forced-damage clip](../../renders/wheel-support/riptide-fixture.mp4) · [intact](../../renders/wheel-support/riptide-intact.png) · [front-left removed](../../renders/wheel-support/riptide-single.png) · [both left removed](../../renders/wheel-support/riptide-detached.png)
- [Bulldozer forced-damage clip](../../renders/wheel-support/bulldozer-fixture.mp4) · [intact](../../renders/wheel-support/bulldozer-intact.png) · [front-left removed](../../renders/wheel-support/bulldozer-single.png) · [both left removed](../../renders/wheel-support/bulldozer-detached.png)
- [Seed 25](../../renders/wheel-support/seed-25.mp4) and [seed 13](../../renders/wheel-support/seed-13.mp4). Bulldozer won both by knockout with 179/200 and 150/200 HP, respectively.
