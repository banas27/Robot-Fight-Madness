# R02 combat pass validation

Tested on Windows with Godot 4.7.2, the Compatibility renderer and the NVIDIA RTX 5070 Ti. The latest Riptide and Bulldozer Blender and GLB files match the pre-pass checkpoint byte for byte.

## Comparable seed-7 recordings

Both clips use the same seed, spawn positions, art, viewport size and recording rate. The first clip runs the original art review arena. The second runs the default R02 arena and includes the countdown, entire fight and result.

| Clip | Video | Audio | Length |
| --- | --- | --- | --- |
| [Before](../../renders/combat-pass/before-seed-7.mp4) | 720 × 1280, 30 FPS | 48 kHz stereo, −11.6 dBFS sample peak | 20.97 s |
| [After](../../renders/combat-pass/after-seed-7.mp4) | 720 × 1280, 30 FPS | 48 kHz stereo, −9.2 dBFS sample peak | 19.67 s |

The Windows display constrained the first window-sized capture to 450 × 800. Switching Godot to viewport stretch gave the comparison and launcher captures their native 720 × 1280 frame. The final launcher run produced 590 frames and completed automatically. Movie Maker logged about 5 seconds of offline recording. The entire launcher run, including H.264/AAC conversion, took 8.26 seconds. The AVI master is `renders/fight-0007-20261109-034637-957.avi`.

Live seed-7 playback ran at a measured **60.0 FPS** with a 60 FPS cap and VSync disabled. Across 792 sampled fight frames at 720 × 1280, the 95th-percentile frame time was **16.84 ms**, the 99th percentile was 17.35 ms, and the slowest sampled frame was 17.77 ms. These are live measurements, separate from Movie Maker. See [frame metrics](../../renders/combat-pass/live-60.json).

## What was verified

- Focused fixtures confirmed direct saw and drum hits, damage-free weapon clashes, glancing yaw, a spike hitting between tick endpoints, near misses, rear contact, idle weapons, sustained-contact cooldown, wall impact and corner escape, and simultaneous knockout with spin-down.
- Ten complete seeded matches finished with valid score accounting and bounded motion. Both weapons landed strikes in every seed. Riptide won six and Bulldozer won four. The highest lift was 0.093 m, the lowest chassis root was 0.372 m and the largest normalized arena extent was 0.830. The longest time with centers closer than 2.2 m was 0.90 s. See [seed results](headless-results.json).
- Seeds 7 and 10 produced identical complete combat reports at fixed render rates of 30, 60 and 120. The live and Movie Maker seed-7 reports matched the fixed 60 FPS headless run after excluding presentation-only counters.
- The final seed-7 recording shows the robots backing away between hits, flashes and sparks at contact, both robots inside the portrait framing, and the disabled robot visible above the lowered result card. The run logged 11 saw strikes, five drum strikes, ten weapon clashes and one shutdown. Particle and voice peaks were 48 and three. See the [impact frame](../../renders/combat-pass/after-impact.png), [contact overlay](../../renders/combat-pass/debug-frame.png) and [match JSON](../../renders/combat-pass/after-seed-7.json).

## Limits

Contact uses swept tooth traces and compound chassis primitives. Weapon clashes check a tooth against the opposing weapon's core. These are arcade approximations, so individual mesh edges can cross briefly. Pitch and roll are visual springs. The rigid bodies have yaw and bounded vertical lift. The seed tests cover this engine and hardware configuration, and the win counts describe this sample.

The recoverable pre-pass project archive is `D:\RobotFightStudio\checkpoints\before-combat-pass-20261109-032219.zip`. Extract it to a separate folder and import its `project.godot` to run that snapshot.

## Re-run

Set `$godot` as shown in [START_HERE.md](../../START_HERE.md), then run from the project folder.

```powershell
& $godot --headless --path . --fixed-fps 60 --quit-after 600 --script res://tools/verify_combat.gd
python tools/verify_matches.py --godot $godot --count 10
& $godot --path . --resolution 720x1280 --disable-vsync --max-fps 60 -- --autostop --seed=7 --perf=renders/live-60.json
```
