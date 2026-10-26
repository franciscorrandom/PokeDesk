import * as THREE from 'three';
export function createPokeball() {
  const root=new THREE.Group(),ball=new THREE.Group();root.add(ball);root.visible=false;
  const white=new THREE.MeshStandardMaterial({color:0xf5f8ff,roughness:.25}),red=new THREE.MeshStandardMaterial({color:0xee2537,roughness:.25}),black=new THREE.MeshStandardMaterial({color:0x161922,roughness:.5});
  const lower=new THREE.Mesh(new THREE.SphereGeometry(.19,32,16,0,Math.PI*2,Math.PI/2,Math.PI/2),white);ball.add(lower);
  const hinge=new THREE.Group();hinge.position.set(0,0,-.19);ball.add(hinge);
  const upper=new THREE.Mesh(new THREE.SphereGeometry(.19,32,16,0,Math.PI*2,0,Math.PI/2),red);upper.position.z=.19;hinge.add(upper);
  const seam=new THREE.Mesh(new THREE.TorusGeometry(.19,.018,8,32),black);seam.rotation.x=Math.PI/2;ball.add(seam);
  const button=new THREE.Mesh(new THREE.CylinderGeometry(.055,.055,.032,24),white);button.rotation.x=Math.PI/2;button.position.z=.20;ball.add(button);
  const rim=new THREE.Mesh(new THREE.TorusGeometry(.062,.013,8,24),black);rim.position.z=.205;ball.add(rim);
  const energy=new THREE.Color(0x1686ff);
  const haloMaterial=new THREE.ShaderMaterial({transparent:true,depthWrite:false,side:THREE.DoubleSide,uniforms:{energy:{value:energy},amount:{value:0}},vertexShader:'varying vec2 p; void main(){p=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);}',fragmentShader:'varying vec2 p;uniform vec3 energy;uniform float amount;void main(){float d=length((p-.5)*2.0);float a=(1.0-smoothstep(.10,1.0,d))*amount*.86;vec3 c=mix(energy,vec3(1.0),1.0-smoothstep(.0,.23,d));gl_FragColor=vec4(c,a);}'});
  const halo=new THREE.Mesh(new THREE.PlaneGeometry(1.25,1.25),haloMaterial);root.add(halo);
  const beamMaterial=new THREE.MeshBasicMaterial({color:energy,transparent:true,opacity:0,depthWrite:false,side:THREE.DoubleSide});
  const beam=new THREE.Mesh(new THREE.CylinderGeometry(.035,.13,1,20,1,true),beamMaterial);root.add(beam);
  const coreMaterial=new THREE.MeshBasicMaterial({color:0xf4faff,transparent:true,opacity:0,depthWrite:false});
  const core=new THREE.Mesh(new THREE.SphereGeometry(.09,16,12),coreMaterial);root.add(core);
  const sparks=new THREE.Group();root.add(sparks);
  const sparkMaterial=new THREE.MeshBasicMaterial({color:energy,transparent:true,opacity:0,depthWrite:false});
  for(let i=0;i<14;i++){const s=new THREE.Mesh(new THREE.SphereGeometry(.017,6,4),sparkMaterial);s.userData.angle=i*Math.PI*2/14;sparks.add(s);}
  const from=new THREE.Vector3(.62,.20,.50),to=new THREE.Vector3(0,1.1,0),direction=to.clone().sub(from);
  function frame(f,phase,time,camera) {
    root.visible=f.ballOpacity>0||f.glow>0;
    energy.set(phase==='recall'?0xff2748:0x1686ff);
    ball.position.copy(from);ball.position.y+=f.ballLift;hinge.rotation.x=-f.lidOpen*1.65;
    for(const m of [white,red,black]){m.transparent=true;m.opacity=f.ballOpacity;}
    beam.position.copy(from).lerp(to,.5);beam.quaternion.setFromUnitVectors(new THREE.Vector3(0,1,0),direction.clone().normalize());beam.scale.y=direction.length();beamMaterial.color.copy(energy);beamMaterial.opacity=f.beam*.72;
    core.position.copy(from);core.position.y+=.04;coreMaterial.opacity=f.glow;
    halo.position.copy(from).lerp(to,.62);halo.quaternion.copy(camera.quaternion);haloMaterial.uniforms.amount.value=f.glow;
    sparkMaterial.color.copy(energy);sparkMaterial.opacity=f.sparks*.95;
    for(const s of sparks.children){const a=s.userData.angle+time*.8,rad=.25+.45*f.sparks;s.position.set(to.x+Math.cos(a)*rad,to.y+Math.sin(a)*rad,to.z+.08*Math.sin(a*3));}
  }
  function dispose(){const geometries=new Set(),materials=new Set();root.traverse(n=>{if(n.geometry)geometries.add(n.geometry);if(n.material)materials.add(n.material);});for(const g of geometries)g.dispose();for(const m of materials)m.dispose();}
  return {root,frame,hide:()=>{root.visible=false;},dispose};
}
