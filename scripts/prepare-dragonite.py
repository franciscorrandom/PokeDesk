#!/usr/bin/env python3
"""Bake the chosen Dragonite standing pose into its indexed bind geometry.

Run by prepare-dragonite.cjs after decoding and animation preparation. NumPy
is an authoring dependency only. This makes an ordinary renderer's static
bounding box agree with the actual skinned standing silhouette.
"""
import json
import struct
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / 'Assets/dragonite-biblioteca.glb'
raw = TARGET.read_bytes()
length = struct.unpack_from('<I', raw, 12)[0]
doc = json.loads(raw[20:20 + length])
binary = bytearray(raw[28 + length:28 + length + doc['buffers'][0]['byteLength']])
nodes = doc['nodes']
parents = {child: i for i, node in enumerate(nodes) for child in node.get('children', [])}


def read(index):
    a = doc['accessors'][index]
    view = doc['bufferViews'][a['bufferView']]
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
    dtype = {5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1'}[a['componentType']]
    size = np.dtype(dtype).itemsize
    values = np.ndarray((a['count'], width), dtype=dtype, buffer=binary,
                        offset=view.get('byteOffset', 0) + a.get('byteOffset', 0),
                        strides=(view.get('byteStride', width * size), size)).copy()
    if a.get('normalized') and a['componentType'] != 5126:
        values = values.astype(float) / np.iinfo(np.dtype(dtype)).max
    return values


def append(values, kind, bounds=False):
    values = np.asarray(values, dtype='<f4')
    assert np.isfinite(values).all()
    binary.extend(b'\0' * (-len(binary) % 4))
    offset = len(binary)
    binary.extend(values.tobytes())
    vi = len(doc['bufferViews'])
    doc['bufferViews'].append({'buffer': 0, 'byteOffset': offset, 'byteLength': values.nbytes})
    accessor = {'bufferView': vi, 'componentType': 5126, 'count': len(values), 'type': kind}
    if bounds:
        accessor.update(min=values.min(axis=0).tolist(), max=values.max(axis=0).tolist())
    ai = len(doc['accessors'])
    doc['accessors'].append(accessor)
    return ai


def local(node):
    if 'matrix' in node:
        return np.asarray(node['matrix']).reshape(4, 4).T
    x, y, z, w = node.get('rotation', [0, 0, 0, 1])
    rotation = np.array([[1-2*y*y-2*z*z, 2*x*y-2*z*w, 2*x*z+2*y*w],
                         [2*x*y+2*z*w, 1-2*x*x-2*z*z, 2*y*z-2*x*w],
                         [2*x*z-2*y*w, 2*y*z+2*x*w, 1-2*x*x-2*y*y]])
    matrix = np.eye(4)
    matrix[:3, :3] = rotation @ np.diag(node.get('scale', [1, 1, 1]))
    matrix[:3, 3] = node.get('translation', [0, 0, 0])
    return matrix


cache = {}


def world(index):
    if index not in cache:
        cache[index] = (world(parents[index]) @ local(nodes[index])
                        if index in parents else local(nodes[index]))
    return cache[index]


bounds = []
for skin_index, skin in enumerate(doc['skins']):
    inverse_binds = read(skin['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
    meshes = [(i, node) for i, node in enumerate(nodes) if node.get('skin') == skin_index and 'mesh' in node]
    mesh_world = world(meshes[0][0])
    assert all(np.max(np.abs(world(i)-mesh_world)) < 1e-6 for i, _ in meshes)
    for node_index, node in meshes:
        transforms = [np.linalg.inv(world(node_index)) @ world(joint) @ inverse_binds[j]
                      for j, joint in enumerate(skin['joints'])]
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            attributes = primitive['attributes']
            positions, normals = read(attributes['POSITION']), read(attributes['NORMAL'])
            joints, weights = read(attributes['JOINTS_0']), read(attributes['WEIGHTS_0'])
            homogeneous = np.c_[positions, np.ones(len(positions))]
            baked_positions, baked_normals = np.zeros_like(positions), np.zeros_like(normals)
            for slot in range(4):
                for joint in np.unique(joints[:, slot]):
                    ids = np.where(joints[:, slot] == joint)[0]
                    weight = weights[ids, slot, None]
                    matrix = transforms[int(joint)]
                    baked_positions[ids] += weight * (homogeneous[ids] @ matrix.T)[:, :3]
                    baked_normals[ids] += weight * (normals[ids] @ np.linalg.inv(matrix[:3, :3]))
            baked_normals /= np.linalg.norm(baked_normals, axis=1)[:, None]
            attributes['POSITION'] = append(baked_positions, 'VEC3', True)
            attributes['NORMAL'] = append(baked_normals, 'VEC3')
            bounds.append((world(node_index) @ np.c_[baked_positions, np.ones(len(positions))].T).T[:, :3])
    skin['inverseBindMatrices'] = append([
        (np.linalg.inv(world(joint)) @ mesh_world).T.reshape(16) for joint in skin['joints']], 'MAT4')

points = np.concatenate(bounds)
metadata = {'min': points.min(axis=0).tolist(), 'max': points.max(axis=0).tolist(),
            'method': 'Standing vertices and normals baked with original weights; inverse binds rebuilt for the same standing joint transforms.'}
doc['asset']['extras']['pokedeskBindPose'] = metadata
doc['asset']['extras']['modifications'] += ' Standing pose baked into indexed geometry and inverse binds rebuilt so static bounds match the skinned silhouette.'
doc['buffers'][0]['byteLength'] = len(binary)
encoded = json.dumps(doc, separators=(',', ':'), ensure_ascii=False).encode()
encoded += b' ' * (-len(encoded) % 4)
binary.extend(b'\0' * (-len(binary) % 4))
result = (struct.pack('<4sII', b'glTF', 2, 28+len(encoded)+len(binary))
          + struct.pack('<II', len(encoded), 0x4E4F534A) + encoded
          + struct.pack('<II', len(binary), 0x004E4942) + binary)
TARGET.write_bytes(result)
catalog_path = ROOT / 'Models/Dragonite/catalogo.json'
catalog = json.loads(catalog_path.read_text())
catalog['source'] = doc['asset']['extras']
catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
print('Dragonite standing bind bounds:', metadata['min'], metadata['max'])
