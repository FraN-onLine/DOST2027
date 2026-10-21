# Art slots: what the artist draws for the UI

Every panel and button in the game is styled by one file,
`UI/theme/bathala_theme.tres`. Right now each style is a placeholder
`PixelStyleBox` (flat face, 2 px border, hard 2 px shadow, 1 px top highlight).
To put real art in, replace that style with a `StyleBoxTexture` that uses the
same content margins. You can do this in the editor (open the theme and swap the
style) or in `tools/build_theme.gd` (then run it again). No scene changes are
needed.

## How to draw

- Draw at **half resolution** on the pixel grid, then export at **200% with
  nearest-neighbour scaling**. The game shows everything at 2x and uses nearest
  filtering, so one source pixel becomes a 2x2 block on screen.
- Stick to the palette in `UI/theme/ui_tokens.gd`: night indigo surfaces, gold
  for anything you can act on, ivory text.
- No gradients, no blur, no anti-aliasing. Use hard edges only.
- Keep ornament simple: a double rule with diamond studs, after banig weaving
  and okir carving. Never put a god's colour on a large fill; it's an accent.
- Every slot is a **9-slice**. The margins below are in **source** pixels (half
  resolution). Double them for the `texture_margin_*` of the `StyleBoxTexture`.
  The middle stretches, so keep it flat or a pattern that tiles.
- Buttons need one image per state: `normal`, `hover`, `pressed`, `disabled`.
  For `pressed`, drop the shadow and move the face down 1 source pixel, so the
  button reads as pushed in. Keep `focus` as the placeholder STAR ring unless
  you have a better idea for it.

## Buttons

| Slot (file name) | Theme variation | Source size | 9-slice L/T/R/B | Notes |
|---|---|---|---|---|
| `btn_primary_{normal,hover,pressed,disabled}.png` | `PrimaryButton` | 130x26 (260x52 large), 130x22 (medium) | 3 / 3 / 3 / 4 | Gold face, `GOLD_LIP` 1 px shadow under it. Only one per screen. |
| `btn_secondary_{...}.png` | `SecondaryButton`, plain `Button`, `OptionButton` | 130x26 / 130x22 | 3 / 3 / 3 / 4 | Indigo face (`NIGHT_600`), gold border on hover. `OptionButton` needs room for the arrow on the right. |
| `btn_ghost_{hover,pressed}.png` | `GhostButton` | 60x16 | 2 / 2 / 2 / 2 | Normal is empty (text only). Hover is a faint plate. |
| `btn_small_{...}.png` | `SmallButton` | 60x16 | 2 / 2 / 2 / 3 | The JOIN on a host row, COPY, the Almanac's favor packets. |
| `btn_danger_{...}.png` | `DangerButton` | 60x16 / 130x22 | 3 / 3 / 3 / 4 | `EMBER` border. |
| `btn_tab_{normal,hover,pressed}.png` | `TabButton` | 40x16 | 2 / 2 / 2 / 2 | Filter chips and tab-like toggles. `pressed` = selected (gold border, lit top). A god's chip has its border tinted at runtime, so draw the border in white or light grey. |
| `keycap.png` (+ `_hover`, `_pressed`) | `KeycapButton`, `KeycapLabel` | 16x16 | 3 / 2 / 3 / 4 | A keyboard key seen from the front, with a thicker bottom lip. Text is drawn on top. |
| `btn_icon_{normal,hover,pressed}.png` | `IconButton` | 22x22 | 2 / 2 / 2 / 2 | The lobby's god icon picker: a square toggle that is only a picture. `pressed` = chosen. |
| `card_shell` (nothing to draw) | `CardButton` | - | - | The invisible, focusable shell of an Almanac card or God's Due packet. It draws nothing; leave it empty. |

## Panels

| Slot | Theme variation | Source size | 9-slice L/T/R/B | Notes |
|---|---|---|---|---|
| `panel_card.png` | `PanelCard` (and plain `Panel`, `PanelContainer`) | 48x48 | 4 / 4 / 4 / 5 | The raised card: lit top edge, 1 px shadow. The default for every panel. |
| `panel_inset.png` | `PanelInset` | 48x48 | 4 / 4 / 4 / 4 | A sunken area (the Almanac's book page, the host list). Shadowed top edge. |
| `panel_hud.png` | `PanelHud` | 32x32 | 3 / 3 / 3 / 3 | In-game, about 80% opaque so the field shows through. |
| `nameplate.png` | `Nameplate` | 32x12 | 4 / 3 / 4 / 4 | Name tabs (HOST, the dialogue speaker). Tinted at runtime, so draw the border light. |
| `panel_empty.png` | `PanelEmpty` | 32x32 | 3 / 3 / 3 / 3 | A dashed outline: an empty lobby slot. |
| `shrine_tile.png` | `ShrineTile` | 48x56 | 4 / 6 / 4 / 6 | The Almanac's god card (96x112 on screen). The base strip is tinted with the god's accent at runtime. |
| `seed_packet.png` | `SeedPacket` | 40x50 | 4 / 8 / 4 / 4 | The Almanac's and God's Due favor card (80x100 on screen): a paper packet with a coloured top band. The band and frame are tinted at runtime, so draw them light. |
| `panel_row.png` | `PanelRow` | 32x16 | 3 / 3 / 3 / 3 | One row of a list (a LAN game, a lobby seat, a rival in the game). Tinted at runtime, so draw the border light. |
| `selection_ring.png` | `SelectionRing` | 16x16 | 3 / 3 / 3 / 3 | The gold outline around a selected card. It sits 2 source px outside the card, so it is a frame only, with a transparent middle. |
| `hud_plate.png` | `HudLabel`, `HudHint` (as the label's `normal` style) | 16x8 | 2 / 1 / 2 / 1 | A translucent plate behind in-game status and hint text. |
| `timer_pill.png` | `TimerPill` | 32x16 | 4 / 3 / 4 / 3 | The trial clock at the top of the screen. |
| `chip.png` | `ChipLabel` | 16x8 | 3 / 2 / 3 / 2 | The Almanac's stat chips ("ARNIS", "30s cooldown"). |
| `badge.png` | `BadgeLabel` | 8x6 | 2 / 1 / 2 / 1 | A seed packet's corner badge (E, Q, PASSIVE, ONCE, END). |
| `code_key.png` | `CodeLabel`, `CodeField` | 32x24 | 4 / 3 / 4 / 4 | The lobby ID drawn as one big key, and the field you type it into. |
| `tooltip.png` | `TooltipPanel` | 16x16 | 3 / 3 / 3 / 3 | |
| `dialog.png` | `Window` (embedded dialogs) | 48x48 | 4 / 16 / 4 / 4 | The top 16 source px hold the title bar. |
| `tab_{selected,unselected,hovered}.png` | `TabContainer` tabs | 32x16 | 3 / 3 / 3 / 2 | The Options screen's tabs. |

## Small icons (whole images, not 9-slices)

| Slot | Used by | Source size | Notes |
|---|---|---|---|
| `check_{on,off}[_disabled].png` | `CheckBox` | 8x8 | A square box with a gold pip when ticked. |
| `radio_{on,off}[_disabled].png` | `CheckBox` in a group, `PopupMenu` | 8x8 | A diamond, the ornament's stud. |
| `toggle_{on,off}[_disabled].png` | `CheckButton` | 16x8 | A switch: the knob sits left when off, right on gold when on. |
| `slider_grab[_hi,_disabled].png` | `HSlider` | 6x10 | |
| `dropdown_arrow.png` | `OptionButton` | 6x3 | |

## Not in the theme (drawn in code, also placeholders)

- **Ornament frame** (`UI/theme/ornament_frame.gd`): the double rule with diamond
  corner studs, drawn with `draw_rect` on the title lockup and the Almanac's
  detail frames. If you want it as art, provide a `ornament_frame.png` 9-slice
  (64x64 source, 8 px margins) and a `ornament_rule.png` (64x8, centre stud).
  The frame is tinted at runtime, so draw it in white.
- **Favor icons**: every favor still uses `res://icon.svg`, tinted with the
  favor's colour. When real icons arrive, set `icon` on each favor in
  `resources/gods/*.tres` and drop the tint (search for `PLACEHOLDER_ICON`).

## The preparation area (scene art, also placeholders)

The rest between two trials (`scenes/prep/PrepArea.tscn`) is drawn with coloured
rects and `res://icon.svg` for now. Each slot is a node in that scene. Swap its
texture or replace the rect with a `Sprite2D`, keeping its position, so the
stall's reach and the layout stay where they are.

| Slot (file name) | Node in `PrepArea.tscn` | Source size | Notes |
|---|---|---|---|
| `prep_ground.png` | `ArenaField/Ground` | 408x236 | The calm field under the camp, inside the drawn `Border`. Night tones only; it should read as rest, not as a game board. |
| `campfire.png` (+ frames) | `Camp/Campfire` (`Logs`, `Flame`, `Glow`) | 32x32 | The centre of the camp. A looping 4-6 frame flame if animated. Keep the glow soft and small (comfort: no flashing). |
| `altar.png` | `Camp/Altar/Stone` | 48x32 | A stone altar. The god who just hosted stands on it: `GodIcon` takes that god's `icon` at runtime, so leave room above the stone. |
| `tindahan_stall.png` | `Camp/Stall` (`Awning`, `Counter`) | 80x48 | A sari-sari store front: an awning and a counter. The shop opens when a mortal stands within `stall_reach` of the stall's centre. |
| `shopkeeper.png` | `Camp/Stall/Shopkeeper` | 24x32 | A neutral keeper behind the counter, not one of the gods. |

## Pamana icons

Every Pamana (`resources/pamana/*.tres`) still uses `res://icon.svg`, tinted with
the item's colour (an item too dark to read on night indigo, the Mighty Pen, is
tinted ivory). Draw one 24x24 source icon per item (`manunggul_jar.png`,
`torn_cedulas.png`, `banton_cloth.png`, `agimat.png`, `mighty_pen.png`,
`mutya.png`, `kampilan.png`, `surigao_gold.png`), set `icon` on the item, and
drop the tint in `UICards.pamana_card` (search for `pamana_edge`). The same icon
shows on the Tindahan's cards, the HUD badges and the Almanac's MGA PAMANA page.

## The opening cutscene (scene art, also placeholders)

`scenes/OpeningCutscene.tscn` plays once at the start of a run. Every slot is a
node under `Stage`, drawn with coloured rects and `res://icon.svg` for now; swap
the texture and keep the node's size, so the tweens in `scripts/OpeningCutscene.gd`
(positions are set in code from the screen size) stay where they are.

| Slot (file name) | Node | Source size | Notes |
|---|---|---|---|
| `cutscene_sky_day.png` | `Sky` | 576x324 | The daytime sky over the suitors. `Sky.color` is tweened to night, so a tintable (greyscale) sky works best. |
| `cutscene_ground.png` | `Ground` | 576x123 | A meadow strip; it is dropped from under the suitors, so draw nothing below it. |
| `cutscene_arena.png` | `Sky` / `Ground` colours | 576x324 | The celestial arena the suitors land in: a night sky and a floor, shown after the fall. |
| `ines.png` | `Ines` | 36x48 | Ines standing, then small in Bathala's palm (the node is scaled to 0.5). |
| `suitor_1.png`, `suitor_2.png` | `Suitor1`, `Suitor2` | 36x48 | The two boastful suitors. They are tinted with bandana colours 0 and 1 until there is art. |
| `bathala_hand.png` | `Hand` (`Arm`) | 40x50 (arm 20x350) | The great hand: the arm runs off the top of the screen. |
| `bathala_portrait.png` | `Bathala` | 90x90 | Already exists (`Assets/Gods/Bathala`); a shape that reads at 180x180. |
| `ines_portrait.png` | `Cutscene.placeholder()` | 32x32 | Ines's small portrait in the dialogue box, and beside Bathala's at the end of the run. |
| `suitor_portrait_1.png`, `_2.png` | `Cutscene.placeholder()` | 32x32 | The suitors' small portraits in the dialogue box. Mortals show no big photo. |
| roll call | `GodRow` slots | 60x60 | Reuses each god's `portrait` (Mayari, Apolaki, Hanan, Tala, Mapulon & Ikapati); they stand as silhouettes, then slide in and light up as Bathala calls them. |
