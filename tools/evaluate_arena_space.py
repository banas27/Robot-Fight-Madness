#!/usr/bin/env python3
"""Compare arena space with identical seeds, starts and frozen robot policies."""
import math
import statistics

from evaluate_riptide_routes import measure_routes, summarize_routes
from evaluate_tracked_ai import PROJECT, SCENE, main

LARGER = "res://scenes/review/arena_tracked_bulldozer_large.tscn"
PAIRINGS = {
    "current-baseline": ("baseline", "baseline"),
    "larger-baseline": ("baseline", "baseline"),
    "current-routes": ("tracked-routes", "baseline"),
    "larger-routes": ("tracked-routes", "baseline"),
}
SCENES = {
    key: (LARGER, "larger") if key.startswith("larger") else (SCENE, "current")
    for key in PAIRINGS
}
QA = PROJECT / "qa/arena-space-test"


def arena_metrics(match, trace):
    scale = math.sqrt(2.0) if match["arena_variant"] == "larger" else 1.0
    width, length = match["usable_floor_m"]
    assert math.isclose(width, 7.9 * scale) and math.isclose(length, 10.3 * scale), match["usable_floor_m"]
    return {
        **measure_routes(match, trace),
        "arena_variant": match["arena_variant"],
        "usable_floor_m": match["usable_floor_m"],
        "first_damage_s": trace["strikes"][0]["time"] if trace["strikes"] else None,
        "exchange_gaps_s": trace["tracked_metrics"]["exchange_gaps_s"],
        "timeout": match["reason"].startswith("time limit"),
    }


def arena_summary(rows):
    hits = [row["first_damage_s"] for row in rows if row["first_damage_s"] is not None]
    gaps = [gap for row in rows for gap in row["exchange_gaps_s"]]
    return {
        **summarize_routes(rows),
        "arena_variant": rows[0]["arena_variant"],
        "usable_floor_m": rows[0]["usable_floor_m"],
        "first_damage_median_s": round(statistics.median(hits), 3) if hits else None,
        "no_damage_fights": len(rows) - len(hits),
        "exchange_gap_count": len(gaps),
        "mean_exchange_gap_s": round(statistics.mean(gaps), 3) if gaps else None,
        "timeouts": sum(row["timeout"] for row in rows),
    }


if __name__ == "__main__":
    main(pairings=PAIRINGS, reserved=QA / "seeds-confirmation.json", diagnostics=(13, 25, 337082),
         extra_metrics=arena_metrics, extra_summary=arena_summary, scene_options=SCENES)
