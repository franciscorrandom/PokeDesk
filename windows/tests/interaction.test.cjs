const test = require('node:test');
const assert = require('node:assert/strict');
const { Interaction } = require('../src/interaction.cjs');
const geometry = import('../src/renderer/geometry.mjs');

test('Mover, girar, acariciar y pulsar botones conservan los clics durante 1000 ciclos', () => {
  const i = new Interaction(), bounds = { x: -300, y: 200, width: 620, height: 520 };
  let changes = 0;
  for (let n = 0; n < 1000; n++) {
    const mode = ['move', 'rotate', 'pet', 'control'][n % 4];
    i.begin(mode, { x: -40, y: 460 }, bounds, 0.3, n * 100);
    i.updateIgnored(i.shouldIgnore(false), () => changes++);
    assert.equal(i.ignored, false); // Even stale/off-character masks cannot disable a held gesture.
    const step = i.step({ x: 10, y: 485 }, n * 100 + 10);
    if (mode === 'move') assert.equal(step.bounds.x, -250);
    if (mode === 'rotate') assert.ok(Math.abs(step.yaw - 0.9) < 1e-9);
    if (mode === 'pet') { assert.equal(step.pet, true); assert.equal(i.step({ x: 11, y: 485 }, n * 100 + 15).pet, undefined); }
    if (mode === 'control') assert.deepEqual(step, {});
    assert.equal(i.end(n % 7 === 0).click, false);
    i.updateIgnored(i.shouldIgnore(false), () => changes++);
    assert.equal(i.ignored, true);
    i.updateIgnored(i.shouldIgnore(true), () => changes++);
    assert.equal(i.ignored, false); assert.equal(i.gesture, null);
  }
  assert.ok(changes > 1000);
});
test('Un clic abre el menú; cancelación o pérdida de captura no produce un clic accidental', () => {
  const i = new Interaction();
  i.begin('move', { x: 100, y: 100 }, {}, 0, 0); i.step({ x: 103, y: 100 }, 100);
  assert.equal(i.end().click, true);
  i.begin('rotate', { x: 100, y: 100 }, {}, 0, 0); assert.equal(i.end(true).click, false);
  assert.equal(i.end(), null);
  i.begin('move', { x: 100, y: 100 }, {}, 0, 0);
  assert.equal(i.step({ x: 100, y: 100 }, 16000).cancelled, true);
  assert.equal(i.shouldIgnore(true), false);
});
test('Silueta y botones funcionan con escalas 100, 125, 150 y 200 por ciento y monitores con coordenadas negativas', async () => {
  const { shapeHit } = await geometry;
  const data = new Uint8Array(8208); data[38 * 108 + 54] = 1;
  const shape = { viewport: { width: 620, height: 520 }, stage: { x: 94, y: 184, width: 432, height: 304 }, mask: { width: 108, height: 76, data }, controls: [{ left: 50, top: 40, right: 100, bottom: 80 }] };
  for (const scale of [1, 1.25, 1.5, 2]) {
    const b = { x: -1200, y: -100, width: 620, height: 520 };
    const nativeDip = (x, y) => ({ x: (b.x * scale + x * scale) / scale, y: (b.y * scale + y * scale) / scale });
    assert.equal(shapeHit(shape, nativeDip(310, 336), b), true);
    assert.equal(shapeHit(shape, nativeDip(75, 50), b), true);
    assert.equal(shapeHit(shape, nativeDip(10, 10), b), false);
    assert.equal(shapeHit(shape, nativeDip(500, 350), b), false);
  }
});
test('Menú y timer se anclan a la silueta; los bordes de cada monitor mantienen visible el conjunto', async () => {
  const { attachments, visibleBounds, fitVisibleWindow, DEFAULT_BODY } = await geometry;
  const body = DEFAULT_BODY, anchor = attachments(body);
  assert.equal(anchor.timer.y - body.bottom, 4);
  assert.equal(anchor.timer.x, (body.left + body.right) / 2);
  assert.equal(anchor.arc.y + 188, body.top);
  for (const workArea of [{ x: 0, y: 0, width: 1920, height: 1080 }, { x: -1280, y: -150, width: 1280, height: 720 }]) {
    for (const menu of [false, true]) for (const x of [workArea.x - 200, workArea.x + workArea.width]) for (const y of [workArea.y - 300, workArea.y + workArea.height]) {
      const visible = visibleBounds(body, menu, true);
      const b = fitVisibleWindow({ x, y, width: 620, height: 520 }, visible, workArea);
      assert.ok(b.x + visible.left >= workArea.x + 7);
      assert.ok(b.x + visible.right <= workArea.x + workArea.width - 7);
      assert.ok(b.y + visible.top >= workArea.y + 7);
      assert.ok(b.y + visible.bottom <= workArea.y + workArea.height - 7);
    }
  }
});
test('La actualización conserva el centro y la base de la antigua posición', async () => {
  const { migratePosition } = await geometry;
  const old = { x: 500, y: 200, width: 252, height: 288 }, next = migratePosition(old, {});
  assert.equal(old.x + old.width / 2, next.x + next.width / 2);
  assert.equal(old.y + old.height, next.y + next.height);
});
test('La posición guardada no deriva al reiniciar con un tamaño personalizado',async()=>{
  const {restorePosition}=await geometry,area={x:-1920,y:0,width:1920,height:1080};
  for(const scale of [.7,1,1.25,1.4]){
    let saved={x:-600,y:300,width:Math.round(620*scale),height:Math.round(520*scale)};
    for(let restart=0;restart<10;restart++)saved=restorePosition(saved,area,scale);
    assert.equal(saved.x,-600);assert.equal(saved.y,300);assert.equal(saved.width,Math.round(620*scale));
  }
});
test('Con escalado alto, la figura, el menú y el timer caben incluso en una pantalla pequeña',async()=>{
  const {fitSurface,visibleBounds,DEFAULT_BODY,restorePosition}=await geometry;
  const visible=visibleBounds(DEFAULT_BODY,true,true);
  for(const area of [{x:0,y:0,width:960,height:500},{x:-800,y:-100,width:800,height:340}]) {
    const b=fitSurface({x:area.x+800,y:area.y+300,width:868,height:728},visible,area),sx=b.width/620,sy=b.height/520;
    assert.ok(b.x+visible.left*sx>=area.x+7);assert.ok(b.x+visible.right*sx<=area.x+area.width-7);
    assert.ok(b.y+visible.top*sy>=area.y+7);assert.ok(b.y+visible.bottom*sy<=area.y+area.height-7);
    assert.equal(restorePosition(b,area,1.4).width,b.width);
  }
});
