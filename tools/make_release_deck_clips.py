"""Label the three release incidents using the frames from their observed movies."""
import argparse
import json
from pathlib import Path
import subprocess

CASES = {
    "standard-03": ("STANDARD SEED 3", 168, 434),
    "standard-04": ("STANDARD SEED 4", 220, 440),
    "swapped-25": ("SWAPPED START / SEED 25", 230, 503),
}


def clip(ffmpeg, stem, audit_dir, movie_dir):
    title, x, y = CASES[stem]
    audit = json.loads((audit_dir / f"{stem}.audit.json").read_text())
    peak = min(audit["ticks"], key=lambda row: row["robots"][0]["bottom_y"])
    frame = next(row for row in audit["rendered_frames"] if row["tick"] >= peak["tick"])
    center = frame["frame"]
    depth = round(-1000 * peak["robots"][0]["bottom_y"])
    if frame["tick"] == peak["tick"]:
        note = f"Frame {center} contains the {depth} mm collider dip"
    else:
        note = f"The {depth} mm peak fell between export frames"
    normal_first, normal_end = center - 27, center + 34
    slow_first, slow_end = center - 7, center + 9
    normal_duration = (normal_end - normal_first) / 30
    slow_duration = (slow_end - slow_first) * 4 / 30

    def caption(text, y, size):
        font = r"fontfile='C\:/Windows/Fonts/segoeui.ttf'"
        return f"drawtext={font}:text='{text}':fontcolor=white:fontsize={size}:x=35:y={y}"

    banner = "drawbox=x=16:y=17:w=688:h=83:color=0x101923@0.91:t=fill"
    zoom = f"crop=340:320:{x}:{y},scale=720:678:flags=lanczos,pad=720:1280:0:294:color=0x101923"
    filters = (
        f"[0:v]trim=start_frame={normal_first}:end_frame={normal_end},setpts=PTS-STARTPTS,setsar=1,{banner},"
        f"{caption(title, 25, 29)},{caption('NORMAL SPEED / ORIGINAL 30 FPS', 62, 21)}[normal];"
        f"[0:v]trim=start_frame={slow_first}:end_frame={slow_end},setpts=4*(PTS-STARTPTS),fps=30,{zoom},setsar=1,"
        f"{caption(title, 132, 31)},{caption('QUARTER SPEED / CROPPED FROM EXPORT', 177, 24)},"
        f"{caption(note, 1016, 25)}[slow];"
        f"[0:a]atrim=start={normal_first / 30}:duration={normal_duration},asetpts=PTS-STARTPTS[a];"
        f"anullsrc=channel_layout=stereo:sample_rate=48000,atrim=duration={slow_duration}[quiet];"
        "[normal][a][slow][quiet]concat=n=2:v=1:a=1[v][audio]"
    )
    output = movie_dir / f"{stem}-penetration.mp4"
    subprocess.run([
        ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(movie_dir / f"{stem}-observed.avi"), "-filter_complex", filters,
        "-map", "[v]", "-map", "[audio]", "-c:v", "libx264", "-crf", "18",
        "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", str(output),
    ], check=True)
    print(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg", required=True)
    parser.add_argument("--audit-dir", type=Path, default=Path("qa/release-check"))
    parser.add_argument("--movie-dir", type=Path, default=Path("renders/release-check"))
    args = parser.parse_args()
    for name in CASES:
        clip(args.ffmpeg, name, args.audit_dir, args.movie_dir)
