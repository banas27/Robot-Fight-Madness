# Riptide routes experiment 02

**Keep original Riptide against baseline tracked Bulldozer.** The `tracked-routes` revision converted more attacks and improved the damage exchange against both frozen opponents. It missed the recovery criteria against both. Against `tracked-intercept`, it was easier to catch again than original Riptide and spent more than half the fight retreating. Keep the revision selectable for comparison.

The experiment started from `6d59c0b6ce46ae8158984bb0821e235780eeaed6`, which records the earlier candidate freeze at `3f10b3418647b40e94d7863a911d23f583a08813`. The route revision, controls and [protocol](PROTOCOL.md) were frozen at `ef12b2f942bcff8aaf22f1f8bf1fec14810a539e` before the clean 240-fight reserved run. The six pairings shared all seeds and both start layouts. Those [reserved seeds](seeds-reserved.json) are now known cases. The release continues to select the wheeled arena and original AI.

## Diagnosis and revision

- **Openings and alignment.** Standard 13 and 25 showed useful shoulder entries and scored support hits with `tracked-flank` against baseline Bulldozer. Standard 36157 also landed a genuine side hit. The same approach against `tracked-intercept` converted zero of 20 passes in the 14 diagnostic starts. Standard 7698's first cut ended at 2.19 s, 0.24 s into its commitment, with the center gap still 2.94 m. The nose-angle cutoff ended the approach before contact. Seed 95440 committed once and 3005 once. Escape changes alone could not fix missing attacks.
- **Exit and re-entry.** On 7698 against baseline, the first scored hit was followed by a forward exit that gained no gap and carried Riptide toward the end rail. Later at 8.88 and 11.73 s, rail recoveries gained essentially zero gap. The 8.88 s replan selected nearly the same reverse heading. Near the rail, later wheel damage cut available grip and further narrowed the feasible turns. The recorded problem includes early re-entry, repeat routes and blocked translation, with much less evidence of free-space spinning as the primary cause.
- **Recovery control.** `recovery-control` calls the original recovery target scorer and drive controller, preserving the original gap/travel checks, timing and one replan. On completion it returns to the candidate's approach instead of installing the original flank target. This diagnostic preserves the original escape scorer's opponent weapon-condition read. The new revision uses only observed opponent pose and velocity, contact, and its own capabilities.
- **Tracked-routes.** Retains saw readiness and alignment, checks approximate footprint and rail room on the approach and at the projected exit, and scores lanes that avoid the drum's approach path. An aligned cut gets more time to reach the target unless the cut angle or closing lane actually breaks down. Recovery scores a small set of forward, reverse and inward lanes against the predicted opponent and available turning room. It penalizes recently blocked directions, measures progress from the current leg, and allows time for initial opposing momentum to decay before replanning. Movement, scoring and weapon contact rearm use the existing simulation. The route test is a planar estimate and can still select a lane that body contact blocks.

| Development, 40 starts per row | Riptide policy | HP dealt / received | Damaging passes / attempts | Sustained escapes % | Loop links per fight |
| --- | --- | ---: | ---: | ---: | ---: |
| Baseline opponent | Baseline | 83.8 / 93.2 | 82/178 | 43.87 | 0.40 |
| Baseline opponent | Tracked-flank | 71.3 / 97.5 | 100/166 | 11.88 | 3.35 |
| Baseline opponent | Recovery control | 89.7 / 84.1 | 133/209 | 21.60 | 1.48 |
| Baseline opponent | Tracked-routes | 93.5 / 87.8 | 135/181 | 11.22 | 3.95 |
| Tracked-intercept | Baseline | 47.3 / 129.4 | 55/144 | 10.34 | 0.75 |
| Tracked-intercept | Tracked-flank | 8.9 / 132.7 | 6/62 | 2.35 | 4.33 |
| Tracked-intercept | Recovery control | 20.0 / 126.4 | 15/82 | 9.32 | 4.45 |
| Tracked-intercept | Tracked-routes | 81.3 / 88.1 | 104/140 | 8.70 | 4.73 |

Against baseline, restoring the old escape controller improved recovery and kept the candidate's conversion benefit. Against `tracked-intercept`, it still barely scored. The revision fixed much of the attack deficit. Development showed that the recovery problem persisted, particularly when contact had already removed the room to turn.

## Reserved results

Each column contains 40 fights. The left group faced baseline tracked Bulldozer. The right group faced `tracked-intercept`. HP and time values are per-fight means except for the stated median and percentages.

| Riptide policy | Base · baseline | Base · tracked-flank | Base · tracked-routes | Intercept · baseline | Intercept · tracked-flank | Intercept · tracked-routes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Wins Riptide/Bulldozer/draw | 15/25/0 | 19/21/0 | 22/18/0 | 8/31/1 | 0/40/0 | 9/31/0 |
| Remaining HP % Riptide / Bulldozer | 36.95 / 65.75 | 41.42 / 55.60 | 43.05 / 43.99 | 25.82 / 71.70 | 11.33 / 95.16 | 30.88 / 72.54 |
| HP dealt / received | 68.5 / 94.6 | 88.8 / 87.9 | 112.0 / 85.4 | 56.6 / 111.3 | 9.7 / 133.0 | 54.9 / 103.7 |
| Damaging passes / attempts | 76/187 | 132/211 | 177/229 | 64/138 | 8/67 | 85/120 |
| Pass conversion | 40.64% | 62.56% | 77.29% | 46.38% | 11.94% | 70.83% |
| Genuine side/rear hits | 15 | 12 | 9 | 4 | 1 | 15 |
| Recoveries per fight | 5.68 | 10.23 | 10.45 | 5.80 | 8.30 | 10.33 |
| Sustained escapes / attempts | 98/227 | 60/409 | 54/418 | 36/232 | 9/332 | 19/413 |
| Rapid recaptures / observed separations | 24/139 | 45/152 | 56/189 | 16/71 | 25/37 | 44/79 |
| Repeated recovery links per fight | 0.33 | 3.10 | 2.95 | 0.68 | 3.88 | 5.30 |
| Physical pin, s | 0.25 | 0.86 | 1.14 | 0.56 | 1.63 | 2.31 |
| Stalled, s | 6.38 | 7.32 | 6.51 | 8.54 | 8.42 | 9.66 |
| Next damage, observed median s | 2.04 | 3.04 | 2.67 | 4.28 | 6.94 | 5.16 |
| Next damage unobserved at end | 77 | 120 | 90 | 113 | 258 | 235 |
| Retreat, s / share | 9.04 / 37.50% | 11.24 / 47.79% | 11.62 / 50.06% | 8.88 / 39.92% | 9.88 / 46.64% | 12.63 / 54.62% |
| Fights with a quiet gap ≥5 s | 29 | 22 | 24 | 26 | 19 | 31 |
| Mean longest quiet gap, s | 6.66 | 5.68 | 6.16 | 6.24 | 6.31 | 7.68 |
| Normalization warnings / solver outlier fights | 20/2 | 6/3 | 7/1 | 16/0 | 8/13 | 8/2 |

Both attack gates passed. Against baseline Bulldozer, the margin improved from −26.1 HP for original Riptide to +26.6 HP, with fewer true flank hits. Against `tracked-intercept`, the margin improved from −123.3 HP for `tracked-flank` to −48.8 HP, ahead of the original's −54.7 HP. Conversion improved in both start layouts. Against `tracked-intercept`, only the rapid recapture rate reached the required improvement, dropping 11.9 points. Physical pin time rose 0.68 s, repeated recovery links rose from 3.88 to 5.30 per fight, and retreat share and quiet gaps exceeded the limits. Against baseline Bulldozer, sustained escapes dropped and loop links fell only 4.8%. Original Riptide remains the stronger recovery choice overall.

## Verification and recordings

- All 240 reserved results completed, with zero non-finite published ticks. All 65 normalization warnings and 21 solver outliers remain in the raw evidence. The outliers were post-detachment floor collider clearance. The worst was −112 mm on swapped 852313 with both original policies. Across the suite, no fight had more than two consecutive ticks past 25 mm deck penetration. No depth, sustained weapon overlap, speed, lift or containment review threshold was exceeded. Floor values are collider measurements. Visible floor clipping was outside this review.
- Passed 15 combat checks, 17 track checks and the damaged-drive suite, including the new controlled rail test. With one failed wheel and a stationary drum, Riptide used the open length of the rail and created physical separation. 56 known tracked fights matched prior combat reports, and the wheeled default matched its prior report. All 24 parity cases matched traced and untraced combat-only and headless full episodes. Detailed tracing on the selected failure also matched its reserved run.
- All six source MP4s decoded completely and matched their headless combat and result. Normal episodes use 720 × 1280 at 30 FPS with both introductions, the full result and combat audio. Sample peaks during combat were −14.46 to −8.58 dBFS. Visual review used extracted frame sequences and combat timing. Audio review covered decoding and signal levels.

The following files are in `renders/riptide-routes-02/movies/`. The ignored `control`, `diagnosis`, `routes-development`, `reserved` and `parity` folders hold per-case reports, traces, warnings and summaries.

| File | Contents |
| --- | --- |
| `tracked-baseline-seed-13.mp4` | Recommended pairing. Bulldozer knocks out Riptide at 24.978 s with 153/200 HP. |
| `tracked-baseline-seed-25.mp4` | Recommended pairing. Bulldozer wins on health, 156/200 against 6/150. |
| `recovery-comparison-seed-7698.mp4` | Independent standard replays against baseline Bulldozer, combat 11–19 s from each. Pin time falls from 2.29 s to 0.41 s over the full fight. The revision disabled the drum at 10.33 s before its excerpt. The two clips have different positions and damage states. |
| `routes-vs-intercept-seed-745273-swapped.mp4` | Tracked-routes against tracked-intercept. A real left-belt hit at 4.589 s is followed by renewed rail pressure and a 43/150 to 134/200 loss. |
| `remaining-failure.mp4` | Standard 867307, tracked-routes against tracked-intercept. Combat 5–15 s shows a brief gap, repeated recapture and wheel drive failure. Riptide spent 14.25 s pinned overall. After 13 s, it alternated forward and reverse orders with nearly zero motion. |

## Reproduce

Run from the tracked worktree with Godot 4.7.2 and FFmpeg. Check out the frozen candidate commit to reproduce the reserved evaluation.

```powershell
$root = 'renders/riptide-routes-02-replay'
New-Item -ItemType Directory -Force $root | Out-Null
$controls = @('baseline-base','tracked-flank-base','control-base','baseline-intercept','tracked-flank-intercept','control-intercept')
py tools/evaluate_riptide_routes.py --godot $godot --split diagnostic --contacts --pairings @controls --output "$root/diagnosis"
py tools/evaluate_riptide_routes.py --godot $godot --split development --pairings @controls --output "$root/control"
py tools/evaluate_riptide_routes.py --godot $godot --split development --pairings tracked-routes-base tracked-routes-intercept --output "$root/routes-development"
py tools/evaluate_riptide_routes.py --godot $godot --split reserved --output "$root/reserved"
py tools/evaluate_riptide_routes.py --godot $godot --split parity --contacts --output "$root/parity"

& $godot --headless --path . --fixed-fps 60 --script res://tools/verify_combat.gd
& $godot --headless --path . --fixed-fps 60 --script res://tools/verify_tracks.gd
& $godot --headless --path . --fixed-fps 60 --script res://tools/verify_tracked_ai.gd -- --riptide-ai=tracked-routes --bulldozer-ai=tracked-intercept

$scene = 'res://scenes/review/arena_tracked_bulldozer_test.tscn'
$seed = 25
$saw = 'baseline'
$drum = 'baseline'
$layout = @()
$stem = "$root/seed-$seed-$saw-$drum"
& $godot --path . --resolution 720x1280 --fixed-fps 30 --quit-after 1350 --write-movie "$stem.avi" $scene -- --autostop "--seed=$seed" "--riptide-ai=$saw" "--bulldozer-ai=$drum" "--report=$stem.match.json" @layout
& $ffmpeg -i "$stem.avi" -c:v libx264 -preset fast -crf 20 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart "$stem.mp4"
py tools/verify_release_video.py --ffmpeg $ffmpeg --tracked-policies $saw $drum --output "$stem.video.json" --case "$stem.mp4" "$stem.match.json"
```

Use seed 13 with the same pairing for the second episode. Use seed 7698 with `tracked-flank` and `tracked-routes` separately for the comparison. Use `tracked-routes` and `tracked-intercept` for 745273 with `$layout = @('--swap-start')`, or 867307 in standard layout. Add `--trace=<file> --contact-trace` to a headless launch for component, route and contact samples.
