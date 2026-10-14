import io

p = 'UI/GodsArena/god_dialogue.tscn'
lines = io.open(p, encoding='utf-8').read().splitlines(True)

# Replace the broken section (lines 65-71, indices 64-70)
# current broken state:
# 65: layout_mode = 2\n
# 66: mouse_filter = 2\n
# 67: layout_mode = 2\n
# 68: [node name="HBox" type="HBoxContainer" parent="Box/Margin"]\n
# 69: layout_mode = 2\n
# 70: mouse_filter = 2\n
# 71: theme_override_constants/separation = 16\n
# We want:
# 65: layout_mode = 2\n
# 66: mouse_filter = 2\n
# 67: theme_override_constants/separation = 16\n
# 68: \n
# 69: [node name="PhotoSprite" type="TextureRect" parent="Box/Margin/HBox"]\n

out = []
skip = 0
for i, l in enumerate(lines):
    if i == 64:  # line 65
        continue  # skip the broken layout_mode
    if i == 65:  # line 66
        continue  # skip broken mouse_filter
    if i == 66:  # line 67
        # This is the duplicate layout_mode from new HBox
        out.append('theme_override_constants/separation = 16\n')
        continue
    if i == 67:  # line 68 - the HBox node line
        out.append('\n')
        continue
    if i == 68:  # line 69 - PhotoSprite duplicate
        continue
    out.append(l)

io.open(p, 'w', encoding='utf-8').writelines(out)
print('rebuilt')
