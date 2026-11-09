# R08 episode validation

Verified on Windows with Godot 4.7.2, the Compatibility renderer, and the existing Movie Maker launcher. All three recordings were 720 × 1280 at 30 FPS with H.264 video and stereo AAC. Each recorded exactly one result. Combat audio was audible in all three.

| Seed | Natural result | Fight | Showcase | Encoded episode |
| --- | --- | ---: | ---: | ---: |
| [25](../../renders/episode-pass/fight-seed-25.mp4) | Bulldozer by knockout, 155/200 HP | 20.428 s | 5.000 s | 35.43 s / 1063 frames |
| [13](../../renders/episode-pass/fight-seed-13.mp4) | Bulldozer by knockout, 175/200 HP | 24.550 s | 5.000 s | 39.57 s / 1187 frames |
| 1, timeout check | Bulldozer on health remaining, 65% vs. 42% | 25.000 s | 5.000 s | 40.03 s / 1201 frames |

- Reviewed the first and last encoded frames, both studio cuts, and the transition to the result. Riptide opens on frame 0, Bulldozer enters on frame 150, and the arena with 25 seconds on the HUD enters on frame 300. Both profiles reveal Health, Speed, Attack and fighting style at 0.5, 1.0, 1.5 and 2.0 seconds within their shots. The stats match the shared combat definitions (150, 10, 25 and 200, 5, 30).
- The two knockout showcases show worn armour, a damaged drum and operational drive. The timeout showcase shows the disabled drum from seed 1. The [isolated draw fixture](draw-fixture.png) verifies both robots at 60%, a disabled saw, a missing wheel and accurate partial-drive status. The frozen arena retains its physical colliders and detached wheels stay absent from the display copies.
- Fifteen focused checks passed, including collision and drive cases, the intro clock, early knockout, percentage scoring, simultaneous knockout, result immutability and fresh-state reset. The live **R** shortcut also restored the first studio shot and cleared the previous fight state. Twelve [seeded headless runs](headless-results.json) passed the score, lifecycle and solver checks.

## Differences from R07

The live arena stays frozen throughout the opening, so the earlier pre-fight spool-up no longer influences the seeded trajectories. R08 cuts at the deciding tick and freezes the arena during the showcase. Its terminal collision depth is measured at that tick, before any post-match settling. The combat tuning, collision shapes, imported assets, arena camera and impact audio are carried forward.

The recorder rounds to full frames. The natural timeout uses exactly 40 seconds of simulation time, with one additional frame showing the final showcase pose. The draw was verified in an isolated fixture.
