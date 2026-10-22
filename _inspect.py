import io, re
p = r'c:/Dost2027/dost-2027/scenes/gods/common/Mortal.tscn'
s = io.open(p, encoding='utf-8').read()
for name in ['walk', 'hit-arnis', 'default', 'defend-arnis']:
    key = '"name": &"' + name + '"'
    i = s.find(key)
    if i < 0:
        print(name, 'NOT FOUND'); continue
    # find the enclosing animation block start
    j = s.rfind('{\n"frames"', 0, i)
    block = s[j:i+40]
    loop = re.search(r'"loop": (\d+)', block)
    speed = re.search(r'"speed": ([\d.]+)', block)
    nframes = block.count('"duration"')
    print('%-14s frames=%-3s loop=%-3s speed=%-6s' % (name, nframes, loop.group(1) if loop else '?', speed.group(1) if speed else '?'))
