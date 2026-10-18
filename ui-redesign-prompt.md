# Prompt: UI redesign and PvZ-style Almanac

**Use:** Opus, effort **high**. This change touches 20+ scenes and scripts, and the design judgment matters as much as the code, so use the strongest model. Max effort isn't needed, because the prompt already spells out the design.

Paste everything below the line into Claude Code, opened at the root of the DOST2027 repo. It works in phases and commits after each one, so you can stop it between phases and review.

---

Redesign every UI screen in this Godot 4.7 project (GDScript, GL Compatibility) so it looks professionally designed and fits the game, and rebuild the Almanac in the style of the *Plants vs. Zombies* Almanac. Final art doesn't exist yet. Build everything on a theme with placeholder styling, so dropping in real art later is a change in one place.

The project is in `dost-2027/`. Before changing anything, read every file named below. Match the code style: tabs, typed GDScript, and comment blocks that explain *why*. **Do not change gameplay, networking, scoring, or the order of signals.** This is a presentation pass only.

## The game, for tone

*Bathala: Ang Laro ng mga Diyos* is a 2-4 player LAN party game. Mortals compete in Filipino street games hosted by Philippine gods, earning FAVOR:
- Mayari, moon, Patintero
- Apolaki, sun and war, Arnis
- Tala, stars, Tumbang Preso
- Hanan, morning, Luksong Baka
- Mapulon & Ikapati, harvest, Langit Lupa
- Bathala's finale, Agawan Base

The title art (`Assets/title/`) is a pixel-art night sky: a deep indigo field, a glowing moon with comet streaks, and a reflection on water. The font is `Assets/fonts/Minecraftia-Regular.ttf` (pixel). Textures use nearest filtering. Each god has a `color`, `icon`, `portrait`, `epithet`, `game_name`, `game_blurb` and `favors` in `resources/gods/*.tres` (`scripts/gods/god.gd`, `god_favor.gd`), read through the `Gods` registry (`scripts/gods/gods.gd`).

**Art direction: "the heavens' tournament."** Night-sky indigo surfaces, Bathala's warm gold for anything you can act on, and ivory text like old paper. Use simple ornament that reads as Filipino without being kitsch: a thin double rule with small diamond corner studs, inspired by banig weaving and okir carving. Draw it with the pixel grid, never with gradients or blur. Each god's color is an *accent* (frames, nameplates, underlines), never a large fill. The tone is ceremonial and celestial, but readable at a glance in a party game.

## Problems in the current UI (verified in the code)

- **No shared Theme.** Every scene and script styles itself with `theme_override_*` and `StyleBoxFlat.new()`. There are 18 different font sizes (9 to 52 px) and five different button widths (200, 260, 320, 420, 800).
- **Blurry text.** Minecraftia is drawn on an 8 px grid, but most sizes (10, 11, 13, 14, 15, 18) aren't multiples of 8, so the text renders soft.
- **Unreadable god color.** Tala's color `Color(0.12, 0.22, 0.48)` is used as text on a dark background and is close to unreadable.
- **Leftover nodes in the Almanac.** `scenes/Almanac.tscn` still has nodes from an older card game: `DetailPanel` with `CardTexture`/`CostLabel`, plus `Poster`, `Poster2` and `AnimatedSprite2D`.
- **No consistent focus or hover states.** Keyboard navigation is uneven between screens.

## UI principles to apply (and to name in comments where they drive a decision)

- **Visual hierarchy.** Each screen has exactly one primary action, drawn in gold. Secondary actions are quiet, and destructive or exit actions are ghost buttons.
- **Fitts's law.** Primary targets are large and close to where the eye already is. Nothing clickable is shorter than 32 px.
- **Hick's law.** Group and limit choices. On the title screen, play actions (HOST, JOIN) are visually separate from browse actions (ALMANAC, OPTIONS) and from QUIT.
- **Gestalt proximity and similarity.** Related things sit together on an 8 px spacing grid, and controls with the same job look the same everywhere.
- **Consistency and standards.** One Theme drives every screen. BACK is always bottom-left and the primary action always bottom-right (or the bottom of a centered stack). Esc always means back or close.
- **Feedback.** Every control has normal, hover, pressed, focus and disabled states. A disabled button says why in a tooltip or a caption.
- **Recognition over recall.** Show keycaps (`E`, `Q`, `F`, `1/2/3`, `Space`) using `Settings.event_label()`, so rebinding is reflected everywhere.
- **Legibility and contrast.** Body text is at least 4.5:1 against its background. Never put raw god colors on text: run them through a `readable_on_dark(color)` helper that lightens them until they pass.
- **Progressive disclosure.** Show the summary first and details on selection (this is the Almanac's whole model).
- **Motion with restraint.** Use 80 to 150 ms tweens for hover and press, and slide or fade on panel open. Skip any flash or pulse when `Settings.reduce_flashing()` is on. Respect the UI scale setting (`Settings.UI_SCALES`) by never hard-coding positions that break at 80 or 150 percent.

## Phase 1: Design system (commit when done)

1. Add `UI/theme/ui_tokens.gd` (`class_name UITokens`) as the single source of truth:
   - **Colors:**
     - Surfaces: `NIGHT_900 #0B1020`, `NIGHT_800 #121A30`, `NIGHT_700 #1B2545`, `NIGHT_600 #26335C`, `LINE #3A4A7A`
     - Text: `IVORY #F2E8CF` (primary text), `MUTED #A9B3CC` (secondary text), `FAINT #6F7A99` (disabled)
     - Actions: `GOLD #E8B84A`, `GOLD_HI #F6D27A`, `GOLD_LO #B98A2A` (primary action states)
     - States: `JADE #5CC48A` (success/ready), `EMBER #E0614F` (danger/loss), `STAR #9FD3FF` (info/focus ring)

     Treat these as starting values: tune them, but keep the roles.
   - **Type scale (multiples of 8 only):** `CAPTION 8`, `BODY 16`, `HEADING 24`, `DISPLAY 32`, `HERO 48`. Use Minecraftia at these exact sizes. Uppercase with letter spacing for headings and buttons; sentence case for body text.
   - **Spacing:** `4, 8, 16, 24, 32, 48`.
   - **Button sizes:** `LARGE 260x52`, `MEDIUM 260x44`, `SMALL 120x32`, `ICON 32x32 / 44x44`. Text fields and dropdowns are 44 tall.
   - **Helpers:** `readable_on_dark(color)`, `god_accent(god)`, and a `tween_press(control)` / `tween_hover(control)` pair that respects `Settings.reduce_flashing()`.
2. Add `UI/theme/bathala_theme.tres` and set it as the project's default theme (`gui/theme/custom` in `project.godot`), with Minecraftia as the default font at size 16. Define **theme type variations** so scenes pick a style by name instead of overriding it:
   - Buttons: `PrimaryButton`, `SecondaryButton`, `GhostButton`, `SmallButton`, `DangerButton`, `TabButton`, `KeycapLabel`
   - Panels: `PanelCard` (raised), `PanelInset` (sunken list area), `PanelHud` (translucent, for in-game), `Nameplate`
   - Labels: `HeroLabel`, `HeadingLabel`, `CaptionLabel`, `MutedLabel`
   - Also style `LineEdit`, `OptionButton`, `CheckBox`, `HSlider`, `ProgressBar`, `ScrollContainer`, `TabContainer`, `TooltipPanel`, and focus.
3. **Placeholder art, built to be replaced.** Build every style as a `StyleBoxFlat` that imitates pixel art:
   - No anti-aliasing, corner radius 0 to 2
   - 2 px borders
   - A hard 2 px drop shadow (`shadow_size 0`, `shadow_offset (0, 2)`, no blur) that moves to 0 when pressed, so the button reads as pushed in
   - A 1 px inner highlight on the top edge of raised panels

   Keep all styles in the theme so they can later be swapped for `StyleBoxTexture` 9-slices in one file. Add `UI/theme/ART_SLOTS.md` listing every texture the artist should provide: name, which variation uses it, and source size drawn at half resolution for 2x scaling (for example a 130x26 primary button and a 130x22 medium button), with the 9-slice margins.
4. Add one reusable ornament: `UI/theme/ornament_frame.gd`, a `Control` that draws the double rule and diamond corner studs with `draw_rect`, tinted by a color. Use it on hero panels and on Almanac detail frames. No textures needed.
5. Remove the per-node `theme_override_*` styling and the `StyleBoxFlat.new()` styling from scenes and scripts as you convert each screen. Keep overrides only for values that really vary at runtime (god colors), and route those through `UITokens`.

## Phase 2: Menus (commit when done)

Keep every node path that a script or a `tools/*.gd` check reads (for example `CenterContainer/VBoxContainer/HostButton`, `.../AlmanacButton`, `.../OptionsButton`, `.../QuitButton`, `Panel/Margin/VBox/Tabs`, `Panel/Margin/VBox/Buttons/BackButton`, `CenterContainer/VBoxContainer/ButtonContainer/OptionsButton`). Otherwise, update the script **and** the check in the same commit.

- **Main menu** (`scenes/MainMenu.tscn`, `scripts/MainMenu.gd`):
  - Keep the night-sky background art.
  - Put a title lockup at the top: BATHALA in `HERO` gold, with "Ang Laro ng mga Diyos" in `BODY` ivory under it and a thin ornament rule.
  - Below it, one centered stack in three groups separated by 24 px:
    - HOST GAME (Primary, large) and JOIN GAME (Secondary, large)
    - ALMANAC and OPTIONS (Secondary, medium)
    - QUIT (Ghost, small)
  - The status line becomes a small footer caption. Keyboard focus starts on HOST.
- **Hosting** and **Join game** (`scenes/Hosting.tscn`, `scenes/JoinGame.tscn`, `scripts/hosting.gd`, `scripts/JoinGame.gd`):
  - Use one form-card layout for both: a heading, a field label above each field, the primary action, and BACK as a Ghost bottom-left.
  - On Join, show discovered LAN hosts as row cards: host name, player count `2/4`, and a JOIN small button on the right.
  - When no hosts are found, show an empty state ("Searching your network…", with a slow dot animation that respects reduce flashing) beside REFRESH.
  - The lobby-ID field is uppercase and spaced for readability.
- **Lobby** (`scenes/Lobby.tscn`, `scripts/lobby.gd`):
  - Use two columns.
  - **Left:** four fixed player slots (`MAX_PLAYERS`). Filled slots show the chosen god icon in a frame of that god's accent color, the name, and a gold HOST nameplate for peer 1. Empty slots are dashed outlines reading "Waiting for a mortal…".
  - **Right:** a "You" card (name field plus UPDATE, and the god icon picker as a row of icon buttons instead of a dropdown), and a "Run" card showing `RunSummaryLabel`'s summary with the OPTIONS button.
  - **Top-right:** the lobby ID as a large keycap-style label with a small COPY button (`DisplayServer.clipboard_set`), host only.
  - **Bottom bar:** LEAVE (Ghost, left) and START GAME (Primary, right). While START is disabled, its caption says why, for example "Need 2+ players" or the LobbyOptions warning.
- **Options** (`scenes/Options.tscn`, `scripts/Options.gd`) and **Lobby options** (`scenes/LobbyOptions.tscn`, `scripts/lobby_options.gd`):
  - Restyle with the theme and use one row pattern everywhere: label column 200 px, control column fills the rest, rows 44 px tall, section headings in `HEADING`.
  - Rebind buttons look like keycaps.
  - Keep all behavior and node paths.

## Phase 3: Almanac, Plants vs. Zombies style (commit when done)

Rebuild `scenes/Almanac.tscn` and `scripts/Almanac.gd`, and delete the leftover card-game nodes. Keep it fully data-driven from `Gods.all()`, as the current script does: a new god or favor appears with no code change.

- **Index page.** Like PvZ's "View Plants / View Zombies," show two large framed choices side by side:
  - **MGA DIYOS** (The Gods), showing a fan of god icons
  - **MGA PABOR** (The Favors), showing a fan of favor icons

  Each has a caption ("6 gods", "40 favors"). BACK (Ghost) sits bottom-left and returns to the main menu.
- **Shared page layout**, as in the PvZ Almanac:
  - The **left ~45%** is a grid of cards inside an inset "book page" panel.
  - The **right ~55%** is the detail display for the selected card:
    - A large framed portrait or icon on a backdrop tinted by the god's accent, using `ornament_frame.gd`
    - The name in `HEADING`, then a subtitle
    - A row of stat chips
    - The description text
    - A short italic-feel flavor line in `MUTED`
  - Page title at the top, a BACK button bottom-left that returns to the index, and Esc does the same.
  - The first card is selected when the page opens.
- **Gods page.**
  - **Grid cards** are 96x112 "shrine tiles": icon, name, and an accent-colored base strip.
  - **Detail:**
    - Portrait (`god.portrait`, falling back to `god.icon`)
    - Name and epithet
    - Chips: the trial name (`game_name`) and the favor count
    - `game_blurb` as the description
    - The first of `intro_lines` as flavor text
    - A small row of that god's favor packets: clicking one jumps to the Favors page with it selected
- **Favors page.**
  - **Grid cards** are 80x100 "seed packets", PvZ's signature look: a packet with the god's accent as its top band, the favor icon in the middle (tinted by `favor.color` while icons are placeholders), the name below, and a corner badge for its slot or kind (`E`, `Q`, `PASSIVE`, `ONCE`, `END`).
  - **Filter chips** across the top: `ALL` plus one per god, in that god's accent.
  - **Detail:**
    - A large icon
    - The name
    - "Bestowed by <god>" in the god's readable accent
    - Chips for slot, kind, cooldown and duration (only the ones that apply)
    - The description
    - The condition line from the existing `_condition_text()` logic; keep that logic and both `requires_god` / `requires_any_god_ids()` cases
- **Navigation.**
  - Arrow keys move the grid selection; Enter or click selects.
  - Tab and Shift+Tab cycle the filter chips.
  - The selected card lifts 2 px and gets a gold focus outline; hover gets a subtle lift.
  - The grid scrolls inside its panel only. The page fits at 1152x648 and still works at 150% UI scale.
- **Checks.** Update `tools/menu_almanac_check.gd` to the new structure. It should still prove the menu opens the Almanac and BACK returns, and add checks that:
  - Both index choices open their pages.
  - Every god and every favor in the registry has exactly one card.
  - Selecting a card fills the detail panel.
  - The god page's favor packet jumps to the right favor.

## Phase 4: In-game UI (commit when done)

Restyle without changing logic or the data each element shows:

- **Game shell** (`scenes/Game.tscn`, `scripts/Game.gd`):
  - Your own card (`TopLeft`) and the opponents column (`OtherPlayersPanel`, `UI/opponentpanels.tscn`, `UI/opponent_panel.gd`) use `PanelHud`.
  - Each player's frame uses their god icon's accent.
  - FAVOR is the largest number on the card and ticks up with a short count animation. God's Due shows as pips.
  - `TrialTimer` becomes a centered top pill that turns `EMBER` in the last 10 seconds (a color change only, no flashing).
  - Restyle `FinalePanel` as a results card.
- **Arena HUD** (`UI/GodsArena/god_hud.tscn` + `.gd`, `UI/GodsArena/skill_bar.tscn` + `.gd`):
  - Skill slots show the bound key as a keycap with the favor icon and a cooldown fill that drains from top to bottom, with the seconds left on top.
  - Restyle the banner, the event log and `ResultsPanel` to match. Keep the HUD clear of the play field's center.
- **God's Due menu** (`UI/GodsArena/gods_due_menu.tscn` + `.gd`):
  - Present the three offered favors as three large packet cards side by side, matching the Almanac's seed-packet style so players recognize them, each with its `1`/`2`/`3` keycap. Clicking or pressing the key still calls `_choose(index)`.
  - Keep the `SidePanel/Margin/VBox/Rows` path, or update `tools/` checks that read it.
- **Dialogue** (`UI/GodsArena/god_dialogue.tscn` + `.gd`):
  - A bottom box with the portrait on the left in an accent frame, a speaker nameplate tab on top in the god's readable accent, the line in `BODY` ivory, and the advance keycap (`Settings.event_label` for `advance_dialogue`) with a slow blink. Don't blink when reduce flashing is on.
- **Per-arena HUDs:** apply the theme variations to `DuelHud`/`Bars` (Apolaki), `AttackHud` (Mayari), `TalaHud`, `HananHud`/`BarLayer`, `LangitHud` and `AgawanHud` (Bathala). Restyle only.
- **Other screens:** the God intro (`scenes/GodIntro.tscn`), `scenes/GameOver.tscn`, and the floating favor popup (`UI/Popups/favor_popup.tscn`). The popup's gain and loss colors come from `JADE`/`EMBER`.

## Verification

- After each phase, run every check in `dost-2027/tools/` that touches the screens you changed, plus `scene_check.gd`, with `godot --headless --path dost-2027 -s res://tools/<file>.gd`, and fix anything they report. At the end, run all of them.
- Add `tools/ui_theme_check.gd`. It verifies that the project theme loads and that every font size used is in the type scale. It also verifies that no `.tscn` under `scenes/` or `UI/` still carries a `theme_override_styles/` entry, unless it is listed in an allow-list with a reason.
- If you can render frames headlessly, save screenshots of each screen at 1152x648 to `.tmp_frames/` (already git-ignored) and look at them before calling a phase done.

## When you finish

Summarize what changed per phase, list any screen or element you left as-is and why, and point to `UI/theme/ART_SLOTS.md` for the art the team needs to draw.
