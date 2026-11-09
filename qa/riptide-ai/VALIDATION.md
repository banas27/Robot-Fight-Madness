# Riptide flank and escape evaluation

**Keep the baseline active.** On the reserved seeds, the candidate turned more committed passes into actual side hits and separated more often. It dealt 15.8 less HP damage per fight, spent longer near the drum at low speed, and spent over three times as long in physical rail pins. The win count was the same. The overall exchange does not justify switching the default or changing the robot stats.

| Riptide metric | Development baseline | Development candidate | Evaluation baseline | Evaluation candidate |
| --- | ---: | ---: | ---: | ---: |
| Wins / fights, no draws | 6 / 40 | 5 / 40 | 10 / 40 | 10 / 40 |
| Mean HP remaining, Riptide / Bulldozer | 26.5% / 70.2% | 21.8% / 79.8% | 28.0% / 65.8% | 28.9% / 73.7% |
| Mean HP damage dealt / received | 59.6 / 110.3 | 40.5 / 117.4 | 68.4 / 108.0 | 52.6 / 106.6 |
| Committed passes that hit / attempts | 65 / 158 | 64 / 129 | 67 / 175 | 98 / 140 |
| Intended flanks with a side/rear hit / attempts | 3 / 158 | 11 / 17 | 6 / 175 | 18 / 23 |
| Actual side/rear hits / all saw hits | 7 / 108 | 14 / 80 | 13 / 128 | 18 / 107 |
| Mean stalled near opponent / rail pin | 6.54 / 0.62 s | 7.91 / 1.27 s | 5.92 / 0.29 s | 6.42 / 0.97 s |
| Recoveries that separated / attempts | 121 / 227 | 134 / 250 | 118 / 209 | 161 / 257 |
| Mean retreat / share of fight | 9.07 s / 38.1% | 9.99 s / 42.1% | 8.66 s / 36.9% | 9.65 s / 41.3% |

Each split uses 20 fixed seeds in both starting layouts. The swapped layout rotates both seeded poses 180° around the arena centre, keeping their relative positions and the same fighter insertion order. The evaluation gain in side/rear hits came from swapped starts (4 to 10). Standard starts went from 9 to 8. Candidate damage fell in both layouts. Only development traces informed tuning. The [candidate fingerprint](candidate.sha256) was saved before running evaluation. These evaluated seeds are now known cases. [Seed lists](seeds.json), [development evidence](development/summary.json), [evaluation evidence](evaluation/summary.json)

## Diagnosis and candidate

In baseline seed 25, Riptide entered its first attack while facing away from the target (forward-to-target dot −0.14), with Bulldozer still facing it (0.95). Its two scored hits landed on the front supports. At 13.69 seconds of combat, another exit gained only 0.03 m of separation. Seed 13 showed the same pattern of early commitments, front-support hits and exits with reduced drive. [Seed 25 baseline trace](development/baseline/standard/25.trace.json), [seed 13 baseline trace](development/baseline/standard/13.trace.json)

The candidate steers around the nose using short motion estimates, tests wall room, checks saw alignment and readiness before committing, and holds the attack aim through a bounded pass. It can take an exposed shoulder when a flank closes, with that intent tracked separately. A hit, miss or blocked pass triggers recovery. Exit selection estimates turn and travel time for forward and reverse drive, using remaining traction and rejecting recent blocked routes. These orders use the existing motors, colliders, weapon rules and capability states. The default baseline policy is the original robot script.

In the isolated fixtures, both policies landed side hits on the stationary target and with one failed wheel. Both opened a gap near the rail, with the candidate landing a subsequent side hit. The candidate cleared the moving charge without contact during the 1.25-second fixture. The baseline took 25 HP damage. These fixtures isolate decisions. The full-fight results determine adoption. [Baseline fixtures](scenarios-baseline.json), [candidate fixtures](scenarios-candidate.json)

## Recordings and checks

- [Seed 25 candidate episode](../../renders/riptide-ai/candidate-seed-25.mp4). Bulldozer won on health at 200/200 versus 33/150. The [7.57-second failure clip](../../renders/riptide-ai/failure-seed-25-exits.mp4) shows Riptide getting caught near the rail with degraded drive. Its first failed exit in that excerpt opened only 0.13 m of gap. [Trace](development/candidate/standard/25.trace.json)
- [Seed 13 candidate episode](../../renders/riptide-ai/candidate-seed-13.mp4). Bulldozer won on health at 124/200 versus 63/150. Riptide hit the side at 6.31 seconds of combat and opened 0.88 m of gap on that recovery. [Trace](development/candidate/standard/13.trace.json)
- Both normal episodes have 1,201 frames at 720 × 1280 and 30 FPS with the existing combat audio. Both decoded successfully, and their combat events match the corresponding headless runs. Seed 25 logged the existing Godot vector normalization fallback warning.
- Fifteen existing combat checks passed with the baseline. The evaluation candidate stayed within the existing speed, lift, containment and sustained-contact limits. Swapped seed 166 had one flagged peak weapon-depth reading of 0.201 m. The candidate's longest run over 25 mm across the evaluation set was 0.028 s. Swapped development seed 21 also flagged a peak for the baseline (0.181 m).

## Repeat the comparison

From the project root, use the same Godot executable as the recording launcher. Reports and private decision traces are written as separate JSON files under each policy and layout.

```powershell
py tools/evaluate_riptide.py --godot $godot --split development --output qa/riptide-ai/development
py tools/evaluate_riptide.py --godot $godot --split evaluation --output qa/riptide-ai/evaluation
py tools/evaluate_riptide.py --godot $godot --split parity --output qa/riptide-ai/parity
& $godot --headless --path . --fixed-fps 30 --script res://tools/verify_riptide.gd -- --riptide-ai=candidate
.\Record-Fight.ps1 -Godot $godot -Seed 13 -RiptideAI candidate
```

Use `--variants baseline` to trace the original policy alone or `--layout standard` for one starting layout. The harness uses the normal 180 Hz solver. The headless runs omit the rendered opening, audio and showcase. They keep the frozen opening ticks because launching combat on the first physics tick caused a later contact divergence despite identical spawn poses. All eight parity pairs produced identical combat reports and traces (seeds 25 and 13, both layouts and policies). The two baseline standard-start reports also match the prior recordings' combat events. [Parity evidence](parity/summary.json)

- A committed pass is one entry into `ATTACK`. It succeeds if it scores damage before exit. The baseline labels these as flank intent. The candidate separately labels the fallback shoulder passes. Strikes while repositioning, recovering or pressing a disabled weapon still count in all-hit totals.
- Hit zone comes from the solver contact point in the defender's local horizontal frame. Bearing from its nose is front below 60°, side from 60° to below 135°, and rear at 135° or more. A flank conversion is a committed pass with at least one side or rear strike. HP damage is actual HP lost, capped by health remaining.
- Stall time counts low-speed spells of at least 0.35 s within 3.15 m, below 0.65 m/s, while contacting a body or rail or running an attack, approach or recovery. Rail pin time requires simultaneous rail and opponent contact. A recovery succeeds if contact clears for 0.13 s, the gap grows by at least 0.45 m, and Riptide moves at least 0.35 m from its recovery origin. Retreat time counts recovery and dodge orders, which can still produce incidental tooth hits.

The pre-change source and assets are saved in `D:/RobotFightStudio/checkpoints/before-riptide-ai-r08`, following the existing local checkpoint workflow.
