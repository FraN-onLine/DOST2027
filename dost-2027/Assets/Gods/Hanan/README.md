# Hanan's art (drop-in)

Hanan's arena (`scenes/gods/hanan/HananArena.tscn`) works without any of these
files. It looks for each one when the arena loads and uses it if it is there.
Missing files fall back to placeholders. Drop a file into this folder with the
exact name below, let Godot import it, and it shows up. No scene or code change is
needed.

| File | What it is | Used by | Fallback when missing |
|---|---|---|---|
| `Hanan-Icon.png` | Hanan's portrait, 64 x 64 px like `Assets/Gods/Tala/Tala-Icon.png` | lobby god icon, sidebars, God's Due menu, Almanac | `res://icon.svg` (see the note below) |
| `Baka.png` | the crouching Baka, standing on its feet at the bottom of the image. Either one image, scaled taller each level, or a horizontal strip of 5 equal frames (Low, Sitting, Standing, High, Over the Moon) | `ArenaField/Baka/Sprite` | the brown `ArenaField/Baka/Body` rectangle, scaled taller each level |
| `Hanan-Overseer.png` | Hanan watching the field, like `Assets/Gods/Tala/Tala-Overseer.png` (one image) | `ArenaField/Overseer` | hidden |
| `Arena-Background.png` | the arena background, ideally 1152 x 648 (it is stretched to fill the screen) | `Background` | Mayari's `AreanaTemp.png` |

A strip is detected by its shape. An image at least 2.5 times as wide as it is
tall is read as 5 frames, and the arena shows the frame for the current level
instead of stretching the image.

## Swap the icon by hand

`resources/gods/hanan.tres` is a resource file and cannot fall back by itself, so
it still points at `res://icon.svg`. Once `Hanan-Icon.png` exists, open
`hanan.tres` in the editor and set **icon** to it. Alternatively, change the
`ext_resource` line `path="res://icon.svg" id="2_icon"` for the god's icon only.
The favors share that same resource, so the simplest edit is to add a second
`ext_resource` for the portrait and point the `[resource]` section's `icon` at it,
the way `tala.tres` does with `4_portrait`.
