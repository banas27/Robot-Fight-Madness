# Robot Fight Madness

Robot Fight Madness runs original robot fights and records them as vertical video. R08 uses Riptide's horizontal saw and Bulldozer's spiked drum from the existing Blender exports.

## Open and play

1. In the standard Godot 4 editor, import `D:\RobotFightStudio\RobotFightStudio\project.godot`. This pass was verified with Godot **4.7.2** and the **Compatibility** renderer.
2. Press **F5** to run an episode. Riptide and Bulldozer each get five seconds on their pedestal before the fight starts. **R** restarts the same seed and **Escape** closes the window.
3. Press **D** to toggle the actual collision shapes. Cyan is chassis, violet is wheels, green is supports, amber is weapon cores, and yellow is teeth. Pink marks the last impact point and normal.

You can also open `scenes/arena_combat.tscn` and press **F6**. The arena builds when you run the scene. To view the original gameplay with the same robot models, open `scenes/review/arena_art_review.tscn` and press **F6**. The separate close-up scenes remain under `scenes/review`.

## Record on Windows

Run the existing launcher in PowerShell from the project folder.

```powershell
Set-Location 'D:\RobotFightStudio\RobotFightStudio'
$godot = 'C:\Users\aurim\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
.\Record-Fight.ps1 -Godot $godot -Seed 7 -FPS 30
```

Let the recording window close on its own after the result screen. The launcher creates a unique **720 × 1280, 30 FPS AVI with audio**, a match JSON and logs under `renders/`. If FFmpeg is on PATH it also creates an MP4. You can supply a specific executable with `-FFmpeg 'C:\Tools\ffmpeg\bin\ffmpeg.exe'`.

If PowerShell blocks scripts, use a process-scoped bypass from the same folder.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Record-Fight.ps1 -Godot $godot -Seed 7 -FPS 30
```

For a direct Movie Maker run, use a fresh output name.

```powershell
& $godot --path . --resolution 720x1280 --write-movie renders/fight.avi --fixed-fps 30 --quit-after 1350 -- --autostop --seed=7 --report=renders/fight.json
```

Add `--debug-combat --debug-close` after `--` to record a closer view with the collision overlay. Add `--trace=qa/identity-pass/trace.json` after `--` to record a combat diagnostic trace.

The project renders to a fixed 720 × 1280 viewport so a shorter monitor can display a smaller window while Movie Maker captures the full portrait frame. The seed sets the starting positions and tactics. A fight that uses all 25 seconds makes a 40-second episode. A knockout cuts directly to the five-second showcase and ends the recording earlier.

## Tuning and verification

| File | What it controls |
| --- | --- |
| `config/match.json` | Arena dimensions and legacy R01 match settings |
| `config/combat.json` | Robot definitions, speed mapping, traction, motor response, cooldown and physics tick rate |
| `config/presentation.json` | Episode durations, arena camera framing and shake, impact pool sizes and sound level |
| `scripts/combat/` | Fitted colliders, movement, solver contacts, match events and debug drawing |
| `scripts/presentation/episode_view.gd` | Pedestal cameras, turntables, profile reveals and result layouts |
| `tools/verify_combat.gd` | Focused solver checks for head-on, near-miss, side, glancing, sustained, wall-pin and knockout contacts |
| `tools/verify_matches.py` | Seeded match completion, score and stability checks |

Keep speeds and cooldowns positive. The fits in `scripts/combat/collision_fit.gd` follow the current meshes and pivots. Recheck them with the overlay if you remodel a robot.

Current clips and measured results are in [R08 validation](qa/episode-pass/VALIDATION.md). See [Robot art review](art/REVIEW.md) for Blender sources and asset export instructions.

Run the [Riptide AI comparison](qa/riptide-ai/VALIDATION.md) with `py tools/evaluate_riptide.py --godot $godot --split development --output qa/riptide-ai/development`. The default fight uses the baseline policy. Pass `-RiptideAI candidate` to `Record-Fight.ps1` to record the alternate policy.

The [wheel and drum investigation](qa/wheel-drum/VALIDATION.md) records the hub collider change, same-pose fixtures, and updated baseline episodes.

The [wheel-support experiment](qa/wheel-support/VALIDATION.md) records the revised models, forced wheel-loss fixtures, seeded comparison and review videos.
