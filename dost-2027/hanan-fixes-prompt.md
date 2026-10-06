# Prompt: Fix the issues found on the `hanan` branch

Paste everything below the line into Claude Code, opened at the root of the DOST2027 repo, with the `hanan` branch checked out.

---

Fix the problems below on the `hanan` branch of this Godot 4.7 project (GDScript, project in `dost-2027/`). Read each file named before changing it. Match the existing style: tab indentation, typed GDScript, and short comments explaining *why*. Keep each fix minimal, and commit each numbered fix separately on `hanan` with a clear message. Don't push.

Run checks with `godot --headless --path dost-2027 -s res://tools/<file>.gd`. Before you start, run every check in `tools/` and note the results. After the fixes, all of them should pass with no `SCRIPT ERROR` and no "Failed to create an autoload" lines.

## 1. Remove the uncommitted `godot_ai` addon from `project.godot`
`project.godot` has the autoload `_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"` and an `[editor_plugins]` section enabling `res://addons/godot_ai/plugin.cfg`. `addons/` is not in the repo, so every launch logs "Failed to create an autoload" errors.
- Remove the autoload line and the `[editor_plugins]` section (or just that entry if other plugins are listed). Keep `Network`, `Global` and `Settings` in their current order.
- Add `addons/godot_ai/` to `.gitignore` so a local copy of the tool can't sneak back into a commit. If the Godot editor re-adds these lines when the plugin is enabled locally, mention that in your summary. Don't fight it in code.

## 2. Make screen blocks cover Hanan's balance bar
In `scenes/gods/hanan/HananArena.tscn`, `HananHud` is a CanvasLayer on **layer 12**. That's above `Patches` (11, Apolaki's sun patches) and `VisionLayer` (5, Mayari's blackout) from `scenes/gods/common/Arena.tscn`. So Half Vision, sun patches and the Sibling's Rivalry blocks do nothing in Hanan's trial.
- Put the **bar** (`HananHud/Bar`) on a layer **below 5**, so both the blackout and the sun patches draw over it.
- Keep the **status, callout and hint labels** readable: leave them on a high layer, or split them into a second CanvasLayer.
- Mayari's blackout leaves a lit circle around the mortal (`_apply_blindness` in `arena.gd`). Position the bar next to the mortal (follow the player's screen position, clamped to the screen), so a blinded player can still see *part* of it, the same way the other trials work under Half Vision. Keep it a Control under a CanvasLayer so the existing sizing code in `_refresh_hud` still works.
- Extend `tools/hanan_check.gd`:
  - The bar's layer is lower than both `VisionLayer` and `Patches`.
  - The labels are still drawn above them.

## 3. Don't punish opening the God's Due menu mid-vault
In `scripts/gods/hanan/hanan_arena.gd`, `_step_indicator` treats the button as released while `due_menu.is_open()` or `dialogue.is_active()`. The indicator falls out of the box and the player trips for −120.
- While the menu or dialogue is open during a vault, **freeze the vault**: the indicator, the box, `_vault_left` and `_outside_time` all stop. Don't bank FAVOR while frozen.
- When the menu closes, resume exactly where it left off. Reset `_holding` from the real button state (`Input.is_action_pressed("attack")`) so a click used inside the menu doesn't count as a hold.
- Add a check to `tools/hanan_check.gd`: open the due menu mid-vault for longer than `grace_time`, close it, and the mortal has not tripped and the box hasn't moved.

## 4. Break of Day must end every running effect, including arena-side ones
`GodMatch.break_of_day()` clears the target's `durations` and `loss_immunity`. Two effects live in `scripts/gods/common/arena.gd` instead, so they keep running:
- **Apolaki's Sibling's Compromise (`siblings_compromise_sun`):** it fills `_double_loss[victim]` and adds sun patches to every other mortal. `_double_loss` isn't keyed by caster, so record who started each entry (e.g. a parallel `_double_loss_source: Dictionary`, victim id → caster id). When Break of Day hits that caster, remove those `_double_loss` entries and the sun patches that cast added. Track the patch source the same way if needed, then `_publish_god_state()` so clients drop them too.
- **Tala's Let Us Light Your Way:** `_movement_override_caster` / `_movement_override_time` run on **every** machine (started locally and via `Network.send_arena_movement_override`).
  - When Break of Day targets that caster, end the override everywhere: set `_movement_override_time = 0.0` on the host and send a cancel to clients.
  - Simplest is to reuse the existing RPC with duration `0.0`. Make `_start_movement_override` / `_on_movement_override_received` treat 0 as "stop now" instead of `maxf(...)`.
- Do this in the arena's `break_of_day` branch of `_apply_skill_effect`, after `rules.break_of_day(caster_id)` returns the target id. Keep `GodMatch.break_of_day` as the rules-side part.
- Extend `tools/hanan_favor_check.gd`. Break of Day on a mortal that's mid-Compromise and mid-Light-Your-Way ends:
  - the double loss on their victims
  - the patches they added
  - the movement override

## 5. Don't lose FAVOR when the trial ends mid-vault
In `_tick_hanan`, when `_phase != Phase.PLAYING` and a vault is in progress, the code calls `_leave_vault()` without `_bank()`. Up to `bank_interval` seconds of `_pending_gain` is dropped.
- Call `_bank()` before leaving the vault there. Make sure the score still reaches the host: if `score_favor` is ignored once the phase has changed, bank in `_end_trial` before the phase flips. The base's `_end_trial` is in `arena.gd`, so override it in `HananArena` and call `super()`.
- Add a check: end the trial mid-vault with pending gain, and the FAVOR is banked.

## 6. Hanan art: placeholders ready to swap
There's no `Assets/Gods/Hanan/` folder yet:
- the Baka is a `ColorRect`
- the background reuses `Assets/Gods/Mayari/AreanaTemp.png`
- `hanan.tres` uses `res://icon.svg` as her icon

Don't invent final art. Make it drop-in:
- Create `Assets/Gods/Hanan/` with a `README.md` listing the files the scene expects:
  - `Hanan-Icon.png` (portrait, same size as `Assets/Gods/Tala/Tala-Icon.png`)
  - `Baka.png` (the crouching Baka; a horizontal strip of frames for the 5 heights if possible)
  - `Hanan-Overseer.png` (her sprite watching the field, like Tala's overseer)
  - `Arena-Background.png`
- Replace the Baka's `ColorRect` with a `Sprite2D` (keep the node path `ArenaField/Baka` and the `Name` label) that uses `Baka.png` if it exists and falls back to the current coloured rectangle if not. Keep the level-based height scaling in `_enter_run` working for both.
- Add an `Overseer` node like Tala's that shows `Hanan-Overseer.png` when present and hides otherwise.
- Point the background and `hanan.tres`'s `icon` at the Hanan files with the same fallback rule. If a `.tres` can't fall back by itself, keep `icon.svg` and leave a note in the README to swap it.
- `tools/scene_check.gd` and `tools/god_audit.gd` must still pass with the art files absent.

## 7. Fix the two checks that were already failing on `main`
These aren't caused by Hanan, but they should go green too:
- **`tools/shock_check.gd`:** its `FakeNet` is missing `publish_mortal_positions(positions: Dictionary)`, which `Arena._publish_positions` calls (see `scripts/Network.gd`, around line 1162). Add a no-op stub with the same signature, and check `Network.gd` for any other methods the arena calls that FakeNet lacks.
- **`tools/lobby_check.gd`:** it saves screenshots with `root.get_texture().get_image()`, which returns null under `--headless`, so the check crashes and then hangs until it's killed. When the image is null (or `DisplayServer.get_name() == "headless"`), skip the screenshot with a printed note instead of crashing. The rest of the check must still run and the script must reach `quit()`.

## When you're done
Run every check in `tools/` and give me:
- a before/after table of the results
- the commits you made
- anything you had to interpret, or left for me to decide
