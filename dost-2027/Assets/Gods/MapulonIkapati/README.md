# Mapulon & Ikapati's art (drop-in)

Langit Lupa (`scenes/gods/mapulon_ikapati/LangitLupaArena.tscn`) works without any
of these files. It looks for each one when the arena loads and uses it if it is
there. Missing files fall back to placeholders. Drop a file into this folder with
the exact name below, let Godot import it, and it shows up. No scene or code change
is needed.

| File | What it is | Used by | Fallback when missing |
|---|---|---|---|
| `MapulonIkapati-Icon.png` | the pair's portrait, 64 x 64 px like `Assets/Gods/Tala/Tala-Icon.png` | lobby god icon, sidebars, God's Due menu, Almanac | `res://icon.svg` (see the note below) |
| `Arena-Background.png` | the field (the Lupa), ideally 1152 x 648 (it is stretched to fill the screen) | `Background` | Mayari's `AreanaTemp.png`, tinted green |
| `Langit.png` | one sky platform (a cloud or a terraced rice-paddy block), centred, about 96 x 60 px. The shadow under it stays | `ArenaField/Langits/LangitN/Sprite` | the white `Body` rectangle (greyed, with the `Lock` shape, on the screen of a runner it is closed to) |
| `Langit-Crumble.png` | the crack / crumble animation, a horizontal strip of square-ish frames (the frame count is read from width / height). It plays over the platform during the warning before a crumble | `ArenaField/Langits/LangitN/Crumble` | the platform shakes and fades instead |
| `Taya-Marker.png` | the marker floating over the Taya's head | `TayaMarker/Sprite` | the green ring (the "TAYA" tag shows either way) |
| `God-Taya.png` | Mapulon & Ikapati on the field as the opening Taya, centred on the body, about 87 px tall (1.5 mortals; `god_height` on the arena) | `GodLook/Art` on the gods' body (made in code, `_spawn_god`) | Ikapati's overseer sprite (`IkapatiOverseer-Sheet.png`, 3 frames looping, `god_height` tall) over a ring in the pair's accent; the mortal sprite on the body is always hidden |
| `MapulonIkapati-Overseer.png` | the pair watching the field, like `Assets/Gods/Tala/Tala-Overseer.png` (one image) | `ArenaField/Overseer` | hidden |

The platform size the rules use is `langit_size` on the arena (96 x 60). If the
art is a different size, change `langit_size` too so the safe area matches what
the players see.

## Swap the icon by hand

`resources/gods/mapulon_ikapati.tres` is a resource file and cannot fall back by
itself, so it still points at `res://icon.svg`. Once `MapulonIkapati-Icon.png`
exists, add a second `ext_resource` for the portrait and point the `[resource]`
section's `icon` at it, the way `tala.tres` does with `4_portrait`.
