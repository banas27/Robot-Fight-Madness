# Riptide rail escape experiment

**Retain baseline.** Rail Exit reduced pin time and improved damage exchange on the development set. In the fresh evaluation, its mean net damage fell by 7.9 HP per fight, rail pin time rose, and the sustained rail exit rate improved by 2.2 percentage points. This falls short of the [preregistered criteria](PROTOCOL.md). The tested policy and seed list were committed as `94ff4a83638cefc2c5489e4aac609eed0fe95708` before running the reserved set.

| Riptide metric | Development baseline | Development Rail Exit | Reserved baseline | Reserved Rail Exit |
| --- | ---: | ---: | ---: | ---: |
| Wins / draws, 40 fights per policy | 6 / 0 | 7 / 0 | 13 / 0 | 9 / 0 |
| Mean HP damage dealt / received | 59.58 / 110.25 | 66.85 / 103.60 | 72.23 / 101.48 | 66.70 / 103.85 |
| Mean net HP damage | −50.68 | −36.75 | −29.25 | −37.15 |
| Side or rear hits | 7 | 14 | 8 | 10 |
| Damaging attack passes / attempts | 65 / 158 | 73 / 186 | 77 / 178 | 76 / 179 |
| Mean time pinned against a rail | 0.619 s | 0.458 s | 0.327 s | 0.454 s |
| Recoveries that opened a gap | 121 / 227 | 148 / 239 | 128 / 209 | 140 / 225 |
| Sustained rail exits / observed rail recoveries | 53 / 101 | 61 / 99 | 37 / 63 | 50 / 82 |
| Re-pins / rail exits with complete follow-up | 2 / 56 | 1 / 67 | 0 / 42 | 0 / 53 |
| Retreat share | 38.12% | 37.48% | 33.08% | 37.62% |
| Fights with solver flags | 1 | 2 | 0 | 0 |

On reserved standard starts, net damage moved from −22.0 to −21.5 HP and pin time rose from 0.147 to 0.292 s. On swapped starts, net damage fell from −36.5 to −52.8 HP and pin time rose from 0.507 to 0.617 s. The damage, pinning, sustained escape and retreat gates failed. Re-pinning and the reserved solver flag count passed. Raw reports and traces are local. [Development JSON](development/summary.json), [reserved JSON](evaluation/summary.json)

## Diagnosis

- The previous candidate’s seed 25 had two attacks, at 1.56–1.92 s and 19.89–20.14 s of combat. Across the fight, all saw weapon contacts were clashes. Its zero damage reflects the absence of saw-to-body tooth contact. Baseline reached the front supports at 5.79 and 8.37 s and dealt 45 HP. [Previous candidate trace](diagnosis/candidate-25.trace.json), [baseline trace](diagnosis/baseline-25.trace.json)
- At 8.07 s, the previous candidate entered recovery under rail pressure with two severely damaged wheels and 0.72 drive grip. Both chosen routes pointed almost straight along the rail. From 8.2 to 9.4 s, the sampled order stayed at 0 m/s and 4.85 rad/s yaw, with actual yaw at roughly 0–0.07 rad/s. The gap gained 0.13 m. Its earlier escape at 6.46 s gained 0.59 m but lost the sustained clearance window. In seed 13 the same policy could land a side hit at 6.31 s, then open 0.88 m of sustained clearance. [Seed 25 trace](diagnosis/candidate-25.trace.json), [seed 13 trace](diagnosis/candidate-13.trace.json)
- Rail Exit changes the baseline’s direction and gear choice only when a recovery starts near a rail under pressure. It scores short turns in both gears using current wheel grip, space for the initial motion, projected separation, and the previous failed direction. At the identical first seed 25 rail entry at 2.628 s, baseline chose forward and gained 0.46 m. Rail Exit chose reverse and gained 0.70 m. Both held the clearance window. [Baseline recovery](development/baseline/standard/25.trace.json), [Rail Exit recovery](development/rail-exit/standard/25.trace.json)

## Wheel and drum core contact

The previous candidate’s swapped seed 166 reproduced the 0.201 m manifold depth at 17.711 s. Both bodies reported the same wheel–core pair. A separate query of those exact collider shapes at the sampled pose confirmed intersection at zero offset and at 0.05 m along the reported normal. The pair cleared by 0.10 m along that axis. The match’s longest run above 0.025 m was two 180 Hz ticks. The intersection was physical, and the manifold depth was larger than the distance needed to separate that sampled pair. [Outlier trace](diagnosis/candidate-166-swapped.trace.json), [Godot shape-query reference](https://docs.godotengine.org/en/4.3/classes/class_physicsdirectspacestate3d.html)

Rail Exit also exposed a development contact regression. On swapped seed 15, the wheel and core intersected at 23.228 s with a 1.127 m manifold reading. The same pair cleared in the query after 0.20 m of downward translation of the wheel, compared with 0.10 m that still intersected. Swapped seed 4 logged a 0.176 m core contact with no intersection of the reported pair at the queried pose. A separate physics pass should isolate wheel–core penetration and validate the manifold depth measurement against the corresponding solver pose. [Seed 15 trace](diagnosis/rail-exit-15.trace.json), [seed 4 trace](diagnosis/rail-exit-4.trace.json)

## Reproduce and review

From the project root, with `$godot` set to the Godot 4.7.2 executable used by the recording launcher, run these PowerShell commands.

```powershell
$qa = 'qa/riptide-ai/experiment-02'
py tools/evaluate_riptide.py --godot $godot --seed-manifest "$qa/seeds.json" --split development --variants baseline rail-exit --output "$qa/development"
py tools/evaluate_riptide.py --godot $godot --seed-manifest "$qa/seeds.json" --split evaluation --variants baseline rail-exit --output "$qa/evaluation"
py tools/evaluate_riptide.py --godot $godot --split parity --variants baseline candidate rail-exit --output "$qa/parity"
& $godot --headless --path . --fixed-fps 60 --script res://tools/verify_combat.gd -- --riptide-ai=baseline
New-Item -ItemType Directory -Force "$qa/diagnosis" | Out-Null
& $godot --headless --path . --fixed-fps 30 -- --combat-only --riptide-ai=candidate --seed=166 --swap-start --contact-trace "--trace=$qa/diagnosis/candidate-166-swapped.trace.json" "--report=$qa/diagnosis/candidate-166-swapped.match.json"
.\Record-Fight.ps1 -Godot $godot -Seed 25 -RiptideAI rail-exit
```

All 15 existing combat checks passed. Twelve episode-versus-headless pairs matched across both layouts and all three policies. Each pair’s combat report also matched its untraced and detailed-contact runs. The rendered candidate combat events matched headless for both review seeds. [Parity JSON](parity/summary.json)

Each full MP4 decoded to 1,201 frames at 720 × 1280 and 30 FPS with combat audio. The comparison is 6.80 s. Seed 25 emitted Godot’s vector normalization fallback warning, also seen in earlier recordings.

- [Seed 25 episode](../../../renders/riptide-rail-exit/rail-exit-seed-25.mp4). Bulldozer won on health, 200/200 to 27/150.
- [Seed 13 episode](../../../renders/riptide-rail-exit/rail-exit-seed-13.mp4). Bulldozer won on health, 131/200 to 54/150.
- [Seed 25 comparison](../../../renders/riptide-rail-exit/seed-25-rail-comparison.mp4). The two labeled excerpts show different rail recoveries in the same seed. Baseline gained 0.03 m after the recovery at 13.69 s, and Rail Exit gained 1.05 m after the recovery at 14.54 s.

Recordings are local under `renders/riptide-rail-exit`. Raw diagnostics are local under `qa/riptide-ai/experiment-02`. The repository carries the source, seed list, protocol and this summary.
