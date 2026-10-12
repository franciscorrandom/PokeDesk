'use strict';
const { randomUUID } = require('node:crypto');

const CHARACTERS = require('./renderer/characters.json');
const CLIPS = CHARACTERS[0].clips;
const character = id => CHARACTERS.find(c => c.id === id) ?? CHARACTERS[0];

const clean = (value, max = 1000) => String(value ?? '').trim().slice(0, max);
const fold = value => clean(value).normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
const dayKey = time => {
  const d = new Date(time);
  return [d.getFullYear(), String(d.getMonth() + 1).padStart(2, '0'), String(d.getDate()).padStart(2, '0')].join('-');
};
function defaults() {
  return {
    version: 1, notes: [], tasks: [], focus: null, reminders: {}, snoozes: [],
    settings: { name: '', voice: 'Gracie', sound: true, volume: 0.8, motion: true, leadMinutes: 10, yaw: 0, petPosition: null, autoStart: false, character: 'arcanine', characterYaws: {}, petScale: 1, pausedUntil: null },
    feeds: [],
    cache: { calendars: [], taskLists: [], events: [], tasks: [], updatedAt: null }
  };
}
function validateState(input) {
  if (!input || input.version !== 1 || !Array.isArray(input.notes) || !Array.isArray(input.tasks)) throw new Error('El archivo de datos no tiene un formato compatible.');
  const base = defaults();
  const result={ ...base, ...input, settings: { ...base.settings, ...input.settings }, feeds: Array.isArray(input.feeds) ? input.feeds : [], cache: base.cache };
  if(!result.notes.every(n=>n && typeof n.body==='string' && Array.isArray(n.revisions)) || !result.tasks.every(t=>t && typeof t.title==='string' && Array.isArray(t.days) && Array.isArray(t.completedDays)))throw new Error('Los datos guardados no tienen un formato compatible.');
  result.snoozes=Array.isArray(result.snoozes)?result.snoozes:[];
  result.settings.character=character(result.settings.character).id;
  result.settings.petScale=Number.isFinite(result.settings.petScale)?Math.max(.7,Math.min(1.4,result.settings.petScale)):1;
  result.settings.yaw=Number.isFinite(result.settings.yaw)?result.settings.yaw:0;
  result.settings.characterYaws=result.settings.characterYaws&&typeof result.settings.characterYaws==='object'?result.settings.characterYaws:{};
  return result;
}
function categoryFor(notes, value) {
  const candidate = clean(value, 64).replace(/\s+/g, ' ');
  return notes.find(n => fold(n.category) === fold(candidate))?.category ?? candidate;
}
function saveNote(state, draft, now = Date.now()) {
  const body = clean(draft.body, 20000);
  if (!body) throw new Error('Escribe algo en la nota antes de guardarla.');
  const category = categoryFor(state.notes, draft.category);
  const title = clean(draft.title, 160);
  if (draft.id) {
    const note = state.notes.find(n => n.id === draft.id);
    if (!note) throw new Error('La nota ya no está disponible.');
    if (note.body === body && note.title === title && note.category === category) return note;
    note.revisions.push({ title: note.title, body: note.body, category: note.category, savedAt: note.updatedAt });
    Object.assign(note, { title, body, category, updatedAt: now });
    return note;
  }
  const note = { id: randomUUID(), title, body, category, createdAt: now, updatedAt: now, archived: false, revisions: [] };
  state.notes.unshift(note);
  return note;
}
function filteredNotes(state, { search = '', category = '', archived = false } = {}) {
  return state.notes.filter(n => n.archived === archived && (!category || fold(n.category) === fold(category)) &&
    fold([n.title, n.body, n.category].join(' ')).includes(fold(search))).sort((a, b) => b.updatedAt - a.updatedAt);
}
function startTimer(state, minutes, now = Date.now()) {
  if (!Number.isFinite(minutes) || minutes < 1 || minutes > 180) throw new Error('El timer debe durar entre 1 y 180 minutos.');
  state.focus = { id: randomUUID(), duration: minutes * 60000, deadline: now + minutes * 60000, paused: false, remaining: minutes * 60000 };
}
function remainingTimer(focus, now = Date.now()) {
  return focus ? Math.max(0, focus.paused ? focus.remaining : focus.deadline - now) : 0;
}
function toggleTimer(state, now = Date.now()) {
  if (!state.focus) return;
  const f = state.focus;
  if (f.paused) { f.deadline = now + f.remaining; f.paused = false; }
  else { f.remaining = remainingTimer(f, now); f.paused = true; }
}
function saveTask(state, draft, now = Date.now()) {
  const title = clean(draft.title, 200);
  if (!title || !/^([01]\d|2[0-3]):[0-5]\d$/.test(draft.time ?? '')) throw new Error('Indica un título y una hora válida.');
  const days = [...new Set(draft.days ?? [0, 1, 2, 3, 4, 5, 6])].filter(d => Number.isInteger(d) && d >= 0 && d <= 6);
  if (!days.length) throw new Error('Selecciona al menos un día.');
  const task = { id: randomUUID(), title, time: draft.time, days, completedDays: [], repeat: draft.repeat !== false, createdAt: now, completedAt: null };
  state.tasks.push(task);
  return task;
}
function checkReminders(state, now = Date.now()) {
  const notices = [], today = dayKey(now), date = new Date(now);
  if (state.focus && !state.focus.paused && remainingTimer(state.focus, now) === 0) {
    state.focus = null;
    notices.push({ id: randomUUID(), type: 'focusFinished', title: '¡Buen trabajo!', body: 'Tu sesión de concentración terminó. Es hora de descansar.' });
  }
  if (state.settings.pausedUntil > now) return notices;
  for (const e of state.cache.events) {
    if (e.allDay || !Number.isFinite(e.start)) continue;
    const key = 'meeting:' + e.id + ':' + e.start;
    const due = e.start - state.settings.leadMinutes * 60000;
    if (now >= due && now < e.start + 60000 && !state.reminders[key]) {
      state.reminders[key] = now;
      notices.push({ id: key, type: 'meeting', title: e.title, body: 'Comienza a las ' + new Date(e.start).toLocaleTimeString('es', { hour: '2-digit', minute: '2-digit' }), link: e.link, start: e.start });
    }
  }
  for (const t of state.tasks) {
    if (t.repeat === false ? t.completedAt != null : !t.days.includes(date.getDay()) || t.completedDays.includes(today)) continue;
    const [h, m] = t.time.split(':').map(Number), due = new Date(date);
    if (t.repeat === false) due.setTime(t.createdAt);
    due.setHours(h, m, 0, 0);
    const key = 'task:' + t.id + ':' + (t.repeat === false ? 'once' : today);
    if (now >= due.getTime() && now >= (t.createdAt ?? 0) && !state.reminders[key]) {
      state.reminders[key] = now;
      notices.push({ id: key, type: 'task', title: t.title, body: 'Tu recordatorio de las ' + t.time });
    }
  }
  // Keep a week of acknowledgements so a wake-up cannot repeat the same reminder.
  for (const [key, timestamp] of Object.entries(state.reminders)) if (timestamp < now - 8 * 86400000) delete state.reminders[key];
  return notices;
}
class Motion {
  constructor(random = Math.random) { this.random = random; this.clip = 'reposo'; this.startedAt = 0; this.nextAt = 18000; this.last = ''; this.revision = 0; this.pending = null; this.enabled = true; this.character = 'arcanine'; this.focusing = false; this.alerting = false; this.lastChase = -Infinity; }
  setCharacter(id, now) { this.character = character(id).id; this.clip = 'reposo'; this.startedAt = now; this.pending = null; this.last = ''; this.nextAt = now + 18000; this.revision++; }
  priority(id) { return id === 'aviso-reunion' ? 3 : id === 'celebracion' ? 2 : id === 'reposo' ? 0 : 1; }
  request(id, now, manual = false) {
    if (!character(this.character).clips.some(c => c.id === id)) throw new Error('Animación desconocida.');
    if (!this.enabled) return;
    if (!manual && this.priority(id) < this.priority(this.clip)) { if (id === 'celebracion') this.pending = id; return; }
    if (!manual && id === 'giro-rapido' && (this.focusing || now - this.lastChase < 180000)) return;
    this.clip = id; this.startedAt = now; this.revision++;
    if (id !== 'reposo') this.last = id;
    if (id === 'giro-rapido') this.lastChase = now;
    this.nextAt = now + character(this.character).clips.find(c => c.id === id).duration * 1000 + (this.focusing ? 75000 + this.random() * 35000 : 18000 + this.random() * 17000);
  }
  setEnabled(enabled, now) { if (this.enabled !== enabled) { this.enabled = enabled; this.clip = 'reposo'; this.startedAt = now; this.pending = null; this.revision++; } }
  choose(ids, now) { const valid = new Set(character(this.character).clips.map(c => c.id)); const choices = ids.filter(id => id !== this.last && valid.has(id)); if (!choices.length) return; this.request(choices[Math.floor(this.random() * choices.length)], now); }
  click(now) { this.choose(['curiosidad', 'saludo', 'cola-alegre', 'olfateo', 'estiramiento'], now); }
  tick(now) {
    if (!this.enabled) return;
    if (this.clip !== 'reposo' && now - this.startedAt >= character(this.character).clips.find(c => c.id === this.clip).duration * 1000) {
      const next = this.pending ?? 'reposo'; this.pending = null; this.request(next, now, true);
    }
    if (this.clip === 'reposo' && now >= this.nextAt && !this.alerting) this.choose(this.focusing ? ['curiosidad', 'olfateo'] : ['curiosidad', 'cola-alegre', 'olfateo', 'estiramiento'], now);
  }
}
module.exports = { CHARACTERS, character, CLIPS, defaults, validateState, clean, fold, dayKey, saveNote, filteredNotes, startTimer, remainingTimer, toggleTimer, saveTask, checkReminders, Motion };
