#!/usr/bin/env python3
"""Reproducible Pikachu/Charizard rig preparation and nine glTF animation clips.

Requires numpy. Uses the downloaded author's geometry and expression atlas;
no external service, textures or animation dependencies are used at runtime.
"""
import sys
import copy
import json
import math
import struct
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
character = sys.argv[1]
assert character in ["pikachu", "charizard"]
source = ROOT / f"Models/{character.title()}/{character}-original.glb"
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
pika = character == 'pikachu'
head = 35 if pika else 73
origin = 10 if pika else 11
spine = 34 if pika else 56
tail = [29,30,31] if pika else list(range(28,35))
arms = [(46,47,48,1),(51,52,53,-1)] if pika else [(58,59,60,1),(80,81,82,-1)]
legs = [(17,18,19),(23,24,25)] if pika else [(16,17,18),(22,23,24)]
wings = [] if pika else [(42,43,44,1),(49,50,51,-1)]
ears = [(37,38,1),(41,42,-1)] if pika else []
unit = 1 if pika else 3


def world_rotation(i, axis, angle, world, q=None):
    basis = world[i][:3,:3]; basis = basis/np.linalg.norm(basis,axis=0)
    ax = basis.T@np.asarray(axis); ax /= np.linalg.norm(ax)
    result = quat_mul(q if q is not None else nodes[i].get('rotation',[0,0,0,1]),np.r_[ax*math.sin(angle/2),math.cos(angle/2)])
    return (result/np.linalg.norm(result)).tolist()

# Relax Pikachu's arms and compact Charizard's long tail, retaining rig weights.
if pika:
    for shoulder, hand, sign in [(45,48,1),(50,53,-1)]:
        # Lower the entire forward-pointing chain at the shoulder, rather than
        # rolling an extended arm. Hands settle beside the belly, slightly bent.
        world = worlds()
        direction = world[hand][:3,3] - world[shoulder][:3,3]
        direction /= np.linalg.norm(direction)
        target = np.array([sign*.50, -.84, .20]); target /= np.linalg.norm(target)
        axis = np.cross(direction, target); axis /= np.linalg.norm(axis)
        nodes[shoulder]['rotation'] = world_rotation(shoulder, axis, math.acos(np.dot(direction,target)), world)
if not pika:
    for i,a in zip(tail,[.13,.22,.28,.30,.29,.24,.16]):
        nodes[i]['rotation'] = world_rotation(i,[0,1,0],a,worlds())
new_world = worlds()
baked = {}
for mi,m in enumerate(doc['meshes']):
    ni = next(i for i,n in enumerate(nodes) if n.get('mesh')==mi)
    prim=m['primitives'][0];attrs=prim['attributes'];pos=read(attrs['POSITION']);normal=read(attrs['NORMAL'])
    joints=read(attrs['JOINTS_0']);weights=read(attrs['WEIGHTS_0'])
    transforms=[np.linalg.inv(new_world[ni])@new_world[j]@old_bind[k] for k,j in enumerate(skin['joints'])]
    extended=np.c_[pos,np.ones(len(pos))];p=np.zeros_like(pos);n=np.zeros_like(normal)
    for slot in range(4):
        for j in np.unique(joints[:,slot]):
            ids=np.where(joints[:,slot]==j)[0];w=weights[ids,slot,None];m=transforms[int(j)]
            p[ids]+=w*(extended[ids]@m.T)[:,:3]
            n[ids]+=w*(normal[ids]@np.linalg.inv(m[:3,:3]))
    n/=np.linalg.norm(n,axis=1)[:,None]
    baked[mi]=(ni,p,n,copy.deepcopy(prim));attrs['POSITION']=append(p,'VEC3',True);attrs['NORMAL']=append(n,'VEC3')
mesh_world=new_world[6]
skin['inverseBindMatrices']=append([(np.linalg.inv(new_world[j])@mesh_world).T.reshape(16) for j in skin['joints']],'MAT4')

# Use the author's expression atlas; the eyes follow the head without scaling the skull.
mi=3 if pika else 0
ni,p,n,primitive=baked[mi]
to_head=np.linalg.inv(new_world[head])@new_world[ni]
positions=(to_head@np.c_[p,np.ones(len(p))].T).T[:,:3]
normals=(np.linalg.inv(to_head[:3,:3]).T@n.T).T;normals/=np.linalg.norm(normals,axis=1)[:,None]
pa=append(positions,'VEC3',True);na=append(normals,'VEC3');uv=read(primitive['attributes']['TEXCOORD_0'])
for label,dv,visible in [('Open',0,True),('Half',-.25,False),('Closed',-.5,False)]:
    name=character.title()+'Eyes'+label;mesh=len(doc['meshes'])
    doc['meshes'].append({'name':name,'primitives':[{**primitive,'attributes':{'POSITION':pa,'NORMAL':na,'TEXCOORD_0':append(uv+[0,dv],'VEC2')}}]})
    nodes.append({'name':name,'mesh':mesh,'scale':[1,1,1] if visible else [0,0,0]});names[name]=len(nodes)-1
    nodes[head].setdefault('children',[]).append(len(nodes)-1)
nodes[ni].pop('mesh');nodes[ni].pop('skin')
# Fire is an emissive, transparent part of Charizard's original mesh, not a new service.
if not pika:
    for i in [3,4]:
        mat=doc['materials'][i];mat['name']='CharizardFlame'+str(i);mat['alphaMode']='BLEND';mat['emissiveFactor']=[1,.30,.015] if i==3 else [1,.65,.06]
        mat['pbrMetallicRoughness']['baseColorFactor']=[1,.30,.015,1] if i==3 else [1,.65,.06,1]
        mat['emissiveTexture']=mat['pbrMetallicRoughness']['baseColorTexture'].copy()
rest=copy.deepcopy(nodes);rest_world=worlds()
catalog=[('reposo',8),('curiosidad',4),('saludo',4),('cola-alegre',4.8),('estiramiento',5),('aviso-reunion',4),('celebracion',3.6),('caricias',5.6),('sentarse',7.2)]

def smooth(x):
    x=min(1,max(0,x));return x*x*x*(x*(x*6-15)+10)

def pose(clip,t,duration):
    rotations={};translations={};scales={}
    e=smooth(t/.8)*smooth((duration-t)/.8)
    def turn(i,axis,a):
        rotations[i]=world_rotation(i,axis,a,rest_world,rotations.get(i,rest[i].get('rotation',[0,0,0,1])))
    def move(i,delta):
        translations[i]=(np.array(rest[i].get('translation',[0,0,0]))+np.asarray(delta)*unit).tolist()
    turn(spine,[1,0,0],e*.016*math.sin(t*math.pi/2))
    turn(head,[1,0,0],e*.013*math.sin(t*math.pi/2+.5))
    for k,i in enumerate(tail):
        turn(i,[0,1,0],e*(.065 if pika else .022)*math.sin(t*2.1-k*.4))
    for i,tip,sign in ears:
        turn(i,[0,0,1],sign*e*.045*math.sin(t*2.3+sign*.5));turn(tip,[1,0,0],e*.035*math.sin(t*2.3-.6))
    for wing,mid,tip,sign in wings:
        turn(wing,[0,1,0],sign*e*.018*math.sin(t*1.6));turn(mid,[0,0,1],sign*e*.015*math.sin(t*1.6-.3))
    if not pika:
        for k,i in enumerate([36,37,38,39]):
            turn(i,[0,0,1],e*.035*math.sin(t*7-k*.6))
    blink=abs(t-(3 if clip=='reposo' else duration*.64))
    state='Closed' if blink<.067 else 'Half' if blink<.135 else 'Open'
    if clip=='curiosidad':
        turn(head,[0,0,1],e*.23*math.sin(t*1.3));turn(head,[0,1,0],e*.18)
        for i,tip,sign in ears: turn(i,[0,0,1],sign*e*.15)
    elif clip=='saludo':
        arm,elbow,hand,sign=arms[1]
        turn(arm,[0,0,1],-e*(1.55 if pika else .85));turn(elbow,[1,0,0],-e*.32)
        turn(hand,[0,0,1],e*.22*math.sin(t*7))
        turn(head,[0,0,1],-e*.08)
        for i,tip,sign in ears:turn(tip,[0,0,1],sign*e*.1*math.sin(t*5))
    elif clip=='cola-alegre':
        for k,i in enumerate(tail): turn(i,[0,1,0],e*(.18 if pika else .065)*math.sin(t*4-k*.4))
        for wing,mid,tip,sign in wings:turn(wing,[0,1,0],sign*e*.10*math.sin(t*2))
    elif clip=='estiramiento':
        turn(spine,[1,0,0],-e*.10);turn(head,[1,0,0],-e*.12)
        for arm,elbow,hand,sign in arms:
            turn(arm,[0,0,1],sign*e*(1.30 if pika else .80));turn(elbow,[1,0,0],-e*.18)
        for wing,mid,tip,sign in wings:
            turn(wing,[0,1,0],sign*e*.16);turn(mid,[0,0,1],sign*e*.10)
    elif clip=='aviso-reunion':
        turn(head,[0,1,0],e*.22);turn(head,[1,0,0],-e*.08)
        arm,elbow,hand,sign=arms[1];turn(arm,[0,0,1],-e*.55);turn(hand,[0,1,0],e*.20)
        for i,tip,sign in ears: turn(i,[0,0,1],sign*e*.12)
    elif clip=='celebracion':
        move(origin,[0,e*(1.7+1.3*math.sin(t*5)),0])
        for arm,elbow,hand,sign in arms: turn(arm,[0,0,1],sign*e*(1.65 if pika else 1.1))
        for wing,mid,tip,sign in wings:turn(wing,[0,1,0],sign*e*.15*math.sin(t*5))
        turn(head,[0,0,1],e*.10*math.sin(t*5))
    elif clip=='caricias':
        turn(head,[0,0,1],e*.17*math.sin(t*2));turn(head,[1,0,0],e*.10)
        for i,tip,sign in ears:turn(i,[0,0,1],sign*e*.20);turn(tip,[1,0,0],e*.12)
        for k,i in enumerate(tail): turn(i,[0,1,0],e*.05*math.sin(t*3-k*.35))
        if .8<t<duration-1:state='Closed'
    elif clip=='sentarse':
        move(origin,[0,-e*(4 if pika else 3),0])
        for thigh,leg,foot in legs:
            turn(thigh,[1,0,0],-e*.34);turn(leg,[1,0,0],e*.50);turn(foot,[1,0,0],-e*.16)
        turn(spine,[1,0,0],e*.055);turn(head,[1,0,0],e*.10)
        for wing,mid,tip,sign in wings:turn(wing,[0,1,0],-sign*e*.07)
        if 1<t<duration-1:state='Closed'
    for label in ['Open','Half','Closed']:
        scales[names[character.title()+'Eyes'+label]]=[1,1,1] if state==label else [0,0,0]
    return {'rotation':rotations,'translation':translations,'scale':scales}

doc['animations']=[];manifest=[]
for clip,duration in catalog:
    times=np.arange(round(duration*30)+1)/30;samples=[pose(clip,float(t),duration) for t in times]
    anim={'name':clip,'samplers':[],'channels':[],'extras':{'loop':clip=='reposo'}};ta=append(times[:,None],'SCALAR',True)
    for path,kind in [('rotation','VEC4'),('translation','VEC3'),('scale','VEC3')]:
        for i in sorted({i for s in samples for i in s[path]}):
            values=[s[path][i] for s in samples]
            if path=='rotation':
                for k in range(len(values)):
                    q=np.asarray(values[k]);q/=np.linalg.norm(q)
                    if k and np.dot(q,values[k-1])<0:q*=-1
                    values[k]=q.tolist()
            assert np.max(np.abs(np.asarray(values[0])-values[-1]))<.0001,(clip,i)
            si=len(anim['samplers']);anim['samplers'].append({'input':ta,'output':append(values,kind),'interpolation':'STEP' if path=='scale' else 'LINEAR'})
            anim['channels'].append({'sampler':si,'target':{'node':i,'path':path}})
    doc['animations'].append(anim);manifest.append({'id':clip,'duration':duration,'channels':len(anim['channels'])})
extras=doc['asset'].setdefault('extras',{})
extras.update(author='jacobjksn42' if pika else 'nguyenlouis32',license='CC-BY-4.0',source='https://sketchfab.com/3d-models/'+('pikachu-c22dab8fc3064c76a0c502d64555a74f' if pika else 'charizard-29bae357dcb74bad8f432704e2d9f531'),modifications='Original rig and textures retained; head-attached expression atlas and nine articulated clips; '+('Pikachu shoulders lowered into a relaxed rebuilt bind pose.' if pika else 'Charizard tail curved in rebuilt bind pose.')+' Generated for PokéDesk.')
doc['buffers'][0]['byteLength']=len(binary)
encoded=json.dumps(doc,separators=(',',':'),ensure_ascii=False).encode();encoded+=b' '*(-len(encoded)%4);binary.extend(b'\0'*(-len(binary)%4))
result=struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4E4F534A)+encoded+struct.pack('<II',len(binary),0x004E4942)+binary
(ROOT/f'Assets/{character}-biblioteca.glb').write_bytes(result)
(ROOT/f'Models/{character.title()}/catalogo.json').write_text(json.dumps({'source':extras,'joints':len(skin['joints']),'clips':manifest},ensure_ascii=False,indent=2)+'\n')
print(f'{character.title()}: {len(skin["joints"])} joints, {len(manifest)} clips, {len(result)} bytes')
