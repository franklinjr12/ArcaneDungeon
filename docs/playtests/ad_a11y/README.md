# AD-083 reduce flash / reduce shake: OFF/ON screenshots

Date: 2026-11-02. Seed: 20261022 (same as `tests/capture_p1_fx.gd`).

Command:

    xvfb-run -a godot --path . --script res://tests/capture_ad_reduce_motion.gd -- docs/playtests/ad_a11y

(A fresh checkout needs `godot --headless --path . --import` once first.)

Both images are the same session state: the scripted run policy fights until a boss dash-lane
telegraph is live, then `player.hit_flash = 12` is set and the canvas is drawn with two settings objects.

- `reduce_off.png`: `reduce_flashes=false`, `screen_shake=true`. Hit flash box on the player, hit sparks, and the frame is shifted by the shake offset.
- `reduce_on.png`: `reduce_flashes=true`, `screen_shake=false`. No flash box or overlay; the player gets a steady reddish tint, no shake offset (the frame is 3 px to the right of the OFF one, which is shifted by the shake).
- In both, the red dash-lane telegraph and enemy ground rings remain clearly visible.

Shake cannot be seen in a still image. The shake amplitude (3 px peak) is [PROPOSED FOR PROTOTYPE].
Evidence for shake, arc and boss-phase sources is the unit suite `tests/test_ad_reduce_motion.gd`.
