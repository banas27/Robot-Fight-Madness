# R05 combat recovery validation

The [new seed 25 recording](../../renders/recovery-pass/fight-seed-25.mp4) and [seed 13 recording](../../renders/recovery-pass/fight-seed-13.mp4) are 25.83-second MP4s at 720 × 1280 and 30 fps with stereo audio. Both were recorded through the existing launcher and matched their headless event logs. Seed 13 shows a real drum shutdown and a Riptide win.

## Diagnosis and changes

The [R04 seed 25 baseline](../../renders/style-pass/fight-seed-25.mp4) reproduced the wheel hit and the 19-HP strike at video time 11.51 s. Riptide lost 13.8% grip after the first 15-damage wheel hit. Another hit to the same wheel reached the old penalty cap, leaving later hits to that wheel with no further drive consequence. Riptide often broke contact successfully but returned to the drum's front when the recovery timer expired. It spent 12.43 seconds near a rail, including 5.14 seconds near a corner, and only 0.44 seconds in simultaneous rail and opponent contact. This was mostly a pattern of frontal re-entry.

Recovery now scores candidate routes against the drum's heading, rail clearance, turning cost and the previous failed route. It allows one reroute when blocked and more time with reduced grip. Riptide looks for a clear gap before moving toward a flank and still commits to a pass after a bounded wait. Bulldozer keeps its committed charge with a tighter steering correction and takes time to realign before the next one.

Wheel damage has three thresholds at 8, 19 and 39 accumulated damage on the actual struck wheel. The same 15-damage first hit now costs 6.4% grip. A failed drive costs 24% for that wheel and leaves the attached wheel supporting the chassis and rolling passively. Wheel visuals and alerts follow the stage. Armour and weapon support damage still follow actual solver strikes.

The 19-HP baseline strike already used a rotor tangent impulse at the contact point. The chassis yawed 2.2° and changed planar velocity by up to 0.87 m/s over the next 160 ms. R05 briefly eases motor torque and traction control for substantial hits so they do not immediately cancel the existing response. It keeps the impulse calculation and gives major hits a short spark fan and light pulse. In the new seed 25, the 18-HP hit at video time 11.25 s produced 6.8° of yaw and up to 1.31 m/s change in planar velocity over that window. These were different contacts and illustrate the observed reactions.

## Fixed seed comparison

Hit counts are in Riptide / Bulldozer order. Recovery success means a gain of at least 0.45 m in center spacing with at least 130 ms free of opponent contact during the attempt. Rail time uses a 1.66 m margin around the arena. Corner time requires being within that margin of two rails. Slow contact is peer contact below 0.65 m/s planar speed.

| Seed | R04 hits | R05 hits | Riptide clear recoveries R04 → R05 | R05 winner |
| --- | ---: | ---: | ---: | --- |
| 25 | 2 / 7 | 5 / 4 | 6/8 → 4/7 | Bulldozer, 50–41 HP |
| 3 | 10 / 2 | 4 / 1 | 1/10 → 5/7 | Riptide, 85–62 HP |
| 5 | 5 / 7 | 6 / 4 | 2/10 → 7/7 | Riptide, 44–41 HP |
| 13 | 2 / 7 | 7 / 2 | 4/7 → 5/7 | Riptide, 70–34 HP |
| 17 | 2 / 3 | 4 / 5 | 7/11 → 4/7 | Bulldozer, 59–28 HP |

Across the five seeds, Riptide spent 44.0 of 93.8 fight seconds near rails before and 29.7 of 110 after. Corner time fell from 6.19 seconds to zero. Clear recoveries improved from 20/46 to 25/35 overall. In seed 25, rail time dropped to 8.97 seconds and there were no simultaneous rail and opponent contacts. Slow contact increased from 0.87 to 2.06 seconds in seed 25 and from 9.53 to 12.39 seconds across the five seeds. Recovery remains dependent on available space and mobility.

Ten [focused checks](fixtures.log) passed, including a wall-pin escape with a failed wheel drive. The damaged fixture gained 1.08 m of clearance and repeated damage to the failed drive did not add another penalty. Thirteen [seeded matches](headless-results.json) passed scoring, cooldown, damage, winner and collision checks. Maximum reported weapon depth was 97 mm, the longest run above 25 mm was 83 ms, and final reported weapon depth was zero in all 13.

Three alternating uncapped seed-25 runs on the RTX 5070 Ti put median p95 frame time at 3.09 ms for R04 and 3.47 ms for R05. This is a 0.38 ms increase against a 33.3 ms budget at 30 fps. The GLBs, collision shapes, strike gates, base damage configuration, camera code and UI layout matched the baseline.

The [seed 25 before trace](before-trace-25.json) and [after trace](after-trace-25.json) include hit locations, grip, transitions, replan directions and clearance. Add `--trace=qa/recovery-pass/trace.json` after `--` to write an equivalent trace from a run. Traces have no viewer-facing overlay.
