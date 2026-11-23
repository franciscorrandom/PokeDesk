#!/usr/bin/env node
/** Prepare the attributed Dragonite rig and nine portable PokéDesk clips.
 * Install @gltf-transform/{core,extensions,functions}@4.3.0, draco3dgltf and
 * sharp in an authoring directory, then set POKEDESK_GLTF_TOOLS to that path.
 * These packages are needed only to regenerate the checked-in GLB.
 */
const path = require('node:path');
const fs = require('node:fs/promises');
const { execFileSync } = require('node:child_process');
const { createRequire } = require('node:module');
const root = path.resolve(__dirname, '..');
const dependencyRoot = process.env.POKEDESK_GLTF_TOOLS || path.join(root, '.build', 'gltf-tools');
const req = createRequire(path.join(dependencyRoot, 'package.json'));
const clamp = x => Math.max(0, Math.min(1, x));
const smooth = x => { x = clamp(x); return x * x * x * (x * (x * 6 - 15) + 10); };
const norm = q => { const n = Math.hypot(...q); return q.map(x => x / n); };
const dot = (a,b) => a.reduce((s,x,i) => s+x*b[i],0);
function slerp(a,b,t) {
  a=norm(a); b=norm(b); let d=dot(a,b);
  if(d<0) { b=b.map(x=>-x); d=-d; }
  if(d>.9995) return norm(a.map((x,i)=>x+(b[i]-x)*t));
  const angle=Math.acos(Math.min(1,d)), sine=Math.sin(angle);
  return a.map((x,i)=>(x*Math.sin((1-t)*angle)+b[i]*Math.sin(t*angle))/sine);
}
function multiply(a,b) {
  const [x,y,z,w]=a,[X,Y,Z,W]=b;
  return norm([w*X+x*W+y*Z-z*Y,w*Y-x*Z+y*W+z*X,w*Z+x*Y-y*X+z*W,w*W-x*X-y*Y-z*Z]);
}
const lerp=(a,b,t)=>a.map((x,i)=>x+(b[i]-x)*t);

(async()=>{
  const { NodeIO } = await req('@gltf-transform/core');
  const { ALL_EXTENSIONS } = await req('@gltf-transform/extensions');
  const { dequantize, prune } = await req('@gltf-transform/functions');
  const draco = req('draco3dgltf'), sharp = req('sharp');
  const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({
    'draco3d.decoder': await draco.createDecoderModule()
  });
  const doc = await io.read(path.join(root,'Models/Dragonite/dragonite-original.glb'));
  const scene = doc.getRoot(), buffer=scene.listBuffers()[0];
  for(const texture of scene.listTextures()) {
    if(texture.getMimeType()==='image/webp') {
      texture.setImage(await sharp(texture.getImage()).png().toBuffer()).setMimeType('image/png');
    }
  }
  for(const extension of scene.listExtensionsUsed()) {
    if(['KHR_draco_mesh_compression','EXT_texture_webp'].includes(extension.extensionName)) extension.dispose();
  }
  await doc.transform(dequantize());
  const nodes=scene.listNodes(), originals=scene.listAnimations();
  // The source uses unlit materials and omits normals. Supply smooth normals
  // without unwelding, changing skin weights, or changing indexed geometry.
  for(const mesh of scene.listMeshes()) for(const primitive of mesh.listPrimitives()) {
    if(primitive.getAttribute('NORMAL')) continue;
    const position=primitive.getAttribute('POSITION'), vertices=position.getArray();
    const indices=primitive.getIndices()?.getArray()||Uint32Array.from({length:position.getCount()},(_,i)=>i);
    const normals=new Float32Array(vertices.length);
    for(let face=0;face<indices.length;face+=3) {
      const [a,b,c]=[indices[face],indices[face+1],indices[face+2]];
      const u=[0,1,2].map(k=>vertices[b*3+k]-vertices[a*3+k]);
      const v=[0,1,2].map(k=>vertices[c*3+k]-vertices[a*3+k]);
      const n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];
      for(const index of [a,b,c]) for(let k=0;k<3;k++) normals[index*3+k]+=n[k];
    }
    for(let i=0;i<position.getCount();i++) {
      const n=Math.hypot(...normals.slice(i*3,i*3+3));
      if(n>1e-12) for(let k=0;k<3;k++) normals[i*3+k]/=n;
      else normals[i*3+1]=1;
    }
    primitive.setAttribute('NORMAL',doc.createAccessor(mesh.getName()+'-normals').setType('VEC3').setArray(normals).setBuffer(buffer));
  }
  const choose=suffix=>{
    const a=originals.find(a=>a.getName().endsWith(suffix));
    if(!a) throw new Error('Missing source animation '+suffix);
    return a;
  };
  const names={idle:'00000_defaultwait01_loop',curious:'00010_defaultidle01',
    stretch:'00320_refresh01',happy:'00550_glad01',notice:'00560_notice01',
    restStart:'00270_rest01_start',rest:'00271_rest01_loop',restEnd:'00272_rest01_end',
    blink:'28000_eye01'};
  const clips=Object.fromEntries(Object.entries(names).map(([name,suffix])=>[name,choose(suffix)]));
  const channels=a=>a.listChannels().filter(c=>['rotation','translation'].includes(c.getTargetPath()));
  const key=c=>nodes.indexOf(c.getTargetNode())+':'+c.getTargetPath();
  const maps=new Map(originals.map(a=>[a,new Map(channels(a).map(c=>[key(c),c]))]));
  const duration=a=>Math.max(...a.listSamplers().map(s=>s.getInput().getMax([])[0]));
  function sample(channel,time) {
    const sampler=channel.getSampler(), times=sampler.getInput().getArray();
    const output=sampler.getOutput(), values=output.getArray(), width=output.getElementSize();
    let i=0; while(i<times.length-2&&times[i+1]<time) i++;
    const j=Math.min(i+1,times.length-1), t=clamp((time-times[i])/(times[j]-times[i]||1));
    const a=Array.from(values.slice(i*width,(i+1)*width));
    const b=Array.from(values.slice(j*width,(j+1)*width));
    if(sampler.getInterpolation()==='STEP') return a;
    return channel.getTargetPath()==='rotation'?slerp(a,b,t):lerp(a,b,t);
  }
  const tracks=new Map();
  for(const a of originals) for(const c of channels(a)) tracks.set(key(c),{node:c.getTargetNode(),path:c.getTargetPath()});
  const defaults=new Map([...tracks].map(([k,{node,path}])=>[k,path==='rotation'?node.getRotation():node.getTranslation()]));
  const idleMap=maps.get(clips.idle);
  const baseline=new Map([...tracks].map(([k])=>[k,idleMap.has(k)?sample(idleMap.get(k),0):defaults.get(k)]));
  // Freeze the authored standing pose into the scene too. The exported rest
  // pose therefore matches the first and final frame of every portable clip.
  for(const [k,{node,path}] of tracks) {
    const value=baseline.get(k);
    if(path==='rotation') node.setRotation(norm(value)); else node.setTranslation(value);
  }
  const eyelids=[...tracks].filter(([,t])=>t.path==='rotation'&&/eyelid/.test(t.node.getName()));
  const closed=new Map(eyelids.map(([k])=>[k,sample(maps.get(clips.blink).get(k),.175)]));
  const catalog=[['reposo',8,'idle'],['curiosidad',4,'curious'],['saludo',4,'notice'],
    ['cola-alegre',4.8,'idle'],['estiramiento',5,'stretch'],['aviso-reunion',4,'notice'],
    ['celebracion',3.6,'happy'],['caricias',5.6,'rest'],['sentarse',7.2,'rest']];
  const manifests=[];
  for(const [label,length,sourceName] of catalog) {
    const animation=doc.createAnimation(label).setExtras({loop:label==='reposo'});
    const frames=Math.round(length*30)+1, times=Float32Array.from({length:frames},(_,i)=>i/30);
    const timeAccessor=doc.createAccessor(label+'-times').setType('SCALAR').setArray(times).setBuffer(buffer);
    const arrays=new Map([...tracks].map(([k])=>[k,[]]));
    for(let frame=0;frame<frames;frame++) {
      const t=times[frame], envelope=smooth(t/.65)*smooth((length-t)/.65);
      let source=clips[sourceName];
      let sourceTime=label==='reposo'?((t% (length/2))/(length/2))*duration(source):clamp((t-.4)/(length-.8))*duration(source);
      if(label==='sentarse') {
        if(t<1.6) { source=clips.restStart;sourceTime=clamp(t/1.6)*duration(source); }
        else if(t<length-1.6) { source=clips.rest;sourceTime=((t-1.6)%(length-3.2))/(length-3.2)*duration(source); }
        else { source=clips.restEnd;sourceTime=clamp((t-(length-1.6))/1.6)*duration(source); }
      }
      const sourceMap=maps.get(source);
      for(const [k,{node,path}] of tracks) {
        const base=baseline.get(k), name=node.getName();
        let value=sourceMap.has(k)?sample(sourceMap.get(k),sourceTime):base;
        let strength=envelope;
        if(label==='saludo') {
          // Reuse the original articulated right-arm greeting/joy motion;
          // keep its support legs and opposite arm in the standing posture.
          if(/^right_(shoulder|arm|hand|middle|ring|index)/.test(name)) {
            const c=maps.get(clips.happy).get(k);
            value=c?sample(c,clamp((t-.5)/(length-1))*duration(clips.happy)):base;
          } else if(!/neck|head|feeler|eyelid|spine/.test(name)) value=base;
        }
        if(label==='caricias'&&!/neck|head|feeler|eyelid|tail/.test(name)) value=base;
        if(label==='caricias') strength*=.4;
        value=path==='rotation'?slerp(base,value,strength):lerp(base,value,strength);
        if(path==='rotation'&&label==='cola-alegre'&&/^tail_0[1-5]_/.test(name)) {
          const phase=Number(name.match(/^tail_0([1-5])/)[1]);
          const angle=.075*envelope*Math.sin(t*3.6-phase*.45);
          value=multiply(value,[0,Math.sin(angle/2),0,Math.cos(angle/2)]);
        }
        if(path==='rotation'&&closed.has(k)) {
          const center=label==='reposo'?3:Math.round(length*.64*30)/30;
          let blink=smooth((.18-Math.abs(t-center))/.12);
          if(label==='caricias') blink=Math.max(blink,smooth((t-1)/.4)*smooth((length-1-t)/.4));
          value=slerp(base,closed.get(k),blink*envelope);
        }
        if(frame===0||frame===frames-1) value=path==='rotation'?norm(base):base.slice();
        const output=arrays.get(k);
        if(path==='rotation'&&output.length) {
          const previous=output.slice(-4);
          if(dot(previous,value)<0) value=value.map(x=>-x);
        }
        output.push(...value);
      }
    }
    let used=0;
    for(const [k,{node,path}] of tracks) {
      const values=arrays.get(k), width=path==='rotation'?4:3;
      // Keep only real animation channels. Static bindings remain in nodes.
      const first=values.slice(0,width);
      if(values.every((x,i)=>Math.abs(x-first[i%width])<1e-7)) continue;
      const output=doc.createAccessor(label+'-'+node.getName()+'-'+path)
        .setType(width===4?'VEC4':'VEC3').setArray(Float32Array.from(values)).setBuffer(buffer);
      const sampler=doc.createAnimationSampler().setInput(timeAccessor).setOutput(output).setInterpolation('LINEAR');
      const channel=doc.createAnimationChannel().setTargetNode(node).setTargetPath(path).setSampler(sampler);
      animation.addSampler(sampler).addChannel(channel); used++;
    }
    manifests.push({id:label,duration:length,channels:used,source:sourceName==='rest'&&label==='sentarse'?'rest start, loop and end':names[sourceName]});
  }
  for(const original of originals) original.dispose();
  const extras=scene.getAsset().extras||{};
  extras.modifications='Decoded Draco and WebP to portable float geometry and embedded PNG textures. Nine 30 Hz articulated clips resampled from the attributed source animations, with quaternion interpolation and smooth returns to a common standing pose, an asymmetric greeting and tail follow-through. The original eight eyelid bones animate real skinned eyelids; no expression marker meshes were added.';
  extras.pokedeskBlink={time:3,nodes:Object.fromEntries(eyelids
    .filter(([k])=>Math.abs(dot(norm(baseline.get(k)),norm(closed.get(k))))<.9999)
    .map(([k,{node}])=>[node.getName(),norm(closed.get(k))]))};
  scene.getAsset().extras=extras;
  await doc.transform(prune({keepLeaves:true,keepAttributes:true}));
  await io.write(path.join(root,'Assets/dragonite-biblioteca.glb'),doc);
  await fs.writeFile(path.join(root,'Models/Dragonite/catalogo.json'),JSON.stringify({source:extras,joints:scene.listSkins()[0].listJoints().length,clips:manifests},null,2)+'\n');
  const python=process.env.POKEDESK_PYTHON || path.join(root,'.build/authoring/bin/python');
  execFileSync(python,[path.join(root,'scripts/prepare-dragonite.py')],{stdio:'inherit'});
  console.log('Dragonite prepared:',scene.listSkins()[0].listJoints().length,'joints;',manifests.length,'clips');
})().catch(error=>{console.error(error);process.exit(1);});
