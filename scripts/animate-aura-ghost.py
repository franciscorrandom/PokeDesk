#!/usr/bin/env python3
"""Prepare Lucario/Gengar rigs and nine clips, baked into portable GLBs.

NumPy is needed for authoring only. Original geometry/weights/texture atlases
and attribution are retained. No inverse kinematics or services run in the app.
"""
import argparse
import copy
import json
import math
import struct
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('character', choices=['lucario','gengar'])
character = parser.parse_args().character
lucario = character == 'lucario'
source = ROOT/f'Models/{character.title()}/{character}-original.glb'
raw = source.read_bytes(); length = struct.unpack_from('<I',raw,12)[0]
doc = json.loads(raw[20:20+length])
binary = bytearray(raw[28+length:28+length+doc['buffers'][0]['byteLength']])
nodes = doc['nodes']; names = {n.get('name'):i for i,n in enumerate(nodes)}
parents = {c:i for i,n in enumerate(nodes) for c in n.get('children',[])}


def qmul(a,b):
    x,y,z,w=a;X,Y,Z,W=b
    return np.array([w*X+x*W+y*Z-z*Y,w*Y-x*Z+y*W+z*X,w*Z+x*Y-y*X+z*W,w*W-x*X-y*Y-z*Z])


def rotation(q):
    x,y,z,w=q
    return np.array([[1-2*y*y-2*z*z,2*x*y-2*z*w,2*x*z+2*y*w],
                     [2*x*y+2*z*w,1-2*x*x-2*z*z,2*y*z-2*x*w],
                     [2*x*z-2*y*w,2*y*z+2*x*w,1-2*x*x-2*y*y]])


def local(n):
    if 'matrix' in n: return np.array(n['matrix']).reshape(4,4).T
    m=np.eye(4);m[:3,:3]=rotation(n.get('rotation',[0,0,0,1]))@np.diag(n.get('scale',[1,1,1]))
    m[:3,3]=n.get('translation',[0,0,0]);return m


def worlds():
    cache={}
    def at(i):
        if i not in cache: cache[i]=at(parents[i])@local(nodes[i]) if i in parents else local(nodes[i])
        return cache[i]
    return {i:at(i) for i in range(len(nodes))}


def read(i):
    a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']]
    width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
    dtype={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']];size=np.dtype(dtype).itemsize
    return np.ndarray((a['count'],width),dtype=dtype,buffer=binary,
                      offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',width*size),size)).copy()


def append(values,kind,bounds=False):
    a=np.asarray(values,dtype='<f4');assert np.isfinite(a).all()
    binary.extend(b'\0'*(-len(binary)%4));offset=len(binary);binary.extend(a.tobytes())
    vi=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':a.nbytes})
    accessor={'bufferView':vi,'componentType':5126,'count':len(a),'type':kind}
    if bounds: accessor.update(min=a.min(axis=0).tolist(),max=a.max(axis=0).tolist())
    ai=len(doc['accessors']);doc['accessors'].append(accessor);return ai


def world_rotation(i,axis,angle,world,q=None):
    basis=world[i][:3,:3]
    if np.min(np.linalg.norm(basis,axis=0))<1e-8:
        # Hidden expression meshes have zero scale; use their unscaled frame.
        basis=world[parents[i]][:3,:3]@rotation(nodes[i].get('rotation',[0,0,0,1]))
    basis=basis/np.linalg.norm(basis,axis=0)
    ax=basis.T@np.asarray(axis);ax/=np.linalg.norm(ax)
    result=qmul(q if q is not None else nodes[i].get('rotation',[0,0,0,1]),np.r_[ax*math.sin(angle/2),math.cos(angle/2)])
    return (result/np.linalg.norm(result)).tolist()


def aim_child(joint,child,direction):
    w=worlds();i,j=names[joint],names[child]
    actual=w[j][:3,3]-w[i][:3,3];actual/=np.linalg.norm(actual)
    target=np.asarray(direction,dtype=float);target/=np.linalg.norm(target)
    axis=np.cross(actual,target);axis/=np.linalg.norm(axis)
    nodes[i]['rotation']=world_rotation(i,axis,math.acos(np.clip(np.dot(actual,target),-1,1)),w)


skin=doc['skins'][0];old_world=worlds()
old_bind=read(skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
if lucario:
    head=names['Head_047'];neck=names['Neck_046'];spine=names['Spine1_032'];origin=names['Origin_02']
    arms=[(names[a],names[b],names[c],sign) for a,b,c,sign in [('LArm_041','LForeArm_042','LHand_043',1),('RArm_079','RForeArm_080','RHand_081',-1)]]
    legs=[(names[a],names[b],names[c]) for a,b,c in [('LThigh_07','LLeg_08','LFoot_09'),('RThigh_015','RLeg_016','RFoot_017')]]
    ears=[(names['LEar1_051'],names['LEar2_052'],1),(names['REar1_031'],names['REar2_064'],-1)]
    tail=[names[f'Tail{k}_{22+k:03}'] for k in range(1,8)]
    feelers=[[names[f'{side}Feeler{label}{k}_{start+k-1:03}'] for k in range(1,5)] for side,label,start in [('L','A',54),('L','B',59),('R','A',66),('R','B',71)]]
    # Keep the shoulders' original chest attachment. Lower only the arms and
    # softly bend the elbows so hands sit slightly forward of the thighs.
    for arm,elbow,hand,finger,sign in [('LArm_041','LForeArm_042','LHand_043','LFinger_044',1),('RArm_079','RForeArm_080','RHand_081','RFinger_082',-1)]:
        aim_child(arm,elbow,[sign*.20,-.96,.18])
        aim_child(elbow,hand,[-sign*.09,-.94,.33])
        aim_child(hand,finger,[-sign*.05,-.94,.33])
    for i,angle in zip(tail,[.05,.07,.10,.12,.10,.07,.04]):
        nodes[i]['rotation']=world_rotation(i,[0,1,0],angle,worlds())
    # The source T-pose holds all four head appendages horizontally. Official
    # Lucario artwork shows a relaxed downward/backward fall. Preserve their
    # scalp attachments and segment lengths, adding a gentle gravity curve.
    for chain in feelers:
        label=nodes[chain[0]]['name'];sign=1 if label.startswith('L') else -1
        directions=([( .28,-.64,-.72),(.25,-.78,-.56),(.18,-.88,-.44),(.10,-.94,-.32)]
                    if 'FeelerA' in label else
                    [(.12,-.60,-.79),(.10,-.77,-.63),(.07,-.89,-.45),(.04,-.96,-.27)])
        for i,(x,y,z) in zip(chain,directions):
            child=nodes[i]['children'][0]
            aim_child(nodes[i]['name'],nodes[child]['name'],[sign*x,y,z])
    eye_mesh=2;eye_offsets={'Open':0,'Half':-.50,'Closed':-.75}
else:
    head=names['Head_020'];neck=head;spine=names['Spine_019'];origin=names['Origin_02']
    arms=[(names[a],names[b],names[c],sign) for a,b,c,sign in [('LArm_033','LForeArm_034','LHand_035',1),('RArm_046','RForeArm_047','RHand_048',-1)]]
    legs=[(names[a],names[b],names[c]) for a,b,c in [('LThigh_05','LLeg_06','LFoot_07'),('RThigh_011','RLeg_012','RFoot_013')]]
    ears=[(names['LEar_029'],None,1),(names['REar_043'],None,-1)]
    tail=[names['Tail_017']];feelers=[]
    for arm,elbow,hand,finger,sign in [('LArm_033','LForeArm_034','LHand_035','LFingerA_037',1),('RArm_046','RForeArm_047','RHand_048','RFingerA_050',-1)]:
        aim_child(arm,elbow,[sign*.65,-.50,.57])
        aim_child(elbow,hand,[sign*.15,-.68,.72])
        aim_child(hand,finger,[sign*.10,-.63,.77])
    eye_mesh=1;eye_offsets={'Open':0,'Half':-.25,'Closed':-.50}

# Skin the original vertices into the relaxed pose and rebuild inverse binds.
# This keeps deformations correct on both SceneKit and Three.js.
new_world=worlds();baked={};mesh_nodes={n['mesh']:i for i,n in enumerate(nodes) if 'mesh' in n}
for mi,mesh in enumerate(doc['meshes']):
    ni=mesh_nodes[mi];pr=mesh['primitives'][0];attrs=pr['attributes']
    p=read(attrs['POSITION']);normal=read(attrs['NORMAL']);joints=read(attrs['JOINTS_0']);weights=read(attrs['WEIGHTS_0'])
    transforms=[np.linalg.inv(new_world[ni])@new_world[j]@old_bind[k] for k,j in enumerate(skin['joints'])]
    extended=np.c_[p,np.ones(len(p))];positions=np.zeros_like(p);normals=np.zeros_like(normal)
    for slot in range(4):
        for joint in np.unique(joints[:,slot]):
            ids=np.where(joints[:,slot]==joint)[0];weight=weights[ids,slot,None];m=transforms[int(joint)]
            positions[ids]+=weight*(extended[ids]@m.T)[:,:3]
            normals[ids]+=weight*(normal[ids]@np.linalg.inv(m[:3,:3]))
    normals/=np.linalg.norm(normals,axis=1)[:,None]
    baked[mi]=(ni,positions,normals,copy.deepcopy(pr))
    attrs['POSITION']=append(positions,'VEC3',True);attrs['NORMAL']=append(normals,'VEC3')
mesh_world=new_world[mesh_nodes[0]]
assert all(np.allclose(new_world[i],mesh_world) for i in mesh_nodes.values())
skin['inverseBindMatrices']=append([(np.linalg.inv(new_world[j])@mesh_world).T.reshape(16) for j in skin['joints']],'MAT4')


def attach_mesh(label,mi,parent,visible=False,positions=None):
    ni,p,n,pr=baked[mi]
    if positions is not None: p=positions
    transform=np.linalg.inv(new_world[parent])@new_world[ni]
    p=(transform@np.c_[p,np.ones(len(p))].T).T[:,:3]
    n=n@np.linalg.inv(transform[:3,:3]);n/=np.linalg.norm(n,axis=1)[:,None]
    attrs={'POSITION':append(p,'VEC3',True),'NORMAL':append(n,'VEC3'),'TEXCOORD_0':pr['attributes']['TEXCOORD_0']}
    mesh=len(doc['meshes']);doc['meshes'].append({'name':label,'primitives':[{**pr,'attributes':attrs}]})
    nodes.append({'name':label,'mesh':mesh,'scale':[1,1,1] if visible else [0,0,0]})
    i=len(nodes)-1;nodes[parent].setdefault('children',[]).append(i);names[label]=i
    parents[i]=parent
    return i


for label,dv in eye_offsets.items():
    i=attach_mesh(character.title()+'Eyes'+label,eye_mesh,head,label=='Open')
    attrs=doc['meshes'][nodes[i]['mesh']]['primitives'][0]['attributes']
    attrs['TEXCOORD_0']=append(read(attrs['TEXCOORD_0'])+[0,dv],'VEC2')
nodes[mesh_nodes[eye_mesh]].pop('mesh');nodes[mesh_nodes[eye_mesh]].pop('skin')
tongue=None;mask=None;tongue_delta=None
if not lucario:
    # FBX variants are all visible in the original GLB. The grin is the rest
    # face; tongues and mouth mask appear only during the playful gesture.
    for mi in [2,3,4]:
        nodes[mesh_nodes[mi]].pop('mesh');nodes[mesh_nodes[mi]].pop('skin')
    ni,p,n,pr=baked[3];p=p.copy()
    # Compact the supplied tongue to a short, mouth-level tease instead of
    # the duplicate sheet hanging below the chin in the original preview.
    p[:,0]*=.66;p[:,1]=(p[:,1]-p[:,1].min())*.48+61
    p[:,2]=(p[:,2]-p[:,2].min())*.26+53
    tongue=attach_mesh('GengarTongue',3,head,positions=p)
    _,mouth,_,_=baked[4];mouth=mouth.copy()
    mouth[:,0]*=1.04;mouth[:,1]=(mouth[:,1]-70)*1.30+70;mouth[:,2]+=3
    mask=attach_mesh('GengarMouthMask',4,head,positions=mouth)
    mouth_material=len(doc['materials'])
    doc['materials'].append({'name':'GengarOpenMouth','doubleSided':True,
                            'pbrMetallicRoughness':{'baseColorFactor':[.14,.045,.18,1],'metallicFactor':0,'roughnessFactor':1}})
    doc['meshes'][nodes[mask]['mesh']]['primitives'][0]['material']=mouth_material
    tongue_delta=np.linalg.solve(new_world[head][:3,:3],new_world[mesh_nodes[3]][:3,:3]@np.array([0,0,28.0]))
    nodes[tongue]['translation']=(-tongue_delta).tolist()

rest=copy.deepcopy(nodes);rest_world=worlds()
height=max(read(pr['attributes']['POSITION'])[:,1].max() for mi,m in enumerate(doc['meshes'][:len(mesh_nodes)]) for pr in m['primitives'])
catalog=[('reposo',8),('curiosidad',4),('saludo',4),('cola-alegre',4.8),('estiramiento',5),('aviso-reunion',4),('celebracion',3.6),('caricias',5.6),('sentarse',7.2)]


def smooth(x):
    x=min(1,max(0,x));return x*x*x*(x*(x*6-15)+10)


def pose(clip,t,duration):
    rotations={};translations={};scales={}
    e=smooth(t/.8)*smooth((duration-t)/.8)
    def turn(i,axis,angle):
        rotations[i]=world_rotation(i,axis,angle,rest_world,rotations.get(i,rest[i].get('rotation',[0,0,0,1])))
    def move(i,offset):
        translations[i]=(np.asarray(rest[i].get('translation',[0,0,0]))+np.asarray(offset)).tolist()
    # Small joint motion continues independently of occasional manual gestures.
    turn(spine,[1,0,0],e*.014*math.sin(t*math.pi/2))
    turn(head,[1,0,0],e*.011*math.sin(t*math.pi/2+.5))
    for k,i in enumerate(tail): turn(i,[0,1,0],e*(.027 if lucario else .07)*math.sin(t*2.1-k*.42))
    for i,tip,sign in ears:
        turn(i,[0,0,1],sign*e*.035*math.sin(t*2.2+sign*.4))
        if tip is not None: turn(tip,[1,0,0],e*.035*math.sin(t*2.2-.5))
    for chain in feelers:
        # More movement at the tips, with a small lag along the hanging chain.
        for k,i in enumerate(chain): turn(i,[1,0,0],e*(.006+k*.0025)*math.sin(t*2.2-k*.5))
    for arm,elbow,hand,sign in arms:
        turn(arm,[0,0,1],sign*e*(.012 if lucario else .045)*math.sin(t*1.8+.4))
    if not lucario:
        move(origin,[0,height*e*(.035+.012*math.sin(t*math.pi/2)),0])
        turn(origin,[0,0,1],e*.020*math.sin(t*1.7))
    blink=abs(t-(3 if clip=='reposo' else duration*.64))
    state='Closed' if blink<.067 else 'Half' if blink<.135 else 'Open'
    if clip=='curiosidad':
        turn(head,[0,1,0],e*.22*math.sin(t*1.5));turn(head,[0,0,1],e*.17)
        for i,tip,sign in ears: turn(i,[0,0,1],sign*e*.10)
    elif clip=='saludo':
        arm,elbow,hand,sign=arms[1]
        turn(arm,[0,0,1],-e*(1.90 if lucario else 1.15))
        turn(elbow,[1,0,0],-e*.34);turn(hand,[0,0,1],e*.19*math.sin(t*7))
        turn(head,[0,0,1],-e*.06)
        if not lucario:
            for name in ['RFingerA_050','RFingerB_052','RFingerC_054']: turn(names[name],[0,0,1],e*.11*math.sin(t*7))
    elif clip=='cola-alegre':
        if lucario:
            for k,i in enumerate(tail): turn(i,[0,1,0],e*.08*math.sin(t*4-k*.45))
            for chain in feelers:
                for k,i in enumerate(chain): turn(i,[1,0,0],e*.035*math.sin(t*3-k*.5))
        else:
            tease=smooth((t-.85)/.55)*(1-smooth((t-3.25)/.60))
            scales[tongue]=[1,1,1] if tease>.005 else [0,0,0]
            scales[mask]=[1,1,1] if tease>.12 else [0,0,0]
            move(tongue,tongue_delta*tease)
            turn(tongue,[0,0,1],.07*tease*math.sin(t*6))
            turn(names['Jaw_027'],[1,0,0],.06*tease)
            turn(spine,[1,0,0],e*.025*math.sin(t*8))
            for arm,elbow,hand,sign in arms: turn(arm,[0,0,1],sign*e*.08*math.sin(t*8))
    elif clip=='estiramiento':
        turn(spine,[1,0,0],-e*.07);turn(head,[1,0,0],-e*.10)
        for arm,elbow,hand,sign in arms:
            turn(arm,[0,0,1],sign*e*(1.1 if lucario else .6));turn(elbow,[1,0,0],-e*.20)
    elif clip=='aviso-reunion':
        turn(head,[0,1,0],e*.20);turn(head,[1,0,0],-e*.08)
        arm,elbow,hand,sign=arms[1]
        turn(arm,[1,0,0],-e*.55);turn(elbow,[1,0,0],-e*.25);turn(hand,[0,1,0],e*.18)
        for i,tip,sign in ears: turn(i,[0,0,1],sign*e*.12)
    elif clip=='celebracion':
        if lucario:
            # A brief triumphant stance keeps the feet planted.
            for arm,elbow,hand,sign in arms:
                turn(arm,[0,0,1],sign*e*1.35);turn(elbow,[1,0,0],-e*.40)
            turn(head,[0,0,1],e*.07*math.sin(t*5))
        else:
            move(origin,[0,height*e*(.07+.025*math.sin(t*5)),0])
            for arm,elbow,hand,sign in arms: turn(arm,[0,0,1],sign*e*.75)
            turn(head,[0,0,1],e*.08*math.sin(t*5))
    elif clip=='caricias':
        turn(head,[0,0,1],e*.17*math.sin(t*2));turn(head,[1,0,0],e*.09)
        for i,tip,sign in ears: turn(i,[0,0,1],sign*e*.11)
        if .8<t<duration-1: state='Closed'
    elif clip=='sentarse':
        if lucario:
            # Standing focus pose, hands gently brought forward; no fake sit.
            for arm,elbow,hand,sign in arms:
                turn(arm,[1,0,0],-e*.32);turn(elbow,[1,0,0],-e*.80)
                turn(hand,[0,1,0],-sign*e*.14)
            turn(head,[1,0,0],e*.08)
        else:
            move(origin,[0,height*e*.075,0])
            for thigh,knee,foot in legs:
                turn(thigh,[1,0,0],-e*.18);turn(knee,[1,0,0],e*.25)
            for arm,elbow,hand,sign in arms: turn(arm,[0,0,1],-sign*e*.10)
        if 1<t<duration-1: state='Closed'
    for label in ['Open','Half','Closed']: scales[names[character.title()+'Eyes'+label]]=[1,1,1] if state==label else [0,0,0]
    if tongue is not None:
        scales.setdefault(tongue,[0,0,0]);scales.setdefault(mask,[0,0,0])
    return {'rotation':rotations,'translation':translations,'scale':scales}


doc['animations']=[];manifest=[]
for clip,duration in catalog:
    times=np.arange(round(duration*30)+1)/30;samples=[pose(clip,float(t),duration) for t in times]
    animation={'name':clip,'samplers':[],'channels':[],'extras':{'loop':clip=='reposo'}}
    ta=append(times[:,None],'SCALAR',True)
    for path,kind in [('rotation','VEC4'),('translation','VEC3'),('scale','VEC3')]:
        for i in sorted({i for sample in samples for i in sample[path]}):
            values=[sample[path][i] for sample in samples]
            if path=='rotation':
                for k in range(len(values)):
                    q=np.asarray(values[k]);q/=np.linalg.norm(q)
                    if k and np.dot(q,values[k-1])<0: q*=-1
                    values[k]=q.tolist()
            assert np.max(np.abs(np.asarray(values[0])-values[-1]))<.0001,(clip,i)
            si=len(animation['samplers']);animation['samplers'].append({'input':ta,'output':append(values,kind),'interpolation':'STEP' if path=='scale' else 'LINEAR'})
            animation['channels'].append({'sampler':si,'target':{'node':i,'path':path}})
    doc['animations'].append(animation);manifest.append({'id':clip,'duration':duration,'channels':len(animation['channels'])})
extras=doc['asset'].setdefault('extras',{})
extras['modifications']=('Relaxed arms with chest attachments preserved, original rig and weights, rebuilt inverse binds and normals; head-attached blink expressions from original atlas; nine articulated PokéDesk clips. '+
                        ('Curved tail, ears and four relaxed downward/backward aura appendages with gentle delayed sway; standing focus pose.' if lucario else 'Hovering, staggered hand gestures, hidden duplicate tongue/mask meshes; short controlled tongue tease and floating rest.'))
doc['buffers'][0]['byteLength']=len(binary)
encoded=json.dumps(doc,separators=(',',':'),ensure_ascii=False).encode();encoded+=b' '*(-len(encoded)%4);binary.extend(b'\0'*(-len(binary)%4))
result=struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4E4F534A)+encoded+struct.pack('<II',len(binary),0x004E4942)+binary
(ROOT/f'Assets/{character}-biblioteca.glb').write_bytes(result)
(ROOT/f'Models/{character.title()}/catalogo.json').write_text(json.dumps({'source':extras,'joints':len(skin['joints']),'clips':manifest,'expressions':eye_offsets},ensure_ascii=False,indent=2)+'\n')
print(f'{character.title()}: {len(skin["joints"])} articulaciones, {len(manifest)} clips, {len(result)} bytes')
