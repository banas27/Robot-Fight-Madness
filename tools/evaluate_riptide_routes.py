#!/usr/bin/env python3
"""Compare Riptide routes against two frozen tracked Bulldozer policies."""
from bisect import bisect_right
import math
import statistics

from evaluate_tracked_ai import PROJECT, main

QA = PROJECT / "qa/riptide-routes-02"
PAIRINGS = {
    f"{saw}-{opponent}": (saw, drum)
    for saw in ("baseline", "tracked-flank", "tracked-routes")
    for opponent, drum in (("base", "baseline"), ("intercept", "tracked-intercept"))
}
CONTROLS = {
    "control-base": ("recovery-control", "baseline"),
    "control-intercept": ("recovery-control", "tracked-intercept"),
}
KNOWN = (13, 25, 36157, 7698, 3005, 35901, 95440)
SUSTAIN_WINDOW = 1.0
RECAPTURE_WINDOW = 1.6
LOOP_WINDOW = 0.60


def measure_routes(match, trace):
    saw = trace["robots"][0]
    exits = saw["recoveries"]
    samples = saw["samples"]
    times = [s["time"] for s in samples]
    strikes = [h["time"] for h in trace["strikes"] if h["attacker"] == "Riptide"]
    end = match["fight_duration"]
    results = {"sustained": 0, "sustain_censored": 0, "recaptured": 0, "recapture_observed": 0,
               "recapture_censored": 0, "loop_links": 0, "next_damage_delay": [], "next_damage_censored": 0}
    for i, attempt in enumerate(exits):
        finish = attempt["end"]
        next_hit = bisect_right(strikes, finish)
        if next_hit < len(strikes):
            results["next_damage_delay"].append(strikes[next_hit] - finish)
        else:
            results["next_damage_censored"] += 1
        if i > 0:
            prior = exits[i - 1]
            after_prior = bisect_right(strikes, prior["end"])
            no_hit = after_prior == len(strikes) or strikes[after_prior] >= attempt["start"]
            if (attempt["start"] - prior["end"] <= LOOP_WINDOW and no_hit
                    and (prior["rail"] or attempt["rail"] or not prior["separated"])):
                results["loop_links"] += 1
        if not attempt["separated"]:
            continue
        separated = attempt["separation_at"]
        first = bisect_right(times, separated)
        follow = samples[first:bisect_right(times, separated + RECAPTURE_WINDOW)]
        floor = attempt["gap"] + 0.20
        sustain = [s for s in follow if s["time"] <= separated + SUSTAIN_WINDOW + 1e-6]
        held = all(not s["contact"] and s["gap"] >= floor for s in sustain)
        complete = end >= separated + SUSTAIN_WINDOW
        results["sustained"] += int(held and complete)
        results["sustain_censored"] += int(held and not complete)
        last_hit = bisect_right(strikes, separated)
        scoring_return = strikes[last_hit] if last_hit < len(strikes) else math.inf
        stuck_samples = 0
        captured = False
        for sample in follow:
            if sample["time"] >= scoring_return:
                break
            # Pressure can persist beside a rail with no actual wall manifold.
            speed = math.hypot(sample["velocity"][0], sample["velocity"][2])
            slow_close = sample["gap"] < 3.15 and speed < 0.65
            pressured = sample["wall"] and sample["contact"] or slow_close
            stuck_samples = stuck_samples + 1 if pressured else 0
            if stuck_samples >= 2:
                captured = True
                break
        known = captured or min(end, scoring_return) >= separated + RECAPTURE_WINDOW or scoring_return <= end
        results["recaptured"] += int(captured)
        results["recapture_observed"] += int(known)
        results["recapture_censored"] += int(not known)
    return {"routes": results}


def summarize_routes(rows):
    routes = [r["routes"] for r in rows]
    sums = {key: sum(x[key] for x in routes) for key in routes[0] if key != "next_damage_delay"}
    delays = [delay for x in routes for delay in x["next_damage_delay"]]
    attempts = sum(r["robots"][0]["recoveries"] for r in rows)
    return {"routes": {
        **sums,
        "attempts_per_fight": round(attempts / len(rows), 3),
        "sustained_pct": round(100 * sums["sustained"] / max(attempts, 1), 2),
        "recapture_pct": round(100 * sums["recaptured"] / max(sums["recapture_observed"], 1), 2),
        "loops_per_fight": round(sums["loop_links"] / len(rows), 3),
        "next_damage_observed": len(delays),
        "next_damage_median_s": round(statistics.median(delays), 3) if delays else None,
        "retreat_pct": round(100 * sum(r["robots"][0]["retreat_s"] for r in rows) / sum(r["fight_s"] for r in rows), 2),
    }}


if __name__ == "__main__":
    main(pairings=PAIRINGS, reserved=QA / "seeds-reserved.json", development=QA / "seeds-development.json",
         diagnostics=KNOWN, diagnostic_pairings=CONTROLS, extra_metrics=measure_routes, extra_summary=summarize_routes)
