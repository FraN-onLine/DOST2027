import re
import sys

path = r'c:/Dost2027/dost-2027/scenes/gods/common/Mortal.tscn'
content = open(path, encoding='utf-8').read()
names = re.findall(r'"name": &"([^"]+)"', content)
print('Mortal.tscn animation names:', names)

# Find the SpriteFrames block and print the anim blocks compactly
for m in re.finditer(r'"name": &"([^"]+)",\s*\n\s*"speed": ([0-9.]+)', content):
    print('  anim:', m.group(1), 'speed:', m.group(2))
