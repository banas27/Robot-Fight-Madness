# First episode release check

**Recommendation: release-ready for the two verified standard exports.** Keep the post-detachment contact issue open for other replays. This check leaves episode selection separate. The combat and presentation source is `9c1ff9861d0e7a510025db3fb533c395ee99d407`, with the validated convex hub from `cf80747`. The release branch adds QA tools and documentation. The exports use baseline Riptide AI and wheeled Bulldozer.

## Post-detachment deck contact

Godot 4.7.2 reproduced the three peaks at 180 Hz. Depth is the distance below the deck plane at Y = 0, calculated separately from enabled collider geometry and transformed wheel mesh vertices. The frame column reports the affected wheel in the specific 30 FPS recording used for each clip. A repeated export can sample a different tick with identical combat.

| Case | Combat time / tick | Peak collider / mesh | Consecutive ticks over 25 mm, collider / mesh | 30 FPS observation |
| --- | ---: | ---: | ---: | --- |
| Standard 3 | 13.028 s / 2345 | 101.6 / 106.1 mm | 2 / 2 | Frame 690 caught the peak. The chassis rolls briefly and the lower tire is partly hidden behind the drum. The next frame recovers. |
| Standard 4 | 22.667 s / 4080 | 48.3 / 57.8 mm | 1 / 2 | The peak fell between frames 979 and 980. Frame 980 shows an 18.7 mm mesh dip. The lower wheel is partly obscured. |
| Swapped 25 | 17.017 s / 3063 | 46.8 / 53.5 mm | 1 / 1 | The selected export skipped the peak between frames 809 and 810. Frame 810 shows 16.2 mm of mesh penetration and a small tire contour change. |

The reports match the uninstrumented movies and the existing headless combat reports. In all three cases, the dominant contact was a drum tooth against a surviving convex wheel hub. The solver reported a 95–101 mm witness projection at that pair and shifted Riptide’s pose. The difference between its measured root motion and one tick of velocity was 39.2, 15.8 and 12.4 mm respectively. Support contacts changed briefly, while Riptide stayed in its current maneuver. Collider depth returned below 12 mm in three, two and two ticks respectively. The captured frames show a small pose change, most clearly in the cropped standard seed 3 replay, with no sustained sinking, launch or abrupt full-body snap.

Bulldozer’s damage latch blocked all three incident contacts. Swapped seed 25 was also on cooldown. No incident tick changed health or component condition. Standard seed 4 ended on a separate eligible tooth hit 32 ticks later, after the latch cleared, with Riptide already at 2 HP. The transient affected movement and contact support. These replays cannot establish how the matches would end without the correction. The prior 6 mm hub bevel moved the worst spike and increased its depth, so the validated hub fit stays in place. [Prior bevel evidence](../wheel-support/bevel-diagnostic/summary.json)

- [Standard 3 clip](../../renders/release-check/standard-03-penetration.mp4) · [tick and frame trace](standard-03.audit.json)
- [Standard 4 clip](../../renders/release-check/standard-04-penetration.mp4) · [tick and frame trace](standard-04.audit.json)
- [Swapped 25 clip](../../renders/release-check/swapped-25-penetration.mp4) · [tick and frame trace](swapped-25.audit.json)

Each clip starts at normal speed with the match framing and audio. The second pass enlarges the same encoded frame sequence at quarter speed. It cannot show ticks that Movie Maker skipped.

## Export checks

FFmpeg decoded every video and audio frame of the two retained episodes, three uninstrumented incident movies and the time-limit control. The two intros each occupy 150 frames, combat starts at frame 300, and one complete showcase follows combat with no intervening blank frame. Each result has 150 frame intervals and an endpoint frame. Seed 5 verified the full 750-frame fight and the health decision at the limit. Frame inspection matched the winner’s displayed HP, weapon and drive condition to each report. Start reports show fresh health and zero rotor speed. The previous support fixtures verified that a damaged winner’s detached wheels stay absent and that a fresh episode restores its state. [Wheel-support fixtures and parity](../wheel-support/VALIDATION.md)

| Standard export | Duration | Outcome | Decoded combat peak |
| --- | ---: | --- | ---: |
| [Seed 13](../../renders/wheel-support/seed-13.mp4) | 32.77 s | Bulldozer KO, 150/200 HP | −9.31 dBFS |
| [Seed 25](../../renders/wheel-support/seed-25.mp4) | 33.70 s | Bulldozer KO, 179/200 HP | −7.59 dBFS |
| Seed 5 time-limit control | 40.03 s | Riptide wins on health percentage, 107/150 HP | −14.58 dBFS |

In standard seed 13 the wheel detaches on the deciding tick and the result cuts in immediately. Standard seed 25 stayed below 8 mm after wheel loss. Both episodes have stereo combat audio and no full-scale decoded samples. Audio levels are signal measurements. [Decode and phase evidence](video-verification.json), [seed 13 transitions](seed-13.boundaries.png), [seed 25 transitions](seed-25.boundaries.png), [time-limit transitions](time-limit.boundaries.png)

## Reproduce

Run from the project folder with Godot 4.7.2 and FFmpeg with `libx264` and `drawtext`. The audit scene inherits the match and samples it without changing combat.

```powershell
New-Item -ItemType Directory -Force renders/release-check, qa/release-check | Out-Null
$cases = @(
    @('standard-03', 3, 2345, $false),
    @('standard-04', 4, 4080, $false),
    @('swapped-25', 25, 3063, $true)
)
foreach ($case in $cases) {
    $stem, $seed, $tick, $swapped = $case
    $opts = @('--autostop', "--seed=$seed", '--riptide-ai=baseline')
    if ($swapped) { $opts += '--swap-start' }
    & $godot --path . --resolution 720x1280 --fixed-fps 30 --quit-after 1350 --write-movie "renders/release-check/$stem.avi" -- @opts "--report=qa/release-check/$stem.movie.json"
    & $ffmpeg -i "renders/release-check/$stem.avi" -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart "renders/release-check/$stem.mp4"
    & $godot --path . --resolution 720x1280 --fixed-fps 30 --quit-after 1350 --write-movie "renders/release-check/$stem-observed.avi" res://tools/audit_release_deck.tscn -- @opts "--deck-tick=$tick" "--deck-report=qa/release-check/$stem.audit.json" "--report=qa/release-check/$stem.observed.json"
}
py tools/make_release_deck_clips.py --ffmpeg $ffmpeg
py tools/verify_release_video.py --ffmpeg $ffmpeg --output qa/release-check/video-verification.json `
    --case renders/wheel-support/seed-13.mp4 renders/wheel-support/seed-13.json `
    --case renders/wheel-support/seed-25.mp4 renders/wheel-support/seed-25.json
```

The episode files were reused from the source commit. To regenerate either, use `Record-Fight.ps1 -Godot $godot -Seed 13 -FPS 30 -RiptideAI baseline -FFmpeg $ffmpeg` and substitute 25 for the second match or 5 for the time-limit control. The QA JSON, images and movies are local artifacts.
