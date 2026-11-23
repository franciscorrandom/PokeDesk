"""Validate the new portable rigs independently of their preparation scripts."""
import copy
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLIPS = {'reposo': 8, 'curiosidad': 4, 'saludo': 4, 'cola-alegre': 4.8,
         'estiramiento': 5, 'aviso-reunion': 4, 'celebracion': 3.6,
         'caricias': 5.6, 'sentarse': 7.2}


def validate(character, joints):
    raw = (ROOT / f'Assets/{character}-biblioteca.glb').read_bytes()
    assert struct.unpack_from('<4sII', raw) == (b'glTF', 2, len(raw))
    length, kind = struct.unpack_from('<II', raw, 12)
    assert kind == 0x4E4F534A
    doc = json.loads(raw[20:20 + length])
    binary = raw[28 + length:]
    assert len(binary) >= doc['buffers'][0]['byteLength']
    assert not {'KHR_draco_mesh_compression', 'EXT_texture_webp', 'KHR_mesh_quantization'} & set(doc.get('extensionsRequired', []))
    assert all('uri' not in item for item in doc['buffers'] + doc['images'])
    assert all(image.get('mimeType') in ['image/png', 'image/jpeg'] for image in doc['images'])
    assert 'creativecommons.org/licenses/by/4.0' in json.dumps(doc['asset']).lower()
    assert doc['asset'].get('extras', {}).get('author')
    assert len(doc['skins'][0]['joints']) == joints

    def read(index):
        accessor = doc['accessors'][index]
        view = doc['bufferViews'][accessor['bufferView']]
        width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[accessor['type']]
        code, size = {5126: ('f', 4), 5125: ('I', 4), 5123: ('H', 2), 5121: ('B', 1), 5122: ('h', 2), 5120: ('b', 1)}[accessor['componentType']]
        start = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
        stride = view.get('byteStride', width * size)
        assert start + (accessor['count'] - 1) * stride + width * size <= doc['buffers'][0]['byteLength']
        result = [struct.unpack_from('<' + code * width, binary, start + i * stride) for i in range(accessor['count'])]
        assert all(math.isfinite(value) for row in result for value in row)
        if accessor.get('normalized') and code != 'f':
            limit = (2 ** (size * 8 - 1) - 1) if code.islower() else (2 ** (size * 8) - 1)
            result = [tuple(max(-1, value / limit) for value in row) for row in result]
        return result

    for skin in doc['skins']:
        assert len(skin['joints']) == len(set(skin['joints']))
        assert len(read(skin['inverseBindMatrices'])) == len(skin['joints'])
        assert all(0 <= index < len(doc['nodes']) for index in skin['joints'])

    triangles = 0
    for node in doc['nodes']:
        if 'mesh' not in node:
            continue
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            assert not primitive.get('extensions', {}).get('KHR_draco_mesh_compression')
            attrs = primitive['attributes']
            positions, normals = read(attrs['POSITION']), read(attrs['NORMAL'])
            assert len(positions) == len(normals)
            assert all(abs(sum(v*v for v in normal) - 1) < .02 for normal in normals)
            assert len(read(attrs['TEXCOORD_0'])) == len(positions)
            indices = read(primitive['indices'])
            triangles += len(indices) // 3
            assert all(0 <= row[0] < len(positions) for row in indices)
            if 'skin' in node:
                limit = len(doc['skins'][node['skin']]['joints'])
                for ids, weights in zip(read(attrs['JOINTS_0']), read(attrs['WEIGHTS_0'])):
                    assert all(0 <= index < limit for index in ids)
                    assert all(0 <= weight <= 1.0001 for weight in weights)
                    assert abs(sum(weights) - 1) < .002
    assert triangles > 500

    assert len(doc['animations']) == len(CLIPS)
    assert {clip['name'] for clip in doc['animations']} == set(CLIPS)
    all_joints = {index for skin in doc['skins'] for index in skin['joints']}
    signatures = set()
    max_step = 0
    for clip in doc['animations']:
        articulated = False
        signature = []
        targets = set()
        for channel in clip['channels']:
            target = channel['target']
            key = (target['node'], target['path'])
            assert key not in targets
            targets.add(key)
            sampler = clip['samplers'][channel['sampler']]
            times = [row[0] for row in read(sampler['input'])]
            values = read(sampler['output'])
            assert len(times) == len(values) and times[0] == 0
            assert abs(times[-1] - CLIPS[clip['name']]) < .0001
            assert all(a < b for a, b in zip(times, times[1:]))
            assert max(abs(a-b) for a, b in zip(values[0], values[-1])) < .0001, (character, clip['name'], key, 'open loop')
            if target['path'] == 'rotation':
                assert all(abs(sum(v*v for v in row) - 1) < .0002 for row in values)
                for a, b in zip(values, values[1:]):
                    dot = sum(x*y for x, y in zip(a, b))
                    assert dot >= 0, 'Quaternion sign must remain continuous'
                    max_step = max(max_step, 2 * math.acos(min(1, dot)))
                if target['node'] in all_joints and any(abs(a-b) > .001 for a, b in zip(values[0], values[len(values)//3])):
                    articulated = True
            signature.append((key, tuple(round(v, 4) for row in values[::max(1, len(values)//8)] for v in row)))
        assert articulated, (character, clip['name'], 'No articulated movement')
        signatures.add(str(signature))
    assert len(signatures) == len(CLIPS), 'Each action must have its own animation'
    assert max_step < .65, (character, 'Abrupt joint changes', math.degrees(max_step))
    idle = next(clip for clip in doc['animations'] if clip['name'] == 'reposo')
    names = {node.get('name'): i for i, node in enumerate(doc['nodes'])}
    if character == 'dragonite':
        blink = doc['asset']['extras']['pokedeskBlink']
        assert blink['time'] == 3 and len(blink['nodes']) >= 2
        for name, expected in blink['nodes'].items():
            index = names[name]
            assert index in all_joints
            channel = next(c for c in idle['channels'] if c['target'] == {'node': index, 'path': 'rotation'})
            sampler = idle['samplers'][channel['sampler']]
            times, values = read(sampler['input']), read(sampler['output'])
            key = min(range(len(times)), key=lambda i: abs(times[i][0] - 3))
            assert abs(times[key][0] - 3) < .0001
            assert abs(sum(a*b for a, b in zip(values[key], expected))) > .99999
            assert abs(sum(a*b for a, b in zip(values[key], values[0]))) < .9999
    else:
        for label in ['Open', 'Half', 'Closed']:
            index = names['EeveeEyes' + label]
            assert 'mesh' in doc['nodes'][index]
            channel = next(c for c in idle['channels'] if c['target'] == {'node': index, 'path': 'scale'})
            sampler = idle['samplers'][channel['sampler']]
            assert sampler['interpolation'] == 'STEP'
            times, values = read(sampler['input']), read(sampler['output'])
            key = min(range(len(times)), key=lambda i: abs(times[i][0] - 3))
            assert values[key] == ((1, 1, 1) if label == 'Closed' else (0, 0, 0))
    if character == 'eevee':
        # Check the visible posture, not an arbitrary head bone axis: this
        # source uses a rotated bone frame while its eye surface faces +Z.
        parents = {child: i for i, node in enumerate(doc['nodes']) for child in node.get('children', [])}
        rest = copy.deepcopy(doc['nodes'])
        def world_matrices(nodes):
            cache = {}
            def multiply(a, b):
                return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]
            def world(index):
                if index in cache:
                    return cache[index]
                node = nodes[index]
                if 'matrix' in node:
                    m = [[node['matrix'][c * 4 + r] for c in range(4)] for r in range(4)]
                else:
                    x, y, z, w = node.get('rotation', [0, 0, 0, 1])
                    scale = node.get('scale', [1, 1, 1])
                    rotation = [[1-2*y*y-2*z*z, 2*x*y-2*z*w, 2*x*z+2*y*w],
                                [2*x*y+2*z*w, 1-2*x*x-2*z*z, 2*y*z-2*x*w],
                                [2*x*z-2*y*w, 2*y*z+2*x*w, 1-2*x*x-2*y*y]]
                    m = [[rotation[r][c] * scale[c] for c in range(3)] + [node.get('translation', [0, 0, 0])[r]] for r in range(3)] + [[0, 0, 0, 1]]
                cache[index] = multiply(world(parents[index]), m) if index in parents else m
                return cache[index]
            return {i: world(i) for i in range(len(nodes))}
        base = world_matrices(rest)
        def point(worlds, index):
            return [worlds[index][r][3] for r in range(3)]
        def distance(a, b):
            return math.sqrt(sum((x-y)**2 for x, y in zip(a, b)))
        head, neck = names['Head_035'], names['Neck_028']
        assert point(base, head)[1] > .43 and point(base, neck)[1] > .35, 'Eevee should hold his head and chest above the forelegs'
        for upper, elbow, paw in [('LArm_024', 'LForeArm_025', 'LHand_026'), ('RArm_051', 'RForeArm_052', 'RHand_053')]:
            a, b, c = [point(base, names[n]) for n in [upper, elbow, paw]]
            assert a[1] - c[1] > .22 and b[1] - c[1] > .08, 'Both forelegs must extend visibly below the chest'
            assert c[2] - a[2] > .05, 'Front paws should stand forward of the upper legs'
        eye = names['EeveeEyesOpen']
        primitive = doc['meshes'][rest[eye]['mesh']]['primitives'][0]
        normal = [sum(row[k] for row in read(primitive['attributes']['NORMAL'])) for k in range(3)]
        facing = [sum(base[eye][r][k] * normal[k] for k in range(3)) for r in range(3)]
        norm = math.sqrt(sum(x*x for x in facing)); facing = [x/norm for x in facing]
        assert facing[2] > .8 and -.05 < facing[1] < .6, 'The eye surface must face forward, without a downward-looking pose'
        paws = [names[n] for n in ['LHand_026', 'RHand_053', 'LFoot_07', 'RFoot_013']]
        contacts = [point(base, paw) for paw in paws]
        max_contact = 0
        for clip in doc['animations']:
            tracks = [(channel['target'], read(clip['samplers'][channel['sampler']]['output'])) for channel in clip['channels']]
            assert all(target['path'] != 'scale' or target['node'] not in all_joints for target, _ in tracks), 'Do not shrink or lengthen Eevee bones'
            assert all(target['path'] != 'translation' or target['node'] == names['Origin_02'] for target, _ in tracks), 'Keep every limb segment at its original length'
            for frame in range(0, len(tracks[0][1]), 3):
                posed = copy.deepcopy(rest)
                for target, values in tracks:
                    posed[target['node']][target['path']] = values[frame]
                worlds = world_matrices(posed)
                planted = [point(worlds, paw) for paw in paws]
                assert min(p[1]-c[1] for p, c in zip(planted, contacts)) > -.002, 'Paws must not pass through the floor'
                if clip['name'] in ['reposo', 'curiosidad', 'cola-alegre', 'aviso-reunion', 'caricias']:
                    max_contact = max(max_contact, max(distance(p, c) for p, c in zip(planted, contacts)))
        assert max_contact < .002, 'Planted paws must remain anchored during upper-body gestures'
        print(f'Eevee: postura frontal natural, dos patas delanteras visibles y apoyos estables (error {max_contact:.6f} m).')
    preview = (ROOT / f'Assets/preview-{character}.png').read_bytes()
    assert preview[:8] == b'\x89PNG\r\n\x1a\n' and struct.unpack_from('>II', preview, 16) == (320, 320)
    print(f'{character.title()}: {joints} articulaciones, {triangles} triángulos, nueve gestos cerrados, texturas portables y miniatura válidos; paso máximo {math.degrees(max_step):.2f}°.')


validate('dragonite', 80)
validate('eevee', 57)
