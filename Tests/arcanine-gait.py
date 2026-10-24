"""Independently inspect footwork in a baked Arcanine study; no authoring imports."""
import copy
import json
import math
import struct
import sys
from pathlib import Path


class Model:
    def __init__(self, path):
        raw = Path(path).read_bytes()
        assert struct.unpack_from('<4sII',raw) == (b'glTF',2,len(raw))
        length = struct.unpack_from('<I',raw,12)[0]
        self.doc = json.loads(raw[20:20+length]); self.binary = raw[28+length:]
        self.nodes = copy.deepcopy(self.doc['nodes'])
        self.parents = {c:i for i,n in enumerate(self.nodes) for c in n.get('children',[])}
        self.names = {n.get('name'):i for i,n in enumerate(self.nodes)}
        self.cache = {}

    def read(self, index):
        a = self.doc['accessors'][index]; v = self.doc['bufferViews'][a['bufferView']]
        width = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
        code,size = {5126:('f',4),5125:('I',4),5123:('H',2),5121:('B',1)}[a['componentType']]
        offset = v.get('byteOffset',0)+a.get('byteOffset',0)
        result = [struct.unpack_from('<'+code*width,self.binary,offset+j*v.get('byteStride',width*size)) for j in range(a['count'])]
        assert all(math.isfinite(x) for row in result for x in row)
        return result

    @staticmethod
    def multiply(a,b):
        return [[sum(a[r][k]*b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]

    def world(self, index):
        if index in self.cache: return self.cache[index]
        n = self.nodes[index]
        if 'matrix' in n: m = [[n['matrix'][c*4+r] for c in range(4)] for r in range(4)]
        else:
            x,y,z,w = n.get('rotation',[0,0,0,1]); scale = n.get('scale',[1,1,1])
            rot = [[1-2*y*y-2*z*z,2*x*y-2*z*w,2*x*z+2*y*w],
                   [2*x*y+2*z*w,1-2*x*x-2*z*z,2*y*z-2*x*w],
                   [2*x*z-2*y*w,2*y*z+2*x*w,1-2*x*x-2*y*y]]
            m = [[rot[r][c]*scale[c] for c in range(3)]+[n.get('translation',[0,0,0])[r]] for r in range(3)]+[[0,0,0,1]]
        self.cache[index] = self.multiply(self.world(self.parents[index]),m) if index in self.parents else m
        return self.cache[index]

    def position(self,index): return [self.world(index)[r][3] for r in range(3)]

    def channels(self,clip):
        result = {}
        for c in clip['channels']:
            s = clip['samplers'][c['sampler']]
            result[c['target']['node'],c['target']['path']] = (self.read(s['input']),self.read(s['output']),s['interpolation'])
        return result

    def sample(self, channels, frame):
        self.nodes = copy.deepcopy(self.doc['nodes']); self.cache.clear()
        for (index,path),(_,values,_) in channels.items(): self.nodes[index][path] = values[frame]


def distance(a,b): return math.sqrt(sum((x-y)**2 for x,y in zip(a,b)))


model = Model(sys.argv[1])
doc = model.doc
assert len(doc['animations']) == 11 and len(doc['skins'][0]['joints']) == 85
clip = next(c for c in doc['animations'] if c['name']=='giro-rapido')
assert clip['extras']['motion'] in ['single-bound-study','four-bound-tail-chase']
hops = clip['extras']['hops']
assert hops in [1,4]
tracks = model.channels(clip)
times = next(iter(tracks.values()))[0]
fps = clip['extras']['authoringFPS']
assert len(times) == 4*fps+1 and times[0] == (0,) and times[-1] == (4,)
dt = 1/fps
max_joint_step = 0
for (index,path),(t,values,interpolation) in tracks.items():
    assert t == times and len(values) == len(times)
    assert interpolation == ('STEP' if path == 'scale' else 'LINEAR')
    closure = max(abs(a-b) for a,b in zip(values[0],values[-1]))
    if path == 'rotation':
        closure = min(closure,max(abs(a+b) for a,b in zip(values[0],values[-1])))
        assert all(abs(sum(x*x for x in q)-1) < 1e-5 for q in values)
        assert all(sum(a*b for a,b in zip(q,r)) >= 0 for q,r in zip(values,values[1:]))
        step = max(2*math.acos(min(1,max(0,abs(sum(a*b for a,b in zip(q,r)))))) for q,r in zip(values,values[1:]))
        max_joint_step = max(max_joint_step,step)
        assert step < .40, 'No abrupt knee flip or lock between consecutive keys'
    assert closure < 1e-5, 'Study must return to rest without a snap'
    assert path != 'scale' or index not in doc['skins'][0]['joints'], 'No bone scaling/shrinking'

legs = [('LArm_044','LForeArm_045','LHand_049'),('RArm_073','RForeArm_074','RHand_078'),
        ('LThigh_06','LLeg_07','LFoot_08'),('RThigh_017','RLeg_018','RFoot_019')]
names = model.names
rest = {n:model.position(names[n]) for leg in legs for n in leg}
origin = names['Origin_02']
if hops == 4:
    heading = [2*math.atan2(q[1],q[3]) for q in tracks[origin,'rotation'][1]]
    for i in range(1,len(heading)):
        while heading[i]-heading[i-1] < -math.pi: heading[i] += 2*math.pi
        while heading[i]-heading[i-1] > math.pi: heading[i] -= 2*math.pi
    assert abs(heading[-1]-heading[0]-2*math.pi) < 1e-5, 'Four hops must complete exactly one full turn'
    assert all(b >= a-1e-6 for a,b in zip(heading,heading[1:])), 'Heading must not reverse or snap'
body = doc['accessors'][doc['meshes'][0]['primitives'][0]['attributes']['POSITION']]
unit = math.sqrt(sum(model.world(origin)[r][0]**2 for r in range(3)))*(body['max'][1]-body['min'][1])
elevation = {leg[2]:[] for leg in legs}
max_bone_error = 0
for frame in range(len(times)):
    model.sample(tracks,frame)
    for upper,knee,paw in legs:
        points = {n:model.position(names[n]) for n in [upper,knee,paw]}
        for a,b in [(upper,knee),(knee,paw)]:
            error = abs(distance(points[a],points[b])-distance(rest[a],rest[b]))/unit
            max_bone_error = max(max_bone_error,error)
            assert error < 1e-5, 'Bone length must stay constant'
        height = (points[paw][1]-rest[paw][1])/unit
        assert height > -.003, 'Paws must not go below the floor'
        elevation[paw].append(height)
intervals = {}
for paw,values in elevation.items():
    airborne = [f for f,v in enumerate(values) if v > .004]
    assert airborne and max(values) > .04
    groups = [[airborne[0]]]
    for f in airborne[1:]:
        if f-groups[-1][-1] > 1: groups.append([])
        groups[-1].append(f)
    assert len(groups) == hops, 'Every paw must have a separate flight/contact interval for each hop'
    intervals[paw] = [(times[g[0]][0],times[g[-1]][0]) for g in groups]
for hop in range(hops):
    front = [intervals[leg[2]][hop] for leg in legs[:2]]
    hind = [intervals[leg[2]][hop] for leg in legs[2:]]
    assert max(t[0] for t in front)+.04 < min(t[0] for t in hind), 'Front paws must rise while the hind pair is still pushing'
    assert max(t[1] for t in front)+.04 < min(t[1] for t in hind), 'Front paws must land before the hind pair'
    assert abs(front[0][0]-front[1][0]) >= dt-1e-6, 'Front departures should be staggered'
    assert abs(front[0][1]-front[1][1]) >= dt-1e-6, 'Front landings should be staggered'
    assert abs(hind[0][0]-hind[1][0]) >= dt-1e-6, 'Hind departures should be staggered'
    assert abs(hind[0][1]-hind[1][1]) >= dt-1e-6, 'Hind landings should be staggered'
assert any(all(elevation[leg[2]][f] > .02 for leg in legs) for f in range(len(times))), 'There must be a genuine aerial phase'
assert any(all(abs(elevation[leg[2]][f]) < .002 for leg in legs[:2]) and all(elevation[leg[2]][f] > .018 for leg in legs[2:]) for f in range(len(times))), 'Hind paws must remain in flight after the forelegs catch the body'
print(f'{hops} salto(s) válido(s): delanteras antes del impulso trasero, suspensión, apoyos delanteros escalonados y aterrizaje trasero posterior.')
print('Intervalos de elevación:',{k:[[round(t,2) for t in interval] for interval in v] for k,v in intervals.items()})
print('Error máximo de longitud de huesos:',max_bone_error)
print(f'Mayor cambio articular entre claves de {round(dt*1000,2)} ms:',round(math.degrees(max_joint_step),2),'grados')

if len(sys.argv) > 2:
    original = Model(sys.argv[2])
    assert doc['nodes'] == original.doc['nodes']
    assert doc['materials'] == original.doc['materials']
    assert doc['asset']['extras']['author'] == original.doc['asset']['extras']['author']
    for a,b in zip(doc['meshes'],original.doc['meshes']):
        for p,q in zip(a['primitives'],b['primitives']):
            for key in p['attributes']: assert model.read(p['attributes'][key]) == original.read(q['attributes'][key])
            assert model.read(p['indices']) == original.read(q['indices'])
    assert model.read(doc['skins'][0]['inverseBindMatrices']) == original.read(original.doc['skins'][0]['inverseBindMatrices'])
    for a,b in zip(doc['images'],original.doc['images']):
        def imagebytes(m,image):
            v = m.doc['bufferViews'][image['bufferView']]; start = v.get('byteOffset',0)
            return m.binary[start:start+v['byteLength']]
        assert imagebytes(model,a) == imagebytes(original,b)
    for a,b in zip(doc['animations'],original.doc['animations']):
        if a['name'] == 'giro-rapido': continue
        assert a['name'] == b['name'] and model.channels(a) == original.channels(b)
    print('Mallas, texturas, rig, atribución y las otras diez animaciones conservadas exactamente.')
