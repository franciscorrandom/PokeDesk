const test = require('node:test');
const assert = require('node:assert/strict');
test('La presentación completa del panel no mantiene pausado el giro cuando el panel está cerrado', async () => {
  const {ambientRotationAllowed} = await import('../src/renderer/ambient.mjs');
  const state={settings:{ambientRotation:true},fullPanel:true,panelOpen:false,menuOpen:false,notice:null,focus:null,smokeTest:false};
  assert.equal(ambientRotationAllowed(state),true);
  for(const patch of [{panelOpen:true},{menuOpen:true},{notice:{}},{focus:{paused:false}},{smokeTest:true},{settings:{ambientRotation:false}}])assert.equal(ambientRotationAllowed({...state,...patch}),false);
  assert.equal(ambientRotationAllowed({...state,focus:{paused:true}}),true);
});
test('Giro frontal de ocho minutos, sin acelerones y limitado a 25 grados por lado', async () => {
  const {AmbientRotation} = await import('../src/renderer/ambient.mjs');
  const a = new AmbientRotation(); assert.equal(a.tick(0,true),0);
  let min=0,max=0,last=0;
  for(let i=1;i<=14400;i++) {const angle=a.tick(i/30,true);assert.ok(Math.abs(angle-last)<.00020);min=Math.min(min,angle);max=Math.max(max,angle);last=angle;}
  assert.ok(Math.abs(min+AmbientRotation.amplitude)<.00001);assert.ok(Math.abs(max-AmbientRotation.amplitude)<.00001);assert.ok(Math.abs(last)<.00001);
});
test('Pausa en foco, menús, gestos y movimiento reducido; no salta al volver de suspensión', async () => {
  const {AmbientRotation} = await import('../src/renderer/ambient.mjs');
  const a = new AmbientRotation();a.tick(0,true);const held=a.tick(.1,true);
  for(let i=1;i<=100;i++) assert.equal(a.tick(i,false),held);
  a.hold(100);assert.equal(a.tick(110,true),held);
  a.reset(120);assert.equal(a.angle,0);assert.equal(a.tick(130,true),0);
  assert.equal(a.tick(NaN,true),0);assert.ok(Math.abs(a.tick(10000,true))<.001);
});
test('La preferencia nueva conserva datos anteriores y el rechazo explícito', () => {
  const {defaults,validateState}=require('../src/core.cjs');
  const legacy=defaults();delete legacy.settings.ambientRotation;
  assert.equal(validateState(legacy).settings.ambientRotation,true);
  legacy.settings.ambientRotation=false;assert.equal(validateState(legacy).settings.ambientRotation,false);
});
