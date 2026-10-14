import io
p = 'UI/GodsArena/god_dialogue.tscn'
lines = io.open(p, encoding='utf-8').read().splitlines(True)
out = []
for l in lines:
    l = l.replace('texture = ExtResource("3_icon")', 'texture = ExtResource("9_photo")')
    if l.strip() == '[node name="HBox" type="HBoxContainer" parent="Box/Margin"]':
        out.append('')
        out.append('[node name="PhotoSprite" type="TextureRect" parent="Box/Margin"]')
        out.append('custom_minimum_size = Vector2(96, 96)')
        out.append('layout_mode = 2')
        out.append('size_flags_vertical = 4')
        out.append('mouse_filter = 2')
        out.append('texture = ExtResource("9_photo")')
        out.append('expand_mode = 1')
        out.append('stretch_mode = 5')
        out.append('')
io.open(p, 'w', encoding='utf-8').writelines(out)
