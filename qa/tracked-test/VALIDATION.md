# Functional tracked Bulldozer baseline

The tracked test scene uses the mechanics at `7d7a6b0c26929d4da3fa1266db23a643f8679ada`. This validation commit is the proposed baseline for later tracked AI experiments. The default project scene uses wheeled Bulldozer v04. Both robots keep their existing stats and AI.

| Check | Result |
| --- | --- |
| Existing isolated track checks | Passed. Grounded thrust, airborne behavior, side strikes, road-hub hits and the damage paths passed. |
| Recorded fixture | Passed. Forward, reverse and both pivot directions agree with belt animation. The failed motor leaves its belt passive. Throwing the belt removes its collider and traction, with the remaining road wheels taking support. The idler can be damaged and detached separately. |
| Debris and reset | Passed. The belt strip and wheel peaked at 0.476 m/s and 1.078 rad/s. Peaks in the final 100 ms sample were 0.019 m/s and 0.084 rad/s. The production scene reload clears the debris and restores both drives, belts and road-wheel assemblies. |
| Winner fixture | Passed. The showcase keeps the belt and idler absent, retains the other road wheels and displays “Left track thrown.” |
| Functional seed 13 | Passed. The 720 × 1280, 30 FPS MP4 decodes completely with combat audio and matches the headless combat report. |
| Release selection | Passed. The default seed 13 replay from this branch matches the existing wheeled release report, apart from render counters. |

The fixture clip is 17.4 seconds. It uses the production drive actuator, damage API, winner view and scene reload with a fixture camera and controlled inputs. The seed 13 episode runs 40.00 seconds on video. Its first two 150-frame segments are the introductions, followed by 749 combat frames and a showcase spanning 150 frame intervals plus its endpoint. Bulldozer won at 24.978 seconds of combat with 153/200 HP. Both belts stayed attached and operational in the natural fight. Damage and detachment were demonstrated in the fixture.

## Seed 25 warning

Godot 4.7.2 `ed1daf0bf` emits the warning once in the reproduced seed 25 match, around combat tick 1838 at 180 Hz. The script logger saw it on a physics worker with an empty script stack. The native stack and binary call sites place it in the GodotPhysics SAT contact recheck. Riptide's front-right convex wheel hub (shape 11) and Bulldozer's right drum-bearing cylinder (shape 9) produced two identical finite witness points. The SAT recheck took their difference, measured zero depth, then divided by that depth. The captured axis was `[NaN, NaN, NaN]` in `GodotConvexPolygonShape3D::project_range`, where normalization reported it. The original zero-length difference and the NaN projection input are separate stages. [SAT contact recheck](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/modules/godot_physics_3d/godot_collision_solver_3d_sat.cpp#L692-L702) · [Convex projection](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/modules/godot_physics_3d/godot_shape_3d.cpp#L810-L833)

The published bearing–hub contact was finite, with about 0.11 mm of witness depth at the sampled tick. Poses, velocities and contacts stayed finite in the 109-tick audit window, and there was no damage event near the warning. The prior seed 25 export and both probe runs have identical combat results. The warning remains an engine limitation on coincident witnesses. The project keeps the validated hub, drivetrain and contact geometry, and the existing seed 25 export remains the comparison recording.

The recommended baseline is this fixed test commit. Each belt is a rigid hull with animated shoes, exposed road-wheel contacts are rigid parts of the chassis, lateral grip uses the chassis controller, and thrown belts use short rigid debris strips. The native warning and these approximations apply when interpreting future AI comparisons.

## Reproduce

Run from the tracked test worktree. Set `$godot` to Godot 4.7.2 and `$ffmpeg` to FFmpeg with libx264.

```powershell
& $godot --headless --path . --fixed-fps 60 --script res://tools/verify_tracks.gd
& $godot --path . --resolution 720x1280 --fixed-fps 30 --quit-after 1000 --write-movie renders/functional-track-validation.avi --script res://tools/record_track_fixtures.gd
& $ffmpeg -i renders/functional-track-validation.avi -an -c:v libx264 -crf 18 -pix_fmt yuv420p -movflags +faststart renders/bulldozer-functional-track-validation.mp4

$scene = 'res://scenes/review/arena_tracked_bulldozer_test.tscn'
& $godot --headless --path . --fixed-fps 30 $scene -- --autostop --seed=25 --riptide-ai=baseline --report=renders/final-track-seed-25-repro.json
& $godot --headless --path . --fixed-fps 30 $scene -- --autostop --seed=13 --riptide-ai=baseline --report=renders/final-functional-tracked-13-headless.json
& $godot --path . --resolution 720x1280 --fixed-fps 30 --quit-after 1350 --write-movie renders/final-functional-tracked-13.avi $scene -- --autostop --seed=13 --riptide-ai=baseline --report=renders/final-functional-tracked-13-movie.json
& $ffmpeg -i renders/final-functional-tracked-13.avi -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart renders/functional-tracked-bulldozer-vs-riptide-seed-13.mp4
py tools/verify_release_video.py --ffmpeg $ffmpeg --output renders/final-functional-tracked-13-video.json --case renders/functional-tracked-bulldozer-vs-riptide-seed-13.mp4 renders/final-functional-tracked-13-movie.json
```

The delivered MP4s are in the release checkout's ignored `renders/tracked-test/` directory. The tracked test worktree's ignored `renders/` contains the AVI masters, reports, fixture logs and native warning evidence in `track-warning-native-stack.json`, `track-warning-native-input.json` and `track-warning-ticks.json`.
