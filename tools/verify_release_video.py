"""Decode a Robot Fight Madness release MP4 and check its episode phases and audio."""
import argparse
import itertools
import json
import math
from pathlib import Path
import re
import subprocess

FPS = 30
SIZE = (72, 128)


def decode(ffmpeg, video, *options):
    return subprocess.run(
        [ffmpeg, "-nostdin", "-hide_banner", "-xerror", "-err_detect", "explode", "-i", str(video), *options],
        capture_output=True, check=True,
    )


def phase_runs(frames):
    width, _ = SIZE
    # The three studio headings stay fixed while the robots turn below them.
    heading = slice(18 * width, 33 * width)
    templates = {name: frames[index][heading] for name, index in (
        ("riptide_intro", 60), ("bulldozer_intro", 210), ("result", -1)
    )}
    labels = []
    for frame in frames:
        region = frame[heading]
        distances = {
            name: sum(abs(a - b) for a, b in zip(region, template)) / len(region)
            for name, template in templates.items()
        }
        nearest = min(distances, key=distances.get)
        labels.append(nearest if distances[nearest] <= 4.0 else "combat")
    return [(label, sum(1 for _ in group)) for label, group in itertools.groupby(labels)]


def peak_db(log):
    levels = re.findall(r"Peak level dB: (\S+)", log)
    assert len(levels) == 1, log
    return float(levels[0])


def verify(ffmpeg, video, report, tracked_policies=None):
    picture = decode(ffmpeg, video, "-map", "0:v:0", "-an", "-vf", f"scale={SIZE[0]}:{SIZE[1]}:flags=area",
                     "-pix_fmt", "gray", "-fps_mode", "passthrough", "-f", "rawvideo", "pipe:1")
    info = picture.stderr.decode(errors="replace")
    assert re.search(r"Video: h264[^\r\n]*\b720x1280\b[^\r\n]*\b30 fps\b", info), info
    assert re.search(r"Audio: aac[^\r\n]*\b48000 Hz, stereo\b", info), info
    frame_bytes = math.prod(SIZE)
    assert len(picture.stdout) % frame_bytes == 0
    frames = [picture.stdout[i:i + frame_bytes] for i in range(0, len(picture.stdout), frame_bytes)]
    minimum_detail = min(sum(pixel > 80 for pixel in frame) for frame in frames)
    assert minimum_detail >= 60, f"{video}: empty or near-empty frame"
    phases = phase_runs(frames)
    assert [name for name, _ in phases] == ["riptide_intro", "bulldozer_intro", "combat", "result"], phases
    assert [count for _, count in phases[:2]] == [150, 150], phases
    assert report["intro_duration"] == 10 and report["showcase_duration"] == 5, report
    if tracked_policies is None:
        assert report["riptide_ai"] == "baseline", report
    else:
        assert (report["riptide_ai"], report["bulldozer_ai"]) == tuple(tracked_policies), report
        assert report["bulldozer_drive"] == "tracks", report
        assert len(report["final_conditions"][1]["tracks"]) == 2, report
    assert [pose[3] for pose in report["start_poses"]] == report["max_hp"], report
    assert [pose[4] for pose in report["start_poses"]] == [0, 0], report
    fight = report["fight_duration"]
    assert 0 < fight <= 25 and abs(phases[2][1] - fight * FPS) <= 1, phases
    assert phases[3][1] in (150, 151), phases
    assert abs(len(frames) - report["duration"] * FPS) <= 1.1, phases
    stats = "astats=measure_perchannel=none:measure_overall=Peak_level"
    peaks = {}
    for label, prefix in (("full", ""), ("combat", f"atrim=start=10:end={10 + fight},")):
        audio = decode(ffmpeg, video, "-map", "0:a:0", "-vn", "-af", prefix + stats, "-f", "null", "-")
        peaks[label] = peak_db(audio.stderr.decode(errors="replace"))
        assert -45 < peaks[label] < 0, (video, label, peaks[label])
    return {"video": str(video), "seed": report["seed"], "start": report["start"],
            "frames": len(frames), "phase_frame_counts": dict(phases), "peak_dbfs": peaks,
            "min_frame_pixels_above_luma_80_at_72x128": minimum_detail}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--case", action="append", nargs=2, metavar=("MP4", "MATCH_JSON"), required=True)
    parser.add_argument("--tracked-policies", nargs=2, metavar=("RIPTIDE", "BULLDOZER"))
    args = parser.parse_args()
    evidence = []
    for video, report in args.case:
        row = verify(args.ffmpeg, Path(video), json.loads(Path(report).read_text(encoding="utf-8-sig")),
                     args.tracked_policies)
        evidence.append(row)
        print(json.dumps(row))
    args.output.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
