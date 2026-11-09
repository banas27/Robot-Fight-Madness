# Arena space experiment

**Use the larger arena with `tracked-routes` for the next tracked test.** The larger floor reduced Riptide's stalls and physical pins under both policies. With `tracked-routes`, attacks converted more often, recovery loops fell and quiet gaps shortened. Its 37–3 record is a strong tilt in this particular matchup, and sustained escapes still account for only 13.2% of recovery attempts. Keep the current arena available as the comparison scene. The release still uses its current wheeled arena and original policies.

The experiment starts at `9f9348174c0c9d731ffa13951a5ec7b6b4155d41` and uses the Riptide candidate frozen at `ef12b2f942bcff8aaf22f1f8bf1fec14810a539e`. The implementation, measurements and [fresh confirmation manifest](seeds-confirmation.json) were frozen at `0decb3b344466c3b6b4831ade9bad0196a1e163d` after the diagnostic review. All four pairings used baseline functional tracked Bulldozer. [Protocol](PROTOCOL.md)

## Dimensions and framing

| Arena | Clear interior width × length | Usable floor |
| --- | ---: | ---: |
| Current | 7.900000 × 10.300000 m | 81.37 m² |
| Larger | 11.172287 × 14.566400 m | 162.74 m² |

The exact configured dimensions of the larger floor are (7.9 × √2) by (10.3 × √2). Rays against the actual collider faces measured 7.8999996 × 10.3000002 m and 11.1722870 × 14.5663996 m, within Godot's floating point precision. Rail colliders remain 0.30 m thick and 0.65 m tall. The deck collision reaches all four corners at the original height. Floor seams and rail stripes extend at their original spacing, and the centre circle and spawn bars stay fixed. Both AI policies and containment read the new rail centres through the existing bounds.

Both scenes use the same robot dimensions and starting transforms. Each seed and layout produced identical recorded start positions, headings, HP and rotor state across the four pairings. Spawns retain their ±3.4 m longitudinal positions and seeded lateral offsets. The policies, track mechanics, solver settings and damage rules are shared.

The larger arena uses the original camera follow and default zoom range. A projected clearance check allows extra width only if the standard shot cannot fit both fighter envelopes. The corner stress fixture needs this extra width. The three recorded larger-arena fights never needed it. Their widest combat view was 12.47 m, and the estimated fighter envelopes stayed at least 88 px from a viewport edge at 720 × 1280. The frame review showed both fighters and weapons in view while some rail segments extend offscreen. Intro shots, HUD, result showcase and audio use the normal presentation.

## Matched confirmation

Twenty fresh seeds ran in both layouts for each pairing, for 160 fights total. All cells contain 40 fights. Times are per-fight means unless marked as pooled or median. Combat statistics for both fighters are in the local raw evidence.

| Metric | Current · baseline | Larger · baseline | Current · tracked-routes | Larger · tracked-routes |
| --- | ---: | ---: | ---: | ---: |
| Wins Riptide / Bulldozer / draws | 18/22/0 | 31/9/0 | 17/23/0 | 37/3/0 |
| Remaining HP % Riptide / Bulldozer | 41.40 / 56.33 | 71.00 / 45.03 | 34.48 / 51.54 | 76.50 / 11.04 |
| HP damage Riptide dealt / received | 87.35 / 87.90 | 109.95 / 43.50 | 96.93 / 98.28 | 177.93 / 35.25 |
| Riptide damaging passes / attempts | 87/172 | 90/196 | 147/195 | 309/379 |
| Riptide conversion | 50.58% | 45.92% | 75.38% | 81.53% |
| Bulldozer damaging passes / attempts | 114/135 | 56/63 | 133/151 | 48/53 |
| Bulldozer conversion | 84.44% | 88.89% | 88.08% | 90.57% |
| Riptide true side or rear hits | 24 | 12 | 15 | 27 |
| Riptide physical pin / stall, s | 0.316 / 6.285 | 0.035 / 2.890 | 1.501 / 7.371 | 0.023 / 2.073 |
| Bulldozer physical pin / stall, s | 0.011 / 3.611 | 0.000 / 4.854 | 0.000 / 2.139 | 0.000 / 1.888 |
| Riptide sustained escapes / attempts | 94/219 (42.92%) | 81/189 (42.86%) | 62/413 (15.01%) | 52/395 (13.16%) |
| Riptide rapid recaptures / observed | 22/129 | 20/140 | 53/179 | 14/330 |
| Riptide repeated recovery links | 12 | 1 | 127 | 9 |
| First damage, median s (40/40 observed) | 1.639 | 1.628 | 2.250 | 2.250 |
| Completed exchange gap, pooled s (count) | 2.685 (286) | 2.642 (261) | 2.580 (309) | 2.101 (354) |
| Fights with quiet gap ≥5 s | 25 | 25 | 25 | 9 |
| Longest quiet gap, s | 6.358 | 7.689 | 6.488 | 4.489 |
| Riptide retreat, s / share | 8.397 / 34.73% | 5.548 / 22.33% | 11.577 / 49.26% | 8.736 / 40.94% |
| Time limit outcomes | 33 | 39 | 25 | 10 |
| Normalization warnings / solver outlier fights | 16 / 1 | 42 / 0 | 9 / 2 | 6 / 0 |

With baseline Riptide, the larger floor reduced stalls by 54% and recovery loops from 12 to one. Its sustained escape rate stayed level. The 1.33 s increase in mean longest quiet gap crossed the preset pacing threshold, and side/rear hits halved.

With `tracked-routes`, stalls fell by 72%, physical pin time by 98% and repeated recovery links from 127 to nine. Its first hit arrived at the same median time and the mean longest gap shortened by 2.00 s. The one-second sustained escape rate fell 1.85 points even as rapid recaptures fell from 29.6% to 4.2%. Twenty-three larger-arena separations ran out of follow-up time, compared with five in the current arena. The revision's shorter time to the next damage event and more frequent knockouts are relevant to those recovery measures. Both start layouts showed the same direction of change in Riptide's pin and stall times. Bulldozer committed to 53 passes on the larger floor against `tracked-routes`, down from 151, and landed fewer true side or rear hits, 14 versus 64.

## Checks and recordings

- Both arena variants passed floor and rail probes, AI bound checks and reload and scene switching checks. The larger scene passed the corner framing stress fixture. The 15 existing combat checks and 17 track checks passed.
- All 16 parity cases agreed across traced and untraced headless runs with and without presentation phases. Twelve current-arena diagnostic fights matched prior combat reports. The wheeled default also matched its prior report. All four video sources decoded and matched the corresponding headless fight and result.
- All 160 confirmation fights completed with zero non-finite published ticks. All 73 engine normalization warnings and three floor-collider outliers remain in the evidence. The worst floor measurement was −48.7 mm on current-arena `tracked-routes`, standard 4068382. The longest run deeper than 25 mm was one tick. No weapon-depth, speed, lift or containment threshold was exceeded. Collider depth is distinct from visible floor clipping.
- Standard 337082 is the prior same-policy recovery failure. Current arena Riptide spent 4.65 s pinned and logged nine recovery links. The larger replay had zero physical pin time and Riptide won by knockout at 20.933 s. The comparison shows combat seconds 8–17 from each independent replay. Damage and positions had already diverged, and Bulldozer's drum stopped at 11.85 s in the larger replay.
- The two full larger-arena episodes show Riptide knocking out Bulldozer at 17.911 s in seed 13 and 23.594 s in seed 25. Both retain the complete intros and result. Combat audio across the four sources peaked from −13.08 to −6.74 dBFS. Review used extracted frame sequences, event timing and signal checks.

Videos and framing reports are in the ignored `renders/arena-space-test/final/` folder. The requested files are `larger-routes-seed-13.mp4`, `larger-routes-seed-25.mp4` and `arena-comparison-seed-337082.mp4`. Per-fight JSON, traces and warnings are in `renders/arena-space-test/confirmation/`, `diagnostic/` and `parity/`.

## Reproduce

Use Godot 4.7.2 from the tracked worktree. Run the confirmation at the frozen commit in a clean checkout.

```powershell
$root = 'renders/arena-space-test-replay'
New-Item -ItemType Directory -Force $root | Out-Null
py tools/evaluate_arena_space.py --godot $godot --split diagnostic --contacts --output "$root/diagnostic"
py tools/evaluate_arena_space.py --godot $godot --split reserved --output "$root/confirmation"
py tools/evaluate_arena_space.py --godot $godot --split parity --contacts --output "$root/parity"
& $godot --headless --path . --resolution 720x1280 --fixed-fps 60 --script res://tools/verify_arena_space.gd
& $godot --headless --path . --fixed-fps 60 --script res://tools/verify_combat.gd
& $godot --headless --path . --fixed-fps 60 --script res://tools/verify_tracks.gd

$scene = 'res://scenes/review/arena_tracked_bulldozer_large.tscn'
$seed = 13
$stem = "$root/larger-routes-seed-$seed"
& $godot --path . --resolution 720x1280 --fixed-fps 30 --quit-after 1350 --write-movie "$stem.avi" $scene -- --autostop "--seed=$seed" --riptide-ai=tracked-routes --bulldozer-ai=baseline "--report=$stem.match.json" "--perf=$stem.framing.json"
& $ffmpeg -i "$stem.avi" -c:v libx264 -preset fast -crf 20 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart "$stem.mp4"
py tools/verify_release_video.py --ffmpeg $ffmpeg --tracked-policies tracked-routes baseline --output "$stem.video.json" --case "$stem.mp4" "$stem.match.json"
```

Select `res://scenes/review/arena_tracked_bulldozer_test.tscn` for current dimensions. Select `--riptide-ai=baseline` for original Riptide. Use standard layout for the three deliverable seeds and add `--swap-start` for paired swapped runs. For the comparison, record seed 337082 once in each scene and take nine seconds from episode time 18.0 s, with the current arena first.
