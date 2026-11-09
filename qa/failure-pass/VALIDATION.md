# R06 capability, wheel state and result validation

[Seed 25](../../renders/failure-pass/fight-seed-25.mp4) and [seed 13](../../renders/failure-pass/fight-seed-13.mp4) are 25.83-second MP4s at 720 × 1280 and 30 fps with stereo audio. Both used the normal recording launcher and matched their headless combat event logs. The R05 project was saved before edits and reproduced the five baseline results. The camera code, scale, existing GLBs, standard collision fit, weapon strike rules, base damage and launcher matched that baseline.

In [R05 seed 13](../../renders/recovery-pass/fight-seed-13.mp4), the drum was disabled at 17.233 s of combat and physically stopped at 17.739 s. Bulldozer still spent 0.94 s in its attack state after the failure. Riptide spent 4.48 of the remaining 4.77 s recovering or repositioning. Its seven saw-to-support contact ticks included the disabling strike and ended at 17.650 s, while the hit was still rearming. Most of the other weapon contacts were against the drum itself. The last seconds went quiet because the tactical states gave Riptide few useful contacts and the ordinary rearm rule blocked repeat damage from the last hit.

R06 immediately switches an unarmed robot to guard, reposition or chassis pushing with its ordinary drive and solid colliders. An armed opponent uses pressure and shorter flank approaches against the exposed body. Walls and the disabled weapon's physical shape still matter. In R06 seed 13 the disablement and spin-down occurred at the same times. Riptide then landed two more support strikes at 18.567 and 20.150 s. Bulldozer dealt no further damage. Contact can still be sustained without producing another scoring opportunity.

| Seed | R05 HP, Riptide / Bulldozer | R06 HP, Riptide / Bulldozer |
| --- | --- | --- |
| 25 | 41 / 50 | 17 / 61 |
| 13 | 70 / 34 | 70 / 14 |
| 3 | 85 / 62 | 85 / 62 |
| 5 | 44 / 41 | 44 / 41 |
| 17 | 28 / 59 | 10 / 81 |

Damaged wheels carry scuff marks. A failed drive has a pale cross on its hub and still rolls passively on the chassis. A continued hit to the same wheel can break the mount at 72 accumulated local damage. At that point the wheel's mesh, tire and hub colliders transfer to a separate rigid body and leave an empty axle. The loose wheel interacts with the deck and rails and cannot score or affect either combatant. The existing chassis physics constrains pitch and roll, so lost support does not add a chassis tipping simulation. Detachment was validated in a controlled fixture and did not occur in the delivered matches. Reduced drive changes turn and gear choices without restoring motor force. Complete drive loss enters hold.

The timeout winner is the robot with higher remaining HP. Equal HP is a draw. Both preselected contacts on the last tick resolve before the outcome, and a knockout takes precedence over expiry. A simultaneous knockout is a draw. The HUD keeps its original positions and adds the rule and both final HP values inside the result card. The top bars and result card use the frozen totals. Result state rejects further strikes.

- Twelve [focused checks](fixtures.log) passed, including attached versus detached wheel support, physical escape with a failed drive, total drive loss, an unarmed opponent, frozen result, timeout tie, last-tick double knockout, and match reset.
- Thirteen [seeded checks](headless-results.json) passed. The maximum reported weapon overlap was 97 mm, the longest episode over 25 mm was 83 ms, and all final ticks had zero weapon depth.
- Three alternating uncapped seed-25 runs on the RTX 5070 Ti measured median p95 frame times of 3.14 ms in R05 and 3.15 ms in R06. Both are within the 33.3 ms budget at 30 fps.
- The [baseline trace](before-trace-13.json) and [R06 trace](after-trace-13.json) show the state and contact changes after drum failure. [Wheel fixture](detached-wheel-fixture.png), [timeout draw](timeout-draw-fixture.png), and [double knockout](double-ko-fixture.png) show the controlled visual checks.
