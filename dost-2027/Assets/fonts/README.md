# Fonts

- `Minecraftia-Regular.ttf`: Minecraftia by Andrew Tyler, CC BY-SA. This is the
  original file, untouched.
- `Minecraftia-UI.ttf`: the same font with its vertical metrics fixed. The theme
  (`UI/theme/bathala_theme.tres`) uses this one. Licensed CC BY-SA, like the
  original.

## Why there is a second file

The original TTF draws every glyph 960 units (0.625 em) above its baseline, and
it stores its descent as a positive number, which Godot reads as 0. So a 16 px
label is 28 px tall, and the text sits in the top half of every button.

The UI copy fixes this:

- Every glyph moves down 960 units, so the capitals sit on the baseline.
- Ascent is 1536 (1 em) and descent is 192 (1/8 em, one font pixel).

A line of text is now 1.125 em: 18 px at 16 px, with the capitals centred.

The fix was made with fontTools. To redo it, shift each `glyf` outline by -960
in y, then set the `hhea` and `OS/2` ascent and descent to the values above.

Use the type scale (8, 16, 24, 32, 48 px). Minecraftia is drawn on an 8 px grid,
so any other size renders soft.
