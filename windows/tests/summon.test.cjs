const test=require('node:test'),assert=require('node:assert/strict');
const {defaults,Motion,CHARACTERS}=require('../src/core.cjs');
test('La Pokébola oculta al entrante desde el primer fotograma y termina en valores exactos',async()=>{
  const {summonFrame,durations}=await import('../src/renderer/summon.mjs');
  assert.equal(summonFrame('release',0).petOpacity,0);assert.equal(summonFrame('release',.77).petAmount,0);
  const end=summonFrame('release',durations.release);assert.equal(end.petAmount,1);assert.equal(end.petOpacity,1);assert.equal(end.ballOpacity,0);assert.equal(end.whiten,0);
  const recall=summonFrame('recall',durations.recall);assert.equal(recall.petOpacity,0);assert.equal(recall.petAmount,0);assert.equal(recall.ballOpacity,0);
  for(const phase of ['release','recall'])for(let i=0;i<200;i++)for(const value of Object.values(summonFrame(phase,i*.02)))assert.ok(Number.isFinite(value));
});
test('Cada Pokémon conserva su repertorio; reposo y gestos automáticos nunca piden un clip ausente',()=>{
  const m=new Motion(()=>.5);
  for(const c of CHARACTERS){m.setCharacter(c.id,0);assert.equal(c.clips.length,c.id==='arcanine'?11:9);for(let i=0;i<150;i++){m.click(i*20000);assert.ok(c.clips.some(c=>c.id===m.clip));m.tick(i*20000+10000);}assert.equal(m.character,c.id);}
  const s=defaults();assert.equal(s.settings.character,'arcanine');assert.deepEqual(s.feeds,[]);
});
