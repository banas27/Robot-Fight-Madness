# Wheel and drum contact investigation

GodotPhysics3D reproduced an excessive positional correction when a Riptide hub cylinder contacted a Bulldozer core prism. The fix gives Riptide’s four hubs the same 32-sided convex construction already used for its treads. The hubs keep their centers, axes, 108 mm radius, 58 mm width, 2 mm margin, and wheel role. The maximum inward difference between a facet and the old circle is 0.52 mm. The default match still selects baseline Riptide.

The pre-change replays use Godot 4.7.2 `ed1daf0bf`, 180 Hz physics, 30 FPS fixed frame scheduling and the original swapped starting arrangement. All three match reports matched the saved experiment results. The branch starts from `main` at `b7bbdf8`. Commit `e6fac22` restores the opt-in replay policies and probes. Commit `8d0c026` separates measurements, and `cf80747` changes the hub collider and tests.

## The three anomalies

| Swapped seed and policy | Observed combat tick | Riptide hub / drum core shape indices | Original peak witness projection | Intersection at solve input / published pose | Continuous input overlap around the peak | Pair ticks over 25 mm around the peak |
| --- | ---: | --- | ---: | --- | ---: | ---: |
| 166, previous candidate | 3188 · 17.711 s | 13 / 25 | 0.2011 m | yes / yes | 9 · 0.0500 s | 2 · 0.0111 s |
| 15, Rail Exit | 4181 · 23.228 s | 11 / 22 | 1.1266 m | yes / yes | 10 · 0.0556 s | 1 · 0.0056 s |
| 4, Rail Exit | 1462 · 8.122 s | 13 / 26 | 0.1759 m | yes / clear | 38 · 0.2111 s | 1 · 0.0056 s |

- **166.** The original query found the same pair still intersecting at the published pose. The reported witness projection coexisted with a 0.795 mm witness on the same pair. Riptide moved 24.1 mm in the solve and its linear velocity changed by 0.014 m/s. The published pair cleared by a 0.10 m shift along the reported normal. [Phase trace](extended/candidate-166-swapped.trace.json)
- **15.** The long drum core produced a witness on its far cap, at +0.5985 m along its local axis. The same tick also had a near-side witness at −0.5242 m with a projection of about 4 µm. Riptide’s position shifted 101.0 mm in one solve while its linear velocity changed by 0.058 m/s. The positional jump reproduced with just the two shapes. A 0.20 m downward shift cleared the published pair in the earlier probe. [Phase trace](extended/rail-exit-15.trace.json)
- **4.** The input pose contained a real contact. The published pose cleared it during that same step, which explains the earlier empty query. The pair intersected for 38 sampled input poses, with projections below 0.04 mm in the 11 ticks leading up to the spike. Riptide moved 11.7 mm at the spike and slowed from 1.79 to 1.67 m/s. The pair then cleared. [Phase trace](extended/rail-exit-4.trace.json)

There were no damage events within 0.20 s of any of the three original spikes. The core is a blocking shape and damage comes from eligible tooth contacts. Seed 15 shows a real positional correction with little change in momentum. In the two other cases the measured responses are smaller and the sampled pair separates after the peak. The sustained overlap count describes query positives at fixed poses, and the >25 mm count describes the contact-point projection.

## What the measurements mean

GodotPhysics creates the world-space contact witnesses during pre-solve and publishes them on the next physics callback, after solving and integrating body poses. The existing depth calculation projects the vector between those witnesses onto the outward normal. The engine also uses that projection when computing positional bias. The report keys `peak_weapon_contact_depth` and `longest_weapon_depth_over_25mm` retain their historical names and values. Their values describe witness projections, and the thresholds remain useful flags for inspection. [Witness reporting and bias](https://github.com/godotengine/godot/blob/ed1daf0bf/modules/godot_physics_3d/godot_body_pair_3d.cpp#L346-L391), [pose integration](https://github.com/godotengine/godot/blob/ed1daf0bf/modules/godot_physics_3d/godot_body_3d.cpp#L673-L697), [physics loop order](https://github.com/godotengine/godot/blob/ed1daf0bf/main/main.cpp#L4626-L4667)

The new optional audit queries the exact two shape indices in both directions. It saves the pose submitted just before the solve and the pose published after it, along with the engine frame IDs. Its traces include body and owner IDs, collider dimensions and local/world transforms, world contact points and normals, velocity vectors, reported impulses, wheel condition and damage logs. The engine’s reported contact impulse is available in the trace. Its pre-solve publication timing makes the measured pose and velocity change a better check of the response than that impulse field alone.

A separate query establishes whether two shapes intersect at a specified pose. A translation along a chosen axis only bounds clearance along that axis. Witness projection, a binary overlap query and a distance to clear along one axis are distinct measurements. Both queries still use Godot’s collision backend. The fixture verifies their separated and deliberately intersecting controls and keeps the shape definitions and phases explicit.

## Same-pose regression

The isolated fixture replays each original input with the captured transforms and starting velocities, then substitutes the actual project hub at the same pose. It removes the deck, other collision shapes and prior manifold cache. Each original cylinder reproduced the far witness. The revised hub retains the deliberate contact control, passes the separated control, and bounds one-step movement in all three saved poses.

| Original input | Isolated peak witness before → after | Isolated Riptide displacement before → after |
| --- | ---: | ---: |
| 166 | 201.11 → 0.80 mm | 43.45 → 3.72 mm |
| 15 | 1126.60 → 0 mm, grazing pair clear | 274.82 → 8.51 mm |
| 4 | 175.93 → 0.002 mm | 25.84 → 9.92 mm |

The original cylinder/convex pair generated the exaggerated witness even in a fresh fixture, and the engine used it for positional correction. The revised convex hub removes that response in these fixtures. This is a project-level collider fix for a specific shape pairing. The general solver and report flags still require case-by-case interpretation. [Fixture JSON](fixture-final.json)

## Fight validation

The full replays diverge after the collider change. In each revised fight, the original shape pair was clear throughout the ±108-tick window around the old peak. The full-fight maximum witness projection changed from 0.2011 to 0.0979 m for seed 166, 1.1266 to 0.0706 m for seed 15, and 0.1759 to 0.1017 m for seed 4. Their longest runs over 25 mm were 2 → 2, 5 → 5 and 2 → 4 ticks respectively. These are whole-fight readings from different encounters. [Replays before](before), [replays after](after)

| Baseline AI, 20 seeds × two starts | Before | Revised hubs |
| --- | ---: | ---: |
| Riptide wins / draws | 6 / 0 | 6 / 0 |
| Mean HP damage dealt / received | 59.58 / 110.25 | 53.80 / 108.18 |
| Mean time pinned against a rail | 0.619 s | 0.520 s |
| Mean stalled time | 6.539 s | 6.246 s |
| Fights flagged by existing solver thresholds | 1 | 0 |
| Maximum witness projection | 0.1814 m | 0.1395 m |
| Longest run over 25 mm | 13 ticks | 13 ticks |
| Max lift / speed | 0.096 m / 4.002 m/s | 0.057 m / 4.002 m/s |

All 15 existing combat checks passed, including the head-on block, wall pin, glancing hit, and sustained contact check. The 40 before and 40 after reports and the anomaly replays pass damage-target and cooldown checks. Twelve episode/headless pairs match across all three replay policies and both starting arrangements. Detailed and untraced reports match those pairs and the three revised anomalies. All eight rendered cases match their headless combat reports. The tests cover the reproduced defect and sampled fights. Other shape pairs can still produce witness spikes. [Before batch](baseline-before/summary.json), [after batch](baseline-after/summary.json), [parity](parity-after/summary.json)

## Commands and recordings

Use the same Godot executable as `Record-Fight.ps1`. Run this loop at commit `8d0c026` for the before captures and at the investigation tip for the after captures, writing each set to a separate directory. Run the fixture on the investigation tip with the path to the before captures.

```powershell
$qa = 'qa/wheel-drum/after'
New-Item -ItemType Directory -Force $qa | Out-Null
$cases = @(
    @('candidate', 166, '3188,13,25', 'candidate-166-swapped'),
    @('rail-exit', 15, '4181,11,22', 'rail-exit-15'),
    @('rail-exit', 4, '1462,13,26', 'rail-exit-4')
)
foreach ($case in $cases) {
    $policy, $seed, $pair, $stem = $case
    & $godot --headless --path . --fixed-fps 30 -- --combat-only --swap-start --contact-trace "--riptide-ai=$policy" "--seed=$seed" "--wheel-drum-audit=$pair" "--trace=$qa/$stem.trace.json" "--report=$qa/$stem.match.json"
}
& $godot --headless --path . --fixed-fps 30 --script res://tools/verify_wheel_drum.gd -- --capture-dir=qa/wheel-drum/extended --fixture-report=qa/wheel-drum/fixture-final.json
& $godot --headless --path . --fixed-fps 60 --script res://tools/verify_combat.gd
py tools/evaluate_riptide.py --godot $godot --split development --variants baseline --output qa/wheel-drum/baseline-after
py tools/evaluate_riptide.py --godot $godot --split parity --variants baseline candidate rail-exit --output qa/wheel-drum/parity-after
.\Record-Fight.ps1 -Godot $godot -Seed 25 -RiptideAI baseline
```

The short clips use the collision overlay. Each revised clip shows the same clock range in a new fight, with its divergence labelled. The MP4s are local under `renders/wheel-drum-investigation`, and the bulk JSON is under `qa/wheel-drum`.

- Collision comparisons of [seed 166](../../renders/wheel-drum-investigation/seed-166-contact-comparison.mp4), [seed 15](../../renders/wheel-drum-investigation/seed-15-contact-comparison.mp4) and [seed 4](../../renders/wheel-drum-investigation/seed-4-contact-comparison.mp4). Each runs 4.80 s.
- [Baseline seed 25](../../renders/wheel-drum-investigation/baseline-seed-25.mp4) runs 35.63 s. Bulldozer won by knockout at 200/200 HP.
- [Baseline seed 13](../../renders/wheel-drum-investigation/baseline-seed-13.mp4) runs 40.03 s. Bulldozer won on health, 125/200 to 30/150.
