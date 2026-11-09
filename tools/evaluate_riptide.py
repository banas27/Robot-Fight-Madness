#!/usr/bin/env python3
"""Compare the two Riptide policies in the actual seeded combat scene."""
import argparse
import json
import math
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import statistics
import subprocess


PROJECT = Path(__file__).resolve().parents[1]
SEEDS = PROJECT / "qa/riptide-ai/seeds.json"


def run_match(godot, root, seed, layout, variant, episode=False):
    folder = root / variant / layout
    folder.mkdir(parents=True, exist_ok=True)
    stem = str(seed) + ("-episode" if episode else "")
    report, trace = (folder / f"{stem}.{ext}.json" for ext in ("match", "trace"))
    report.unlink(missing_ok=True)
    trace.unlink(missing_ok=True)
    args = [
        godot, "--headless", "--path", str(PROJECT), "--fixed-fps", "30", "--",
        "--autostop", f"--seed={seed}", f"--riptide-ai={variant}",
        f"--report={report}", f"--trace={trace}",
    ]
    if not episode:
        args.append("--combat-only")
    if layout == "swapped":
        args.append("--swap-start")
    result = subprocess.run(args, capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    if result.returncode or "ERROR:" in output or not (report.exists() and trace.exists()):
        raise RuntimeError(f"{variant}/{layout}/{seed} failed:\n{output}")
    match = json.loads(report.read_text(encoding="utf-8"))
    decisions = json.loads(trace.read_text(encoding="utf-8"))
    assert (match["seed"], match["start"], match["riptide_ai"]) == (seed, layout, variant)
    assert match["physics_hz"] == 180 and 0 < match["fight_duration"] <= 25.0, report
    assert [pose[3] for pose in match["start_poses"]] == match["max_hp"], report
    assert [pose[4] for pose in match["start_poses"]] == [0, 0], report
    if not episode:
        assert match["intro_duration"] == match["showcase_duration"] == 0, report
        assert match["duration"] == match["fight_duration"], report
    hp = match["max_hp"].copy()
    for hit in match["events"]:
        target = int(hit["attacker"] == "Riptide")
        hp[target] = max(0, hp[target] - hit["damage"])
        assert hp[target] == hit["target_hp"], report
    assert hp == match["hp"], report
    return match, decisions


def metrics(match, trace):
    saw = trace["robots"][0]
    hits = [hit for hit in trace["strikes"] if hit["attacker"] == "Riptide"]
    flank = [p for p in saw["passes"] if p["intent"] in ("side", "rear")]
    return {
        "seed": match["seed"], "start": match["start"], "winner": match["winner"],
        "hp_percent": [100 * ratio for ratio in match["remaining_ratio"]],
        "damage_dealt": match["max_hp"][1] - match["hp"][1],
        "damage_received": match["max_hp"][0] - match["hp"][0],
        "attack_attempts": len(saw["passes"]),
        "successful_attempts": sum(p["hits"] > 0 for p in saw["passes"]),
        "flank_conversions": sum(p["side_rear_hits"] > 0 for p in saw["passes"]),
        "intended_flanks": len(flank),
        "intended_flank_conversions": sum(p["side_rear_hits"] > 0 for p in flank),
        "weapon_hits": len(hits),
        "side_rear_hits": sum(hit["zone"] != "front" for hit in hits),
        "stalled_s": saw["stalled_s"], "pin_s": saw["pin_s"],
        "recoveries": len(saw["recoveries"]),
        "separated": sum(r["separated"] for r in saw["recoveries"]),
        "retreat_s": sum(saw["state_seconds"].get(s, 0) for s in ("2", "7")),
        "fight_s": match["fight_duration"],
        "peak_depth": match["peak_weapon_contact_depth"],
        "deep_contact_s": match["longest_weapon_depth_over_25mm"],
        "peak_speed": match["peak_speed"], "peak_lift": match["peak_lift"],
        "lowest_root": match["lowest_root"], "arena_extent": match["max_arena_extent_ratio"],
    }


def solver_outliers(rows):
    limits = {"peak_depth": .16, "deep_contact_s": .12, "peak_speed": 8,
              "peak_lift": .26, "arena_extent": 1.08}
    flagged = []
    for row in rows:
        failures = {key: row[key] for key, limit in limits.items() if row[key] >= limit}
        if row["lowest_root"] <= .32:
            failures["lowest_root"] = row["lowest_root"]
        if failures:
            flagged.append({"seed": row["seed"], "start": row["start"], "metrics": failures})
    return flagged


def aggregate(rows):
    mean = lambda key: round(statistics.mean(r[key] for r in rows), 3)
    total = lambda key: sum(r[key] for r in rows)
    max_metric = lambda key: round(max(r[key] for r in rows), 4)
    return {
        "matches": len(rows),
        "wins": sum(r["winner"] == "RIPTIDE" for r in rows),
        "draws": sum(r["winner"] == "DRAW" for r in rows),
        "mean_hp_percent": [round(statistics.mean(r["hp_percent"][i] for r in rows), 3) for i in range(2)],
        **{key: mean(key) for key in ("damage_dealt", "damage_received", "stalled_s", "pin_s", "retreat_s", "fight_s")},
        **{key: total(key) for key in ("attack_attempts", "successful_attempts", "flank_conversions",
                                       "intended_flanks", "intended_flank_conversions", "weapon_hits",
                                       "side_rear_hits", "recoveries", "separated")},
        "retreat_percent": round(100 * total("retreat_s") / total("fight_s"), 2),
        "solver_outliers": solver_outliers(rows),
        **{f"max_{key}": max_metric(key) for key in ("peak_depth", "deep_contact_s", "peak_speed", "peak_lift", "arena_extent")},
        "lowest_root": round(min(r["lowest_root"] for r in rows), 4),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--split", required=True, choices=("development", "evaluation", "parity"))
    parser.add_argument("--variants", nargs="+", default=["baseline", "candidate"], choices=("baseline", "candidate"))
    parser.add_argument("--layout", default="both", choices=("standard", "swapped", "both"))
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    root = args.output.resolve()
    seeds = json.loads(SEEDS.read_text())
    assert all(len(set(group)) == 20 for group in seeds.values())
    assert set(seeds["development"]).isdisjoint(seeds["evaluation"])
    layouts = ["standard", "swapped"] if args.layout == "both" else [args.layout]
    selected = [25, 13] if args.split == "parity" else seeds[args.split]
    variants = list(dict.fromkeys(args.variants))
    jobs = [(seed, layout, variant) for seed in selected for layout in layouts for variant in variants]
    rows = {variant: [] for variant in variants}
    starts = {}

    def run(job):
        return run_match(args.godot, root, *job)

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for (seed, layout, variant), (match, trace) in zip(jobs, pool.map(run, jobs)):
            assert match["start_poses"] == starts.setdefault((seed, layout), match["start_poses"]), match
            row = metrics(match, trace)
            assert all(math.isfinite(row[k]) for k in ("peak_depth", "peak_speed", "peak_lift", "lowest_root")), row
            rows[variant].append(row)
            if args.split == "parity":
                full, full_trace = run_match(args.godot, root, seed, layout, variant, episode=True)
                combat_fields = set(match) - {"duration", "intro_duration", "showcase_duration"}
                differences = [k for k in sorted(combat_fields) if match[k] != full[k]]
                if differences or trace != full_trace:
                    raise AssertionError(f"Parity {variant}/{layout}/{seed}: {differences}, trace equal={trace == full_trace}")

    if len(layouts) == 2:
        for seed in selected:
            for original, swapped in zip(starts[seed, "standard"], starts[seed, "swapped"]):
                assert original[:2] == [-x for x in swapped[:2]]
                assert math.isclose(math.cos(original[2] - swapped[2]), -1, abs_tol=1e-6)
    summary = {"split": args.split, "seeds": selected, "layouts": layouts}
    for variant, matches in rows.items():
        summary[variant] = {"combined": aggregate(matches), "matches": matches,
                            **{layout: aggregate([r for r in matches if r["start"] == layout]) for layout in layouts}}
        print(variant, json.dumps(summary[variant]["combined"]))
    if args.split == "parity":
        summary["identical_combat_reports_and_traces"] = len(jobs)
        print(f"Parity passed in {len(jobs)} pairs")
    (root / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
