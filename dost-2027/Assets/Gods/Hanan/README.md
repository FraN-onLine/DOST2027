# Hanan's art (drop-in)

Hanan's arena (`scenes/gods/hanan/HananArena.tscn`) works without any of these
files. It looks for each one when the arena loads and uses it if it is there.
Missing files fall back to placeholders. Drop a file into this folder with the
exact name below, let Godot import it, and it shows up. No scene or code change is
needed.

| File | What it is | Used by | Fallback when missing |
|---|---|---|---|
| `Hanan-Icon.png` | Hanan's portrait, 64 x 64 px like `Assets/Gods/Tala/Tala-Icon.png` | lobby god icon, sidebars, God's Due menu, Almanac | `res://Assets/Placeholders/favor.png` (see the note below) |
| `Hanan-Overseer.png` | Hanan watching the field, like `Assets/Gods/Tala/Tala-Overseer.png` (one image) | `ArenaField/Overseer` | hidden |
| `Arena-Background.png` | the arena background, ideally 1152 x 648 (it is stretched to fill the screen) | `Background` | Mayari's `AreanaTemp.png` |

Hanan herself is the Baka, and she is not a drop-in file any more: she is her own
scene, `scenes/gods/hanan/HananBaka.tscn` (the old `Baka.png` strip is no longer
read). Put the frames in its `Art` SpriteFrames, clips `low`, `sitting` and
`standing` (see `UI/theme/ART_SLOTS.md`, "God scenes"). The Godot placeholder stays
until then.

## Swap the icon by hand

`resources/gods/hanan.tres` is a resource file and cannot fall back by itself, so
it still points at `res://Assets/Placeholders/favor.png`. Once `Hanan-Icon.png` exists, open
`hanan.tres` in the editor and set **icon** to it. Alternatively, change the
`ext_resource` line `path="res://Assets/Placeholders/favor.png" id="2_icon"` for the god's icon only.
The favors share that same resource, so the simplest edit is to add a second
`ext_resource` for the portrait and point the `[resource]` section's `icon` at it,
the way `tala.tres` does with `4_portrait`.
