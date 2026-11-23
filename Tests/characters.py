"""Validate the distributed companion rigs and animation payload, without graphics."""
import json
import copy
import math
import struct
from pathlib import Path

root = Path(__file__).resolve().parent.parent
def validate(character, joint_count, author):
    raw = (root/f'Assets/{character}-biblioteca.glb').read_bytes()
    magic, version, length = struct.unpack_from('<4sII', raw)
    assert (magic, version, length) == (b'glTF', 2, len(raw))
    size = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20+size]); binary = raw[28+size:]
    assert len(binary) >= doc['buffers'][0]['byteLength']
    assert all('uri' not in x for x in doc['buffers']+doc['images'])
    assert author in doc['asset']['extras']['author']
    assert 'CC-BY-4.0' in doc['asset']['extras']['license']
    assert len(doc['skins'][0]['joints']) == joint_count
    assert len(set(doc['skins'][0]['joints'])) == joint_count
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

    # Validate the rest pose independently of the animation generator.
    def multiply(a,b):
        return [[sum(a[r][k]*b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]
    parents = {child:i for i,n in enumerate(doc['nodes']) for child in n.get('children',[])}
    world_cache = {}
    def world(i):
        if i in world_cache: return world_cache[i]
        n=doc['nodes'][i]
        if 'matrix' in n: m=[[n['matrix'][c*4+r] for c in range(4)] for r in range(4)]
        else:
            x,y,z,w=n.get('rotation',[0,0,0,1]); scale=n.get('scale',[1,1,1])
            rotation=[[1-2*y*y-2*z*z,2*x*y-2*z*w,2*x*z+2*y*w],[2*x*y+2*z*w,1-2*x*x-2*z*z,2*y*z-2*x*w],[2*x*z-2*y*w,2*y*z+2*x*w,1-2*x*x-2*y*y]]
            m=[[rotation[r][c]*scale[c] for c in range(3)]+[n.get('translation',[0,0,0])[r]] for r in range(3)]+[[0,0,0,1]]
        world_cache[i]=multiply(world(parents[i]),m) if i in parents else m
        return world_cache[i]
    if character=='pikachu':
        for shoulder,arm,elbow,hand in [(45,46,47,48),(50,51,52,53)]:
            chest,upper,fore,paw=world(shoulder),world(arm),world(elbow),world(hand)
            assert -1.5 < upper[1][3]-chest[1][3] < 0, 'Shoulder exit must not be dragged down the torso'
            assert paw[1][3] < upper[1][3]-8, 'Hands must rest below the upper arm'
            assert 3 < paw[2][3]-upper[2][3] < 5, 'Resting hands should sit slightly forward'
            assert abs(paw[0][3]) < abs(fore[0][3]), 'Elbows should bend gently inward'

    if character=='lucario':
        names={n.get('name'):i for i,n in enumerate(doc['nodes'])}
        unit=math.sqrt(sum(world(names['Origin_02'])[r][0]**2 for r in range(3)))
        for arm,hand in [('LArm_041','LHand_043'),('RArm_079','RHand_081')]:
            upper,paw=world(names[arm]),world(names[hand])
            assert paw[1][3] < upper[1][3]-25*unit, 'Lucario should rest his hands below the chest'
            assert 4*unit < paw[2][3]-upper[2][3] < 25*unit, 'Lucario hands should rest gently forward'
        # A relaxed silhouette must not regress to the horizontal source T-pose.
        shoulder_y=world(names['LArm_041'])[1][3]
        for side,label,start in [('L','A',54),('L','B',59),('R','A',66),('R','B',71)]:
            chain=[names[f'{side}Feeler{label}{k}_{start+k-1:03}'] for k in range(1,5)]
            chain.append(doc['nodes'][chain[-1]]['children'][0])
            points=[world(i) for i in chain]
            assert parents[chain[0]]==names['Head_047'], 'Aura appendages must remain attached to the head'
            assert all(a[1][3]>b[1][3] for a,b in zip(points,points[1:])), 'Resting appendages must fall downward'
            assert points[-1][1][3] < points[0][1][3]-18*unit, 'Aura appendages should hang below the cheeks'
            assert points[-1][2][3] < points[0][2][3]-10*unit, 'Aura appendages must hang behind the neck'
            assert abs(points[-1][1][3]-shoulder_y)<10*unit, 'Resting tips should sit near shoulder height'
    if character=='gengar':
        names={n.get('name'):i for i,n in enumerate(doc['nodes'])}
        assert all(doc['nodes'][names[n]].get('scale')==[0,0,0] for n in ['GengarTongue','GengarMouthMask'])
        assert all(n.get('mesh') not in [2,3,4] for n in doc['nodes']), 'Duplicate source tongue and mask meshes must not show at rest'

    if character=='bulbasaur':
        names={n.get('name'):i for i,n in enumerate(doc['nodes'])}
        assert all(n.get('mesh') not in [1,3,4,5] for n in doc['nodes']), 'Extended vines and duplicate source eyes must not show'
        for label in ['Open','Half','Closed']:
            assert parents[names['BulbasaurEyes'+label]]==names['Head_046']
        paws=[names[n] for n in ['LHand_057','RHand_031','LFoot_08','RFoot_015']]
        chains=[(names[a],names[b],paw) for a,b,paw in [
            ('LArm_055','LForeArm_056',paws[0]),('RArm_062','RForeArm_063',paws[1]),
            ('LThigh_06','LLeg_07',paws[2]),('RThigh_013','RLeg_014',paws[3])]]
        rest_nodes=copy.deepcopy(doc['nodes'])
        def point(i): return [world(i)[r][3] for r in range(3)]
        def dist(a,b): return math.sqrt(sum((x-y)**2 for x,y in zip(a,b)))
        contacts=[point(i) for i in paws]
        lengths={(a,b):dist(point(a),point(b)) for chain in chains for a,b in zip(chain,chain[1:])}
        max_step=0;max_contact=0
        for clip in doc['animations']:
            tracks=[(c['target'],read(clip['samplers'][c['sampler']]['output'])) for c in clip['channels']]
            frame_count=len(tracks[0][1]);lifted=[]
            for target,values in tracks:
                if target['path']=='rotation':
                    max_step=max(max_step,max(2*math.acos(min(1,abs(sum(a*b for a,b in zip(q,r))))) for q,r in zip(values,values[1:])))
                assert target['path']!='scale' or target['node'] not in doc['skins'][0]['joints'], 'Never shrink the legs'
            for frame in range(0,frame_count,2):
                doc['nodes']=copy.deepcopy(rest_nodes);world_cache.clear()
                for target,values in tracks:doc['nodes'][target['node']][target['path']]=values[frame]
                for (a,b),length in lengths.items():
                    assert abs(dist(point(a),point(b))-length)<1e-5, 'Leg segment lengths must stay constant'
                elevations=[point(paw)[1]-rest[1] for paw,rest in zip(paws,contacts)]
                assert min(elevations)>-.002, (clip['name'],'Paws must not penetrate the floor')
                if clip['name'] in ['reposo','curiosidad','cola-alegre','aviso-reunion','caricias']:
                    max_contact=max(max_contact,max(dist(point(p),c) for p,c in zip(paws,contacts)))
                if clip['name']=='saludo':
                    assert max(dist(point(p),c) for p,c in zip(paws[2:],contacts[2:]))<.002
                    lifted.append(elevations[0])
                if clip['name']=='celebracion':
                    assert sum(h>.008 for h in elevations[:2])<=1, 'Front steps must alternate'
            if clip['name']=='saludo':assert max(lifted)>.18, 'The greeting must lift one front paw'
        assert max_contact<.002, 'Planted paws should stay in place during head and bulb gestures'
        assert max_step<.30, 'No abrupt elbow or hock flips between keys'
        doc['nodes']=rest_nodes;world_cache.clear()
        print(f'Bulbasaur: apoyos estables (error {max_contact:.6f} m), patas sin encogerse y paso articular máximo {math.degrees(max_step):.2f}°.')


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
        expected_expressions={character.title()+'Eyes'+x for x in ['Open','Half','Closed']} | ({'MewtwoPupils'} if character == 'mewtwo' else set())
        if character=='gengar': expected_expressions |= {'GengarTongue','GengarMouthMask'}
        assert expressions == expected_expressions

    for n in doc['nodes']:
        if 'skin' not in n or 'mesh' not in n: continue
        for p in doc['meshes'][n['mesh']]['primitives']:
            a = p['attributes']; positions = read(a['POSITION'])
            assert all(v[0] < len(positions) for v in read(p['indices']))
            for joints, weights in zip(read(a['JOINTS_0']), read(a['WEIGHTS_0'])):
                assert all(0 <= j < joint_count for j in joints)
                assert all(0 <= w <= 1 for w in weights) and abs(sum(weights)-1) < .0001
            assert all(abs(sum(x*x for x in n)-1) < .001 for n in read(a['NORMAL']))
    assert len(read(doc['skins'][0]['inverseBindMatrices'])) == joint_count
    print(f'{character.title()} GLB válido: {joint_count} articulaciones, 9 clips, {animated_channels} canales; cierres, expresiones y pesos correctos.')

for spec in [("mewtwo",77,"nguyenlouis32"),("pikachu",49,"jacobjksn42"),("charizard",87,"nguyenlouis32"),("lucario",86,"nguyenlouis32"),("gengar",65,"nguyenlouis32"),("bulbasaur",72,"nguyenlouis32")]:
    validate(*spec)

# Every chooser image is a dedicated, consistently sized 3D render.
for character in ['arcanine','mewtwo','pikachu','charizard','lucario','gengar','bulbasaur']:
    raw=(root/f'Assets/preview-{character}.png').read_bytes()
    assert raw[:8]==b'\x89PNG\r\n\x1a\n'
    assert struct.unpack_from('>II',raw,16)==(320,320)
print('Siete miniaturas 3D de 320 × 320 incluidas.')
