#!/usr/bin/env python3
"""Author Arcanine's bounding gait with staggered fore/hind foot contacts.

Requires numpy for authoring only. Runtime uses the same embedded glTF clip on
SceneKit and Three.js. Geometry, textures, bind matrices and other clips survive
unchanged; unused animation buffers are discarded so regeneration is idempotent.
"""
import argparse
import copy
import json
import math
import struct
from pathlib import Path

import numpy as np


def smooth(t):
    t = min(1, max(0, t))
    return t*t*t*(10+t*(-15+6*t))


def curve(points, t):
    """Monotone cubic Hermite interpolation, including zero-speed extrema."""
    if t <= points[0][0]: return points[0][1]
    if t >= points[-1][0]: return points[-1][1]
    slopes = [(b[1]-a[1])/(b[0]-a[0]) for a,b in zip(points,points[1:])]
    tangent = [0]
    for i in range(1,len(points)-1):
        left,right = slopes[i-1],slopes[i]
        tangent.append(0 if left*right <= 0 else 2*left*right/(left+right))
    tangent.append(0)
    for i,(a,b) in enumerate(zip(points,points[1:])):
        if a[0] <= t <= b[0]:
            span = b[0]-a[0]; u = (t-a[0])/span
            return ((2*u**3-3*u*u+1)*a[1]+(u**3-2*u*u+u)*span*tangent[i]
                    +(-2*u**3+3*u*u)*b[1]+(u**3-u*u)*span*tangent[i+1])


def qmul(a, b):
    x, y, z, w = a; X, Y, Z, W = b
    return np.array([w*X+x*W+y*Z-z*Y, w*Y-x*Z+y*W+z*X,
                     w*Z+x*Y-y*X+z*W, w*W-x*X-y*Y-z*Z])


def axisq(axis, angle):
    axis = np.asarray(axis, dtype=float)
    axis /= np.linalg.norm(axis)
    return np.r_[axis*math.sin(angle/2), math.cos(angle/2)]


def rotation(q):
    x, y, z, w = q
    return np.array([[1-2*y*y-2*z*z, 2*x*y-2*z*w, 2*x*z+2*y*w],
                     [2*x*y+2*z*w, 1-2*x*x-2*z*z, 2*y*z-2*x*w],
                     [2*x*z-2*y*w, 2*y*z+2*x*w, 1-2*x*x-2*y*y]])


def matrixq(m):
    K = np.array([[m[0,0]-m[1,1]-m[2,2],m[0,1]+m[1,0],m[0,2]+m[2,0],m[2,1]-m[1,2]],
                  [m[0,1]+m[1,0],m[1,1]-m[0,0]-m[2,2],m[1,2]+m[2,1],m[0,2]-m[2,0]],
                  [m[0,2]+m[2,0],m[1,2]+m[2,1],m[2,2]-m[0,0]-m[1,1],m[1,0]-m[0,1]],
                  [m[2,1]-m[1,2],m[0,2]-m[2,0],m[1,0]-m[0,1],m[0,0]+m[1,1]+m[2,2]]])/3
    _,vectors = np.linalg.eigh(K)
    return vectors[:,-1]


def mix_basis(a, b, weight):
    qa,qb = matrixq(a),matrixq(b); dot = float(np.dot(qa,qb))
    if dot < 0: qb = -qb; dot = -dot
    if dot > .9995:
        q = qa*(1-weight)+qb*weight; q /= np.linalg.norm(q)
    else:
        theta = math.acos(min(1,dot))
        q = (qa*math.sin((1-weight)*theta)+qb*math.sin(weight*theta))/math.sin(theta)
    return rotation(q)


class Rig:
    def __init__(self, doc):
        self.rest = copy.deepcopy(doc['nodes'])
        self.parents = {c:i for i,n in enumerate(self.rest) for c in n.get('children', [])}
        self.names = {n.get('name'):i for i,n in enumerate(self.rest)}
        self.reset()
        self.restworld = self.worlds()
        # Model has an FBX inch-to-metre transform. Author offsets in native
        # mesh units, expressed as fractions of the original body height.
        body = doc['accessors'][doc['meshes'][0]['primitives'][0]['attributes']['POSITION']]
        self.height = body['max'][1]-body['min'][1]
        self.feet = [('LArm_044','LForeArm_045','LHand_049'),
                     ('RArm_073','RForeArm_074','RHand_078'),
                     ('LThigh_06','LLeg_07','LFoot_08'),
                     ('RThigh_017','RLeg_018','RFoot_019')]
        self.origin = self.names['Origin_02']
        self.unit = np.linalg.norm(self.restworld[self.origin][:3, 0])*self.height

    def reset(self):
        self.nodes = copy.deepcopy(self.rest)

    def worlds(self):
        cache = {}
        def at(i):
            if i in cache: return cache[i]
            n = self.nodes[i]
            if 'matrix' in n:
                m = np.asarray(n['matrix']).reshape(4,4).T
            else:
                m = np.eye(4)
                m[:3,:3] = rotation(n.get('rotation',[0,0,0,1]))@np.diag(n.get('scale',[1,1,1]))
                m[:3,3] = n.get('translation',[0,0,0])
            cache[i] = at(self.parents[i])@m if i in self.parents else m
            return cache[i]
        return {i:at(i) for i in range(len(self.nodes))}

    def local_rotate(self, name, axis, angle):
        n = self.nodes[self.names[name]]
        q = qmul(n.get('rotation',[0,0,0,1]), axisq(axis,angle))
        n['rotation'] = (q/np.linalg.norm(q)).tolist()

    def actor_rotate(self, name, axis, angle):
        w = self.worlds(); i = self.names[name]
        worldaxis = w[self.origin][:3,:3]@np.asarray(axis)
        self.local_rotate(name, np.linalg.solve(w[i][:3,:3],worldaxis),angle)

    def set_world_rotation(self, name, delta):
        i = self.names[name]; w = self.worlds()
        # Conjugate a world-space delta into this joint's local frame.
        basis = w[i][:3,:3]
        basis = basis/np.linalg.norm(basis,axis=0)
        axis, angle = delta
        self.local_rotate(name, basis.T@axis, angle)

    def aim(self, name, target):
        w = self.worlds(); i = self.names[name]
        current = w[i][:3,0]; current /= np.linalg.norm(current)
        direction = target-w[i][:3,3]; direction /= np.linalg.norm(direction)
        axis = np.cross(current,direction); sine = np.linalg.norm(axis)
        if sine > 1e-9:
            self.set_world_rotation(name,(axis/sine, math.atan2(sine,np.dot(current,direction))))

    def solve(self, names, target, foot_basis):
        w = self.worlds(); ids = [self.names[n] for n in names]
        a = w[ids[0]][:3,3]
        first = np.linalg.norm(self.restworld[ids[1]][:3,3]-self.restworld[ids[0]][:3,3])
        second = np.linalg.norm(self.restworld[ids[2]][:3,3]-self.restworld[ids[1]][:3,3])
        offset = target-a; distance = np.linalg.norm(offset)
        length = np.clip(distance,abs(first-second)+1e-5,first+second-1e-5)
        direction = offset/distance
        # Use the resting knee's own bend plane; never flip it backwards on
        # take-off or collapse a leg merely to reach a rotating floor anchor.
        pole = np.linalg.solve(self.restworld[self.origin][:3,:3],
                               self.restworld[ids[1]][:3,3]-self.restworld[ids[0]][:3,3])
        pole = w[self.origin][:3,:3]@pole
        perpendicular = pole-direction*np.dot(pole,direction)
        perpendicular /= np.linalg.norm(perpendicular)
        cosine = np.clip((first*first+length*length-second*second)/(2*first*length),-1,1)
        elbow = a+direction*(cosine*first)+perpendicular*(math.sqrt(1-cosine*cosine)*first)
        self.aim(names[0],elbow); self.aim(names[1],target)
        # Preserve pad orientation during contact. Convert desired world
        # orientation to a quaternion, without altering bone scales/lengths.
        w = self.worlds(); p = w[self.parents[ids[2]]][:3,:3]
        p = p/np.linalg.norm(p,axis=0)
        m = p.T@foot_basis
        # Stable matrix-to-quaternion conversion, including 180-degree turns.
        self.nodes[ids[2]]['rotation'] = matrixq(m).tolist()

    def torso(self, angle, bend, lift=0, load=0, pitch=0):
        self.local_rotate('Origin_02',[0,1,0],angle)
        offset = self.unit*np.array([.035*(1-math.cos(angle)), lift-.009*bend-.018*load,
                                    .035*math.sin(angle)])
        parent = self.restworld[self.parents[self.origin]]
        position = self.restworld[self.origin][:3,3]+offset
        self.nodes[self.origin]['translation'] = (np.linalg.inv(parent)@np.r_[position,1])[:3].tolist()
        self.actor_rotate('Waist_03',[1,0,0],pitch)
        self.actor_rotate('Hips_04',[0,1,0],-.22*bend)
        self.actor_rotate('Spine1_034',[0,1,0],.28*bend)
        self.actor_rotate('Spine2_035',[0,1,0],.18*bend)

    def anchor(self, angle, bend, names):
        saved = self.nodes
        self.reset(); self.torso(angle,bend)
        w = self.worlds(); i = self.names[names[2]]
        target = w[i][:3,3].copy()
        target[1] = self.restworld[i][1,3]
        basis = w[i][:3,:3]; basis = basis/np.linalg.norm(basis,axis=0)
        self.nodes = saved
        return target,basis

    def pose(self, t, single=False):
        self.reset()
        bend = 0 if single else smooth((t-.08)/.30)*(1-smooth((t-2.88)/.76))
        start, period = (.40,.62) if single else (.42,.62)
        hops = 1 if single else 4
        clock = (t-start)/period
        hop = min(hops-1,max(0,int(math.floor(clock))))
        phase = (clock-hop)*.74
        active = 0 <= clock < hops
        # Front paws lift first; hind legs remain planted to deliver the push.
        # Yaw begins only after the last hind paw leaves the floor, ending
        # before the leading front paw lands. Contact feet never swivel.
        turn = smooth((phase-.295)/.185) if active else 0
        angle = 0 if single else ((hop+turn)*math.pi/2 if active else (2*math.pi if clock >= hops else 0))
        lift = curve([(0,0),(.10,-.030),(.24,-.011),(.295,-.001),(.36,.098),(.43,.014),(.49,.004),(.61,-.022),(.74,0)],phase) if active else 0
        pitch = curve([(0,0),(.17,-.16),(.29,-.17),(.40,.035),(.50,.10),(.62,.032),(.74,0)],phase) if active else 0
        self.torso(angle,bend,lift,0,pitch)
        # Keep the head steadier than the chest, with a small following delay.
        self.actor_rotate('Neck_053',[1,0,0],-.58*pitch)
        self.actor_rotate('Neck_053',[0,1,0],.65*bend)
        self.actor_rotate('Head_054',[0,1,0],.32*bend)
        self.local_rotate('Head_054',[0,0,1],-.055*bend)
        self.local_rotate('Jaw_062',[0,1,0],-.065*bend-.015*max(0,lift/.082))
        for j,name in enumerate(['Tail1_028','Tail2_029','Tail3_030','Tail4_031','Tail5_032']):
            lag = .035*math.sin(t*10-j*.6)*(1 if active else 0)
            self.local_rotate(name,[0,0,1],(bend*(.52+.10*math.sin(t*13-j*.55))+lag)/(j+1))
        for j,name in enumerate(['LEar_064','REar_068']):
            self.local_rotate(name,[0,0,1],(-1 if j else 1)*.035*math.sin(t*14)*(1 if active else bend))
        contacts = []
        for j,names in enumerate(self.feet):
            w = self.worlds(); i = self.names[names[2]]
            flight = w[i][:3,3].copy()
            footbasis = w[i][:3,:3]; footbasis = footbasis/np.linalg.norm(footbasis,axis=0)
            stance = True
            if active:
                depart = [.06,.095,.23,.295][j]
                touch = [.48,.52,.60,.64][j]
                departure,departure_basis = self.anchor(0 if single else hop*math.pi/2,bend,names)
                arrival,arrival_basis = self.anchor(0 if single else (hop+1)*math.pi/2,bend,names)
                u = min(1,max(0,(phase-depart)/(touch-depart)))
                arc = math.sin(math.pi*u)
                # Forelegs fold at their elbows and reach forward to catch
                # the body; hind feet trail the push, then swing underneath.
                forward = (.06*arc*(2*u-.45) if j < 2 else -.036*math.sin(2*math.pi*u)*arc)
                clearance = (.105 if j < 2 else .046)*arc
                flight += rotation(axisq([0,1,0],angle))@np.array([0,clearance*self.unit,forward*self.unit])
                # During the final rear push the pelvis is still low. A toe
                # cannot swing through the ground to follow that low pelvis.
                toe_clearance = (.012 if j < 2 else .024)*self.unit*arc
                flight[1] = max(self.restworld[i][1,3]+toe_clearance,flight[1])
                padpitch = (-.20 if j < 2 else .13)*arc
                footbasis = rotation(axisq([1,0,0],padpitch))@footbasis
                launch_blend = .045 if j < 2 else .035
                if phase <= depart:
                    target = departure; footbasis = departure_basis
                elif phase < depart+launch_blend:
                    weight = smooth((phase-depart)/launch_blend)
                    target = departure*(1-weight)+flight*weight
                    footbasis = mix_basis(departure_basis,footbasis,weight)
                    stance = False
                elif phase < touch-.080:
                    target = flight; stance = False
                elif phase < touch:
                    weight = smooth((phase-touch+.080)/.080)
                    target = flight*(1-weight)+arrival*weight
                    footbasis = mix_basis(footbasis,arrival_basis,weight)
                    stance = False
                else:
                    target = arrival; footbasis = arrival_basis
            elif clock < 0:
                target,footbasis = self.anchor(0,bend,names)
            else:
                target,footbasis = self.anchor(0 if single else 2*math.pi,bend,names)
            requested = target.copy()
            if not stance:
                # The swing is authored within the leg's physical reach. A
                # trailing kick may otherwise hyperextend the short rear rig.
                w = self.worlds(); shoulder = w[self.names[names[0]]][:3,3]
                ids = [self.names[n] for n in names]
                reach = sum(np.linalg.norm(self.restworld[b][:3,3]-self.restworld[a][:3,3]) for a,b in zip(ids,ids[1:]))*.98
                offset = target-shoulder; distance = np.linalg.norm(offset)
                if distance > reach: target = shoulder+offset/distance*reach
            self.solve(names,target,footbasis)
            actual = self.worlds()[i][:3,3]
            contacts.append({'time':t,'paw':names[2],'stance':stance,'requested':requested.tolist(),'target':target.tolist(),
                             'actual':actual.tolist(),'error':float(np.linalg.norm(actual-target))})
        distance = min(abs(t-.22),abs(t-3.65))
        eye = 2 if distance < .04 else 1 if distance < .09 else 0
        for j,name in enumerate(['ArcanineEyesOpen','ArcanineEyesHalf','ArcanineEyesClosed']):
            self.nodes[self.names[name]]['scale'] = [1,1,1] if eye == j else [0,0,0]
        self.nodes[self.names['ArcaninePupils']]['scale'] = [1,1,1] if eye == 0 else [0,0,0]
        # Exact endpoints make blend-out and interruption restore the rest pose.
        if t == 0 or t >= 4: self.reset()
        return contacts


def bake(path, output, single=False):
    raw = path.read_bytes(); size = struct.unpack_from('<I',raw,12)[0]
    doc = json.loads(raw[20:20+size]); binary = bytearray(raw[28+size:28+size+doc['buffers'][0]['byteLength']])
    rig = Rig(doc); fps = 75
    eyes = {rig.names[n] for n in ['ArcanineEyesOpen','ArcanineEyesHalf','ArcanineEyesClosed','ArcaninePupils']}
    animated = list(doc['skins'][0]['joints'])+sorted(eyes)
    samples = {i:[] for i in animated}; translations = []; max_error = 0; contact_report = []
    for frame in range(4*fps+1):
        contacts = rig.pose(frame/fps,single)
        contact_report.extend(contacts)
        max_error = max(max_error,max(c['error'] for c in contacts))
        for i in animated:
            node = rig.nodes[i]
            samples[i].append(node.get('scale',[1,1,1]) if i in eyes else node.get('rotation',[0,0,0,1]))
        translations.append(rig.nodes[rig.origin].get('translation',[0,0,0]))

    def append(values, kind, bounds=False):
        data = np.asarray(values,dtype='<f4'); assert np.isfinite(data).all()
        binary.extend(b'\0'*(-len(binary)%4)); offset = len(binary); binary.extend(data.tobytes())
        vi = len(doc['bufferViews']); doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':data.nbytes})
        a = {'bufferView':vi,'componentType':5126,'count':len(data),'type':kind}
        if bounds: a.update(min=data.min(axis=0).tolist(),max=data.max(axis=0).tolist())
        ai = len(doc['accessors']); doc['accessors'].append(a); return ai

    animation = {'name':'giro-rapido','channels':[],'samplers':[],
                 'extras':{'title':'Persiguiendo su cola','loop':False,'trigger':'Reacción juguetona',
                           'motion':'single-bound-study' if single else 'four-bound-tail-chase','hops':1 if single else 4,'authoringFPS':fps}}
    times = append([[f/fps] for f in range(4*fps+1)],'SCALAR',True)
    def channel(i, path, values):
        values = np.array(values,dtype=float)
        if path == 'rotation':
            for f in range(1,len(values)):
                if np.dot(values[f-1],values[f]) < 0: values[f] *= -1
            assert np.max(np.abs(np.linalg.norm(values,axis=1)-1)) < 1e-5
        if np.max(np.abs(values-values[0])) < 1e-6: return
        ai = append(values,'VEC4' if path == 'rotation' else 'VEC3')
        s = len(animation['samplers'])
        animation['samplers'].append({'input':times,'output':ai,'interpolation':'STEP' if path == 'scale' else 'LINEAR'})
        animation['channels'].append({'sampler':s,'target':{'node':i,'path':path}})
    for i,values in samples.items(): channel(i,'scale' if i in eyes else 'rotation',values)
    channel(rig.origin,'translation',translations)
    index = next(i for i,a in enumerate(doc['animations']) if a['name']=='giro-rapido')
    doc['animations'][index] = animation
    doc['asset']['extras']['modifications'] = ('Eleven articulated clips and head-attached blink expressions. '+
        ('Local study of a single coordinated bound; not integrated into the distributed app. ' if single else 'Tail chase revised to four coordinated bounds. ')+
        'Front paws lift before the rear push; fore/hind touchdowns are staggered. Geometry, textures, other gestures and original attribution preserved.')
    # Compact buffer views and remap every live accessor reference. The old
    # chase's unused accessors are discarded, preventing growth on rebaking.
    used = set()
    for mesh in doc['meshes']:
        for p in mesh['primitives']:
            used.update(p['attributes'].values())
            if 'indices' in p: used.add(p['indices'])
            for target in p.get('targets',[]): used.update(target.values())
    used.update(s['inverseBindMatrices'] for s in doc['skins'] if 'inverseBindMatrices' in s)
    for a in doc['animations']:
        for s in a['samplers']: used.update([s['input'],s['output']])
    remap = {a:i for i,a in enumerate(sorted(used))}
    doc['accessors'] = [doc['accessors'][i] for i in sorted(used)]
    for mesh in doc['meshes']:
        for p in mesh['primitives']:
            p['attributes'] = {k:remap[v] for k,v in p['attributes'].items()}
            if 'indices' in p: p['indices'] = remap[p['indices']]
            for target in p.get('targets',[]):
                for k in target: target[k] = remap[target[k]]
    for s in doc['skins']:
        if 'inverseBindMatrices' in s: s['inverseBindMatrices'] = remap[s['inverseBindMatrices']]
    for a in doc['animations']:
        for s in a['samplers']:
            s['input'] = remap[s['input']]; s['output'] = remap[s['output']]
    views = {a['bufferView'] for a in doc['accessors']}|{im['bufferView'] for im in doc['images']}
    compact = bytearray(); viewmap = {}; newviews = []
    for vi in sorted(views):
        v = copy.deepcopy(doc['bufferViews'][vi]); start = v.get('byteOffset',0)
        compact.extend(b'\0'*(-len(compact)%4)); v['byteOffset'] = len(compact)
        compact.extend(binary[start:start+v['byteLength']]); viewmap[vi] = len(newviews); newviews.append(v)
    for a in doc['accessors']: a['bufferView'] = viewmap[a['bufferView']]
    for im in doc['images']: im['bufferView'] = viewmap[im['bufferView']]
    doc['bufferViews'] = newviews; doc['buffers'][0]['byteLength'] = len(compact)
    encoded = json.dumps(doc,separators=(',',':'),ensure_ascii=False).encode(); encoded += b' '*(-len(encoded)%4)
    compact.extend(b'\0'*(-len(compact)%4))
    result = struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(compact))
    result += struct.pack('<II',len(encoded),0x4E4F534A)+encoded+struct.pack('<II',len(compact),0x004E4942)+compact
    output.write_bytes(result)
    output.with_suffix('.contacts.json').write_text(json.dumps({'contacts':contact_report},separators=(',',':'))+'\n')
    print(f'{1 if single else 4} salto(s) coordinado(s) · 4 s · {fps} claves/s · {len(animation["channels"])} canales · error IK máximo {max_error:.6g} · {len(result)} bytes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input',type=Path,nargs='?',default=Path(__file__).resolve().parent.parent/'Assets/arcanine-biblioteca.glb')
    parser.add_argument('--output',type=Path,required=True,help='Salida explícita; la muestra no reemplaza automáticamente el modelo distribuido')
    parser.add_argument('--single-hop-preview',action='store_true',help='Estudio de un salto sin giro, separado del modelo distribuido')
    args = parser.parse_args()
    bake(args.input,args.output,args.single_hop_preview)
