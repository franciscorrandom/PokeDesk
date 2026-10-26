import * as THREE from 'three';
import { GLTFLoader } from './vendor/three-addons/loaders/GLTFLoader.js';
import { maskHit } from './geometry.mjs';
import characters from './characters.json' with {type:'json'};
import {summonFrame,durations} from './summon.mjs';
import {createPokeball} from './pokeball.js';
import {AmbientRotation} from './ambient.mjs';

export async function createPet(container,onShape=()=>{},settings={},onReady=()=>{},prepareToShow=async()=>({shown:true})) {
  let width=container.clientWidth,height=container.clientHeight;
  const scene=new THREE.Scene(),camera=new THREE.PerspectiveCamera(34,width/height,.01,100);
  const renderer=new THREE.WebGLRenderer({alpha:true,antialias:true,powerPreference:'low-power'});
  renderer.setPixelRatio(Math.min(devicePixelRatio,1.5));renderer.setSize(width,height);renderer.setClearColor(0,0);
  renderer.outputColorSpace=THREE.SRGBColorSpace;renderer.toneMapping=THREE.ACESFilmicToneMapping;renderer.toneMappingExposure=1.25;
  renderer.domElement.id='pet-canvas';container.append(renderer.domElement);
  scene.add(new THREE.AmbientLight(0xffffff,1.5));
  const key=new THREE.DirectionalLight(0xfff4df,2.5);key.position.set(3,5,5);scene.add(key);
  const fill=new THREE.DirectionalLight(0xd2e5ff,.8);fill.position.set(-4,3,-3);scene.add(fill);
  const orientation=new THREE.Group();scene.add(orientation);
  const appearance=new THREE.Group();appearance.position.y=1.1;orientation.add(appearance);
  const effect=createPokeball();scene.add(effect.root);
  const systemReduced=matchMedia('(prefers-reduced-motion: reduce)');
  // CI desktops disable OS animations. Only the isolated smoke profile overrides that preference.
  const reduced=settings.testEffects?{matches:false,addEventListener(){}}:systemReduced;
  let initialized=false;
  const ambient = new AmbientRotation();
  let baseYaw = settings.yaw ?? 0, ambientAllowed = !settings.testEffects, interactionBusy = false;
  let current=null,pendingId='',switching=false,motionEnabled=settings.motion!==false,visible=!document.hidden,disposed=false,contextLost=false;
  const phaseHistory=[];
  let frameHandle=0,lastTime=0,lastShapeTime=-Infinity,currentClip='reposo',phase=null,dirty=true,frames=0,shapeReads=0;
  const maskWidth=108,maskHeight=76,hitTarget=new THREE.WebGLRenderTarget(maskWidth,maskHeight),rgba=new Uint8Array(maskWidth*maskHeight*4);
  let mask={width:maskWidth,height:maskHeight,data:new Uint8Array(maskWidth*maskHeight)},body;
  const temp=new THREE.Vector3();
  function cameraFor(id=current?.id,clip=currentClip){
    // The wide wing and tail envelope needs more room in every horizontal profile.
    const distance=id==='charizard'?1.10:1;
    camera.position.set((clip==='giro-rapido'?4.1:3.2)*distance,(clip==='giro-rapido'?2.8:2.25)*distance,(clip==='giro-rapido'?7:5.4)*distance);
    camera.lookAt(0,1.1,0);camera.updateMatrixWorld(true);
  }
  function materialsOf(model){const out=new Set();model.traverse(n=>{if(n.isMesh)for(const m of Array.isArray(n.material)?n.material:[n.material])out.add(m);});return out;}
  function disposeModel(model){
    const geometries=new Set(),textures=new Set();
    model.traverse(n=>{if(n.geometry)geometries.add(n.geometry);if(n.skeleton)n.skeleton.dispose();});
    for(const m of materialsOf(model)){for(const v of Object.values(m))if(v?.isTexture)textures.add(v);m.dispose();}
    for(const t of textures){t.dispose();if(t.image?.close)t.image.close();}for(const g of geometries)g.dispose();
  }
  function makeFire(material){
    const fire=new THREE.MeshBasicMaterial({name:material.name,map:material.map,transparent:true,depthWrite:false,side:THREE.DoubleSide,toneMapped:false});
    fire.onBeforeCompile=shader=>{shader.fragmentShader=shader.fragmentShader.replace('#include <map_fragment>',`#ifdef USE_MAP\nvec4 sampledDiffuseColor=texture2D(map,vMapUv);\nfloat mask=sampledDiffuseColor.r;\nfloat alpha=smoothstep(.04,.30,mask)*mask;\ndiffuseColor.rgb=mix(vec3(1.,.08,.005),vec3(1.,${material.name==='CharizardFlame3'?'.45,.02':'.85,.12'}),mask);\ndiffuseColor.a*=alpha;\n#endif`);};
    fire.customProgramCacheKey=()=>material.name;material.dispose();return fire;
  }
  async function load(id){
    const gltf=await new GLTFLoader().loadAsync('/assets/'+id+'.glb'),model=gltf.scene;
    try {
      const spec=characters.find(c=>c.id===id);if(!spec||!spec.clips.every(c=>gltf.animations.some(a=>a.name===c.id)))throw new Error('La biblioteca 3D está incompleta.');
      model.traverse(n=>{if(n.isMesh){n.frustumCulled=false;const materials=Array.isArray(n.material)?n.material:[n.material];const fixed=materials.map(m=>id==='charizard'&&m.name.startsWith('CharizardFlame')?makeFire(m):m);n.material=Array.isArray(n.material)?fixed:fixed[0];}});
      model.updateMatrixWorld(true);const box=new THREE.Box3().setFromObject(model),size=box.getSize(new THREE.Vector3()),center=box.getCenter(new THREE.Vector3());
      if(!(size.y>0))throw new Error('El modelo 3D no tiene una altura válida.');
      const scale=id==='charizard'?Math.min(2.2/size.y,4.6/Math.hypot(size.x,size.z)):2.2/size.y;
      const placement=new THREE.Group();placement.scale.setScalar(scale);placement.position.set(-center.x*scale,-box.min.y*scale-1.1,-center.z*scale);placement.add(model);
      const mixer=new THREE.AnimationMixer(model),actions=new Map(gltf.animations.map(a=>[a.name,mixer.clipAction(a)])),bones=[],meshes=[];
      model.traverse(n=>{if(n.isBone)bones.push(n);if(n.isMesh)meshes.push(n);});
      const materials=[...materialsOf(model)].map(m=>({m,opacity:m.opacity,transparent:m.transparent,emissive:m.emissive?.clone(),intensity:m.emissiveIntensity}));
      // Compile the incoming model offscreen. It never reaches the visible scene before release t=0.
      await renderer.compileAsync(placement,camera,scene);
      return {id,model,placement,mixer,actions,bones,meshes,materials,active:null,fading:[]};
    } catch(e){disposeModel(model);throw e;}
  }
  function play(id,instant=false){
    if(!current)return;const next=current.actions.get(id);if(!next)return;
    if(current.active===next&&id==='reposo')return;
    if(instant){current.mixer.stopAllAction();current.fading=[];}
    const old=current.active;next.reset().setEffectiveWeight(1).setEffectiveTimeScale(1);next.enabled=true;
    next.setLoop(id==='reposo'?THREE.LoopRepeat:THREE.LoopOnce,id==='reposo'?Infinity:1);next.clampWhenFinished=true;
    if(old&&old!==next&&!instant){old.fadeOut(.22);current.fading.push({action:old,time:.22});next.fadeIn(.22);}else next.stopFading();
    next.play();current.active=next;currentClip=id;cameraFor();invalidate();
  }
  function finishPhase(){if(!phase)return;const done=phase.resolve;applyFrame(summonFrame(phase.id,durations[phase.id]),phase.id,durations[phase.id]);phase=null;effect.hide();done();}
  function applyFrame(f,id,time){
    appearance.visible=f.petOpacity>0;appearance.scale.setScalar(Math.max(.001,f.petAmount));
    for(const {m,opacity,transparent,emissive,intensity} of current?.materials??[]){m.transparent=true;m.opacity=opacity*f.petOpacity;if(m.emissive){m.emissive.copy(emissive).lerp(new THREE.Color(id==='recall'?0xff4060:0x80caff),f.whiten);m.emissiveIntensity=intensity+f.whiten*1.5;}}
    effect.frame(f,id,time,camera);
  }
  function settle(){
    appearance.visible=true;appearance.scale.setScalar(1);effect.hide();
    for(const {m,opacity,transparent,emissive,intensity} of current?.materials??[]){m.opacity=opacity;m.transparent=transparent;if(m.emissive){m.emissive.copy(emissive);m.emissiveIntensity=intensity;}}
    invalidate();
  }
  function animate(id){
    phaseHistory.push({id,animated:motionEnabled&&!reduced.matches&&visible});if(phaseHistory.length>50)phaseHistory.shift();
    if(!motionEnabled||reduced.matches||!visible){applyFrame(summonFrame(id,durations[id]),id,durations[id]);effect.hide();return Promise.resolve();}
    return new Promise(resolve=>{phase={id,start:performance.now(),resolve};applyFrame(summonFrame(id,0),id,0);invalidate();});
  }
  async function setCharacter(id){
    if(disposed||id===current?.id||id===pendingId)return;
    if(switching)return;
    pendingId=id;switching=true;let incoming;
    try {
      incoming=await load(id);
      if(disposed){disposeModel(incoming.model);return;}
      if(!current){const shown=await prepareToShow();visible=shown.shown;lastTime=performance.now();}
      if(current){play('reposo',true);await animate('recall');appearance.remove(current.placement);current.mixer.stopAllAction();current.mixer.uncacheRoot(current.model);disposeModel(current.model);}
      appearance.visible=false;appearance.scale.setScalar(.001);current=incoming;appearance.add(current.placement);cameraFor(id,'reposo');play('reposo',true);
      await animate('release');settle();draw(true);
      if(initialized)onReady({ok:true,character:id,clips:current.actions.size,bones:current.bones.length,phases:phaseHistory.slice(),reducedMotion:reduced.matches});
    } catch(e){settle();onReady({ok:false,character:current?.id,error:'No pude cargar el modelo 3D. Reabre PokéDesk o vuelve a descargar la app completa.'});throw e;}
    finally{pendingId='';switching=false;}
  }
  function hit(x,y){if(switching||contextLost)return false;const r=container.getBoundingClientRect();return maskHit(mask,(x-r.left)/r.width*maskWidth,(y-r.top)/r.height*maskHeight);}
  function updateShape(){
    const previousVisibility=effect.root.visible;effect.root.visible=false;
    renderer.setRenderTarget(hitTarget);renderer.render(scene,camera);renderer.readRenderTargetPixels(hitTarget,0,0,maskWidth,maskHeight,rgba);renderer.setRenderTarget(null);effect.root.visible=previousVisibility;shapeReads++;
    const data=new Uint8Array(maskWidth*maskHeight);let left=maskWidth,top=maskHeight,right=-1,bottom=-1;
    for(let y=0;y<maskHeight;y++)for(let x=0;x<maskWidth;x++)if(rgba[((maskHeight-1-y)*maskWidth+x)*4+3]>24){data[y*maskWidth+x]=1;left=Math.min(left,x);right=Math.max(right,x);top=Math.min(top,y);bottom=Math.max(bottom,y);}
    mask={width:maskWidth,height:maskHeight,data};const r=container.getBoundingClientRect();
    if(right>=left&&!switching)body={left:r.left+left/maskWidth*r.width,right:r.left+(right+1)/maskWidth*r.width,top:r.top+top/maskHeight*r.height,bottom:r.top+(bottom+1)/maskHeight*r.height};
    if(body)onShape({mask,body,stage:{x:r.left,y:r.top,width:r.width,height:r.height}});
  }
  function draw(shape=false){if(disposed||contextLost)return;if(shape)updateShape();renderer.render(scene,camera);frames++;}
  function render(time){
    frameHandle=0;if(disposed||contextLost||!visible)return;
    if(time-lastTime<1000/30){frameHandle=requestAnimationFrame(render);return;}
    const delta=Math.min((time-lastTime)/1000,.1);lastTime=time;
    const offset=ambient.tick(time/1000,ambientAllowed&&!interactionBusy&&motionEnabled&&!reduced.matches&&visible&&!switching&&!phase&&currentClip==='reposo');
    orientation.rotation.set(0,baseYaw+offset,0);
    if(motionEnabled&&!reduced.matches&&current&&!switching){current.mixer.update(delta);current.fading=current.fading.filter(f=>{f.time-=delta;if(f.time<=0){if(f.action!==current.active)f.action.stop();return false;}return true;});}
    if(phase){const elapsed=(time-phase.start)/1000;applyFrame(summonFrame(phase.id,elapsed),phase.id,elapsed);if(elapsed>=durations[phase.id])finishPhase();}
    const shape=dirty||(!switching&&time-lastShapeTime>=250);if(shape)lastShapeTime=time;
    draw(shape);dirty=false;
    if(phase||motionEnabled&&!reduced.matches)frameHandle=requestAnimationFrame(render);
  }
  function invalidate(){dirty=true;if(!frameHandle&&visible&&!disposed&&!contextLost)frameHandle=requestAnimationFrame(render);}
  function setYaw(yaw){if(baseYaw===yaw)return;baseYaw=yaw;orientation.rotation.set(0,baseYaw+ambient.angle,0);invalidate();}
  function setAmbientAllowed(value){ambientAllowed=!!value&&!settings.testEffects;}
  function beginInteraction(mode){interactionBusy=true;ambient.hold(performance.now()/1000);if(mode==='rotate'){baseYaw=orientation.rotation.y;ambient.reset(performance.now()/1000);}return baseYaw;}
  function endInteraction(){interactionBusy=false;ambient.hold(performance.now()/1000);}
  function setMotion(enabled){if(enabled===motionEnabled)return;motionEnabled=enabled;if(!enabled){finishPhase();settle();play('reposo',true);current?.mixer.update(0);}invalidate();}
  function resize(){width=container.clientWidth;height=container.clientHeight;camera.aspect=width/height;camera.updateProjectionMatrix();renderer.setPixelRatio(Math.min(devicePixelRatio,1.5));renderer.setSize(width,height);invalidate();}
  function visibility(){visible=!document.hidden;if(!visible){cancelAnimationFrame(frameHandle);frameHandle=0;finishPhase();settle();}else{lastTime=performance.now();invalidate();}}
  function lost(e){e.preventDefault();contextLost=true;cancelAnimationFrame(frameHandle);frameHandle=0;finishPhase();onReady({ok:false,character:current?.id,error:'El controlador gráfico perdió el contexto 3D. Intentaré recuperarlo automáticamente.'});}
  function restored(){contextLost=false;renderer.compileAsync(scene,camera).then(()=>{
    if(disposed)return;settle();
    // A driver reset can happen during the first GLTF upload. Initialization
    // owns that ready event until the model and diagnostics have been installed.
    if(initialized&&current&&!switching)onReady({ok:true,character:current.id,clips:current.actions.size,bones:current.bones.length,phases:phaseHistory.slice(),reducedMotion:reduced.matches});
  }).catch(()=>{if(!disposed)onReady({ok:false,character:current?.id,error:'No pude recuperar el visor 3D. Reabre PokéDesk.'});});}
  window.addEventListener('resize',resize);document.addEventListener('visibilitychange',visibility);reduced.addEventListener('change',()=>{if(reduced.matches){finishPhase();play('reposo',true);}invalidate();});
  renderer.domElement.addEventListener('webglcontextlost',lost);renderer.domElement.addEventListener('webglcontextrestored',restored);
  cameraFor(settings.character);setYaw(settings.yaw??0);lastTime=performance.now();
  await setCharacter(settings.character??'arcanine');
  const diagnostic={
    sample(id){play(id,true);const a=current.actions.get(id);current.mixer.update(.02);scene.updateMatrixWorld(true);const before=current.bones.flatMap(n=>n.matrixWorld.elements);current.mixer.update(a.getClip().duration*.4);scene.updateMatrixWorld(true);const after=current.bones.flatMap(n=>n.matrixWorld.elements);draw(true);return {finite:after.every(Number.isFinite),changes:after.filter((v,i)=>Math.abs(v-before[i])>1e-6).length,duration:a.getClip().duration};},
    rotation(){play('reposo',true);current.mixer.update(.1);setYaw(Math.PI/2);draw(true);const r=container.getBoundingClientRect();let found=false;for(let y=r.top+20;y<r.bottom-20;y+=15)for(let x=r.left+20;x<r.right-20;x+=15)if(hit(x,y))found=true;const gl=renderer.getContext(),px=new Uint8Array(4);gl.readPixels(0,0,1,1,gl.RGBA,gl.UNSIGNED_BYTE,px);const result={horizontalOnly:orientation.rotation.x===0&&orientation.rotation.z===0,hit:found,emptyMiss:!hit(2,2),alpha:px[3]===0};setYaw(0);draw(true);return result;},
    profiles(){const results=[];for(const [id,a]of current.actions)for(const fraction of [0,.25,.5,.75,.99])for(let turn=0;turn<12;turn++){play(id,true);current.mixer.update(a.getClip().duration*fraction);setYaw(turn*Math.PI/6);scene.updateMatrixWorld(true);camera.updateMatrixWorld(true);const b={left:Infinity,top:Infinity,right:-Infinity,bottom:-Infinity};for(const mesh of current.meshes)for(let i=0;i<mesh.geometry.attributes.position.count;i++){mesh.getVertexPosition(i,temp);temp.applyMatrix4(mesh.matrixWorld).project(camera);b.left=Math.min(b.left,(temp.x+1)*width/2);b.right=Math.max(b.right,(temp.x+1)*width/2);b.top=Math.min(b.top,(1-temp.y)*height/2);b.bottom=Math.max(b.bottom,(1-temp.y)*height/2);}results.push({id,fraction,turn,...b,fits:b.left>=6&&b.top>=6&&b.right<=width-6&&b.bottom<=height-6});}play('reposo',true);setYaw(0);draw(true);return {cases:results.length,clipped:results.filter(r=>!r.fits),minMargin:Math.min(...results.flatMap(b=>[b.left,b.top,width-b.right,height-b.bottom]))};},
    info(){return {character:current?.id,visible,contextLost,switching,appearanceVisible:appearance.visible,amount:appearance.scale.x,effectVisible:effect.root.visible,frames,shapeReads,memory:renderer.info.memory,programs:renderer.info.programs?.length,pixelRatio:renderer.getPixelRatio(),phases:phaseHistory.slice(),activeActions:current?[...current.actions.values()].filter(a=>a.isRunning()).length:0};},
    setCharacter,
    async repeatedSwitch(count=characters.length*2){for(let i=0;i<count;i++)await setCharacter(characters[i%characters.length].id);return diagnostic.info();}
  };
  window.petDiagnostics=diagnostic;
  initialized=true;
  return {hit,play,setYaw,setMotion,setCharacter,setAmbientAllowed,beginInteraction,endInteraction,refresh:()=>invalidate(),repeatSummon:async()=>{if(switching)return;switching=true;play('reposo',true);await animate('release');settle();switching=false;},
    get info(){return {ok:true,character:current.id,clips:current.actions.size,bones:current.bones.length,phases:phaseHistory.slice(),reducedMotion:reduced.matches};},
    dispose(){disposed=true;cancelAnimationFrame(frameHandle);finishPhase();window.removeEventListener('resize',resize);document.removeEventListener('visibilitychange',visibility);if(current){current.mixer.stopAllAction();current.mixer.uncacheRoot(current.model);disposeModel(current.model);}effect.dispose();hitTarget.dispose();renderer.dispose();}
  };
}
