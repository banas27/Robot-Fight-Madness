#!/usr/bin/env python3
"""Matched opt-in AI comparisons on the functional tracked arena."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import statistics
import subprocess

from evaluate_riptide import PROJECT, SEEDS, run_match, solver_outliers, metrics as saw_metrics

SCENE = "res://scenes/review/arena_tracked_bulldozer_test.tscn"
RESERVED = PROJECT / "qa/tracked-ai-01/seeds-reserved.json"
PAIRINGS = {
    "baseline": ("baseline", "baseline"),
    "riptide": ("tracked-flank", "baseline"),
    "bulldozer": ("baseline", "tracked-intercept"),
    "both": ("tracked-flank", "tracked-intercept"),
}
PARITY_KEYS = (
    "winner", "reason", "hp", "max_hp", "hits", "events", "other_impacts",
    "component_events", "final_conditions", "fight_duration", "start_poses",
    "maneuvers", "recoveries", "peak_speed", "peak_weapon_contact_depth", "lowest_root",
    "longest_weapon_depth_over_25mm", "max_arena_extent_ratio",
)


def fighter_metrics(bot, strikes):
    hits = [hit for hit in strikes if hit["attacker"] == bot["name"]]
    exits = bot["recoveries"]
    attempts = bot["passes"]
    return {
        "hit_passes": sum(p["hits"] > 0 for p in attempts),
        "passes": len(attempts),
        "side_rear": sum(h["zone"] != "front" for h in hits),
        "hits": len(hits),
        "pin_s": bot["pin_s"],
        "stalled_s": bot["stalled_s"],
        "retreat_s": sum(bot["state_seconds"].get(s, 0) for s in ("2", "7")),
        "escapes": sum(q["separated"] for q in exits),
        "recoveries": len(exits),
        "sustained": sum(q.get("sustained", False) for q in exits),
        "repins": sum(q.get("repinned", False) for q in exits),
        "unobserved_after_separation": sum(q.get("followup_censored", False) for q in exits),
    }


def case_metrics(match, trace, output):
    observed = trace["tracked_metrics"]
    row = {
        **saw_metrics(match, trace),
        "clashes": match["other_impacts"]["clash"],
        "longest_quiet_s": observed["longest_quiet_s"],
        "nonfinite_ticks": observed["nonfinite_ticks"],
        "first_nonfinite_s": observed["first_nonfinite_s"],
        "normalization_warnings": sum(
            "WARNING:" in line and "normaliz" in line.lower() for line in output.splitlines()
        ),
        "warnings": [line.strip() for line in output.splitlines() if "WARNING:" in line],
        "robots": [fighter_metrics(bot, trace["strikes"]) for bot in trace["robots"]],
    }
    for i, bot in enumerate(row["robots"]):
        bot["productive_push_s"] = observed["productive_push_s"][i]
        bot["ineffective_push_s"] = observed["push_s"][i] - bot["productive_push_s"]
    return row


def summarize(rows):
    def mean(values):
        return round(statistics.mean(values), 3)

    results = {
        "fights": len(rows),
        "wins": [sum(row["winner"] == name for row in rows) for name in ("RIPTIDE", "BULLDOZER", "DRAW")],
        "hp_percent": [mean(row["hp_percent"][i] for row in rows) for i in range(2)],
        "damage_dealt": [mean(row[key] for row in rows) for key in ("damage_dealt", "damage_received")],
        "clashes": sum(row["clashes"] for row in rows),
        "long_quiet_fights": sum(row["longest_quiet_s"] >= 5.0 for row in rows),
        "mean_longest_quiet_s": mean(row["longest_quiet_s"] for row in rows),
        "max_quiet_s": max(row["longest_quiet_s"] for row in rows),
        "normalization_warnings": sum(row["normalization_warnings"] for row in rows),
        "warning_fights": sum(bool(row["warnings"]) for row in rows),
        "nonfinite_ticks": sum(row["nonfinite_ticks"] for row in rows),
        "solver_outliers": solver_outliers(rows),
        "robots": [],
    }
    for i in range(2):
        records = [row["robots"][i] for row in rows]
        stats = {key: (mean(row[key] for row in records) if key.endswith("_s")
                       else sum(row[key] for row in records)) for key in records[0]}
        stats["conversion_pct"] = round(100 * stats["hit_passes"] / max(1, stats["passes"]), 2)
        results["robots"].append(stats)
    return results


def main(*, pairings=PAIRINGS, reserved=RESERVED, development=SEEDS, diagnostics=(),
         diagnostic_pairings=None, extra_metrics=None, extra_summary=None, scene_options=None):
    diagnostic_pairings = diagnostic_pairings or {}
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    splits = ("development", "reserved", "parity") + (("diagnostic",) if diagnostics else ())
    parser.add_argument("--split", choices=splits, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--pairings", nargs="+", choices=(*pairings, *diagnostic_pairings))
    parser.add_argument("--jobs", type=int, default=6)
    parser.add_argument("--contacts", action="store_true")
    args = parser.parse_args()
    selection = {**pairings, **diagnostic_pairings}
    args.pairings = args.pairings or list(pairings)
    if args.split in ("reserved", "parity") and any(key not in pairings for key in args.pairings):
        parser.error("Diagnostic controls are available only on known seeds")
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=True)
    if args.split == "parity":
        seeds = [13, 25]
    elif args.split == "diagnostic":
        seeds = list(diagnostics)
    else:
        manifest = reserved if args.split == "reserved" else development
        seeds = json.loads(manifest.read_text(encoding="utf-8"))[args.split]
        if len(seeds) != 20 or len(set(seeds)) != 20:
            parser.error("Expected exactly 20 distinct seeds")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=PROJECT, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=PROJECT, text=True).strip())
    if args.split == "reserved" and (dirty or set(args.pairings) != set(pairings)):
        parser.error("Reserved runs require a clean frozen checkout and all evaluation pairings")

    def run(case):
        pairing, seed, layout = case
        saw, drum = selection[pairing]
        scene, variant = (scene_options or {}).get(pairing, (SCENE, None))

        def run_one(episode=False, trace_level="standard"):
            return run_match(args.godot, root / pairing, seed, layout, saw, episode, trace_level,
                             scene=scene, extra_args=(f"--bulldozer-ai={drum}",), keep_log=True)
        level = "contacts" if args.contacts else "standard"
        try:
            match, trace = run_one(trace_level=level)
            assert match["bulldozer_ai"] == drum
            if variant is not None:
                assert match["arena_variant"] == variant, (scene, match["arena_variant"])
            assert (match["bulldozer_drive"], len(match["final_conditions"][1]["tracks"]),
                    len(match["final_conditions"][1]["road_wheels"])) == ("tracks", 2, 6)
            if args.split == "parity":
                for episode, run_level in ((False, "untraced"), (True, "untraced"), (True, level)):
                    alternate, _ = run_one(episode, run_level)
                    changed = [key for key in PARITY_KEYS if match[key] != alternate[key]]
                    if variant is not None:
                        assert alternate["arena_variant"] == variant
                        assert alternate["usable_floor_m"] == match["usable_floor_m"]
                    assert not changed, f"Parity differences {changed}, episode={episode}, trace={run_level}"
                    if episode:
                        assert abs(alternate["intro_duration"] - 10.0) < 1e-6
                        assert abs(alternate["showcase_duration"] - 5.0) < 1e-6
            suffix = "-contacts" if args.contacts else ""
            log = root / pairing / saw / layout / f"{seed}{suffix}.log"
            row = case_metrics(match, trace, log.read_text(encoding="utf-8"))
            if extra_metrics is not None:
                row.update(extra_metrics(match, trace))
            return case, row
        except (OSError, ValueError, AssertionError, KeyError, RuntimeError, TypeError, subprocess.TimeoutExpired) as exc:
            return case, {"error": str(exc) or type(exc).__name__}

    cases = [(pair, seed, layout) for pair in args.pairings for seed in seeds
             for layout in ("standard", "swapped")]
    with ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(run, cases))
    summary = {"commit": commit, "dirty": dirty, "split": args.split, "scene": SCENE,
               "seeds": seeds, "pairings": {}, "errors": [], "parity": args.split == "parity"}
    if scene_options:
        del summary["scene"]
        summary["scenes"] = {pair: scene_options[pair][0] for pair in args.pairings}
    by_pair = {pair: [] for pair in args.pairings}
    starts = {}
    for (pair, seed, layout), row in results:
        if "error" not in row:
            saw, _ = selection[pair]
            suffix = "-contacts" if args.contacts else ""
            report = root / pair / saw / layout / f"{seed}{suffix}.match.json"
            poses = json.loads(report.read_text(encoding="utf-8"))["start_poses"]
            if starts.setdefault((seed, layout), poses) != poses:
                row["error"] = "Unmatched starting pose"
        if "error" in row:
            summary["errors"].append({"pair": pair, "seed": seed, "start": layout, **row})
        else:
            by_pair[pair].append(row)
    def combined_summary(rows):
        return {**summarize(rows), **(extra_summary(rows) if extra_summary else {})}

    for pair, rows in by_pair.items():
        summary["pairings"][pair] = {
            "policies": selection[pair], "expected": 2 * len(seeds),
            "summary": combined_summary(rows) if rows else {},
            "by_layout": {layout: combined_summary([r for r in rows if r["start"] == layout])
                          for layout in {r["start"] for r in rows}},
            "rows": rows,
        }
    (root / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({pair: entry["summary"] for pair, entry in summary["pairings"].items()}, indent=2))
    if summary["errors"]:
        print(f"{len(summary['errors'])} failed runs retained in {root / 'summary.json'}")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
