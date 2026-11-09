# Riptide route evaluation protocol

The experiment starts at `6d59c0b6ce46ae8158984bb0821e235780eeaed6`. Tracked physics, Bulldozer's baseline and `tracked-intercept` are frozen. Use the functional tracked review scene for every start. Test Riptide's `baseline`, `tracked-flank` and `tracked-routes` independently against each Bulldozer. The six pairings share 20 fresh seeds with both starting layouts. The development-only `recovery-control` reuses the original recovery controller with `tracked-flank` attack and approach.

The commit introducing this protocol and the reserved manifest freezes the policies, criteria and measurement. Use the manifest from a clean checkout. The [development list](seeds-development.json) contains known cases. [Reserved seeds](seeds-reserved.json) are sampled from a fresh range with no overlap with prior manifests. Do no additional tuning after evaluating them.

## Measurements

Use the existing tracked [evaluation protocol](../tracked-ai-01/PROTOCOL.md) for wins, actual HP damage, damaging attack passes, true side/rear hit position, stalls, physical pins, retreat, quiet gaps and solver flags. Historical metrics remain in the trace and JSON. Additional recovery measurements use the same replay's 5 Hz combat samples and exact logged transition and strike times.

- Initial separation retains the existing requirement of 0.45 m gap growth, 0.35 m own displacement and 0.13 seconds clear of the opponent. Count a sustained escape when the next 1.0 seconds stay contact-free and preserve 0.20 m of gap growth at every sample. Report per recovery attempt, with clean but incomplete follow-up reported separately.
- Rapid recapture means two consecutive 5 Hz samples of simultaneous wall and opponent contact or of close slow pressure (gap below 3.15 m, own planar speed below 0.65 m/s), within 1.6 seconds of initial separation and before the next Riptide damage event. A scoring return or full window closes an observed result. Track censoring at fight end. This captures renewed pressure beside the rail as well as physical pins.
- A repeated recovery link starts within 0.60 seconds of the prior attempt ending with no intervening Riptide damage, with either attempt near the rail or the prior attempt failing to separate. Report links per fight. Count every logged recovery attempt even when it never separates.
- Time to next meaningful attack is the time from a recovery ending to Riptide's next awarded strike. Report the median among observed strikes and the count of attempts censored by fight end. The same strike may be the next strike for multiple preceding attempts.

## Adoption criteria

Evaluate each opponent separately across its 40 reserved starts. Treat wins and single replays as descriptive. Adoption as the proposed tracked policy requires evidence across both opponents.

- Against baseline Bulldozer, retain conversion within 8 percentage points of `tracked-flank` and improve mean HP damage margin over original Riptide by at least 5 HP. Against `tracked-intercept`, improve margin over `tracked-flank` by at least 15 HP and stay within 8 HP of original Riptide. Retain conversion within 8 points of original Riptide against `tracked-intercept`. Report real side/rear hits and damage as corroboration.
- Against each opponent, improve at least two of the following over `tracked-flank`: sustained escape rate by at least 3 percentage points, rapid recapture rate by at least 10 percentage points, or repeated recovery links per fight by at least 20%. Mean physical pin time may rise by at most 0.25 seconds and stalled time by at most 0.75 seconds.
- Mean longest quiet gap may rise by at most 1.0 seconds and retreat share by at most 5 points versus `tracked-flank` against either opponent. Check recorded behavior alongside these metrics. Missing results, trace/presentation disagreement, non-finite state or materially worse physical instability prevent adoption. Retain warnings and solver outliers with all results.
