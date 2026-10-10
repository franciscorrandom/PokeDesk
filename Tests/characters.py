"""Validate the distributed Mewtwo rig and animation payload, without graphics."""
import json
import math
import struct
from pathlib import Path

root = Path(__file__).resolve().parent.parent
raw = (root/'Assets/mewtwo-biblioteca.glb').read_bytes()
magic, version, length = struct.unpack_from('<4sII', raw)
assert (magic, version, length) == (b'glTF', 2, len(raw))
size = struct.unpack_from('<I', raw, 12)[0]
doc = json.loads(raw[20:20+size]); binary = raw[28+size:]
assert len(binary) >= doc['buffers'][0]['byteLength']
assert all('uri' not in x for x in doc['buffers']+doc['images'])
assert 'nguyenlouis32' in doc['asset']['extras']['author']
assert 'CC-BY-4.0' in doc['asset']['extras']['license']
assert len(doc['skins'][0]['joints']) == 77
assert len(set(doc['skins'][0]['joints'])) == 77
for v in doc['bufferViews']:
    assert v.get('byteOffset', 0)+v['byteLength'] <= doc['buffers'][0]['byteLength']

def read(i):
    a = doc['accessors'][i]; v = doc['bufferViews'][a['bufferView']]
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
    code, size = {5126: ('f', 4), 5125: ('I', 4), 5123: ('H', 2), 5121: ('B', 1)}[a['componentType']]
    start = v.get('byteOffset', 0)+a.get('byteOffset', 0)
    values = [struct.unpack_from('<'+code*width, binary, start+j*v.get('byteStride', width*size)) for j in range(a['count'])]
    assert all(math.isfinite(x) for row in values for x in row)
    return values

expected = {'reposo', 'curiosidad', 'saludo', 'cola-alegre', 'estiramiento', 'aviso-reunion', 'celebracion', 'caricias', 'sentarse'}
assert len(doc['animations']) == 9
assert {a['name'] for a in doc['animations']} == expected
animated_channels = 0
for clip in doc['animations']:
    joint_motion = False; expressions = set()
    for channel in clip['channels']:
        s = clip['samplers'][channel['sampler']]
        times = [v[0] for v in read(s['input'])]; values = read(s['output'])
        assert len(times) == len(values) and times[0] == 0 and times[-1] > 3
        assert all(a < b for a, b in zip(times, times[1:]))
        assert max(abs(a-b) for a, b in zip(values[0], values[-1])) < .0001
        node = channel['target']['node']; path = channel['target']['path']
        assert 0 <= node < len(doc['nodes'])
        if path == 'rotation':
            assert all(abs(sum(v*v for v in row)-1) < .0001 for row in values)
            assert all(sum(a*b for a, b in zip(q, r)) >= 0 for q, r in zip(values, values[1:]))
            if node in doc['skins'][0]['joints'] and values[0] != values[len(values)//3]: joint_motion = True
        if path == 'scale':
            assert s['interpolation'] == 'STEP'
            assert set(values) <= {(0, 0, 0), (1, 1, 1)}
            expressions.add(doc['nodes'][node]['name'])
        animated_channels += 1
    assert joint_motion, clip['name']
    assert expressions == {'MewtwoEyesOpen', 'MewtwoEyesHalf', 'MewtwoEyesClosed', 'MewtwoPupils'}

for n in doc['nodes']:
    if 'skin' not in n or 'mesh' not in n: continue
    for p in doc['meshes'][n['mesh']]['primitives']:
        a = p['attributes']; positions = read(a['POSITION'])
        assert all(v[0] < len(positions) for v in read(p['indices']))
        for joints, weights in zip(read(a['JOINTS_0']), read(a['WEIGHTS_0'])):
            assert all(0 <= j < 77 for j in joints)
            assert all(0 <= w <= 1 for w in weights) and abs(sum(weights)-1) < .0001
        assert all(abs(sum(x*x for x in n)-1) < .001 for n in read(a['NORMAL']))
assert len(read(doc['skins'][0]['inverseBindMatrices'])) == 77
print(f'Mewtwo GLB válido: 77 articulaciones, 9 clips, {animated_channels} canales; cierres, expresiones y pesos correctos.')
