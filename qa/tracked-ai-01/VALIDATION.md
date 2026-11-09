# Tracked AI experiment 01

**Retain both baseline policies for the proposed tracked pairing.** Riptide's candidate improves attack conversion and damage exchange on the reserved starts. It still gets caught at the rail more often and completes fewer sustained exits. Bulldozer's candidate produces a much better damage exchange with less ineffective push time on the reserved starts. Its conversion drops beyond the preset limit, and the earlier development runs showed longer ineffective pushes. Both candidates remain selectable for follow-up work. The wheeled release still uses the original policies.

Frozen track baseline `4dadb397d17ea72863883373ff8902b5898ef044`. Candidate source and preregistration `3f10b3418647b40e94d7863a911d23f583a08813`. The reserved suite ran from that clean commit. No policy was changed after opening the results. [Metrics and adoption gates](PROTOCOL.md) · [Development seeds](../riptide-ai/seeds.json) · [Reserved seeds](seeds-reserved.json)

## Diagnosis and policy changes

- **Riptide.** In standard seed 13, four baseline attacks began with forward-to-target dots between −0.54 and −0.31. It took wheel damage at 1.59 s and 5.32 s, and both its damaging hits reached Bulldozer's front supports. Standard seed 25 showed the same alignment and support pattern. Detailed contact traces also distinguish weapon clashes, latched contacts, glancing teeth and eligible hits. Being near the drum did not guarantee another eligible saw strike. Seed 13 had 8.88 s stalled and only 0.18 s in simultaneous opponent and wall contact. Some reversals opened room without keeping it. Wheel grip loss and the 0.13 s weapon-contact rearm rule are physical constraints shared by both policies.
- **Tracked-flank.** Selects a reachable shoulder using the current opponent pose and bounded velocity lead, with an early lateral gate outside the closing lane. It aims at the side envelope and commits only when its own saw is ready and aligned. It exits after a scored hit, closed cut or timeout. Exit scoring accounts for rail room, remaining grip, reverse alignment and recently failed directions. A disabled saw guards its wheels. The first development iteration attempted only 23 passes in 40 fights, against the baseline's 180. Moving the gate earlier and admitting aligned outside shoulders brought this back to 162. That improved conversion and side hits on development but still lost HP exchange and stayed at the rail longer.
- **Bulldozer.** In the instrumented 40-start baseline, 122 of 141 rams scored, while 2.64 s per fight was ineffective push time and 1.11 s was productive. The approach was already effective and the main opportunity was what happened after contact. Tracked-intercept estimates lateral motion for up to 0.32 s and caps the target offset at 0.72 m. Ram and press heading corrections stay bounded around the committed heading. Non-advancing pushes trigger a short exit and realignment. One functioning belt uses translated arcs in a direction the surviving belt can turn. Losing both drives enters hold. The first development iteration still increased ineffective pushing, which prompted an earlier stall trigger and tighter heading correction during presses. Even after that adjustment the final development mean was 3.51 s.
- Original policies are preserved, including Riptide's dodge reading Bulldozer's private maneuver, charge ID and charge heading, and the base policy's opponent-weapon-disabled branch. Candidates use observed pose and velocity, contact and their own component state and hit feedback. Stats, actuators, models, collision rules, camera, presentation and audio are shared.

## Matched results

All cells cover 20 seeds in both starting layouts. HP, damage, and seconds are per-fight means unless stated. Pairs of values are Riptide / Bulldozer.

| Development | Both baseline | Riptide candidate | Bulldozer candidate | Both candidates |
| --- | ---: | ---: | ---: | ---: |
| Wins R/B, zero draws | 15 / 25 | 14 / 26 | 11 / 29 | 0 / 40 |
| HP damage dealt | 78.7 / 90.0 | 68.5 / 101.1 | 50.5 / 119.4 | 8.6 / 135.0 |
| Damaging passes / attempts, Riptide | 78/180 | 100/162 | 60/149 | 7/63 |
| Damaging passes / attempts, Bulldozer | 122/141 | 127/144 | 149/212 | 187/212 |

| Reserved | Both baseline | Riptide candidate | Bulldozer candidate | Both candidates |
| --- | ---: | ---: | ---: | ---: |
| Wins R/B/draw | 11/29/0 | 18/22/0 | 1/39/0 | 0/40/0 |
| HP remaining % | 32.25 / 65.35 | 49.78 / 54.56 | 5.50 / 82.40 | 4.55 / 95.49 |
| HP damage dealt | 69.30 / 101.63 | 90.88 / 75.33 | 35.20 / 141.75 | 9.03 / 143.18 |
| Damaging passes / attempts, Riptide | 81/172 | 138/237 | 46/136 | 2/50 |
| Damaging passes / attempts, Bulldozer | 134/148 | 99/122 | 175/214 | 182/193 |
| Genuine side/rear hits | 10 / 82 | 15 / 51 | 2 / 83 | 0 / 112 |
| Weapon clashes | 299 | 261 | 521 | 298 |
| Productive push, s | 0.16 / 1.22 | 0.21 / 0.36 | 0.01 / 1.28 | 0.10 / 0.84 |
| Ineffective push, s | 3.10 / 3.13 | 3.19 / 3.14 | 0.58 / 2.55 | 2.35 / 4.42 |
| Physical pin, s | 0.18 / 0.01 | 0.60 / 0.00 | 0.59 / 0.00 | 1.18 / 0.00 |
| Stalled, s | 6.65 / 3.77 | 5.63 / 2.64 | 7.32 / 1.00 | 8.35 / 1.88 |
| Retreat, s | 9.26 / 4.58 | 10.10 / 3.71 | 9.27 / 2.49 | 9.46 / 2.92 |
| Recovery attempts | 219 / 191 | 398 / 160 | 232 / 142 | 316 / 162 |
| Opened a gap | 112 / 118 | 205 / 109 | 77 / 71 | 40 / 43 |
| Sustained exits | 105 / 104 | 89 / 97 | 49 / 33 | 18 / 0 |
| Immediate physical re-pins after separation | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| Fights with a quiet gap ≥5 s | 27 | 27 | 25 | 11 |
| Longest quiet gap, mean s | 6.34 | 6.18 | 5.65 | 5.26 |
| Normalization warnings / warned fights | 11/9 | 11/5 | 4/3 | 9/4 |
| Solver outlier fights / non-finite ticks | 4/0 | 2/0 | 8/0 | 8/0 |

Riptide's isolated HP damage margin moved from −32.3 to +15.6, improving in both layouts. Conversion rose from 47.1% to 58.2%, and genuine side/rear hits rose from 10 to 15. Physical pinning rose by 0.41 s, retreat share rose from 39.05% to 42.22%, and sustained exits fell from 105 to 89 despite many more attempts. The short physical re-pin window did not register the later re-engagement loops in the failure clip. **Keep baseline Riptide.**

Bulldozer's isolated HP damage margin improved from +32.3 to +106.6 in the reserved aggregate and improved in both layouts. Ineffective push dropped from 3.13 to 2.55 s, and the productive share rose from 28% to 33%. Conversion fell from 90.5% to 81.8%, beyond the five-point gate. Sustained exits fell from 104 to 33 and clashes rose from 299 to 521. **Keep baseline Bulldozer.** The combined pairing's 40 Bulldozer wins came with just 2 converted Riptide passes out of 50 and no genuine Riptide side/rear hits. All 20 reserved seeds are now known cases.

## Simulation and recording checks

- Passed 15 combat checks, 17 track checks, the three captured wheel–drum fixture cases and eight damaged-policy fixture assertions. One remaining belt produced a translated turn with the opposite motor failed or belt thrown. The damaged Riptide fixture scored on a stationary side and entered recovery. These are controlled tests.
- The 40 frozen baseline development starts preserved the pre-edit combat results. All 16 parity cases (four pairings × two seeds × two layouts) agreed across traced and untraced combat-only runs and full headless episodes. The default seed 13 scene remained wheeled and matched the prior release report. It rejects the tracked policy options.
- All 160 reserved results are present. GodotPhysics normalization warnings match the documented warning text. Tick checks found zero non-finite published combat states. Outliers were post-detachment floor collider clearance except for a 173 mm pre-solve tooth/support witness projection on standard 95440 with Bulldozer's candidate at 23.283 s. This measurement is a solver witness projection. It does not measure visible overlap. The worst flagged deck clearance was −65 mm on standard 52931 with Bulldozer's candidate. No reserved fight had more than one consecutive tick past 25 mm deck penetration. No speed, lift, containment or sustained weapon-depth threshold was exceeded. This pass did not audit visible floor contact for every flagged case. The original solver behavior and its known limitations remain. [Tracked baseline warning diagnosis](../tracked-test/VALIDATION.md)
- All six rendered episodes decoded and matched their headless winner, damage events, components, timing and physics fields. They used 720 × 1280 at 30 FPS, 150 frames per introduction, one full result, and AAC stereo combat audio. Baseline seed 13 had 749 combat frames after its 24.978 s knockout and seed 25 had 750. The early knockout on failure seed 7698 kept the complete result. Decoded combat sample peaks ranged from −14.46 to −8.58 dBFS with no sample clipping. I reviewed extracted sequences and matched them to tick/event timing. The clips show attacks and recovery direction at the normal camera scale. Very brief collider contacts and subjective audio quality were outside that frame and signal review.

## Review files

Files are under the worktree's ignored `renders/tracked-ai-01/` directory. Keep the `development`, `reserved`, `parity-final` and `movies` folders for per-case match, trace and log evidence. The `summary.json` files include per-layout and per-fight measurements. Movie parity comparisons and decode evidence sit next to the videos.

| File under `movies/` | What to inspect |
| --- | --- |
| `tracked-baseline-seed-13.mp4` | Proposed pairing. Bulldozer KO at 24.978 s, 153/200 versus 0/150. Both tracks present and functional throughout. |
| `tracked-baseline-seed-25.mp4` | Proposed pairing. Bulldozer time-limit win, 156/200 versus 6/150. Both tracks present and functional throughout. |
| `compare-riptide-seed-13.mp4` | Silent 7 s side-by-side from episode 10 s. Candidate steps outside the opening charge and scores at combat 2.306 s. Its hit registers on the front support, and the later reversal still runs toward the rail. |
| `compare-bulldozer-seed-25.mp4` | Silent 8 s side-by-side from episode 12.5 s. Candidate holds a connected ram, backs out at combat 5.02 s and scores on the next contact at 6.35 s. Several following pushes repeat this pattern. |
| `riptide-candidate-seed-36157.mp4` | Additional reserved fight using the isolated Riptide candidate. At episode 23.106 s it takes 17 HP from Bulldozer's right belt with a confirmed side strike. |
| `failure-riptide-repeated-rail-recovery.mp4` | Normal-speed 10.4 s excerpt from episode 21.0 s, standard seed 7698. Two exit attempts add no usable gap and Bulldozer repeatedly catches the damaged Riptide along the rail. |

## Reproduce

Use the tracked worktree and Godot 4.7.2. The reserved command expects a clean checkout of the frozen candidate commit. Use the same Godot binary for every pairing.

```powershell
$root = 'renders/tracked-ai-01-replay'
New-Item -ItemType Directory -Force $root | Out-Null
py tools/evaluate_tracked_ai.py --godot $godot --split development --output "$root/development"
py tools/evaluate_tracked_ai.py --godot $godot --split reserved --output "$root/reserved"
py tools/evaluate_tracked_ai.py --godot $godot --split parity --output "$root/parity"

& $godot --headless --path . --fixed-fps 60 --script res://tools/verify_combat.gd
& $godot --headless --path . --fixed-fps 60 --script res://tools/verify_tracks.gd
& $godot --headless --path . --fixed-fps 60 --script res://tools/verify_tracked_ai.gd -- --riptide-ai=tracked-flank --bulldozer-ai=tracked-intercept

$scene = 'res://scenes/review/arena_tracked_bulldozer_test.tscn'
$seed = 25
$saw = 'baseline'
$drum = 'baseline'
$stem = "$root/episode-$seed-$saw-$drum"
& $godot --path . --resolution 720x1280 --fixed-fps 30 --quit-after 1350 --write-movie "$stem.avi" $scene -- --autostop "--seed=$seed" "--riptide-ai=$saw" "--bulldozer-ai=$drum" "--report=$stem.match.json"
& $ffmpeg -i "$stem.avi" -c:v libx264 -preset fast -crf 20 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart "$stem.mp4"
py tools/verify_release_video.py --ffmpeg $ffmpeg --tracked-policies $saw $drum --output "$stem.video.json" --case "$stem.mp4" "$stem.match.json"
```

The wheel–drum fixture takes the prior captures from the wheel-support evidence. Pass their directory as `--capture-dir=<absolute path>` to `res://tools/verify_wheel_drum.gd` using `--fixed-fps 30`.

All exported review clips use the standard start. Set seed 13 with both baseline policies for the other proposed episode. Select `tracked-flank / baseline` on 13, 36157 and 7698 and `baseline / tracked-intercept` on 25 for the comparison sources. The evaluator runs both layouts automatically. Add `--swap-start` to a direct launch to reproduce a swapped start. Use `--contacts` on the evaluator or `--trace=<path> --contact-trace` on a direct launch for private contact reasons.
