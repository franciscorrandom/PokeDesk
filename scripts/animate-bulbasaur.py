#!/usr/bin/env python3
"""Author Bulbasaur's portable, articulated clips. NumPy is authoring-only.

The original rig, skin weights, bulb and texture atlas remain intact. Leg IK
is baked at 30 Hz; no IK, service or per-vertex work runs in the desktop app.
"""
import copy, json, math, struct
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parent.parent
raw=(ROOT/'Models/Bulbasaur/bulbasaur-original.glb').read_bytes()
length=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+length])
binary=bytearray(raw[28+length:28+length+doc['buffers'][0]['byteLength']])
nodes=doc['nodes'];names={n.get('name'):i for i,n in enumerate(nodes)}
parents={c:i for i,n in enumerate(nodes) for c in n.get('children',[])}

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


skin=doc['skins'][0]
head=names['Head_046'];spine=names['Spine1_019'];chest=names['Spine2_045']
origin=names['Origin_02'];bulb=names['Feeler_020'];ears=[names['LEar_050'],names['REar_052']]
legs=[(names[a],names[b],names[c],front) for a,b,c,front in [
    ('LArm_055','LForeArm_056','LHand_057',True),
    ('RArm_062','RForeArm_063','RHand_031',True),
    ('LThigh_06','LLeg_07','LFoot_08',False),
    ('RThigh_013','RLeg_014','RFoot_015',False)]]
original_world=worlds()
mesh_nodes={n['mesh']:i for i,n in enumerate(nodes) if 'mesh' in n}
# The download also contains two fully extended attack vines. They are not
# part of the resting silhouette, and must not affect framing or hit testing.
for mi in [4,5]:
    nodes[mesh_nodes[mi]].pop('mesh');nodes[mesh_nodes[mi]].pop('skin')

def eye_primitive(mi,dv=0):
    ni=mesh_nodes[mi];pr=doc['meshes'][mi]['primitives'][0]
    transform=np.linalg.inv(original_world[head])@original_world[ni]
    p=read(pr['attributes']['POSITION']);n=read(pr['attributes']['NORMAL'])
    p=(transform@np.c_[p,np.ones(len(p))].T).T[:,:3]
    n=n@np.linalg.inv(transform[:3,:3]);n/=np.linalg.norm(n,axis=1)[:,None]
    return {**pr,'attributes':{
        'POSITION':append(p,'VEC3',True),'NORMAL':append(n,'VEC3'),
        'TEXCOORD_0':append(read(pr['attributes']['TEXCOORD_0'])+[0,dv],'VEC2')}}

expressions={}
for label,offset in [('Open',0),('Half',-.5),('Closed',-.75)]:
    primitives=[eye_primitive(1,offset)]
    # Iris overlays belong only to the open expression: no floating pupils
    # remain over a closed lid. Each expression follows the original head.
    if label=='Open':primitives.append(eye_primitive(3))
    mi=len(doc['meshes']);doc['meshes'].append({'name':'BulbasaurEyes'+label,'primitives':primitives})
    i=len(nodes);nodes.append({'name':'BulbasaurEyes'+label,'mesh':mi,'scale':[1,1,1] if label=='Open' else [0,0,0]})
    nodes[head].setdefault('children',[]).append(i);parents[i]=head;expressions[label]=i
for mi in [1,3]:
    nodes[mesh_nodes[mi]].pop('mesh');nodes[mesh_nodes[mi]].pop('skin')
rest=copy.deepcopy(nodes);rest_world=worlds()

def smooth(x):
    x=np.clip(x,0,1);return float(x*x*x*(x*(x*6-15)+10))

def direction_rotation(i,actual,target):
    a=actual/np.linalg.norm(actual);b=target/np.linalg.norm(target)
    dot=np.clip(a@b,-1,1);axis=np.cross(a,b)
    if np.linalg.norm(axis)<1e-9:return
    nodes[i]['rotation']=world_rotation(i,axis,math.acos(dot),worlds())

def solve_leg(chain,target):
    upper,knee,paw,front=chain;w=worlds()
    a,b,c=[w[i][:3,3] for i in [upper,knee,paw]]
    l1=np.linalg.norm(b-a);l2=np.linalg.norm(c-b)
    delta=target-a;distance=np.clip(np.linalg.norm(delta),abs(l1-l2)+1e-5,l1+l2-1e-5)
    direction=delta/np.linalg.norm(delta)
    ra,rb,rc=[rest_world[i][:3,3] for i in [upper,knee,paw]]
    rest_direction=(rc-ra)/np.linalg.norm(rc-ra)
    pole=(rb-ra)-rest_direction*((rb-ra)@rest_direction)
    if np.linalg.norm(pole)<1e-6:pole=np.array([0.,0.,-1. if front else 1.])
    pole-=direction*(pole@direction);pole/=np.linalg.norm(pole)
    along=(l1*l1-l2*l2+distance*distance)/(2*distance)
    bend=a+direction*along+pole*math.sqrt(max(0,l1*l1-along*along))
    direction_rotation(upper,b-a,bend-a)
    w=worlds();direction_rotation(knee,w[paw][:3,3]-w[knee][:3,3],target-w[knee][:3,3])
    # Keep the paw level while the elbow and hock fold. Two basis alignments
    # avoid inheriting a rotated wrist from the changing two-bone solution.
    for axis in [0,2]:
        w=worlds();direction_rotation(paw,w[paw][:3,axis],rest_world[paw][:3,axis])

catalog=[('reposo',8),('curiosidad',4),('saludo',4),('cola-alegre',4.8),('estiramiento',5),('aviso-reunion',4),('celebracion',3.6),('caricias',5.6),('sentarse',7.2)]

def pose(clip,t,duration):
    for i,n in enumerate(rest):nodes[i]=copy.deepcopy(n)
    e=smooth(t/.8)*smooth((duration-t)/.8)
    def turn(i,axis,angle):
        nodes[i]['rotation']=world_rotation(i,axis,angle,worlds())
    def move_world(i,offset):
        basis=worlds()[parents[i]][:3,:3] if i in parents else np.eye(3)
        nodes[i]['translation']=(np.asarray(nodes[i].get('translation',[0,0,0]))+np.linalg.solve(basis,offset)).tolist()
    # A small settling of the torso gives the nearly straight source legs
    # enough reach to keep all planted contacts during breathing and tilts.
    move_world(origin,[0,-.012*e,0])
    turn(spine,[1,0,0],e*.008*math.sin(t*math.pi/2))
    turn(head,[1,0,0],e*.012*math.sin(t*math.pi/2+.4))
    turn(bulb,[0,0,1],e*.018*math.sin(t*1.6-.5))
    for k,i in enumerate(ears):turn(i,[0,0,1],e*.022*math.sin(t*2.1+k))
    targets=[rest_world[paw][:3,3].copy() for _,_,paw,_ in legs]
    blink=abs(t-(3 if clip=='reposo' else duration*.64))
    state='Closed' if blink<.067 else 'Half' if blink<.135 else 'Open'
    if clip=='curiosidad':
        turn(head,[0,1,0],e*.24*math.sin(t*1.4));turn(head,[0,0,1],e*.12)
        turn(bulb,[0,0,1],-e*.045)
    elif clip=='saludo':
        lift=smooth((t-.35)/.7)*(1-smooth((t-2.7)/.7))
        move_world(origin,[-.035*lift,0,-.012*lift])
        targets[0]+=np.array([.025,.22,.18])*lift
        turn(head,[0,0,1],-e*.07)
    elif clip=='cola-alegre':
        turn(bulb,[0,0,1],e*.085*math.sin(t*3.5))
        turn(bulb,[1,0,0],e*.035*math.sin(t*3.5-.7))
        turn(head,[0,0,1],e*.055*math.sin(t*3.5+.4))
    elif clip=='estiramiento':
        move_world(origin,[0,-e*.075,-e*.035])
        turn(chest,[1,0,0],e*.13);turn(head,[1,0,0],-e*.08)
        targets[0][2]+=.055*e;targets[1][2]+=.055*e
        turn(bulb,[1,0,0],-e*.06)
    elif clip=='aviso-reunion':
        turn(head,[1,0,0],-e*.075);turn(head,[0,1,0],e*.15)
        for k,i in enumerate(ears):turn(i,[0,0,1],(1 if k else -1)*e*.08)
        turn(bulb,[1,0,0],-e*.035)
    elif clip=='celebracion':
        # Alternating front-paw steps, with weight shifted over the supporting
        # side. No rigid-body bounce or simultaneous four-paw takeoff.
        left=e*max(0,math.sin((t-.3)*math.pi*2))**2
        right=e*max(0,math.sin((t-.8)*math.pi*2))**2
        targets[0]+=np.array([0,.065,.025])*left
        targets[1]+=np.array([0,.065,.025])*right
        move_world(origin,[.022*(right-left),0,0])
        turn(head,[0,0,1],e*.07*math.sin(t*5));turn(bulb,[0,0,1],e*.065*math.sin(t*5-.6))
    elif clip=='caricias':
        turn(head,[0,0,1],e*.12*math.sin(t*1.9));turn(head,[1,0,0],-e*.035)
        turn(bulb,[0,0,1],e*.03*math.sin(t*1.9-.6))
        if .8<t<duration-1:state='Closed'
    elif clip=='sentarse':
        # A compact four-legged creature settles into a low resting crouch.
        # Keep contacts anchored while the elbows and hocks bend individually.
        move_world(origin,[0,-e*.12,-e*.015])
        turn(head,[1,0,0],e*.075);turn(bulb,[1,0,0],e*.03)
        for k,target in enumerate(targets):target[2]+=e*(.035 if k<2 else .015)
        if 1<t<duration-1:state='Closed'
    if e>1e-8:
        for chain,target in zip(legs,targets):solve_leg(chain,target)
    if clip=='saludo':turn(legs[0][2],[0,0,1],e*.13*math.sin(t*7))
    for label,i in expressions.items():nodes[i]['scale']=[1,1,1] if state==label else [0,0,0]
    return {path:{i:n.get(path,rest[i].get(path,default)) for i,n in enumerate(nodes) if i in animated[path]} for path,default in [('rotation',[0,0,0,1]),('translation',[0,0,0]),('scale',[1,1,1])]}

animated={'rotation':{head,spine,chest,bulb,*ears,*[i for chain in legs for i in chain[:3]]},'translation':{origin},'scale':set(expressions.values())}
doc['animations']=[];manifest=[]
for clip,duration in catalog:
    times=np.arange(round(duration*30)+1)/30;samples=[pose(clip,float(t),duration) for t in times]
    animation={'name':clip,'samplers':[],'channels':[],'extras':{'loop':clip=='reposo'}}
    ta=append(times[:,None],'SCALAR',True)
    for path,kind in [('rotation','VEC4'),('translation','VEC3'),('scale','VEC3')]:
        for i in sorted(animated[path]):
            values=[sample[path][i] for sample in samples]
            if path=='rotation':
                for k in range(len(values)):
                    q=np.asarray(values[k]);q/=np.linalg.norm(q)
                    if k and np.dot(q,values[k-1])<0:q*=-1
                    values[k]=q.tolist()
            assert np.max(np.abs(np.asarray(values[0])-values[-1]))<.0001,(clip,i)
            si=len(animation['samplers']);animation['samplers'].append({'input':ta,'output':append(values,kind),'interpolation':'STEP' if path=='scale' else 'LINEAR'})
            animation['channels'].append({'sampler':si,'target':{'node':i,'path':path}})
    doc['animations'].append(animation);manifest.append({'id':clip,'duration':duration,'channels':len(animation['channels'])})
doc['nodes']=copy.deepcopy(rest)
extras=doc['asset'].setdefault('extras',{})
extras['modifications']='Nine articulated PokéDesk clips with anchored paw contacts and baked leg IK, head-attached eyelid atlas expressions, bulb follow-through, ears, greeting, alternating paw celebration, petting and low rest. Extended attack vines hidden at rest. Original body geometry, skin weights and inverse binds retained.'
doc['buffers'][0]['byteLength']=len(binary)
encoded=json.dumps(doc,separators=(',',':'),ensure_ascii=False).encode();encoded+=b' '*(-len(encoded)%4);binary.extend(b'\0'*(-len(binary)%4))
result=struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4E4F534A)+encoded+struct.pack('<II',len(binary),0x004E4942)+binary
(ROOT/'Assets/bulbasaur-biblioteca.glb').write_bytes(result)
(ROOT/'Models/Bulbasaur/catalogo.json').write_text(json.dumps({'source':extras,'joints':len(skin['joints']),'clips':manifest,'expressions':{'Open':0,'Half':-.5,'Closed':-.75}},ensure_ascii=False,indent=2)+'\n')
print(f'Bulbasaur: {len(skin["joints"])} articulaciones, {len(manifest)} clips, {len(result)} bytes')
