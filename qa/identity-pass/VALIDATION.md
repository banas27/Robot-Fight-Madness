# R07 robot identity validation

The [seed 25](../../renders/identity-pass/fight-seed-25.mp4) and [seed 13](../../renders/identity-pass/fight-seed-13.mp4) recordings are 27.43-second vertical MP4s at 720 × 1280 and 30 fps with stereo audio. Both used the existing recording launcher. Their combat events matched repeat headless runs. The 2.6-second matchup intro and result cards were checked at 360 × 640. The camera and collision fit use the existing code.

## Definitions and scoring

The saw and drum entries in `config/combat.json` supply the name, weapon, maximum HP, speed rating, base attack and intro text. The same definitions feed the HUD and combat. `intro_seconds` sets the opening duration, with a supported range of 0.5–6 seconds.

| Robot | Max HP | Speed rating | Undamaged drive speed | Base attack |
| --- | ---: | ---: | ---: | ---: |
| Riptide | 150 | 10 | 5.20 | 25 |
| Bulldozer | 200 | 5 | 2.60 | 30 |

The speed rating is multiplied by 0.52 world units per second per point. Bounded motor force compensates nominal deck resistance near cruising speed. A straight-line physics fixture measured 5.20 and 2.60 with the existing fitted bodies on an undamaged deck. Riptide has quicker acceleration and yaw response. Contact, braking and component damage change the speeds seen during a fight.

For an accepted tooth hit, damage is the base attack multiplied by `0.51 + 0.49 × contact strength` and rounded to the nearest integer. Contact qualification, cooldowns of 0.76 s and 0.84 s, and 0.13 s of clear contact for rearming still apply. The existing component thresholds are measured in local damage, so the new attack values can progress component wear in fewer qualifying hits.

Timeout compares the unrounded remaining HP ratios. An absolute ratio difference of 0.000001 or less is a draw. The result freezes both HP totals and ratios, and adds display precision when normal rounding would hide the winner's lead. Knockout precedence and double-knockout draws still apply.

## Tactical validation

Riptide chooses a side or rear lane with wall clearance, steers around the front and samples bounded translational lead every 150 ms. It keeps the lane orientation committed, turns the saw in, and times the short pass from alignment or contact. A reachable sidestep can divert a developing charge. Bulldozer lines up, holds a charge heading within a small correction, and pushes on frontal contact. A miss or lost contact enters a brake and realignment phase. The existing guard, press and no-drive behavior applies after component failure.

| Seed | Riptide HP | Bulldozer HP | Result | Hits, saw / drum |
| --- | ---: | ---: | --- | --- |
| 25 | 99 / 150 | 72 / 200 | Riptide, 66.0% vs 36.0% | 6 / 2 |
| 13 | 56 / 150 | 134 / 200 | Bulldozer, 67.0% vs 37.3% | 3 / 4 |
| 3 | 61 / 150 | 107 / 200 | Bulldozer, 53.5% vs 40.7% | 4 / 4 |
| 5 | 37 / 150 | 138 / 200 | Bulldozer, 69.0% vs 24.7% | 3 / 4 |
| 17 | 7 / 150 | 175 / 200 | Bulldozer, 87.5% vs 4.7% | 1 / 6 |

The [seed 25 trace](after-trace-25.json) shows two side strikes to the chassis and 3.64 seconds of Bulldozer's pressure state. Seed 5 also produced a side strike. The five traced runs selected side lanes. Rear lanes remain available when the pose and rail clearance favour them. A controlled missed-charge fixture confirmed braking and realignment without damage. Some side attempts still meet the drum or yield a frontal support hit as Bulldozer turns. The longest interval below 0.45 world units per second in the five traced runs was 3.21 seconds. This speed measure includes aiming in place.

Fourteen [focused checks](fixtures.log) and thirteen [seeded simulations](headless-results.json) passed. They cover solver contacts, single hits during sustained contact, wall-pin escape with damaged drive, component state, the measured speed ratio, close percentage decisions, and fresh matches. The largest reported penetration was 127 mm and the longest episode above 25 mm lasted 39 ms. The maximum on a final tick was 10 mm. The 180 Hz solver still evaluates contact in discrete steps.
