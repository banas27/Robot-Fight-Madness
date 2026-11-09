# R03 collision pass validation

Verified on Windows with Godot 4.7.2, Compatibility rendering, and the existing Movie Maker launcher.

## Reproduction and cause

The original R02 [seed 7 recording](../../renders/combat-pass/after-seed-7.mp4) shows the saw and drum crossing near 16–17 s. Its replay reproduced the hit sequence and the knockout at 13.617 s of combat (16.62 s into the video). The robots finished nose-to-nose at the rail. See the [original frames](../../renders/collision-pass/reference-overlap.png) and [old debug replay](../../renders/collision-pass/reference-debug-closeup.mp4).

R02 let Godot solve chassis boxes and long wheel rails. The weapon checks separately sampled an analytic sweep for scoring and could kick the robots on selected weapon clashes. Neither check supplied a solid saw or drum to the solver. Wheel rails also filled space between the tires, and the weapon supports were underfit. Cosmetic pitch, roll and lift moved the visible model away from its physical hull. Both drivers started braking at the knockout without opening space. The live movement code drove the bodies with forces and torque; there was no per-frame body teleport to remove.

## Fit and contact handling

Both imports are unit scale and face local −Z. The GLBs' chassis transforms are identity. The imported rig check passed for four independent wheels and one weapon pivot per robot, with no embedded physics shapes.

| Local fit | Riptide | Bulldozer |
| --- | --- | --- |
| Weapon pivot and spin axis | (0, 0.040, −0.870), Y | (0, −0.021, −1.125), X |
| Wheel pivots and roll axis | (±0.730, −0.080, ±0.430), X | (±0.605, −0.105, ±0.433), X |
| Shapes checked over the visible art | Armor, central body, four tires and hubs, bridge and bearing, faceted saw core and hub, 24 teeth | Armor and wheel guards, four tires and hubs, both forks and bearings, faceted drum core and end rings, 15 spikes |

Both robots and their shape owners use layer 1 and mask 1|2|4. Walls use layer 2 and the deck uses layer 4; both mask layer 1. All parts stay solid during spin-down and after a knockout. Stationary supports and rotating teeth are separate. The saw's compound tooth collider can use any equivalent phase one tooth pitch apart; the visible rotation and surface speed use the actual phase. Press **D** to see the solver's shape edges, including hidden edges through the robot and rail.

A powered tooth hitting a solid part can score once per contact episode and is also subject to the attack cooldown. Brief breaks of less than 130 ms do not rearm the strike. Weapon-on-weapon contact blocks and can spark without scoring. A strike uses the same reported contact point and normal for the event, effects and bounded tangential kick; the solver supplies the normal impulse. Forward drive eases into existing contact. Clash and strike recovery use motor forces to reverse or flank. At knockout both attacks stop, both rotors wind down, and the survivor can steer and move away using the motors.

## Checks and tuning

The focused tests use live solver contacts. They passed a near miss, direct saw/drum clash, side saw strike to the chassis, glancing drum strike to a wheel, sustained contact, corner impact, two-robot wall pin, and a near-wall knockout. The sustained press scored once across 1.89 s of reported contacts, beyond cooldown. The knockout opened the center gap from 2.30 m to 2.90 m. Both rotors and bodies settled, and a subsequent test push still collided with the defeated body without scoring.

| Physics rate | Head-on peak reported depth | Longest continuous head-on depth above 25 mm |
| --- | ---: | ---: |
| 60 Hz | 53 mm | 16.7 ms |
| 120 Hz | 72 mm | 25.0 ms |
| **180 Hz** | 75 mm | **11.1 ms** |
| 240 Hz | 78 mm | 16.7 ms |

180 Hz is scoped to R03 and limits each step to about 11.5° of saw rotation or 10.5° of drum rotation at full speed. It gave the shortest deep-contact run in the head-on fixture. 240 Hz did not improve that fixture. Body CCD on and off gave the same 180 Hz fixture results. Earlier tests with primitive weapon cores sometimes reported implausibly deep contacts, even with CCD off. Switching those cores to fitted inscribed convex profiles removed the outliers in the 20-seed rerun on the existing backend. Body CCD is off for R03; its translational sweep does not sweep the rotating tooth owners.

[Twenty seeded matches](headless-results.json) passed scoring, cooldown, containment, and end-depth checks. The largest reported weapon manifold depth was 98 mm; no run above 25 mm lasted longer than 62 ms, and the largest reported depth on the final tick was under 8 mm. These are solver contact measurements, not a guarantee that every rendered triangle clears at every instant. Collision is still discrete, with rigid approximations for teeth, armor edges and tire treads. Very fast or shallow contacts may be missed between ticks. The work did not tune competitive balance.

## Recordings

- [Close-up comparison](../../renders/collision-pass/collision-debug-closeup.mp4), 11.8 s: original seed 7 near the knockout; revised seed 7 at the same part of the clip; revised seed 25 at the knockout and settle.
- [Clean full match](../../renders/collision-pass/fight-seed-25.mp4), 25.5 s: the existing launcher recorded Riptide winning by knockout. The clean and debug seed 25 reports match, with zero weapon contact depth reported on the final tick. The revised seed 7 reaches a time decision, so a separate seed shows the new knockout.
- Both MP4s decode at 720 × 1280, 30 fps with stereo AAC. Contact and result frames were visually checked. The [file hashes](preserved-hashes.txt) match the pre-pass snapshot for the two Blender files, both GLBs, the launcher and the main project settings.

From the project folder with `$godot` set as in START_HERE:

```powershell
& $godot --headless --path . --fixed-fps 60 --quit-after 900 --script tools/verify_combat.gd
python tools/verify_matches.py --godot $godot --count 20
```
