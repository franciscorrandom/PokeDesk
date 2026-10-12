'use strict';
const { app, BrowserWindow, ipcMain, protocol, screen, Tray, Menu, dialog, shell, safeStorage, powerMonitor, nativeImage } = require('electron');
const path = require('node:path');
const fs = require('node:fs/promises');
const { createHash } = require('node:crypto');
const { Store, TokenVault } = require('./store.cjs');
const { Calendars } = require('./calendar.cjs');
const { CHARACTERS, character, CLIPS, saveNote, startTimer, toggleTimer, remainingTimer, saveTask, dayKey, checkReminders, Motion } = require('./core.cjs');
const { Interaction } = require('./interaction.cjs');

const root = path.resolve(__dirname, '..'), smoke = process.argv.includes('--smoke-test');
const interactiveDemo = process.argv.includes('--demo');
app.setName('PokeDesk');
const previewProfiles = app.isPackaged ? path.join(app.getPath('temp'), 'pokedesk-desktop-preview') : path.join(root, '.build');
const diagnosticsRoot = app.isPackaged ? path.join(previewProfiles, 'verification') : path.join(root, '.build');
app.setPath('userData', smoke || interactiveDemo ? path.join(previewProfiles, smoke ? 'smoke-profile' : 'demo-profile') :
  path.join(app.getPath('appData'), process.platform === 'darwin' ? 'PokeDesk Windows Preview' : 'PokeDesk'));
if (smoke) require('node:fs').rmSync(app.getPath('userData'), { recursive: true, force: true });
app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required');
protocol.registerSchemesAsPrivileged([{ scheme: 'pokedesk', privileges: { standard: true, secure: true, supportFetchAPI: true, stream: true, corsEnabled: true } }]);
const windows = new Map(), ready = new Map(), motion = new Motion();
const interaction = new Interaction();
let geometry, menuOpen = false, panelFull=true;
let store, calendars, tray, calendarStatus = {syncing:false, errors:[]}, characterLoading = true, section = 'home', yaw = 0, timerTick, cursorTick, nextSync = 0, syncing = false, syncFailures = 0;
let noticeActionBusy=false;
let notices = [], error = '', petVisible = true, lastMotionRevision = -1;
const logs = [], smokeResults = {};
function record(message) { logs.push(message); if (smoke || process.env.POKEDESK_DIAGNOSTICS === '1') console.log(message); }
function ownWindow(sender) { return [...windows.values()].find(w => !w.isDestroyed() && w.webContents === sender); }
function viewOf(sender) { for (const [view, w] of windows) if (w.webContents === sender) return view; return ''; }
function sendAll(event, value) { for (const [view,w] of windows) if (!w.isDestroyed() && (view==='pet' || w.isVisible())) w.webContents.send(event, value); }
function snapshot() {
  return { ...structuredClone(store.state), now: Date.now(), remaining: remainingTimer(store.state.focus), section, calendarStatus: {...calendarStatus, syncing}, clips: character(store.state.settings.character).clips, characters: CHARACTERS, characterLoading,
    motion: { clip: motion.clip, revision: motion.revision, enabled: motion.enabled }, notice: notices[0] ?? null, noticeCount: notices.length,
    error, menuOpen, fullPanel:panelFull, version: app.getVersion(), platform: process.platform, demo: smoke || interactiveDemo, smokeTest:smoke };
}
function broadcast() { sendAll('state', snapshot()); }
async function mutate(fn) { const result = await store.update(fn); error = ''; broadcast(); return result; }
function clampWindow(bounds, display = screen.getDisplayMatching(bounds)) {
  const a = display.workArea;
  return { ...bounds, x: Math.round(Math.max(a.x + 8, Math.min(bounds.x, a.x + a.width - bounds.width - 8))), y: Math.round(Math.max(a.y + 8, Math.min(bounds.y, a.y + a.height - bounds.height - 8))) };
}
function placeMenus() {
  const p = windows.get('pet'); if (!p || p.isDestroyed()) return;
  const b = p.getContentBounds(), rawBody = interaction.shape?.body ?? geometry.DEFAULT_BODY, k=b.width/geometry.PET_SIZE.width;
  const body=Object.fromEntries(Object.entries(rawBody).map(([name,value])=>[name,value*k]));
  const a = screen.getDisplayNearestPoint({ x: Math.round(b.x + (body.left + body.right) / 2), y: Math.round(b.y + body.bottom) }).workArea;
  const local = geometry.attachments(rawBody).arc;
  const arc = { x: b.x + local.x*k, y: b.y + local.y*k, width: local.width*k, height: local.height*k };
  const detail = panelFull?null:windows.get('dashboard');
  if (detail) {
    const height = Math.min(438,a.height-16), width = Math.min(370,a.width-16);
    let y = arc.y - height - 10, x = b.x + (body.left + body.right) / 2 - width / 2;
    if (y < a.y + 8) { y = Math.max(a.y + 8, b.y + body.top - 110); x = b.x + body.left - width - 12; if (x < a.x) x = b.x + body.right + 12; }
    detail.setBounds(clampWindow({ x, y, width, height }, { workArea: a }));
  }
  windows.get('notice')?.setBounds(clampWindow({ x: b.x + (body.left + body.right) / 2 - 178, y: b.y + body.top - 178, width: 356, height: 170 }, { workArea: a }));
}
function closeMenus() { menuOpen = false; if(!panelFull)windows.get('dashboard')?.hide(); broadcast(); }
function fitPet(bounds = windows.get('pet').getBounds(), point = null) {
  const body = interaction.shape?.body ?? geometry.DEFAULT_BODY;
  const visible = geometry.visibleBounds(body, menuOpen, !!store.state.focus);
  const scale=bounds.width/geometry.PET_SIZE.width;
  const display = point ? screen.getDisplayNearestPoint(point) : screen.getDisplayNearestPoint({ x: Math.round(bounds.x + (body.left + body.right) / 2*scale), y: Math.round(bounds.y + body.bottom*scale) });
  return geometry.fitSurface(bounds, visible, display.workArea);
}
function resizePet() {
  interaction.end(true); const w=windows.get('pet'),b=w.getBounds(),scale=store.state.settings.petScale;
  w.webContents.send('gesture-cancelled');w.webContents.setZoomFactor(scale);
  setPetBounds(fitPet({x:Math.round(b.x+b.width/2-geometry.PET_SIZE.width*scale/2),y:Math.round(b.y+b.height-geometry.PET_SIZE.height*scale),width:Math.round(geometry.PET_SIZE.width*scale),height:Math.round(geometry.PET_SIZE.height*scale)}));
}
function setPetBounds(bounds) {
  const w = windows.get('pet'), old = w.getBounds();
  if(bounds.width!==old.width||bounds.height!==old.height){
    w.webContents.setZoomFactor(bounds.width/geometry.PET_SIZE.width);
    if(interaction.gesture){interaction.gesture.bounds.width=bounds.width;interaction.gesture.bounds.height=bounds.height;}
  }
  if (bounds.x !== old.x || bounds.y !== old.y || bounds.width !== old.width || bounds.height !== old.height) w.setBounds(bounds);
  placeMenus();
}
function setInputEnabled(enabled) {
  const w = windows.get('pet');
  interaction.updateIgnored(!enabled, ignore => w.setIgnoreMouseEvents(ignore, { forward: true }));
}
function updateNativePointer(point) {
  const w = windows.get('pet'); if (!w?.isVisible()) return;
  const step = interaction.step(point);
  if (step?.bounds) setPetBounds(fitPet(step.bounds, point));
  if (Number.isFinite(step?.yaw)) {
    yaw = ((step.yaw + Math.PI) % (2 * Math.PI) + 2 * Math.PI) % (2 * Math.PI) - Math.PI;
    store.state.settings.yaw = yaw;
    w.webContents.send('orientation', yaw);
  }
  if (step?.pet && !characterLoading) { motion.request('caricias', Date.now(), true); broadcast(); }
  if (step?.cancelled) w.webContents.send('gesture-cancelled');
  const hit = geometry.shapeHit(interaction.shape, point, w.getContentBounds());
  setInputEnabled(!interaction.shouldIgnore(hit));
}
async function finishNativeGesture(cancelled = false) {
  const end = interaction.end(cancelled);
  if (!end) return;
  if (end.moved && (end.mode === 'rotate' || end.mode === 'move')) await mutate(s => {
    if (end.mode === 'rotate') s.settings.yaw = yaw; s.settings.characterYaws[s.settings.character]=yaw;
    s.settings.petPosition = windows.get('pet').getBounds();
  });
  if (end.click) await execute(end.mode === 'pet' ? 'pet' : 'toggleMenu');
  updateNativePointer(screen.getCursorScreenPoint());
}
function createWindow(view, width, height, { focusable = true } = {}) {
  const existing = windows.get(view); if (existing && !existing.isDestroyed()) return existing;
  const win = new BrowserWindow({ width, height, frame: false, transparent: true, backgroundColor: '#00000000',
    alwaysOnTop: true, skipTaskbar: true, resizable: false, maximizable: false, fullscreenable: false, hasShadow: false, show: false, focusable,
    title: 'PokéDesk', webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, sandbox: true, nodeIntegration: false, webSecurity: true, zoomFactor: 1, backgroundThrottling: view !== 'pet' } });
  windows.set(view, win);
  if (process.platform === 'win32') win.setMenu(null);
  win.setAlwaysOnTop(true, 'floating');
  win.webContents.setZoomFactor(view === 'pet' ? store.state.settings.petScale : 1);
  win.webContents.setVisualZoomLevelLimits(1, 1);
  win.webContents.on('zoom-changed', () => win.webContents.setZoomFactor(view === 'pet' ? win.getContentBounds().width/geometry.PET_SIZE.width : 1));
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('will-navigate', (e, url) => { if (!url.startsWith('pokedesk://app/')) e.preventDefault(); });
  win.webContents.on('console-message', (details, level, message) => { if (details.level === 'error' || level === 3) record(view + ': ' + (details.message ?? message)); });
  win.webContents.on('did-fail-load', (_event, code, description) => record(view + ': carga fallida ' + code + ' ' + description));
  win.webContents.on('preload-error', (_event, file, e) => record(view + ': preload ' + e.message));
  win.webContents.on('render-process-gone', (_e, details) => { error = 'Se cerró la vista ' + view + ' (' + details.reason + '). Reinicia PokeDesk.'; record(error); });
  win.webContents.on('before-input-event', (event, input) => {
    if ((input.control || input.meta) && ['+', '-', '=', '0'].includes(input.key)) event.preventDefault();
    if (input.key === 'Escape') { closeMenus(); if (view === 'dashboard') win.hide(); finishNativeGesture(true).catch(showError); }
  });
  if (view === 'dashboard') win.on('blur', () => setTimeout(() => {
    const focused = BrowserWindow.getFocusedWindow();
    if (!panelFull && (!focused || ![...windows.values()].includes(focused))) win.hide();
  }, 160));
  win.on('closed', () => { windows.delete(view); ready.delete(view); });
  if (view === 'pet') win.on('move', () => placeMenus());
  win.loadURL('pokedesk://app/app/index.html?view=' + view).catch(e => record(view + ': ' + e.message));
  return win;
}
async function showSection(value, full = false) {
  const sections = ['home', 'agenda', 'tasks', 'focus', 'animations', 'notes', 'settings', 'characters'];
  if (!sections.includes(value)) throw new Error('Sección desconocida.');
  section = value; panelFull=full;
  const win = createWindow('dashboard', full ? 440 : 370, full ? 742 : 438);
  if (full) {
    closeMenus();
    const a = screen.getPrimaryDisplay().workArea;
    win.setBounds(clampWindow({ x: a.x + a.width / 2 - 220, y: a.y + a.height / 2 - 371, width: 440, height: Math.min(742, a.height - 16) }));
  } else placeMenus();
  win.show(); broadcast(); win.focus();
}
function updateTray() {
  if (!tray) return;
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: 'Abrir PokeDesk', click: () => showSection('home', true) },
    { label: petVisible ? 'Ocultar mascota' : 'Mostrar mascota', click: () => { petVisible = !petVisible; petVisible ? windows.get('pet').showInactive() : windows.get('pet').hide(); closeMenus(); } },
    { label: 'Cambiar Pokémon', submenu: CHARACTERS.map(c=>({label:c.name,type:'radio',checked:store.state.settings.character===c.id,click:()=>execute('character',{id:c.id}).catch(showError)})) },
    { label: 'Repetir salida de la Pokébola', click:()=>execute('repeatSummon') },
    { label: 'Pausar avisos por una hora', type:'checkbox',checked:store.state.settings.pausedUntil>Date.now(),click:item=>execute('pauseNotices',{paused:item.checked}) },
    { label: 'Restablecer posición y perfil', click: () => resetPosition() },
    { type: 'separator' }, { label: 'Salir', click: () => app.quit() }
  ]));
}
function resetPosition() {
  const a = screen.getPrimaryDisplay().workArea, win = windows.get('pet');
  interaction.end(true); win.webContents.send('gesture-cancelled');
  const b=geometry.migratePosition(null,a);b.width=Math.round(geometry.PET_SIZE.width*store.state.settings.petScale);b.height=Math.round(geometry.PET_SIZE.height*store.state.settings.petScale);setPetBounds(fitPet(b));
  yaw = 0; store.state.settings.yaw = 0; broadcast(); placeMenus();
  mutate(s => { s.settings.yaw = 0; s.settings.petPosition = win.getBounds(); }).catch(showError);
}
function showError(e) { error = e.message || String(e); record(error); broadcast(); }
function sound(type, preview = false) { windows.get('pet')?.webContents.send('voice', { type, preview, voice: store.state.settings.voice, enabled: store.state.settings.sound, volume: store.state.settings.volume }); }
function advanceNotice() {
  if(!notices.length){windows.get('notice')?.hide();return;}const n=notices[0];sound(n.type==='meeting'&&n.link?'meetingWithLink':n.type);motion.request(n.type==='meeting'?'aviso-reunion':'celebracion',Date.now());
}
function pushNotice(notice) {
  const first=notices.length===0;notices.push(notice);if(!first){broadcast();return;} motion.request(notice.type === 'meeting' ? 'aviso-reunion' : 'celebracion', Date.now());
  sound(notice.type==='meeting'&&notice.link?'meetingWithLink':notice.type); createWindow('notice', 356, 170); placeMenus();
  windows.get('notice').showInactive(); broadcast();
}
async function syncCalendars(force = false) {
  if (syncing || !store.state.feeds.length || (!force && Date.now()<nextSync)) return;
  if (force && Date.now()<nextSync-240000) return;
  syncing=true;broadcast();
  const failures=[];
  try {
    const entries=await Promise.all(store.state.feeds.map(async feed=>{
      try{return await calendars.fetch(feed);}catch(e){failures.push({id:feed.id,name:feed.name,message:e.message});return null;}
    }));
    const known=new Set(store.state.feeds.map(f=>f.id));
    for(const snapshot of entries.filter(Boolean)) if(known.has(snapshot.id)) {
      store.state.cache.events=store.state.cache.events.filter(e=>e.feedId!==snapshot.id).concat(snapshot.events);
      const feed=store.state.feeds.find(f=>f.id===snapshot.id);feed.lastUpdated=snapshot.updatedAt;
    }
    store.state.cache.events.sort((a,b)=>a.start-b.start);store.state.cache.updatedAt=Date.now();
    calendarStatus.errors=failures;syncFailures=failures.length?syncFailures+1:0;
    nextSync=Date.now()+Math.min(3600000,300000*2**Math.min(syncFailures,4));
  } finally {syncing=false;broadcast();}
}

async function tick() {
  const now = Date.now();
  motion.focusing = !!store.state.focus; motion.alerting = notices.length > 0;
  motion.setEnabled(store.state.settings.motion, now); motion.tick(now);
  const clone = { ...store.state, focus: structuredClone(store.state.focus), reminders: {...store.state.reminders} }, due = checkReminders(clone, now);
  if (due.length || Object.keys(clone.reminders).length !== Object.keys(store.state.reminders).length) {
    const committed = await store.update(s => checkReminders(s, now));
    committed.forEach(pushNotice);
  }
  const pending=store.state.snoozes.filter(s=>s.at<=now);
  if(pending.length){await store.update(s=>{s.snoozes=s.snoozes.filter(s=>s.at>now);});pending.forEach(s=>pushNotice(s.notice));}
  if (store.state.focus || due.length || motion.revision !== lastMotionRevision) { lastMotionRevision = motion.revision; broadcast(); }
  if (!smoke && !interactiveDemo) syncCalendars().catch(showError);
}
async function execute(name, p = {}, view = 'dashboard') {
  if (name === 'snapshot') return snapshot();
  switch (name) {
    case 'petPrepared': if(view==='pet'&&petVisible){windows.get('pet').showInactive();return {shown:true};} return {shown:false};
    case 'toggleMenu': {
      if (characterLoading) return {ok:true};
      if (menuOpen) closeMenus();
      else { menuOpen = true; setPetBounds(fitPet()); motion.click(Date.now()); broadcast(); }
      break;
    }
    case 'section': await showSection(p.section, !!p.full); break;
    case 'close': { if (view === 'dashboard') windows.get('dashboard')?.hide(); else if (view === 'notice') { notices.shift(); advanceNotice(); } else closeMenus(); broadcast(); break; }
    case 'gestureStart': if (view === 'pet') { interaction.begin(p.mode, screen.getCursorScreenPoint(), windows.get('pet').getBounds(), store.state.settings.yaw); setInputEnabled(true); } break;
    case 'gestureEnd': if (view === 'pet') await finishNativeGesture(!!p.cancelled); break;
    case 'resetView': yaw = 0; await mutate(s => { s.settings.yaw = 0; s.settings.characterYaws[s.settings.character]=0; }); break;
    case 'pet': if(characterLoading) break; motion.request('caricias', Date.now(), true); broadcast(); break;
    case 'animation': if(characterLoading) break; motion.request(p.id, Date.now(), true); broadcast(); break;
    case 'notesSave': return mutate(s => saveNote(s, p));
    case 'notesArchive': await mutate(s => { const n = s.notes.find(n => n.id === p.id); if (!n) throw new Error('No se encontró la nota.'); n.archived = !!p.archived; }); break;
    case 'timerStart': await mutate(s => startTimer(s, Number(p.minutes))); sound('focusStart'); motion.request('curiosidad', Date.now()); broadcast(); break;
    case 'timerToggle': await mutate(s => toggleTimer(s)); break;
    case 'timerCancel': await mutate(s => { s.focus = null; }); break;
    case 'taskSave': await mutate(s => saveTask(s, p)); break;
    case 'taskComplete': await mutate(s => { const t = s.tasks.find(t => t.id === p.id); if (!t) throw new Error('No se encontró la tarea.'); const today = dayKey(Date.now()); t.completedDays = t.completedDays.filter(d => d !== today); if (p.completed) t.completedDays.push(today); if(t.repeat===false)t.completedAt=p.completed?Date.now():null; }); break;
    case 'taskDelete': await mutate(s => { s.tasks = s.tasks.filter(t => t.id !== p.id); }); break;
    case 'settings': {
      const allowed = {};
      if (typeof p.name === 'string') allowed.name = p.name.trim().slice(0, 100);
      if (['Gracie', 'Holden'].includes(p.voice)) allowed.voice = p.voice;
      for (const key of ['motion', 'sound', 'autoStart']) if (typeof p[key] === 'boolean') allowed[key] = p[key];
      if (Number.isFinite(p.volume)) allowed.volume = Math.max(0, Math.min(1, p.volume));
      if (Number.isFinite(p.petScale)) {allowed.petScale=Math.round(Math.max(.7,Math.min(1.4,p.petScale))*20)/20;}
      if (Number.isFinite(p.leadMinutes)) allowed.leadMinutes = Math.max(1, Math.min(60, Math.round(p.leadMinutes)));
      if ('autoStart' in allowed && process.platform === 'win32') app.setLoginItemSettings({ openAtLogin: allowed.autoStart });
      await mutate(s => Object.assign(s.settings, allowed)); if('petScale' in allowed) {resizePet();await mutate(s=>{s.settings.petPosition=windows.get('pet').getBounds();});} if('motion' in allowed) {motion.setEnabled(allowed.motion,Date.now());broadcast();} break;
    }
    case 'calendarAdd': {
      if(syncing)throw new Error('Espera a que termine la actualización actual.');
      if(store.state.feeds.length>=10)throw new Error('Puedes conectar hasta diez calendarios.');
      syncing=true;broadcast();
      try {
        const snapshot=await calendars.connect(p.url,String(p.name??'').slice(0,100));
        try {await mutate(s=>{s.feeds.push({id:snapshot.id,name:snapshot.name,lastUpdated:snapshot.updatedAt});s.cache.events.push(...snapshot.events);s.cache.events.sort((a,b)=>a.start-b.start);s.cache.updatedAt=Date.now();});}
        catch(e){await calendars.remove(snapshot.id);throw e;}
        nextSync=Date.now()+300000;
      } finally {syncing=false;broadcast();}
      break;
    }
    case 'calendarRemove': {
      if(syncing)throw new Error('Espera a que termine la actualización actual.');
      if(!store.state.feeds.some(f=>f.id===p.id))throw new Error('Calendario no encontrado.');
      syncing=true;broadcast();
      try{await calendars.remove(p.id);
      await mutate(s=>{s.feeds=s.feeds.filter(f=>f.id!==p.id);s.cache.events=s.cache.events.filter(e=>e.feedId!==p.id);});
      calendarStatus.errors=calendarStatus.errors.filter(e=>e.id!==p.id);}
      finally{syncing=false;broadcast();}break;
    }
    case 'calendarSync': await syncCalendars(true); break;
    case 'character': {
      if(!CHARACTERS.some(c=>c.id===p.id))throw new Error('Compañero desconocido.');
      if(characterLoading || p.id===store.state.settings.character)break;
      characterLoading=true;closeMenus();interaction.end(true);windows.get('pet').webContents.send('gesture-cancelled');
      await mutate(s=>{s.settings.characterYaws[s.settings.character]=yaw;s.settings.character=p.id;s.settings.yaw=s.settings.characterYaws[p.id]??0;});
      yaw=store.state.settings.yaw;motion.setCharacter(p.id,Date.now());broadcast();updateTray();break;
    }
    case 'repeatSummon': if(!characterLoading)windows.get('pet').webContents.send('summon');break;
    case 'pauseNotices': await mutate(s=>{s.settings.pausedUntil=p.paused?Date.now()+3600000:null;});updateTray();break;
    case 'join': {
      const notice = notices.find(n => n.id === p.id), event = store.state.cache.events.find(e => e.id === p.id);
      const link = notice?.link || event?.link;
      if (!link || !/^https?:\/\//i.test(link)) throw new Error('Esta reunión no tiene un enlace válido.');
      const url = new URL(link); if (url.username || url.password) throw new Error('El enlace no es válido.');
      if (smoke || interactiveDemo) { record('Demo: enlace ' + url.host); break; }
      await shell.openExternal(url.href); break;
    }
    case 'noticeDismiss': if(noticeActionBusy)break;if(p.id&&p.id!==notices[0]?.id)break;notices.shift(); advanceNotice(); broadcast(); break;
    case 'noticeSnooze': if(noticeActionBusy||p.id&&p.id!==notices[0]?.id)break;noticeActionBusy=true;try{if(notices.length){const notice=notices[0];await mutate(s=>{s.snoozes.push({notice,at:Date.now()+300000});});notices.shift();}advanceNotice();broadcast();}finally{noticeActionBusy=false;}break;
    case 'voicePreview': sound('meeting', true); break;
    case 'quit': app.quit(); break;
    default: throw new Error('Acción no disponible.');
  }
  return { ok: true };
}
async function installProtocol() {
  const html = await fs.readFile(path.join(__dirname, 'renderer/index.html'), 'utf8');
  const map = html.match(/<script type="importmap">([\s\S]*?)<\/script>/)[1];
  const hash = createHash('sha256').update(map).digest('base64');
  protocol.handle('pokedesk', async request => {
    const url = new URL(request.url);
    if (smoke) console.log('Recurso: ' + url.pathname);
    const prefixes = { app: path.join(__dirname, 'renderer'), assets: path.join(root, 'assets'), vendor: path.join(root, 'node_modules/three') };
    const segments = decodeURIComponent(url.pathname).split('/').filter(Boolean), base = prefixes[segments.shift()];
    if (url.host !== 'app' || !base || !['GET', 'HEAD'].includes(request.method)) return new Response('', { status: 404 });
    const file = path.resolve(base, ...segments);
    if (!file.startsWith(base + path.sep)) return new Response('', { status: 403 });
    try {
      // Electron's fs understands app.asar; explicit MIME types also keep ESM
      // loading consistent between development and the installed application.
      const data = await fs.readFile(file);
      const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.glb': 'model/gltf-binary', '.mp3': 'audio/mpeg', '.ico': 'image/x-icon' };
      const headers = new Headers({ 'Content-Type': mime[path.extname(file)] || 'application/octet-stream', 'X-Content-Type-Options': 'nosniff' });
      headers.set('Content-Security-Policy', "default-src 'self'; script-src 'self' 'sha256-" + hash + "'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self'; connect-src 'self' blob:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'");
      return new Response(request.method === 'HEAD' ? null : data, { headers });
    } catch (e) { record('Recurso no disponible: ' + url.pathname + ' · ' + e.message); return new Response('', { status: 404 }); }
  });
}
async function runSmoke() {
  const sleep=ms=>new Promise(r=>setTimeout(r,ms)), pet=windows.get('pet');
  const js=code=>pet.webContents.executeJavaScript(code);
  const waitReady=async id=>{for(let i=0;i<300;i++){const r=ready.get('pet');if(r?.ok&&r.character===id&&!characterLoading)return r;await sleep(100);}throw new Error('No cargó '+id+': '+JSON.stringify({ready:ready.get('pet'),logs}));};
  await fs.mkdir(path.join(diagnosticsRoot,'previews'),{recursive:true});
  const capture=async name=>fs.writeFile(path.join(diagnosticsRoot,'previews',name+'.png'),(await pet.webContents.capturePage()).toPNG());
  smokeResults.roster=[];
  for(const c of CHARACTERS) {
    if(c.id!==store.state.settings.character) {await execute('character',{id:c.id});await sleep(1000);await capture(c.id+'-pokeball');}
    const info=await waitReady(c.id);if(c.id==='arcanine'&&!info.reducedMotion&&!info.phases?.some(p=>p.id==='release'&&p.animated))throw new Error('No se reprodujo la Pokébola inicial.');if(info.clips!==c.clips.length)throw new Error('Clips incompletos de '+c.id);
    for(const clip of c.clips){const sample=await js('window.petDiagnostics.sample('+JSON.stringify(clip.id)+')');if(!sample.finite||!sample.changes)throw new Error('Animación inválida '+c.id+'/'+clip.id);}
    const rotation=await js('window.petDiagnostics.rotation()');if(!rotation.hit||!rotation.emptyMiss||!rotation.alpha||!rotation.horizontalOnly)throw new Error('Falló el perfil/transparencia de '+c.id+': '+JSON.stringify({rotation,info:await js('window.petDiagnostics.info()')}));
    const profiles=await js('window.petDiagnostics.profiles()');if(profiles.clipped.length)throw new Error('Recorte '+c.id+': '+JSON.stringify(profiles.clipped.slice(0,8)));
    await execute('toggleMenu');await sleep(300);const anchor=await js('window.petUIDiagnostics.attachments()');
    if(!anchor.sameWindow||anchor.menuGap<0||anchor.menuGap>30)throw new Error('Menú separado en '+c.id+': '+JSON.stringify(anchor));
    await capture(c.id+'-menu');closeMenus();
    smokeResults.roster.push({info,rotation,profiles,anchor,memory:await js('window.petDiagnostics.info()')});
  }
  await execute('notesSave',{title:'Primera nota',body:'Preparar la reunión.',category:'Trabajo'});const note=store.state.notes[0];
  await execute('notesSave',{id:note.id,title:'Primera nota',body:'Preparar la reunión. Versión actualizada.',category:'trabajo'});
  if(store.state.notes[0].revisions.length!==1)throw new Error('Historial de notas perdido.');
  await showSection('notes',true);await sleep(800);await fs.writeFile(path.join(diagnosticsRoot,'previews/notas.png'),(await windows.get('dashboard').webContents.capturePage()).toPNG());windows.get('dashboard').hide();
  await execute('timerStart',{minutes:1});await execute('toggleMenu');await sleep(300);
  const timer=await js('window.petUIDiagnostics.attachments()');if(timer.timerGap<0||timer.timerGap>8)throw new Error('Timer separado del compañero.');smokeResults.timerAnchor=timer;
  const cycles=await js('window.petUIDiagnostics.cycle(300)');if(!cycles.ready||interaction.gesture)throw new Error('Gesto bloqueado después de 300 ciclos.');smokeResults.interactionCycles=300;
  for(const scale of [.7,1,1.25,1.4]) {
    await execute('settings',{petScale:scale});await sleep(300);
    const input=interaction.shape, bounds=pet.getContentBounds();
    if(!input||Math.abs(input.viewport.width-geometry.PET_SIZE.width)>2)throw new Error('La escala rompió la zona de interacción.');
    const p={x:bounds.x+(input.controls[0]?.left??input.body.left)*scale+2,y:bounds.y+(input.controls[0]?.top??input.body.top)*scale+2};
    smokeResults['scale-'+scale]={viewport:input.viewport,bounds,controlHit:geometry.shapeHit(input,p,bounds)};
    if(input.controls.length&&!geometry.shapeHit(input,p,bounds))throw new Error('Botón no pulsable a escala '+scale);
  }
  await execute('settings',{petScale:1,motion:false});closeMenus();
  const before=await js('window.petDiagnostics.info()');await sleep(300);
  const stationary=await js('window.petDiagnostics.info()');if(stationary.frames-before.frames>3)throw new Error('Se siguen dibujando frames sin movimiento.');smokeResults.stationaryFrames=stationary.frames-before.frames;
  for(let i=0;i<12;i++){await execute('character',{id:CHARACTERS[i%4].id});await waitReady(CHARACTERS[i%4].id);}
  const after=await js('window.petDiagnostics.info()');smokeResults.resourcesAfter12Switches=after;
  if(after.memory.geometries>100||after.memory.textures>50||after.switching||!after.appearanceVisible||after.amount!==1||after.effectVisible)throw new Error('Recursos o estado visual no se liberaron al cambiar.');
  await mutate(s=>{s.focus.deadline=Date.now()-1;});await tick();await tick();if(store.state.focus||notices.filter(n=>n.type==='focusFinished').length!==1)throw new Error('Timer no finalizó una sola vez.');
  await mutate(s=>{s.cache.events=[{id:'demo/meeting',title:'Revisión de equipo',start:Date.now()+60000,link:'https://meet.google.com/abc-defg-hij',allDay:false}];});await tick();
  if(!notices.some(n=>n.type==='meeting'&&n.link))throw new Error('No apareció aviso con enlace.');
  await showSection('characters',true);await sleep(400);await fs.writeFile(path.join(diagnosticsRoot,'previews/selector.png'),(await windows.get('dashboard').webContents.capturePage()).toPNG());
  const {parseCalendar}=require('./calendar.cjs');
  const date=new Date(Date.now()+3600000).toISOString().replace(/[-:]/g,'').slice(0,15)+'Z';
  const parsed=await parseCalendar('BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:isolated-smoke\r\nDTSTART:'+date+'\r\nSUMMARY:Prueba ficticia\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n');
  if(parsed.events.length!==1)throw new Error('El lector iCal empaquetado no funcionó.');
  smokeResults.calendarWorker=true;
  if(process.platform==='win32') {const vault=new TokenVault(path.join(app.getPath('userData'),'fake-calendar-links.enc'),safeStorage);await vault.write({fake:'enlace-ficticio'});if((await vault.read()).fake!=='enlace-ficticio')throw new Error('No se recuperó el enlace cifrado en Windows.');await vault.clear();smokeResults.windowsEncryption=true;}
  await execute('noticeSnooze',{id:notices[0].id});
  if(JSON.parse(await fs.readFile(store.file,'utf8')).snoozes.length!==1)throw new Error('No se conservó el aviso pospuesto.');
  await mutate(s=>{s.snoozes[0].at=Date.now()-1;});await tick();if(store.state.snoozes.length)throw new Error('El aviso pospuesto no se reanudó.');smokeResults.snoozePersistence=true;
  smokeResults.hostPlatform=process.platform;smokeResults.electron=process.versions.electron;smokeResults.gpu=await app.getGPUInfo('basic');smokeResults.metrics=app.getAppMetrics();
  await fs.writeFile(path.join(diagnosticsRoot,'smoke-results.json'),JSON.stringify({...smokeResults,logs},null,2));
  if(logs.some(l=>/error|failed|not found|refused/i.test(l)))throw new Error('Errores del visor: '+logs.join('\n'));
  console.log('SMOKE OK: cuatro modelos, 38 clips, perfiles completos, menú y timer unidos, interacción, escalas, recursos, notas y avisos.');app.quit();
}

app.whenReady().then(async () => {
  geometry = await import('./renderer/geometry.mjs');
  if (!smoke && !interactiveDemo && !app.requestSingleInstanceLock()) { app.quit(); return; }
  if (process.platform === 'win32') app.setAppUserModelId('cl.guiaestudio.pokedesk');
  store = new Store(path.join(app.getPath('userData'), 'estado.json'));
  try { await store.load(); } catch (e) { dialog.showErrorBox('PokeDesk · datos guardados', e.message); app.quit(); return; }
  const memoryVault = { value: null, async read() { return this.value; }, async write(v) { this.value = v; }, async clear() { this.value = null; } };
  calendars = new Calendars(smoke || interactiveDemo ? memoryVault : new TokenVault(path.join(app.getPath('userData'),'calendar-links.enc'),safeStorage));
  motion.setCharacter(store.state.settings.character,Date.now());motion.setEnabled(store.state.settings.motion,Date.now());yaw=store.state.settings.yaw;
  await installProtocol();
  ipcMain.handle('command', async (event, name, payload) => {
    if (!ownWindow(event.sender) || !event.senderFrame.url.startsWith('pokedesk://app/app/')) return { error: 'Acceso no permitido.' };
    try { return await execute(name, payload, viewOf(event.sender)); } catch (e) { showError(e); return { error: e.message }; }
  });
  ipcMain.on('shape', (event, shape) => {
    if (viewOf(event.sender) !== 'pet' || !shape?.mask || !(shape.mask.data instanceof Uint8Array) ||
        shape.mask.width !== 108 || shape.mask.height !== 76 || shape.mask.data.length !== 8208 ||
        Math.abs(shape.viewport.width - geometry.PET_SIZE.width)>2 || Math.abs(shape.viewport.height - geometry.PET_SIZE.height)>2 ||
        ![shape.body.left, shape.body.top, shape.body.right, shape.body.bottom].every(Number.isFinite) ||
        !Array.isArray(shape.controls) || shape.controls.length > 14) return;
    interaction.shape = shape;
    if (!interaction.gesture) setPetBounds(fitPet());
    updateNativePointer(screen.getCursorScreenPoint());
  });
  ipcMain.on('renderer-ready', (event, value) => { if (ownWindow(event.sender)) { ready.set(viewOf(event.sender), value); if(viewOf(event.sender)==='pet'){characterLoading=false;if(!value.ok){windows.get('pet').showInactive();error=value.error||'No pude cargar el compañero 3D.';if(value.character){store.state.settings.character=value.character;motion.setCharacter(value.character,Date.now());}}else error='';} broadcast(); } });
  const pet = createWindow('pet', geometry.PET_SIZE.width, geometry.PET_SIZE.height, { focusable: false });
  const a = screen.getPrimaryDisplay().workArea;
  const initial = store.state.settings.petPosition;
  const initialBounds=geometry.restorePosition(initial,a,store.state.settings.petScale,smoke||interactiveDemo);
  setPetBounds(fitPet(initialBounds));
  // The pet asks to show only after its initial GPU resources are prepared.
  tray = new Tray(nativeImage.createFromPath(path.join(root, 'assets/PokeDesk.png')).resize({ width: 22, height: 22 }));
  tray.setToolTip('PokeDesk · asistente de escritorio'); tray.on('click', () => showSection('home', true)); updateTray();
  timerTick = setInterval(() => tick().catch(showError), 1000);
  cursorTick = setInterval(() => updateNativePointer(screen.getCursorScreenPoint()), 40);
  powerMonitor.on('resume', () => { interaction.end(true); pet.webContents.send('gesture-cancelled'); tick().catch(showError); });
  screen.on('display-metrics-changed', () => { interaction.end(true); pet.webContents.send('gesture-cancelled'); setPetBounds(fitPet()); });
  app.on('second-instance', () => showSection('home', true));
  app.on('activate', () => showSection('home', true));
  if (smoke) runSmoke().catch(async e => { console.error(e); await fs.mkdir(diagnosticsRoot, { recursive: true }); await fs.writeFile(path.join(diagnosticsRoot, 'smoke-error.txt'), e.stack); app.exit(1); });
  else if (interactiveDemo) {
    await mutate(s => { s.cache = { calendars: [{ id: 'demo', title: 'Trabajo', primary: true }], taskLists: [], tasks: [], events: [{ id: 'demo/reunion', title: 'Revisión de equipo', start: Date.now() + 35 * 60000, link: 'https://meet.google.com/abc-defg-hij', allDay: false }], updatedAt: Date.now() }; });
    await showSection('home', true);
  }
}).catch(e => { console.error(e); app.exit(1); });
app.on('window-all-closed', () => { /* Tray owns the lifetime of the desktop assistant. */ });
app.on('before-quit', () => { clearInterval(timerTick); clearInterval(cursorTick); calendars?.cancel(); });
