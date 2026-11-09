#!/usr/bin/env python3
"""Evaluate the larger-arena episode policies with matched starts."""
from evaluate_arena_space import LARGER, arena_metrics, arena_summary
from evaluate_tracked_ai import PROJECT, main

PAIRINGS = {
    "reference": ("tracked-routes", "tracked-intercept"),
    "peel": ("tracked-peel", "tracked-intercept"),
    "pressure": ("tracked-routes", "tracked-pressure"),
    "combined": ("tracked-peel", "tracked-pressure"),
}
SCENES = {name: (LARGER, "larger") for name in PAIRINGS}

if __name__ == "__main__":
    main(pairings=PAIRINGS, reserved=PROJECT / "qa/episode-001/seeds-confirmation.json",
         development=PROJECT / "qa/episode-001/seeds-development.json", diagnostics=(13, 25, 337082),
         extra_metrics=arena_metrics, extra_summary=arena_summary, scene_options=SCENES)
