const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { defaults, saveNote, filteredNotes, startTimer, remainingTimer, toggleTimer, saveTask, checkReminders, Motion } = require('../src/core.cjs');
const { Store, TokenVault } = require('../src/store.cjs');

test('El timer termina una vez, quita el contador y conserva el tiempo al pausar', () => {
  const s = defaults(); startTimer(s, 5, 1000);
  toggleTimer(s, 61000); assert.equal(s.focus.remaining, 240000);
  assert.equal(remainingTimer(s.focus, 300000), 240000);
  toggleTimer(s, 400000); assert.equal(s.focus.deadline, 640000);
  assert.equal(checkReminders(s, 640000)[0].type, 'focusFinished');
  assert.equal(s.focus, null); assert.deepEqual(checkReminders(s, 640001), []);
});
test('Las notas conservan versiones y categorías equivalentes sin duplicar el historial', () => {
  const s = defaults(), n = saveNote(s, { title: 'Idea', body: 'Uno', category: 'Reunión' }, 100);
  saveNote(s, { id: n.id, title: 'Idea', body: 'Dos', category: 'reunion' }, 200);
  assert.equal(n.category, 'Reunión'); assert.equal(n.revisions[0].body, 'Uno'); assert.equal(n.createdAt, 100);
  saveNote(s, { id: n.id, title: 'Idea', body: 'Dos', category: 'REUNIÓN' }, 300);
  assert.equal(n.revisions.length, 1); assert.equal(filteredNotes(s, { search: 'reunion' }).length, 1);
  n.archived = true; assert.equal(filteredNotes(s).length, 0); assert.equal(filteredNotes(s, { archived: true }).length, 1);
  assert.throws(() => saveNote(s, { body: ' ' }), /Escribe/);
});
test('Los avisos de reuniones conservan enlaces, excluyen todo el día y no se repiten', () => {
  const s = defaults(), now = Date.now();
  s.cache.events = [{ id: 'a', title: 'Equipo', start: now + 5 * 60000, link: 'https://meet.google.com/a' }, { id: 'b', start: now + 5 * 60000, allDay: true }];
  const first = checkReminders(s, now); assert.equal(first.length, 1); assert.equal(first[0].link, 'https://meet.google.com/a');
  assert.deepEqual(checkReminders(s, now + 1000), []);
});
test('Las tareas locales respetan hora, días y completado diario', () => {
  const now = new Date(2026, 9, 8, 9, 4).getTime(), s = defaults();
  saveTask(s, { title: 'Agua', time: '09:00', days: [new Date(now).getDay()] }, now-1000);
  assert.equal(checkReminders(s, now)[0].type, 'task');
  assert.deepEqual(checkReminders(s, now + 1000), []);
  assert.throws(() => saveTask(s, { title: 'Mala', time: '25:00' }), /válida/);
});
test('Un aviso interrumpe los gestos y la celebración pendiente se ejecuta después', () => {
  const m = new Motion(() => 0);
  m.request('caricias', 100); m.request('aviso-reunion', 200); m.request('celebracion', 300);
  assert.equal(m.clip, 'aviso-reunion'); m.tick(4200); assert.equal(m.clip, 'celebracion');
  m.tick(8000); assert.equal(m.clip, 'reposo'); m.setEnabled(false, 9000);
  m.request('sentarse', 10000, true); assert.equal(m.clip, 'reposo');
});
test('Guardado atómico: las notas sobreviven al reinicio y un JSON dañado queda intacto', async t => {
  const folder = await fs.mkdtemp(path.join(os.tmpdir(), 'arcanine-store-')); t.after(() => fs.rm(folder, { recursive: true, force: true }));
  const file = path.join(folder, 'estado.json'), a = new Store(file); await a.load();
  await Promise.all([a.update(s => saveNote(s, { body: 'Primera' })), a.update(s => saveNote(s, { body: 'Segunda' }))]);
  const b = new Store(file); await b.load(); assert.equal(b.state.notes.length, 2);
  await fs.writeFile(file, '{dañado'); const c = new Store(file); await assert.rejects(c.load(), /conservó/);
  assert.equal(await fs.readFile(file, 'utf8'), '{dañado');
});
test('El almacén seguro nunca guarda tokens en texto plano cuando no hay cifrado disponible', async t => {
  const folder = await fs.mkdtemp(path.join(os.tmpdir(), 'arcanine-vault-')); t.after(() => fs.rm(folder, { recursive: true, force: true }));
  const file = path.join(folder, 'tokens.enc');
  const v = new TokenVault(file, { isAsyncEncryptionAvailable: async () => false });
  await assert.rejects(v.write({ refresh_token: 'private' }), /segura/);
  await assert.rejects(fs.access(file));
});
