# R01 validation

Historical prototype validation. See [R08 validation](episode-pass/VALIDATION.md) for the current default episode.

## Environment

Godot **4.5.1.stable.official.f62fdbde1**, Linux x86_64. Render check used the
Compatibility renderer with Mesa llvmpipe software rendering and a virtual display.
This is not a benchmark of the owner's RTX 5070 Ti or Windows PC.

## Completed checks

- Godot imported and executed the actual project scripts.
- Ten full headless matches, seeds 1–10, verified valid results, bounded duration,
  at least one attack, nonnegative health, arena containment, event damage accounting
  and correct winner selection. Results: `headless-results.json`.
- Controlled configurations separately exercised the time-limit draw, simultaneous
  double knockout and reverse recovery. Results: `boundary-results.json`.
- A full rendered seed-7 match recorded through Godot Movie Maker at 720 × 1280,
  30 fps, with audio, and stopped automatically after the result screen.
- FFmpeg converted the AVI to H.264/AAC MP4. ffprobe confirmed 720 × 1280,
  30 fps, stereo audio and 20.966667 seconds duration.
- Video frames inspected across countdown, combat and winner screen. Audio is
  non-silent; measured peak is approximately -11.6 dBFS after conversion.
- Final movie run completed without script errors or leaked-object warnings.
  A V-sync warning comes from the software-rendering test environment.

## Evidence and interpretation

`movie-seed-7.json` records the rendered match: Riptide wins with 16 health left,
13 spinner hits and 3 ram hits. The movie has 629 frames. A headless seed-7 run
is a separate execution, not proof of frame-for-frame replay across settings.

Ten seeds are a smoke test, not long-run production reliability or statistical
balance evidence. The spinner wins 9/10 of these current headless matchups; the
rammer wins seed 1. Tuning and more interesting tactics remain future work.

## Not yet verified

- Windows editor import/playback and `Record-Fight.ps1` execution. The PowerShell
  launcher is supplied for the user's PC but was not executed in this Linux environment.
- Newer Godot versions, other rendering backends, or export templates/standalone builds.
- High-volume overnight batches, real platform uploads or social-video safe areas.
- Visual quality, commercial appeal, sustained audience interest or earnings.

## Re-run the headless smoke test

Python 3 is needed only for this optional development check:

```text
python tools/verify_matches.py --godot /absolute/path/to/godot --count 10
```

The verification tool runs real simulations and checks their JSON output. It does
not validate rendering. The recording example in START_HERE.md is the separate
visual/audio check.
