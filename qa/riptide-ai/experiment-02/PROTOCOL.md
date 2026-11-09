# Rail escape evaluation protocol

The development and reserved seeds are fixed in [seeds.json](seeds.json). Development uses known seeds. The previous evaluation seeds are known cases and remain available for regression work. Each reserved seed runs once per policy in each of the standard and 180°-rotated starts, giving 40 fights per policy at 180 Hz. The reserved runs compare `baseline` with `rail-exit` after the candidate is committed.

The candidate changes direction and gear selection during a recovery near a rail under opponent pressure. It inherits baseline attack decisions, recovery timing and motor commands. The original `candidate` selector remains available for comparison.

An opened gap requires 0.13 s without opponent contact, a gap increase of at least 0.45 m, and at least 0.35 m of Riptide movement. Starting at the first qualifying tick, an escape is sustained if for 0.60 s it keeps the gap at least 0.20 m wider than at recovery entry and avoids opponent contact. A simultaneous opponent and rail contact during the window counts as re-pinning. A match ending inside that window censors the follow-up. Sustained rail exit rate uses all rail-near recoveries except censored follow-ups. Re-pinning rate uses momentary rail exits with complete follow-up. Rail-near means either center coordinate starts within 1.66 m of its corresponding rail.

All of the following descriptive gates must hold on the reserved set to recommend further consideration.

- Riptide’s mean net damage improves by at least 3 HP per fight, and its damage dealt drops by no more than 2 HP.
- Average simultaneous rail and opponent contact falls by at least 0.05 s, and the sustained rail exit rate rises at least 5 percentage points.
- Immediate re-pinning rises no more than 2 percentage points and retreat share rises no more than 3 percentage points.
- There are no additional fights flagged by the existing solver stability thresholds.

Report wins, draws, side and rear hits, attack pass conversion, and both start layouts alongside the gates. A committed pass is an entry into `ATTACK`, and it converts if it deals damage before exit. The gates compare the complete damage exchange and recovery behavior. Baseline remains the default after review.
