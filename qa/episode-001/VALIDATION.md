# Episode 001 validation

The primary and backup are ready for the owner's final phone viewing and listening approval. They use `tracked-peel` Riptide against frozen `tracked-intercept` Bulldozer in the larger functional tracked arena. The recording source is `e78748b3fca70c5906320cc4b2d706cfb58c9de4` and the experiment freeze is `eac9a026d36cac70695e0adecc9a590b86d014ff`. Godot reported `4.7.2.stable.official.ed1daf0bf`.

The initial frozen comparison repeated all 40 larger-arena baseline outcomes from `d720d4c2c803c6255ed21d4838071dd83a47c5c7`. On those same seeds and starts, switching only Bulldozer to `tracked-intercept` moved its wins from 3 to 30 and increased mean Riptide stalls from 2.07 to 7.63 seconds. All eight comparison MP4s for seeds 13 and 25 matched headless combat in standard and swapped layouts. The original comparison evidence is under `renders/arena-intercept-followup`.

Two focused improvement rounds addressed the observed pressure. Riptide's exit now chooses a short forward or reverse arc across the drum's approach, bounded by wheel support and wall room. A reachable shoulder can end the retreat once there is room and the saw can rearm. Bulldozer's trial re-aimed connected pushes while keeping the original commitment and motor commands. Both were tested separately on known seeds before the combined pairing. [Protocol](PROTOCOL.md) · [Fresh seeds](seeds-confirmation.json)

| Fresh confirmation, 40 fights each | Frozen reference | Riptide change only | Bulldozer change only | Both changes |
| --- | ---: | ---: | ---: | ---: |
| Wins Riptide / Bulldozer | 11 / 29 | 32 / 8 | 12 / 28 | 30 / 10 |
| Mean HP damage dealt Riptide / Bulldozer | 60.6 / 108.6 | 122.8 / 54.0 | 72.4 / 99.4 | 122.8 / 54.9 |
| Riptide damaging passes / attempts | 87 / 122 | 171 / 244 | 90 / 132 | 167 / 253 |
| Riptide side or rear hits | 7 | 30 | 5 | 33 |
| Mean Riptide pin / stall, s | 0.73 / 7.41 | 0.15 / 5.54 | 0.20 / 7.44 | 0.12 / 4.94 |
| Repeated Riptide recovery links | 54 | 19 | 31 | 21 |
| Mean Bulldozer productive / ineffective push, s | 0.81 / 4.60 | 0.46 / 4.40 | 0.85 / 4.87 | 0.43 / 4.37 |
| Bulldozer damaging passes / attempts | 124 / 190 | 59 / 141 | 104 / 178 | 61 / 141 |
| Mean longest quiet gap, s | 6.12 | 6.44 | 6.66 | 6.37 |
| Time limit outcomes | 24 | 37 | 30 | 38 |

Riptide's 25% stall reduction, 65% drop in repeated recovery links and near-preserved conversion passed the preset gates. Both layouts showed the reduction. The Bulldozer change increased ineffective push time and reduced conversion by 6.8 percentage points in isolation. The final source retains frozen `tracked-intercept`. The full four-way comparison can be rerun from the experiment freeze. Riptide's improvement still comes with fewer Bulldozer connections and more time-limit decisions. The larger-arena result applies to these pairings and this confirmation set.

## Footage and verification

| Export | Seed and start | Result | Review evidence |
| --- | --- | --- | --- |
| `Robot-Fight-Madness-Episode-001.mp4` | 4773270 swapped | Riptide on health, 96/150 to 60/200 | A side hit damages the right belt. Both fighters make damaging contacts. |
| `Robot-Fight-Madness-Episode-001-Backup.mp4` | 6990406 swapped | Bulldozer on health, 131/200 to 60/150 | Bulldozer damages Riptide's wheel drive and finishes with its drum disabled, reflected in the showcase. |

These fights came from a separate known development pool. The screen recorded eligibility and ranking for all 40 starts, then four candidates were recorded and inspected. Selection considered damaging exchanges from both fighters, clear changes of position, readable framing and accurate damage presentation. The backup has an eight-second closing stretch without another scored strike. The sampled footage shows repositioning during that stretch.

Both files decode fully at 720 × 1280 and 30 FPS. Each has two 150-frame introductions, 750 combat frames, and a five-second result plus its endpoint frame. The headless replay matched start, hit events, condition changes, timing and result for each. Estimated fighter envelopes cleared the image edges by at least 89 px in the primary and 100 px in the backup. Combat audio peaks were −12.92 and −13.02 dBFS, respectively. Review used sampled frames and consecutive frames around important contacts, plus audio decode and peak checks. Final playback and listening are for phone review. Music integration is pending documented permission.

The 160 confirmation runs retained 50 engine normalization warnings and had zero non-finite published ticks or solver outliers. The frozen 80-fight comparison retained 18 warnings and one single-tick floor-collider outlier. Neither selected fight logged a warning or a detached-floor outlier. The existing combat, track, wheel-support and damaged-policy checks passed. Retained policy parity passed, and the wheeled default replay matched the prior report. The selected footage does not establish that every fight will render without a physical artifact.

## Reproduce

Run from the tracked worktree. To reproduce all four confirmation pairings, check out the experiment freeze. The recording source contains the retained pairings.

```powershell
py tools/evaluate_episode_001.py --godot $godot --split reserved --output renders/episode-001/replay
py tools/evaluate_episode_001.py --godot $godot --split parity --contacts --output renders/episode-001/parity-replay
& $godot --headless --path . --fixed-fps 60 --script res://tools/verify_tracked_ai.gd -- --riptide-ai=tracked-peel --bulldozer-ai=tracked-intercept
& $godot --path . --resolution 720x1280 --fixed-fps 30 --quit-after 1350 --write-movie renders/episode-001-replay.avi res://scenes/review/arena_tracked_bulldozer_large.tscn -- --autostop --seed=4773270 --swap-start --riptide-ai=tracked-peel --bulldozer-ai=tracked-intercept --report=renders/episode-001-replay.match.json
& $ffmpeg -i renders/episode-001-replay.avi -c:v libx264 -preset fast -crf 20 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart renders/episode-001-replay.mp4
```

The final review folder is `renders/episode-001/final-review`. Raw results and selection records sit next to it in `renders/episode-001`.
