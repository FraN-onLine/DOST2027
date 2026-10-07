# Prompt: Mapulon & Ikapati's arena (Langit Lupa), favors and god resource

Paste everything below the line into Claude Code, opened at the root of the DOST2027 repo on your machine. It builds on the `hanan` branch (options menu, Hanan, lobby options), so check that branch out first.

---

Add **Mapulon & Ikapati, the Harvest Pair**, to this Godot 4.7 project (GDScript, project in `dost-2027/`). They are one god resource for two gods: Mapulon, god of the seasons, and his wife Ikapati, goddess of cultivated land and the giver of food. They host **Langit Lupa**. They need a playable arena, seven favors, and a god resource so they join the random trial pool. Read the files named below before changing anything, and match the existing style: tab indentation, typed GDScript (`var x := ...`, `-> void`), and a comment block at the top of each script saying what it is for.

## Step 0: branch, and look for my work
- Start from the `hanan` branch and create a new branch `langit-lupa`. Commit there; don't push.
- Run `git status` and search case-insensitively for `mapulon`, `ikapati` and `langit`. If I already started a scene, script or art, read it fully and **build on it**: keep my node names, art and layout. Never delete my files, and tell me what you changed.
- `dost-2027/hanan-fixes-prompt.md` is a prompt file that got committed by mistake. Leave it alone; I'll handle it.

## How gods work in this repo (read these)
- `scripts/gods/god.gd` (`God`) and `scripts/gods/god_favor.gd` (`GodFavor`: `Slot {PASSIVE, E, Q}`, `Kind {PASSIVE, ACTIVE, INSTANT, END_OF_TRIAL}`, `cooldown`, `duration`, `params`, `requires_god_id()`, `requires_any_god_ids()`).
- `scripts/gods/gods.gd` (`Gods` registry) loads every `.tres` in `res://resources/gods/`. A god joins the random pool when `implemented = true` and it isn't Bathala. Add `MAPULON_IKAPATI := &"mapulon_ikapati"` and a `mapulon_ikapati()` helper like the others.
- `resources/gods/hanan.tres` is the newest god file and the template: favors as sub-resources, `epithet`, `color`, `icon`, `game_name`, `game_blurb`, `arena_scene`, `implemented`, `intro_lines`, `trial_end_lines`, `transition_lines` (keyed by next god id, `"*"` fallback).
- `scripts/gods/god_match.gd` (`GodMatch`) is the host-authoritative rules engine: FAVOR, God's Due, favors, cooldowns, durations, `add_favor` / `lose_favor` / `_apply`, `gain_multiplier` / `loss_multiplier`, `loss_history`, `begin_trial`, `_tick_mortal`, `end_trial`, `snapshot` / `apply_snapshot`. Hanan's favor rules live here (`_fire_instant_effect`, `restore_recent_losses`, `break_of_day`, `_highest_other`); put the new match-level rules next to them.
- `scripts/gods/common/arena.gd` (`Arena`): read its header comment first. It owns the round, the mortal, ghosts, `mortal_position()` / `mortal_entries()`, `bank_favor` / `lose_favor` / `score_favor`, mercy seconds (`set_mortal_invuln`), `knock_mortal`, `_apply_skill_effect`, `_end_arena_effects_of`, `_update_movement_favors`, and the network hooks `arena_rules_tick`, `arena_layout_fields` / `arena_read_layout`, `arena_tick_fields` / `arena_read_tick`.
- Langit Lupa is a **shared** arena: everyone is on one field and sees each other (`separate_players()` stays false, `shares_mortal_positions()` true). `scripts/gods/mayari/mayari_arena.gd` is the closest model for host-run rules on a shared field; `scripts/gods/hanan/hanan_arena.gd` and `scenes/gods/hanan/HananArena.tscn` are the newest example of an arena subclass, its HUD and its art placeholders (`Assets/Gods/Hanan/README.md`).
- `scripts/gods/common/mortal.gd` (`ArenaMortal`) moves the local mortal; positions travel client to host at `position_tick_rate`.
- `scripts/Game.gd` sets every arena's `trial_time` from the lobby (`RunSettings.trial_time`). `scripts/RunSettings.gd` and `scripts/lobby_options.gd` list the playable gods for the custom order; make sure the new god shows up there.
- Headless checks: `tools/*.gd` (`extends SceneTree`, PASS/FAIL, exit 1 on failure). Run with `godot --headless --path dost-2027 -s res://tools/<file>.gd`. `tools/hanan_check.gd` and `tools/hanan_favor_check.gd` are the closest examples; `tools/god_audit.gd` and `tools/scene_check.gd` keep lists of arena scenes.

## 1. The god resource: `resources/gods/mapulon_ikapati.tres`
- `id = &"mapulon_ikapati"`, `display_name = "MAPULON & IKAPATI"`, `epithet = "The Harvest Pair"`, `color` harvest green `Color(0.56, 0.78, 0.33, 1)`, `game_name = "LANGIT LUPA"`, `arena_scene = "res://scenes/gods/mapulon_ikapati/LangitLupaArena.tscn"`, `implemented = true`.
- `icon`: use `Assets/Gods/MapulonIkapati/` art if I've added any, else `res://icon.svg`.
- `game_blurb`: one or two sentences in the voice of the other blurbs: the Taya chases, the sky platforms (Langit) are safe until they crumble, and the less time you spend as Taya the more the pair pays you.
- **Dialogue.** They speak as a pair, so prefix each line with the speaker (`"Mapulon: ..."`, `"Ikapati: ..."`) and let them trade lines. Write `intro_lines`, `trial_end_lines`, and `transition_lines` for `mayari`, `apolaki`, `tala`, `hanan`, `bathala` and `"*"`. Lore to draw on:
  - Mapulon turns the seasons (the sky: when the rain comes, when the sun dries the field). Ikapati keeps the cultivated land and feeds the people (the earth: seed, root, harvest). Langit is his, Lupa is hers.
  - They are husband and wife, the only pair among the gods, and they finish each other's thoughts. They are patient, like farmers: everything they give grows over time.
  - Their daughter is Anagolay, goddess of lost things; a passing mention is welcome.
  - Sources disagree on details (some merge Ikapati with Lakapati). Stick to the parts above.
- Also add a `mapulon_ikapati` entry to the `transition_lines` of `mayari.tres`, `apolaki.tres`, `tala.tres` and `hanan.tres`, so every hand-over to them is written.

## 2. The arena: Langit Lupa (`LangitLupaArena`, `extends Arena`)
Files: `scenes/gods/mapulon_ikapati/LangitLupaArena.tscn` (inherits `scenes/gods/common/Arena.tscn`) and `scripts/gods/mapulon_ikapati/langit_lupa_arena.gd`. Shared field, tag game, host-authoritative. Rules from my design doc, with the open details filled in:

**Round length.** The design doc fixes Langit Lupa at **60 seconds**. Add an `@export var fixed_trial_time := 60.0` on this arena (0 means "use the lobby length") and make `Game.gd` respect it when it copies `settings.trial_time`, so the clock and HUD show 1:00.

**The Taya.**
- When the countdown ends (after `begin_trial()` has run, so First Light has already paid), the mortal with the **highest FAVOR** becomes the first Taya. Ties: random among the tied.
- The Taya wears a clear marker everyone can see (a "TAYA" tag and a ring in the pair's colour above the mortal).
- **Tagging:** the host checks, every rules tick, whether the Taya is within `tag_radius` of a mortal who is on the Lupa (not standing on a claimed Langit). If so, Taya passes to the tagged mortal at once.
- **Tag-back buffer:** the new Taya cannot tag anyone for `tagback_immunity` (1.0s). Show it (the marker blinks). This is how I read "1-second immunity buffer applies to the new Taya".
- If the Taya disconnects, the highest-FAVOR remaining mortal becomes Taya.

**Langit (safe havens).**
- Raised platforms on the field (draw them lifted with a shadow; clouds or terraced rice-paddy blocks both fit). A mortal standing on a Langit cannot be tagged.
- **One mortal per Langit**, musical-chairs style: the first non-Taya mortal to step on claims it and is safe; anyone else on it is not. The Taya can walk over them but never claims one.
- Count: `max(1, mortals - 2)` platforms (2 players: 1, 3 players: 1, 4 players: 2), so at least one runner is always exposed. Keep the formula in one function so I can tune it.
- **Crumbling every 3 seconds** (`shift_interval`): all Langit crumble and reappear at new random spots, so everyone is back on the Lupa. Give a `shift_warning` (0.75s) of shaking/cracking before they go so it's readable, and the new ones fade in. New spots: inside the field, not in the UI strip, not overlapping each other, and at least `taya_clearance` away from the Taya.
- The host picks positions and sends them in `arena_tick_fields` (with a shift counter so clients redraw only on change). The host decides who is safe from the positions it has.

**Dash (Shift, also Space).**
- Add a `dash` input action (Shift, plus Space as a second key). Space is also `advance_dialogue`, so dash must do nothing while a dialogue or the God's Due menu is open, and must not advance anything during play.
- Add a generic `dash(direction, distance, time)` to `ArenaMortal` (dash along the movement direction, or facing when standing). Enable it from the arena with an `@export var dash_enabled := false` on `Arena`, true only here, so other arenas are untouched.
- Defaults: distance 110px over 0.15s, cooldown 1.6s. Show the dash cooldown in the HUD.

**FAVOR (inverse time).**
- A **Time as Taya** tracker for every mortal, on screen all trial (small list in the HUD, sorted, the current Taya highlighted). Sync it in `arena_tick_fields`.
- **Passive loss:** while Taya you lose `taya_drain` FAVOR per second (default 10). Bank it once per second through `lose_favor` so loss favors (Waning Moon, The Unmoving, Bagong Umaga, Apolaki's) all react normally, but not every frame.
- **Final payout** when the clock ends, ranked by least time as Taya: first place gets `payout_best` (1200), last place gets `payout_worst` (200), and the places between are spread evenly. Times within 0.25s count as a tie and share the better payout. Bank it before `end_trial()` settles, with the reason "Langit Lupa payout", so it shows in the results.

**Solo.** Other arenas just let the simulated rivals gain FAVOR, but a tag game needs someone to chase. When the arena runs solo, spawn two simple bot mortals bound to the simulated rival ids: they flee the Taya and head for free Langit, and chase when they are Taya. Keep the bot code small and inside this arena's script.

**HUD and feedback.** A small HUD like `TalaHud` / Hanan's: Taya timer list, dash cooldown, "SAFE" when you've claimed a Langit, a "TAYA!" banner when you become it, and a crumble warning. Popups and log lines in the pair's colour.

**Art.** Use placeholders the way Hanan does: add `Assets/Gods/MapulonIkapati/README.md` listing the files to drop in (field background, Langit platform, crumble frames, Taya marker, overseer art for the pair), and have the scene use them when they exist.

Put every number in `@export` vars under `@export_category("Langit Lupa")`: `fixed_trial_time`, `tag_radius` (26), `tagback_immunity` (1.0), `shift_interval` (3.0), `shift_warning` (0.75), `taya_clearance` (120), `taya_drain` (10), `payout_best` (1200), `payout_worst` (200), dash distance/time/cooldown.

Make sure E/Q, the God's Due menu (F, 1/2/3), Mayari's blindness, Apolaki's sun patches and Tala's Let Us Light Your Way all still work here.

## 3. The seven favors (sub-resources in `mapulon_ikapati.tres`, `god_id = &"mapulon_ikapati"`)
Theme: they are a pair and they are farmers, so **everything grows over time**. Each favor belongs to one of them (shown in the name, like Mayari and Apolaki's sibling favors). Mapulon's are about time and seasons; Ikapati's are about seed, soil and harvest. As a pair they offer **two E skills and two Q skills**; a mortal still holds one of each (choosing a new one replaces the old, as `bestow_favor` already does). E is offensive, Q is defensive.

Favors travel with the mortal into every later trial, so each one must work in **every** arena, not just Langit Lupa. Put all numbers in `params`.

| id | Name | slot / kind | Effect |
|---|---|---|---|
| `binhi` | Binhi (Ikapati) | PASSIVE / PASSIVE | The seed. At the end of every trial you hold it, gain `50 × trials held so far` (50, then 100, then 150...). The earlier you plant it, the bigger it grows. `params {"growth_per_trial": 50}` |
| `panahon_ng_anihan` | Panahon ng Anihan (Mapulon) | PASSIVE / PASSIVE | Harvest season. FAVOR you earn during the **last 15 seconds** of every trial is increased by 30%. End-of-trial payouts (Langit Lupa's payout, Binhi, Favorable Outcome) don't count. `params {"window": 15.0, "gain_mult": 1.3}` |
| `kabiyak` | Kabiyak (The Pair) | PASSIVE / INSTANT | "Your other half." On grant you are paired with the mortal closest to you in FAVOR (ties random). For the rest of the run, whenever your kabiyak gains FAVOR, you also gain 10% of what they actually gained; they lose nothing. If they leave, re-pair to the next closest. Only offered to mortals already holding a Mapulon & Ikapati favor. `params {"requires_god": "mapulon_ikapati", "share": 0.1}` |
| `tagtuyot` | Tagtuyot (Mapulon) | E / ACTIVE | Drought. The leading mortal (or second place if you lead; ties random, same targeting as Break of Day) withers: they lose 3% of their current FAVOR every second for 5s, at most 400 in total. Cooldown 30. `params {"percent_per_second": 0.03, "max_total": 400}`, `duration = 5` |
| `ligaw_na_damo` | Ligaw na Damo (Ikapati) | E / ACTIVE | Weeds. For 6s, weeds grow in every opponent's field: 30% of all FAVOR they gain goes to you instead. Cooldown 30. `params {"siphon": 0.3}`, `duration = 6` |
| `unang_ulan` | Unang Ulan (Mapulon) | Q / ACTIVE | First rain. For 6s, every bit of FAVOR you lose is watered; 5s after the rain stops, it grows back at 125%. You still take the losses now (so other favors still see them). Cooldown 30. `params {"regrow_delay": 5.0, "regrow_mult": 1.25}`, `duration = 6` |
| `kamalig` | Kamalig (Ikapati) | Q / ACTIVE | The granary. Store 25% of your current FAVOR (at most 400) where nothing can touch it. At the end of the trial it comes back with 20% interest. While stored it doesn't count toward your FAVOR, so it also hides you from "highest FAVOR" targeting (Break of Day, An Even Playing Field, Tagtuyot, Langit Lupa's first Taya). Cooldown 40. `params {"store_fraction": 0.25, "max_store": 400, "interest": 0.2}` |

Engine changes these need. Keep each small and generic:
- **`GodMatch.end_trial()`** currently pays every `END_OF_TRIAL` favor only to the top mortal (that's Favorable Outcome's rule). Don't reuse that kind for Binhi; keep Binhi `PASSIVE` and pay it by id at trial end. Order at trial end: return Kamalig stores with interest, then Binhi, then the existing Favorable Outcome check, so "highest FAVOR" is judged on real totals.
- **Trial counter** per mortal for Binhi (trials ended while holding it), carried in `snapshot()` / `apply_snapshot()`.
- **Panahon ng Anihan:** the arena tells `GodMatch` when the clock is inside the harvest window (host only), and `gain_multiplier` applies it. Turn the flag off before end-of-trial payouts.
- **Kabiyak:** after `add_favor` works out what a mortal actually gained, pay 10% of it to anyone whose kabiyak they are, through `_apply` (not `add_favor`), so two mortals paired with each other can't loop and Full Moon doesn't stack on the share. Store the pairing per mortal and send it in the snapshot; show "Kabiyak: <name>" in the HUD.
- **Ligaw na Damo:** per-mortal "weeds" timer plus the caster id. In `add_favor`, after the target's multipliers, move the siphon share to the caster through `_apply`. If several casters weed the same mortal, the latest one wins.
- **Tagtuyot:** per-mortal drought timer, ticked once a second on the host in `_tick_mortal`, through `lose_favor` (so Waning Moon and The Unmoving reduce it). Track the running total to enforce `max_total`. Reuse Break of Day's targeting rather than copying it.
- **Unang Ulan:** while it's active, record what `lose_favor` actually took; when the duration ends, schedule a regrowth of `lost × regrow_mult` after `regrow_delay`, paid through `_apply` with reason "Unang Ulan".
- **Kamalig:** moving FAVOR into the store is **not a loss**. It must not go into `loss_history`, must not trigger The Sun God, The Ruler, The Victor, Bagong Umaga or a red loss popup. Add a clear way for `_apply` to mark a transfer (an explicit argument or a reason constant the loss listeners skip), and use it for the return too. Returning stored FAVOR must not hand out God's Dues again (milestones are first pass only already; keep it that way). Show the stored amount in the HUD.
- **Break of Day** (Hanan) should also end an active Tagtuyot, Ligaw na Damo or Unang Ulan cast by its target. Add those to `_end_arena_effects_of` / `break_of_day` as needed.
- **`Arena._apply_skill_effect`:** dispatch `tagtuyot`, `ligaw_na_damo`, `unang_ulan` and `kamalig` on the host, then `_publish_god_state()`.
- Feedback: a banner/log line for each favor firing, in the pair's colour, like the others do. The Almanac should show Kabiyak's condition.

## 4. Lobby: at most 5 trials
There are now 5 playable gods plus Bathala, so a run is **at most 5 trials** (then Bathala's finale), with every god at most once.
- `Gods.TRIALS_MAX` goes from 9 to 5. Keep `TRIALS_MIN = 3` and `TRIALS_DEFAULT = 4`. Fix the comments that say 3..9 (`gods.gd`, `RunSettings.validate`).
- Random order draws each playable god at most once. Custom order can't pick a god that is already in another slot: grey it out or skip it in that slot's picker. The old "repeats right after itself" warning becomes "already plays in trial N".
- A saved `user://lobby_settings.cfg` with more than 5 trials or duplicate gods must load cleanly (clamped and de-duplicated by `validate()`).
- Update `tools/lobby_options_check.gd`, `tools/shared_order_client.gd` and anything in `scenes/Lobby.tscn` that assumes 9 or allows repeats.

## 5. Tests
- Add `tools/langit_lupa_check.gd`. Load the arena headless and check:
  - the highest-FAVOR mortal starts as Taya, and a tie is resolved to one of the tied mortals
  - a tag on the Lupa passes Taya; a tag on a claimed Langit does not
  - the new Taya can't tag back for 1s
  - only one mortal claims a Langit, and the platform count follows the formula for 2, 3 and 4 mortals
  - platforms move every 3s and never spawn on top of the Taya
  - Time as Taya grows only for the current Taya, and the drain lands once a second
  - payouts go to the least-time mortal highest, ties share, and the trial lasts 60s
  - dash moves the mortal, respects its cooldown, and is off in other arenas
- Add `tools/mapulon_ikapati_favor_check.gd` (pattern: `tools/hanan_favor_check.gd`) covering all seven favors, including these edge cases:
  - Binhi growing over three trials
  - Panahon ng Anihan inside and outside the window, and not touching payouts
  - Kabiyak with two mortals paired to each other (no loop) and re-pairing after a leave
  - Tagtuyot's cap and Waning Moon reducing it
  - Ligaw na Damo with Full Moon on the target
  - Unang Ulan not regrowing losses taken outside its window
  - Kamalig not counting as a loss for Apolaki's favors, and its interest at trial end
- Check that the lobby caps at 5 trials, a random order of 5 has no repeats, and an old saved setting with 9 trials loads as 5.
- Add the new arena to the arena lists in `tools/god_audit.gd` and `tools/scene_check.gd`. Then run **all** existing checks in `tools/` and fix anything you broke. A fifth god changes the random pool, so expect order and count assertions to need a look, but don't weaken a check just to make it pass.

## When you're done
Tell me:
- every file touched
- the check results
- any rule above you had to interpret
- anything that felt unfun when you ran it solo with the bots (for example, if 3s shifts are too frantic), so I can tune it
