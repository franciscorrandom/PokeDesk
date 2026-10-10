#!/usr/bin/env python3
"""Reproducible Mewtwo rig preparation and nine portable glTF animation clips.

Requires numpy. Uses the downloaded author's geometry and expression atlas;
no external service, textures or animation dependencies are used at runtime.
"""
import copy
import json
import math
import struct
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
source = ROOT / "Models/Mewtwo/mewtwo-original.glb"
raw = source.read_bytes()
json_length = struct.unpack_from("<I", raw, 12)[0]
doc = json.loads(raw[20:20 + json_length])
binary = bytearray(raw[28 + json_length:28 + json_length + doc['buffers'][0]['byteLength']])
nodes = doc['nodes']
parents = {c: i for i, n in enumerate(nodes) for c in n.get('children', [])}
names = {n.get('name'): i for i, n in enumerate(nodes)}


def quat_mul(a, b):
    x, y, z, w = a; X, Y, Z, W = b
    return np.array([w*X+x*W+y*Z-z*Y, w*Y-x*Z+y*W+z*X,
                     w*Z+x*Y-y*X+z*W, w*W-x*X-y*Y-z*Z])


def rotation(q):
    x, y, z, w = q
    return np.array([[1-2*y*y-2*z*z, 2*x*y-2*z*w, 2*x*z+2*y*w],
                     [2*x*y+2*z*w, 1-2*x*x-2*z*z, 2*y*z-2*x*w],
                     [2*x*z-2*y*w, 2*y*z+2*x*w, 1-2*x*x-2*y*y]])


def local(n):
    if 'matrix' in n:
        return np.array(n['matrix']).reshape(4, 4).T
    m = np.eye(4)
    m[:3, :3] = rotation(n.get('rotation', [0, 0, 0, 1])) @ np.diag(n.get('scale', [1, 1, 1]))
    m[:3, 3] = n.get('translation', [0, 0, 0])
    return m


def worlds():
    cache = {}
    def at(i):
        if i not in cache:
            cache[i] = at(parents[i]) @ local(nodes[i]) if i in parents else local(nodes[i])
        return cache[i]
    return {i: at(i) for i in range(len(nodes))}


def read(i):
    a = doc['accessors'][i]; v = doc['bufferViews'][a['bufferView']]
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
    dtype = {5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1'}[a['componentType']]
    size = np.dtype(dtype).itemsize
    return np.ndarray((a['count'], width), dtype=dtype, buffer=binary,
                      offset=v.get('byteOffset', 0)+a.get('byteOffset', 0),
                      strides=(v.get('byteStride', width*size), size)).copy()


def append(values, kind, bounds=False):
    data = np.asarray(values, dtype='<f4')
    assert np.isfinite(data).all()
    binary.extend(b'\0' * (-len(binary) % 4))
    offset = len(binary); binary.extend(data.tobytes())
    vi = len(doc['bufferViews'])
    doc['bufferViews'].append({'buffer': 0, 'byteOffset': offset, 'byteLength': data.nbytes})
    a = {'bufferView': vi, 'componentType': 5126, 'count': len(data), 'type': kind}
    if bounds:
        a.update(min=data.min(axis=0).tolist(), max=data.max(axis=0).tolist())
    ai = len(doc['accessors']); doc['accessors'].append(a)
    return ai


old_world = worlds()
skin = doc['skins'][0]
old_bind = read(skin['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)


def add_world_rotation(i, axis, angle, world):
    basis = world[i][:3, :3]
    basis = basis / np.linalg.norm(basis, axis=0)
    axis_local = basis.T @ np.asarray(axis)
    axis_local /= np.linalg.norm(axis_local)
    delta = np.r_[axis_local * math.sin(angle/2), math.cos(angle/2)]
    result = quat_mul(nodes[i].get('rotation', [0, 0, 0, 1]), delta)
    return (result / np.linalg.norm(result)).tolist()


# Bake a compact, relaxed bind pose. The authored rig and weights are preserved,
# and inverse binds are rebuilt to match the posed vertices (including normals).
for i, a in [(47, -.34), (71, .34)]:
    nodes[i]['rotation'] = add_world_rotation(i, [0, 0, 1], a, old_world)
for k, i in enumerate(range(34, 43)):
    nodes[i]['rotation'] = add_world_rotation(i, [0, 1, 0], [.20, .30, .36, .38, .38, .34, .28, .20, .12][k], old_world)
    nodes[i]['rotation'] = add_world_rotation(i, [1, 0, 0], .035, worlds())
new_world = worlds()
baked = {}
for mi in range(3):
    ni = next(i for i, n in enumerate(nodes) if n.get('mesh') == mi)
    prim = doc['meshes'][mi]['primitives'][0]; attrs = prim['attributes']
    pos = read(attrs['POSITION']); normal = read(attrs['NORMAL'])
    joints = read(attrs['JOINTS_0']); weights = read(attrs['WEIGHTS_0'])
    transforms = [np.linalg.inv(new_world[ni]) @ new_world[j] @ old_bind[k] for k, j in enumerate(skin['joints'])]
    p = np.zeros_like(pos); n = np.zeros_like(normal)
    extended = np.c_[pos, np.ones(len(pos))]
    for v in range(len(pos)):
        for j, weight in zip(joints[v], weights[v]):
            if weight <= 0: continue
            m = transforms[int(j)]
            p[v] += weight * (m @ extended[v])[:3]
            n[v] += weight * (np.linalg.inv(m[:3, :3]).T @ normal[v])
    n /= np.linalg.norm(n, axis=1)[:, None]
    baked[mi] = (ni, p, n, copy.deepcopy(prim))
    attrs['POSITION'] = append(p, 'VEC3', True)
    attrs['NORMAL'] = append(n, 'VEC3')
mesh_world = new_world[6]
skin['inverseBindMatrices'] = append([ (np.linalg.inv(new_world[j]) @ mesh_world).T.reshape(16) for j in skin['joints']], 'MAT4')

# Head-attached expression variants use the original texture atlas and pupils.
for mi, variants in [(1, [('MewtwoEyesOpen', 0, 0, True), ('MewtwoEyesHalf', 0, -.25, False), ('MewtwoEyesClosed', 0, -.5, False)]),
                     (2, [('MewtwoPupils', 0, 0, True)])]:
    ni, p, n, primitive = baked[mi]
    if mi == 2:
        # The downloadable GLB has an untextured grey iris placeholder. Shape
        # the existing iris polygons into narrow purple irises, with inset
        # dark pupils and small highlights, rather than painting a new atlas.
        p = p.copy()
        for side in [-1, 1]:
            ids = np.where(p[:, 0]*side > 0)[0]
            center = p[ids].mean(axis=0); normal = n[ids].mean(axis=0)
            normal /= np.linalg.norm(normal)
            right = np.cross([0, 1, 0], normal); right /= np.linalg.norm(right)
            up = np.cross(normal, right)
            delta = p[ids]-center
            p[ids] = center + np.outer(delta@right, right)*.29 + np.outer(delta@up, up)*.82 + np.outer(delta@normal, normal) + normal*.12
        doc['materials'][2]['pbrMetallicRoughness']['baseColorFactor'] = [.32, .12, .55, 1]
    to_head = np.linalg.inv(new_world[60]) @ new_world[ni]
    positions = (to_head @ np.c_[p, np.ones(len(p))].T).T[:, :3]
    normals = (np.linalg.inv(to_head[:3, :3]).T @ n.T).T
    normals /= np.linalg.norm(normals, axis=1)[:, None]
    pa = append(positions, 'VEC3', True); na = append(normals, 'VEC3')
    uv = read(primitive['attributes']['TEXCOORD_0'])
    for name, du, dv, visible in variants:
        mesh = len(doc['meshes'])
        doc['meshes'].append({'name': name, 'primitives': [{**primitive, 'attributes': {
            'POSITION': pa, 'NORMAL': na, 'TEXCOORD_0': append(uv + [du, dv], 'VEC2')}}]})
        nodes.append({'name': name, 'mesh': mesh, 'scale': [1, 1, 1] if visible else [0, 0, 0]})
        names[name] = len(nodes)-1
        nodes[60].setdefault('children', []).append(len(nodes)-1)
        if mi == 2:
            parent = len(nodes)-1
            for label, color, width, height, highlight in [('MewtwoIrisDark', [.07, .03, .12, 1], .34, .92, False), ('MewtwoIrisHighlight', [1, 1, 1, 1], .25, .13, True)]:
                smaller = p.copy()
                for side in [-1, 1]:
                    ids = np.where(p[:, 0]*side > 0)[0]
                    center = p[ids].mean(axis=0); normal = n[ids].mean(axis=0); normal /= np.linalg.norm(normal)
                    right = np.cross([0, 1, 0], normal); right /= np.linalg.norm(right); up = np.cross(normal, right)
                    delta = p[ids]-center
                    smaller[ids] = center + np.outer(delta@right, right)*width + np.outer(delta@up, up)*height + np.outer(delta@normal, normal) + normal*(.22 if highlight else .11)
                    if highlight: smaller[ids] += up*3.0-right*.35
                sp = (to_head @ np.c_[smaller, np.ones(len(smaller))].T).T[:, :3]
                mat = len(doc['materials']); doc['materials'].append({'name': label, 'doubleSided': True, 'pbrMetallicRoughness': {'baseColorFactor': color, 'metallicFactor': 0, 'roughnessFactor': 1}})
                mesh = len(doc['meshes']); doc['meshes'].append({'name': label, 'primitives': [{**primitive, 'material': mat, 'attributes': {'POSITION': append(sp, 'VEC3', True), 'NORMAL': na}}]})
                nodes.append({'name': label, 'mesh': mesh}); nodes[parent].setdefault('children', []).append(len(nodes)-1)
    nodes[ni].pop('mesh'); nodes[ni].pop('skin')

rest = copy.deepcopy(nodes)
rest_world = worlds()
catalog = [
    ('reposo', 'Levitación y parpadeo', 8),
    ('curiosidad', 'Mirada curiosa', 4),
    ('saludo', 'Saludo con la mano', 4),
    ('cola-alegre', 'Cola en movimiento', 4.8),
    ('estiramiento', 'Estiramiento', 5),
    ('aviso-reunion', 'Aviso psíquico', 4),
    ('celebracion', 'Celebración', 3.6),
    ('caricias', 'Disfrutar las caricias', 5.6),
    ('sentarse', 'Meditación', 7.2),
]


def smooth(x):
    x = min(1, max(0, x)); return x*x*x*(x*(x*6-15)+10)


def envelope(t, duration, fade=.8):
    return smooth(t/fade) * smooth((duration-t)/fade)


def pose(clip, t, duration):
    rotations = {}; translations = {}; scales = {}
    e = envelope(t, duration)
    def turn(i, axis, a):
        q = rotations.get(i, rest[i].get('rotation', [0, 0, 0, 1]))
        basis = rest_world[i][:3, :3]; basis = basis / np.linalg.norm(basis, axis=0)
        ax = basis.T @ np.asarray(axis); ax /= np.linalg.norm(ax)
        rotations[i] = quat_mul(q, np.r_[ax*math.sin(a/2), math.cos(a/2)]).tolist()
    def move(i, offset):
        translations[i] = (np.array(rest[i].get('translation', [0, 0, 0])) + offset).tolist()

    # Independent articulated breathing, hovering and a traveling tail wave.
    move(10, [0, e*(3.0+1.5*math.sin(t*2*math.pi/4)), 0])
    turn(44, [1, 0, 0], e*.012*math.sin(t*2*math.pi/4))
    turn(60, [1, 0, 0], e*.012*math.sin(t*2*math.pi/4+.6))
    for k, i in enumerate(range(34, 43)):
        turn(i, [0, 1, 0], e*.023*math.sin(t*2*math.pi/3-k*.42))
        turn(i, [1, 0, 0], e*.014*math.sin(t*2*math.pi/4-k*.35))
    for arm, sign in [(47, 1), (71, -1)]:
        turn(arm, [0, 0, 1], sign*e*.012*math.sin(t*2*math.pi/4+.5))

    blink_time = 3.0 if clip == 'reposo' else duration*.64
    blink = abs(t-blink_time)
    state = 'closed' if blink < .065 else 'half' if blink < .13 else 'open'
    if clip == 'curiosidad':
        turn(60, [0, 1, 0], e*.32*math.sin(t*1.9))
        turn(60, [0, 0, 1], e*.10*math.sin(t*1.5+.2))
        turn(59, [0, 1, 0], e*.05*math.sin(t*1.9-.3))
    elif clip == 'saludo':
        turn(47, [0, 0, 1], e*1.55)
        turn(48, [0, 0, 1], e*.70)
        turn(49, [0, 0, 1], e*.19*math.sin((t-.7)*7))
        turn(49, [0, 1, 0], e*.10*math.sin((t-.7)*7+.5))
        turn(60, [0, 0, 1], e*-.07)
        for i in [50, 53, 56]: turn(i, [0, 0, 1], e*.09*math.sin(t*7))
    elif clip == 'cola-alegre':
        for k, i in enumerate(range(34, 43)):
            turn(i, [0, 1, 0], e*.085*math.sin(t*3.8-k*.46))
            turn(i, [1, 0, 0], e*.045*math.sin(t*3.8-k*.46+.8))
        turn(60, [0, 1, 0], e*.18*math.sin(t*1.3))
    elif clip == 'estiramiento':
        for arm, elbow, sign in [(47, 48, 1), (71, 72, -1)]:
            turn(arm, [0, 0, 1], e*sign*2.0)
            turn(elbow, [0, 0, 1], e*sign*.20)
        turn(44, [1, 0, 0], e*-.08)
        turn(60, [1, 0, 0], e*-.10)
        move(10, [0, e*6, 0])
    elif clip == 'aviso-reunion':
        turn(71, [1, 0, 0], e*-.90)
        turn(72, [0, 1, 0], e*.18)
        turn(73, [1, 0, 0], e*.28)
        turn(60, [1, 0, 0], e*.09)
        turn(47, [0, 0, 1], e*.20)
        for i in [74, 77, 80]: turn(i, [0, 0, 1], e*.13)
    elif clip == 'celebracion':
        pulse = e*(.85+.15*math.cos(t*5))
        for arm, elbow, sign in [(47, 48, 1), (71, 72, -1)]:
            turn(arm, [0, 0, 1], sign*pulse*1.65)
            turn(elbow, [0, 0, 1], sign*pulse*.4)
        move(10, [0, e*(6+3*math.sin(t*5)), 0])
        turn(60, [0, 0, 1], e*.09*math.sin(t*5))
    elif clip == 'caricias':
        turn(60, [0, 0, 1], e*.18*math.sin(t*2.0))
        turn(60, [1, 0, 0], e*.12)
        turn(59, [0, 0, 1], e*.04*math.sin(t*2.0-.4))
        turn(44, [0, 0, 1], e*.025*math.sin(t*2.0-.7))
        for k, i in enumerate(range(34, 43)):
            turn(i, [0, 1, 0], e*.05*math.sin(t*3-k*.4))
        if .8 < t < duration-1: state = 'closed'
    elif clip == 'sentarse':
        move(10, [0, e*19, 0])
        for thigh, leg, foot in [(14, 15, 16), (24, 25, 26)]:
            turn(thigh, [1, 0, 0], e*-.65)
            turn(leg, [1, 0, 0], e*.88)
            turn(foot, [1, 0, 0], e*-.22)
        for arm, elbow, hand, sign in [(47, 48, 49, 1), (71, 72, 73, -1)]:
            turn(arm, [1, 0, 0], e*-.33)
            turn(elbow, [0, 0, 1], e*sign*.65)
            turn(hand, [0, 1, 0], e*sign*.20)
        turn(60, [1, 0, 0], e*.09)
        if 1.0 < t < duration-1.0: state = 'closed'
    for name, selected in [('MewtwoEyesOpen', state == 'open'), ('MewtwoEyesHalf', state == 'half'),
                           ('MewtwoEyesClosed', state == 'closed'), ('MewtwoPupils', state == 'open')]:
        scales[names[name]] = [1, 1, 1] if selected else [0, 0, 0]
    return {'rotation': rotations, 'translation': translations, 'scale': scales}


doc['animations'] = []
manifest = []
for clip, title, duration in catalog:
    fps = 30; times = np.arange(round(duration*fps)+1)/fps
    samples = [pose(clip, float(t), duration) for t in times]
    anim = {'name': clip, 'samplers': [], 'channels': [], 'extras': {'title': title, 'loop': clip == 'reposo'}}
    time_accessor = append(times[:, None], 'SCALAR', True)
    for path, kind in [('rotation', 'VEC4'), ('translation', 'VEC3'), ('scale', 'VEC3')]:
        for i in sorted({i for s in samples for i in s[path]}):
            values = [s[path][i] for s in samples]
            if path == 'rotation':
                for k in range(len(values)):
                    q = np.array(values[k]); q /= np.linalg.norm(q)
                    if k and np.dot(q, values[k-1]) < 0: q *= -1
                    values[k] = q.tolist()
            assert np.max(np.abs(np.asarray(values[0])-values[-1])) < .0001, (clip, i)
            ai = append(values, kind)
            si = len(anim['samplers'])
            anim['samplers'].append({'input': time_accessor, 'output': ai, 'interpolation': 'STEP' if path == 'scale' else 'LINEAR'})
            anim['channels'].append({'sampler': si, 'target': {'node': i, 'path': path}})
    doc['animations'].append(anim)
    manifest.append({'id': clip, 'title': title, 'duration': duration, 'channels': len(anim['channels'])})
doc['asset']['extras']['modifications'] = 'Relaxed bind pose with curved tail, rebuilt inverse bind matrices and baked mesh normals; head-attached expressions from the original atlas; procedural purple irises, dark pupils and highlights; nine articulated clips including hovering, blinking, waving, curiosity, tail movement, stretching, meeting alert, celebration, petting and meditation. Original attribution retained.'
doc['buffers'][0]['byteLength'] = len(binary)
encoded = json.dumps(doc, separators=(',', ':'), ensure_ascii=False).encode()
encoded += b' ' * (-len(encoded) % 4); binary.extend(b'\0' * (-len(binary) % 4))
result = struct.pack('<4sII', b'glTF', 2, 28+len(encoded)+len(binary))
result += struct.pack('<II', len(encoded), 0x4E4F534A)+encoded+struct.pack('<II', len(binary), 0x004E4942)+binary
(ROOT/'Assets/mewtwo-biblioteca.glb').write_bytes(result)
(ROOT/'Models/Mewtwo/catalogo.json').write_text(json.dumps({'source': doc['asset']['extras'], 'joints': len(skin['joints']), 'clips': manifest}, ensure_ascii=False, indent=2)+'\n')
print(f'Mewtwo: {len(skin["joints"])} joints, {len(manifest)} clips, {len(result)} bytes')
