# R04 fighting styles, component damage and broadcast validation

The [seed 25 recording](../../renders/style-pass/fight-seed-25.mp4) is 20.80 seconds at 720 × 1280, 30 fps, with stereo AAC. It was recorded through the existing Movie Maker launcher. At 360 × 640, the opening prompt, health changes, component alerts and result were readable. The default and debug camera code, camera tuning, GLB assets, base damage values and launcher were checked against the R03 baseline.

| Seed 25 | Riptide hits | Bulldozer hits | Result |
| --- | ---: | ---: | --- |
| R03 | 11 | 1 | Riptide by knockout, 87 HP |
| R04 | 2 | 7 | Bulldozer by knockout, 81 HP |

At about 18 seconds in R03, Riptide had 100 HP and Bulldozer 14. Riptide was hitting the drum supports repeatedly. Over that match the solver reported Bulldozer's core against a wheel on 22 ticks and a tooth against a wheel on four. The one eligible tooth episode scored. Cooldown or contact rearming covered the remaining tooth ticks. The probe recorded no rear reach-gate rejection. The relative opportunities came from alignment and which surfaces met.

Riptide opens at an angle, looks for a flank, commits to a short pass and peels away to let the saw recover. Bulldozer realigns before charging, holds a lane with limited steering corrections, keeps forward pressure after contact and backs off sooner when blocked. Both use the existing force and torque drive. New trajectories exposed deep solver readings in crossed tire and drum contacts. Riptide's four tire colliders now use inscribed convex profiles with the same radius and width, within 1.6 mm of the previous circular surface. The solver still uses the fitted weapon contacts and the same 180 Hz rate.

Chassis and support strikes wear the armour material. A strike's actual wheel collider identifies the affected wheel and applies a capped drive and steering penalty. Support strikes can slow the weapon and eventually disable scoring while the rotor winds down. Low health triggers intermittent smoke. All damage states are local to the match. The armour and wheels use runtime material treatments on the existing models. The first version has no mesh deformation or detached parts. The weapon icons are drawn in the HUD.

- Nine [focused checks](fixtures.log) passed, including the original collision and knockout cases, wheel penalty, disabled weapon blocking without scoring, notification queue and fresh match reset.
- [Twelve seeded matches](headless-results.json) passed. Both robots scored in each sampled match. Bulldozer won 11 and Riptide won seed 3. Seed 3 produced a real weapon disable and no later damage from that weapon. The sample favours Bulldozer and does not establish roster balance.
- Peak weapon contact depth was under 100 mm, the longest reported depth above 25 mm was 83 ms, and the last tick of all 12 matches had zero reported weapon depth. Clean seed 25 matched its headless event log.
- On the RTX 5070 Ti, three alternating uncapped seed-25 runs gave median p95 frame times of 2.56 ms for R03 and 3.02 ms for R04. The extra 0.46 ms still leaves both well within the 33.3 ms frame budget at 30 fps. This comparison measures the new fight and rendering workload together.

Re-run from the project folder with the Godot executable set as in START_HERE.

```powershell
& $godot --headless --path . --fixed-fps 60 --quit-after 900 --script tools/verify_combat.gd
python tools/verify_matches.py --godot $godot --seeds 1 2 3 4 5 7 13 17 23 25 29 32
```
