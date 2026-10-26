import { attachments, DEFAULT_BODY, PET_SIZE } from './geometry.mjs';
import { icon } from './icons.js';
const api = window.arcanine, root = document.getElementById('app'), view = new URLSearchParams(location.search).get('view');
let state, pet, currentRevision = -1, renderKey = '', gesture = null, petMenu, petShape;
let panelSection='', panelDrafts=new Map();
let menuAnimations=[],menuAnimationFrame=0,menuAnimationRevision=0;
let noteDraft = { title: '', body: '', category: '' }, noteSearch = '', noteCategory = '', showArchived = false;
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const time = value => new Date(value).toLocaleTimeString('es', { hour: '2-digit', minute: '2-digit' });
const date = value => new Date(value).toLocaleDateString('es', { weekday: 'short', day: 'numeric', month: 'short' });
const fold = value => String(value ?? '').normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
const clock = ms => Math.ceil(ms / 1000);
const timerText = ms => { const seconds = clock(ms); return String(Math.floor(seconds / 60)).padStart(2, '0') + ':' + String(seconds % 60).padStart(2, '0'); };
const button = (label, action, data = '', cls = '') => '<button class="' + cls + '" data-action="' + action + '" ' + data + '>' + label + '</button>';
async function command(name, payload = {}) {
  try {
    const result = await api.command(name, payload);
    if (result?.error) throw new Error(result.error);
    return result;
  } catch (e) { toast(e.message); return null; }
}
function toast(text) {
  document.querySelector('.toast')?.remove();
  const box = document.createElement('div'); box.className = 'toast'; box.textContent = text; root.append(box);
  setTimeout(() => box.remove(), 3500);
}
const tabs = [['home', 'Inicio'], ['agenda', 'Agenda'], ['tasks', 'Tareas'], ['focus', 'Foco'], ['animations', 'Gestos'], ['notes', 'Notas'], ['characters', 'Pokémon'], ['settings', 'Ajustes']];
const titles = Object.fromEntries(tabs);
function renderArc(target = root) {
  const items = [['heart', 'Cariño', 'pet'], ['calendar', 'Agenda', 'agenda'], ['timer', 'Foco', 'focus'], ['sparkles', 'Gestos', 'animations'], ['notes', 'Notas', 'notes'], ['panel', 'Panel', 'home']];
  target.innerHTML = '<div class="arc">' +
    items.map(([symbol, label, target], i) => {
      const a = (166 - i * 152 / 5) * Math.PI / 180, x = 274 + 222 * Math.cos(a), y = 151 - 104 * Math.sin(a);
      return '<button class="arc-button" style="left:' + (x - 47) + 'px;top:' + (y - 38) + 'px" data-action="' + (target === 'pet' ? 'pet' : 'section') + '" data-section="' + target + '" data-full="' + (target === 'home') + '" aria-label="' + (target==='pet'?'Acariciar':label) + '"><span class="arc-symbol">' + icon(symbol) + '</span><span class="arc-label">' + label + '</span></button>';
    }).join('') + button(icon('close'), 'close', 'aria-label="Cerrar accesos"', 'arc-close') + button(icon('switch')+'Cambiar Pokémon','section','data-section="characters"','arc-switch') + '</div>';
}

function companionBar(){return '<div class="companion-bar"><div class="companion-name"><img src="/assets/preview-'+state.settings.character+'.png" alt=""><div><strong>'+esc(companion().name)+'</strong><small>Tu compañero de escritorio</small></div></div><div class="companion-picker" aria-label="Cambiar de Pokémon">'+state.characters.map(c=>button('<img src="/assets/preview-'+c.id+'.png" alt="">','character','data-id="'+c.id+'" aria-label="Elegir a '+esc(c.name)+'" aria-pressed="'+(c.id===state.settings.character)+'" '+(state.characterLoading?'disabled':''),'companion-choice')).join('')+'</div></div>';}
function home() {
  const events = state.cache.events.filter(e => !e.allDay && e.start >= state.now), notes = state.notes.filter(n => !n.archived);
  return '<div class="section"><div class="intro"><img src="/assets/preview-' + state.settings.character + '.png" alt="' + esc(companion().name) + '"><div><p class="eyebrow">Tu compañero de escritorio</p><h2>Hola' + (state.settings.name ? ', ' + esc(state.settings.name) : '') + '</h2><p class="muted">Agenda, foco e ideas, siempre a mano.</p></div></div>' +
    (state.demo ? '<div class="card muted">Vista de prueba · la reunión de ejemplo no pertenece a tu calendario.</div>' : '') +
    '<div class="card"><p class="eyebrow">Próxima reunión</p><h3>' + (events.length ? esc(events[0].title) : 'Sin reuniones próximas') + '</h3><p class="muted">' + (events.length ? date(events[0].start) + ' · ' + time(events[0].start) : state.feeds.length ? 'Revisa tus calendarios en Ajustes.' : 'Pega tu enlace iCal para ver tu agenda.') + '</p></div>' +
    '<div class="tile-grid">' + [['agenda', '◷ Agenda', events.length + ' reuniones'], ['focus', '◉ Concentración', state.focus ? timerText(state.remaining) + ' en curso' : 'Encuentra tu ritmo'], ['notes', '✎ Notas', notes.length + ' ideas guardadas'], ['tasks', '✓ Tareas', 'Tus rutinas diarias'], ['animations', '✧ Animaciones', 'Gestos de tu compañero'], ['settings', '⚙ Ajustes', 'iCal, voz y apariencia']].map(([id, label, sub]) => button('<b>' + label + '</b><span>' + esc(sub) + '</span>', 'section', 'data-section="' + id + '" data-full="true"', 'tile')).join('') + '</div>' +
    '<p class="muted">Arrastra para mover · Alt + arrastrar para girar · Mayús + arrastrar para acariciar.</p></div>';
}
function agenda() {
  return '<div class="section"><div class="row spread"><div><h2>Tu agenda</h2><p class="muted">Próximos siete días</p></div>' + button('↻', 'calendarSync', 'aria-label="Actualizar agenda"', 'small') + '</div>' + calendarWarning() +
    (state.cache.events.length ? '<div class="stack">' + state.cache.events.map(e => '<article class="card"><p class="event-time">' + esc(date(e.start)) + (e.allDay ? ' · Todo el día' : ' · ' + time(e.start)) + '</p><h3>' + esc(e.title) + '</h3><p class="event-calendar">' + esc(e.calendarName) + '</p>' + (e.link ? '<div style="margin-top:9px">' + button('Entrar a la reunión ↗', 'join', 'data-id="' + esc(e.id) + '"', 'blue small') + '</div>' : '') + '</article>').join('') + '</div>' :
      '<div class="empty">Aquí aparecerán tus reuniones.' + (state.feeds.length ? '' : '<br>' + button('Conectar calendario iCal', 'section', 'data-section="settings" data-full="true"', 'small')) + '</div>') +
    '<p class="muted">' + (state.cache.updatedAt ? 'Última actualización: ' + time(state.cache.updatedAt) + '. ' : '') + 'Los avisos usan los eventos guardados; Google se consulta aproximadamente cada cinco minutos.</p></div>';
}
function calendarWarning() {
  return state.calendarStatus.errors.map(e=>'<div class="error">'+esc(e.name)+': '+esc(e.message)+'</div>').join('');
}
function companion() {return state.characters.find(c=>c.id===state.settings.character);}
function characters() {
  return '<div class="section roster-section"><h2 class="roster-title">Elige a tu compañero</h2><p class="muted roster-description">Tus reuniones, tareas, notas y timer continúan contigo.</p><div class="tile-grid roster">'+state.characters.map(c=>button('<img src="/assets/preview-'+c.id+'.png" alt="'+esc(c.name)+'"><b>'+esc(c.name)+'</b><span>#'+c.number+' · '+esc(c.type)+'</span>','character','data-id="'+c.id+'" '+(state.characterLoading?'disabled':''),'tile '+(c.id===state.settings.character?'selected':''))).join('')+'</div>'+button('Repetir salida de la Pokébola','repeatSummon','', 'small')+'</div>';
}

function focus() {
  return '<div class="section"><div><h2>Tiempo de foco</h2><p class="muted">Una tarea a la vez.</p></div>' +
    (state.focus ? '<div class="card"><p class="eyebrow" style="text-align:center">' + (state.focus.paused ? 'En pausa' : 'Concentración en curso') + '</p><div class="timer" data-timer>' + timerText(state.remaining) + '</div><div class="row" style="justify-content:center">' + button(state.focus.paused ? 'Continuar' : 'Pausar', 'timerToggle', '', 'primary') + button('Terminar', 'timerCancel') + '</div></div>' :
      '<div class="preset-grid">' + [5, 10, 30].map(m => button(m + ' min', 'timerStart', 'data-minutes="' + m + '"')).join('') + '</div><form id="timer-form" class="card"><label for="minutes">Duración personalizada</label><div class="row"><input id="minutes" name="minutes" type="number" min="1" max="180" value="25" aria-label="Minutos"><button class="primary" type="submit">Comenzar</button></div></form>') +
    '<p class="muted">El contador aparece junto a tu Pokémon y desaparece al finalizar. Podrás recibir los avisos de reuniones durante la sesión.</p></div>';
}
function animations() {
  return '<div class="section"><div><h2>Sus movimientos</h2><p class="muted">Elige cómo quieres verlo reaccionar.</p></div>' +
    '<div class="tile-grid">' + state.clips.map(c => button(esc(c.title), 'animation', 'data-id="' + c.id + '"', 'small')).join('') + '</div>' +
    button('♥ Acariciar', 'pet', '', 'primary') + button('Restablecer perfil', 'resetView', '', 'small') +
    '<p class="muted">También puedes mantener Mayús y acariciarlo arrastrando sobre él. Para girarlo horizontalmente, mantén Alt y arrastra.</p></div>';
}
function notes() {
  const categories = [...new Set(state.notes.map(n => n.category).filter(Boolean))].sort((a, b) => a.localeCompare(b, 'es'));
  const found = state.notes.filter(n => n.archived === showArchived && (!noteCategory || fold(n.category) === fold(noteCategory)) && fold(n.title + ' ' + n.body + ' ' + n.category).includes(fold(noteSearch))).sort((a, b) => b.updatedAt - a.updatedAt);
  return '<div class="section"><div class="row spread"><div><h2>Tus notas</h2><p class="muted">Ideas que merece la pena guardar.</p></div>' + button('+ Nueva', 'newNote', '', 'small') + '</div>' +
    '<form id="note-form" class="card"><p class="eyebrow">' + (noteDraft.id ? 'Editar nota' : 'Nueva nota') + '</p>' +
    '<label for="note-title">Título · opcional</label><input id="note-title" data-draft="title" maxlength="160" value="' + esc(noteDraft.title) + '" placeholder="Una idea, un pendiente…">' +
    '<label for="note-body">Nota</label><textarea id="note-body" data-draft="body" maxlength="20000" required placeholder="Escribe aquí…">' + esc(noteDraft.body) + '</textarea>' +
    '<label for="note-category">Categoría · opcional</label><input id="note-category" data-draft="category" list="categories" maxlength="64" value="' + esc(noteDraft.category) + '" placeholder="Trabajo, personal…"><datalist id="categories">' + categories.map(c => '<option value="' + esc(c) + '"></option>').join('') + '</datalist><div style="margin-top:10px"><button class="primary" type="submit">' + (noteDraft.id ? 'Guardar cambios' : 'Guardar nota') + '</button></div></form>' +
    '<div class="stack"><input id="note-search" type="search" value="' + esc(noteSearch) + '" placeholder="Buscar en tus notas" aria-label="Buscar notas"><div class="row"><select id="category-filter" aria-label="Filtrar por categoría"><option value="">Todas las categorías</option>' + categories.map(c => '<option ' + (c === noteCategory ? 'selected' : '') + ' value="' + esc(c) + '">' + esc(c) + '</option>').join('') + '</select>' + button(showArchived ? 'Ver activas' : 'Archivadas', 'toggleArchive', '', 'small') + '</div></div>' +
    (found.length ? '<div>' + found.map(n => '<article class="note-row"><div class="row spread"><h3>' + esc(n.title || 'Sin título') + '</h3>' + (n.category ? '<span class="badge">' + esc(n.category) + '</span>' : '') + '</div><p>' + esc(n.body) + '</p><div class="row spread"><span class="muted">' + date(n.updatedAt) + ' · ' + time(n.updatedAt) + '</span><div class="row">' + button('Editar', 'editNote', 'data-id="' + n.id + '"', 'small') + button(n.archived ? 'Restaurar' : 'Archivar', 'notesArchive', 'data-id="' + n.id + '" data-archived="' + !n.archived + '"', 'small') + '</div></div>' +
      (n.revisions.length ? '<details><summary>Historial · ' + n.revisions.length + ' versiones anteriores</summary>' + [...n.revisions].reverse().map(r => '<div class="history"><b>' + date(r.savedAt) + ' · ' + time(r.savedAt) + '</b><p>' + esc(r.title) + '</p>' + esc(r.body) + '</div>').join('') + '</details>' : '') + '</article>').join('') + '</div>' : '<div class="empty">' + (noteSearch || noteCategory ? 'No hay notas que coincidan.' : showArchived ? 'No tienes notas archivadas.' : 'Tu primera idea puede empezar aquí.') + '</div>') + '</div>';
}
function localDay() { const d = new Date(state.now); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); }
function tasks() {
  const weekdays = ['Do', 'Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá'];
  return '<div class="section"><div><h2>Tus tareas</h2><p class="muted">Tus recordatorios, guardados en este equipo.</p></div>' +
    '<form id="task-form" class="card"><label for="task-title">Nuevo recordatorio</label><input id="task-title" name="title" maxlength="200" required placeholder="¿Qué quieres recordar?"><label for="task-time">Hora</label><input id="task-time" name="time" type="time" value="09:00" required><div class="day-picker">' + weekdays.map((label, i) => '<label><input name="days" type="checkbox" value="' + i + '" checked>' + label + '</label>').join('') + '</div><label class="check-row"><input name="repeat" type="checkbox" checked>Repetir los días seleccionados</label><button class="primary" style="margin-top:10px" type="submit">Añadir tarea</button></form>' +
    '<div class="stack">' + state.tasks.map(t => '<div class="card row"><input type="checkbox" aria-label="Completar ' + esc(t.title) + '" data-task="' + t.id + '" ' + ((t.repeat===false ? t.completedAt!=null : t.completedDays.includes(localDay())) ? 'checked' : '') + '><div class="grow"><h3>' + esc(t.title) + '</h3><p class="muted">' + t.time + ' · ' + (t.repeat===false?'Una vez':t.days.map(d => weekdays[d]).join(', ')) + '</p></div>' + button('×', 'taskDelete', 'data-id="' + t.id + '" aria-label="Eliminar tarea"', 'icon') + '</div>').join('') + '</div>' +
    '<p class="muted">Las tareas son propias de PokéDesk. No se conectan a Google Tasks.</p></div>';
}
function settings() {
  const s=state.settings;
  return '<div class="section"><h2>Ajustes</h2><div class="card stack"><h3>Google Calendar por iCal</h3><p class="muted">En Google Calendar: Configuración → tu calendario → Integrar el calendario → Dirección secreta en formato iCal. Pega ese enlace aquí. No necesitas Google Cloud ni tu contraseña de Google.</p>'+calendarWarning()+
    '<form id="calendar-form"><label for="calendar-name">Nombre · opcional</label><input id="calendar-name" name="name" maxlength="100" placeholder="Trabajo"><label for="calendar-url">Enlace privado iCal</label><input id="calendar-url" name="url" type="password" maxlength="4096" required autocomplete="off" placeholder="https://calendar.google.com/calendar/ical/…"><button type="submit" class="primary" '+(state.calendarStatus.syncing?'disabled':'')+'>Conectar calendario</button></form><p class="muted">El enlace se cifra con el almacén seguro de Windows. No lo compartas. La conexión es de lectura y se actualiza cada cinco minutos.</p>'+state.feeds.map(f=>'<div class="card"><b>'+esc(f.name)+'</b><p class="muted">'+(f.lastUpdated?'Actualizado '+time(f.lastUpdated):'Pendiente de actualizar')+'</p>'+button('Eliminar conexión','calendarRemove','data-id="'+esc(f.id)+'"','small')+'</div>').join('')+button(state.calendarStatus.syncing?'Actualizando…':'Actualizar calendarios','calendarSync',state.calendarStatus.syncing?'disabled':'','small')+'</div>'+
    '<form id="settings-form" class="card stack"><h3>Tu compañero</h3>'+button('Elegir Pokémon','section','data-section="characters" data-full="true"','small')+'<div><label for="name">Tu nombre</label><input id="name" name="name" value="'+esc(s.name)+'" maxlength="100" placeholder="¿Cómo te llamas?"></div>'+
    '<div><label for="size">Tamaño</label><input id="size" name="petScale" type="range" min=".7" max="1.4" step=".05" value="'+s.petScale+'"><p class="muted">Se ajusta al espacio disponible para mantener visible todo el menú.</p></div>'+
    '<div><label for="voice">Voz de los avisos · inglés</label><div class="row"><select id="voice" name="voice">'+['Gracie','Holden'].map(v=>'<option '+(s.voice===v?'selected':'')+'>'+v+'</option>').join('')+button('▶','voicePreview','type="button" aria-label="Escuchar aviso de reunión"','small')+'</div><p class="muted">Grabaciones de reuniones en inglés; timers y tareas usan un sonido. No requiere servicios de voz ni créditos.</p></div>'+
    '<div><label for="lead">Avisar antes de reuniones · minutos</label><input id="lead" name="leadMinutes" type="number" min="1" max="60" value="'+s.leadMinutes+'"></div><div><label for="volume">Volumen</label><input id="volume" name="volume" type="range" min="0" max="1" step=".05" value="'+s.volume+'"></div>'+
    '<label class="check-row"><input name="sound" type="checkbox" '+(s.sound?'checked':'')+'>Sonido en los avisos</label><label class="check-row"><input name="motion" type="checkbox" '+(s.motion?'checked':'')+'>Gestos y movimiento</label>'+
    '<label class="check-row"><input name="ambientRotation" type="checkbox" '+(s.ambientRotation!==false?'checked':'')+'>Giro suave en reposo</label><p class="muted">25° por lado en un ciclo de ocho minutos. Se pausa durante el foco, los avisos y la interacción.</p>'+
    (state.platform==='win32'?'<label class="check-row"><input name="autoStart" type="checkbox" '+(s.autoStart?'checked':'')+'>Iniciar al entrar a Windows</label>':'')+'<button type="submit" class="primary">Guardar ajustes</button></form>'+
    button(s.pausedUntil>state.now?'Reanudar avisos':'Pausar avisos por una hora','pauseNotices','data-paused="'+!(s.pausedUntil>state.now)+'"','small')+
    '<details class="card"><summary>Créditos y privacidad</summary><p>Proyecto de fans independiente. Arcanine, Mewtwo, Charizard, Lucario y Gengar: nguyenlouis32. Pikachu: jacobjksn42. Modelos bajo CC BY 4.0, adaptados con animaciones y parpadeos. Personajes Pokémon: sus respectivos titulares.</p><p class="muted">Tareas y notas permanecen en tu equipo. No hay cuenta de PokéDesk, analítica ni sincronización entre equipos.</p></details>'+button('Cerrar PokéDesk','quit','','small')+'</div>';
}

function renderNotice() {
  const n = state.notice;const key=JSON.stringify(n);if(key===renderKey)return;renderKey=key;
  root.innerHTML = n ? '<article class="notice-panel"><div class="row spread"><p class="eyebrow">' + (n.type === 'meeting' ? '◷ Próxima reunión' : n.type === 'task' ? '✓ Recordatorio' : '◉ Foco terminado') + '</p>' + button('×', 'noticeDismiss', 'data-id="' + esc(n.id) + '" aria-label="Cerrar aviso"', 'icon') + '</div><h3>' + esc(n.title) + '</h3><p class="muted">' + esc(n.body) + '</p><div class="row">' + (n.link ? button('Entrar ↗', 'join', 'data-id="' + esc(n.id) + '"', 'primary small') : '') + button('En 5 min', 'noticeSnooze', 'data-id="' + esc(n.id) + '"', 'small') + '</div></article>' : '';
}
function renderPanel(force = false) {
  const key = JSON.stringify([state.notes, state.tasks, state.focus, state.cache, state.settings, state.calendarStatus, state.section, state.error]);
  if (!force && renderKey === key) { updateTimers(); return; }
  renderKey = key;
  const sameSection=panelSection===state.section;
  if(sameSection)for(const field of root.querySelectorAll('form input[id],form select[id]'))panelDrafts.set(field.id,{value:field.value,checked:field.checked});else panelDrafts.clear();
  panelSection=state.section;
  const scroll = document.querySelector('.content')?.scrollTop ?? 0;
  const focusId = document.activeElement?.id, selection = document.activeElement?.selectionStart;
  const section = state.section;
  root.innerHTML = '<div class="panel ' + (!state.fullPanel ? 'detail' : '') + '"><header class="header"><div class="identity"><span class="lens" aria-hidden="true">'+icon('pokeball')+'</span><div><h1>PokéDesk</h1>' + (!state.fullPanel ? '<p class="eyebrow">'+esc(titles[section])+'</p>' : '') + '</div></div><div class="header-actions">'+(state.fullPanel&&section!=='home'?button(icon('home'),'section','data-section="home" data-full="true" aria-label="Inicio"','icon'):'')+(state.fullPanel?button(icon('settings'),'section','data-section="settings" data-full="true" aria-label="Ajustes"','icon'):'')+button(icon('close'), 'close', 'aria-label="Cerrar panel"', 'icon') + '</div></header>' +
    (state.error ? '<div class="error" role="alert">' + esc(state.error) + '</div>' : '') +
    (state.fullPanel ? companionBar()+'<nav class="tabs" aria-label="Secciones">' + tabs.filter(([id])=>!['home','characters','settings'].includes(id)).map(([id, label]) => button(icon({agenda:'calendar',tasks:'tasks',focus:'timer',animations:'sparkles',notes:'notes'}[id])+label, 'section', 'data-section="' + id + '" data-full="true" aria-pressed="'+(section===id)+'"', section === id ? 'active' : '')).join('') + '</nav>' : '') +
    '<div class="content">' + ({ home, agenda, tasks, focus, animations, notes, settings, characters }[section] ?? home)() + '</div><footer class="foot"><span>PokéDesk · ' + esc(state.version) + '</span><span>' + (state.feeds.length ? 'Calendario configurado' : 'Tu compañero está aquí') + '</span></footer></div>';
  for(const [id,draft]of panelDrafts){const field=document.getElementById(id);if(field){if(field.type==='checkbox')field.checked=draft.checked;else field.value=draft.value;}}
  document.querySelector('.content').scrollTop = scroll;
  if (focusId) { const field = document.getElementById(focusId); if (field) { field.focus(); try { field.setSelectionRange(selection, selection); } catch {} } }
}
function updateTimers() {
  document.querySelectorAll('[data-timer]').forEach(n => { n.textContent = timerText(state.remaining); });
  if (view === 'pet') {
    let badge = document.querySelector('.pet-badge');
    if (state.focus && state.remaining > 0) {
      if (!badge) { badge = document.createElement('button'); badge.className = 'pet-badge'; badge.dataset.action = 'section'; badge.dataset.section = 'focus'; root.append(badge); }
      badge.textContent = (state.focus.paused ? 'Ⅱ ' : '◉ ') + timerText(state.remaining);
    } else badge?.remove();
    positionPetControls();
  }
}
function positionPetControls() {
  if (view !== 'pet' || !petMenu) return;
  const a = attachments(petShape?.body ?? DEFAULT_BODY, PET_SIZE);
  if (gesture?.mode !== 'control') {
    petMenu.style.left = a.arc.x + 'px'; petMenu.style.top = a.arc.y + 'px';
    const badge = root.querySelector('.pet-badge');
    if (badge) { badge.style.left = a.timer.x + 'px'; badge.style.top = a.timer.y + 'px'; }
  }
  const opening=petMenu.hidden&&state?.menuOpen;
  if(!state?.menuOpen&&(!petMenu.hidden||menuAnimations.length))stopMenuAnimation();
  petMenu.hidden = !state?.menuOpen;
  if(opening)animateMenuOpen(a);
}
function stopMenuAnimation(){menuAnimationRevision++;cancelAnimationFrame(menuAnimationFrame);menuAnimationFrame=0;menuAnimations.forEach(a=>a.cancel());menuAnimations=[];}
function animateMenuOpen(a){
  stopMenuAnimation();if(matchMedia('(prefers-reduced-motion: reduce)').matches)return;
  const token=menuAnimationRevision,body=petShape?.body??DEFAULT_BODY;
  const origin={x:(body.left+body.right)/2-a.arc.x,y:(body.top+body.bottom)/2-a.arc.y};
  menuAnimations=[...petMenu.querySelectorAll('.arc-button,.arc-switch')].map((button,i)=>{
    const x=parseFloat(button.style.left)||190,y=parseFloat(button.style.top)||135;
    const dx=origin.x-x-button.offsetWidth/2,dy=origin.y-y-button.offsetHeight/2;
    const animation=button.animate([{transform:`translate(${dx}px,${dy}px) scale(.18)`,opacity:0},{transform:'translate(0,0) scale(1)',opacity:1}],{duration:400,delay:i*18,easing:'cubic-bezier(.18,.76,.21,1)',fill:'backwards'});
    animation.finished.catch(()=>{});return animation;
  });
  const end=performance.now()+550;
  function refreshHits(){if(token!==menuAnimationRevision||petMenu.hidden)return;publishPetShape();if(performance.now()<end)menuAnimationFrame=requestAnimationFrame(refreshHits);else{menuAnimationFrame=0;menuAnimations=[];}}
  menuAnimationFrame=requestAnimationFrame(refreshHits);
}
function publishPetShape(value = petShape) {
  if (!value) return;
  petShape = value; positionPetControls();
  const controls = [...root.querySelectorAll('button')].filter(b => b.getClientRects().length).map(b => {
    const r = b.getBoundingClientRect(); return { left: r.left, top: r.top, right: r.right, bottom: r.bottom };
  });
  api.shape({ ...value, controls, viewport: { width: innerWidth, height: innerHeight } });
}
function applyState(next) {
  state = next;
  document.documentElement.dataset.character=state.settings.character;
  if (view === 'pet') {
    if (pet) {
      pet.setCharacter(state.settings.character).catch(e=>toast(e.message));
      pet.setYaw(state.settings.yaw); pet.setMotion(state.motion.enabled);
      pet.setAmbientAllowed(state.settings.ambientRotation!==false&&!state.menuOpen&&!state.fullPanel&&!state.notice&&!(state.focus&&!state.focus.paused)&&!state.smokeTest);
      if (currentRevision !== state.motion.revision) { currentRevision = state.motion.revision; pet.play(state.motion.clip); }
    }
    updateTimers();
    publishPetShape();
  } else if (view === 'notice') renderNotice();
  else if (view !== 'arc') renderPanel();
}
root.addEventListener('input', e => {
  if (e.target.dataset.draft) noteDraft[e.target.dataset.draft] = e.target.value;
  if (e.target.id === 'note-search') { noteSearch = e.target.value; renderPanel(true); }
});
root.addEventListener('change', e => {
  if (e.target.id === 'category-filter') { noteCategory = e.target.value; renderPanel(true); }
  if (e.target.dataset.task) command('taskComplete', { id: e.target.dataset.task, completed: e.target.checked });
  if (e.target.id === 'voice') command('settings', { voice: e.target.value });
});
root.addEventListener('click', async e => {
  const b = e.target.closest('[data-action]'); if (!b) return;
  const action = b.dataset.action;
  if (action === 'newNote') { noteDraft = { title: '', body: '', category: '' }; renderPanel(true); document.getElementById('note-body')?.focus(); }
  else if (action === 'editNote') { const n = state.notes.find(n => n.id === b.dataset.id); noteDraft = { id: n.id, title: n.title, body: n.body, category: n.category }; renderPanel(true); document.querySelector('.content').scrollTop = 0; document.getElementById('note-body')?.focus(); }
  else if (action === 'toggleArchive') { showArchived = !showArchived; renderPanel(true); }
  else if (action === 'section') await command(action, { section: b.dataset.section, full: b.dataset.full === 'true' || view === 'dashboard' });
  else if (action === 'timerStart') await command(action, { minutes: Number(b.dataset.minutes) });
  else if (action === 'noticeDismiss' || action === 'noticeSnooze' || action === 'calendarRemove' || action === 'character' || action === 'animation' || action === 'join' || action === 'taskDelete') await command(action, { id: b.dataset.id });
  else if (action === 'notesArchive') await command(action, { id: b.dataset.id, archived: b.dataset.archived === 'true' });
  else if(action==='pauseNotices') await command(action,{paused:b.dataset.paused==='true'});
  else await command(action);
});
root.addEventListener('submit', async e => {
  e.preventDefault();
  const form = e.target, values = new FormData(form);
  if (form.id === 'note-form') {
    const result = await command('notesSave', noteDraft);
    if (result) { noteDraft = { title: '', body: '', category: '' }; renderPanel(true); toast('Nota guardada'); }
  } else if (form.id === 'timer-form') await command('timerStart', { minutes: Number(values.get('minutes')) });
  else if (form.id === 'task-form') await command('taskSave', { title: values.get('title'), time: values.get('time'), days: values.getAll('days').map(Number), repeat: values.has('repeat') });
  else if(form.id==='calendar-form') {const result=await command('calendarAdd',{url:values.get('url'),name:values.get('name')});if(result){panelDrafts.clear();renderPanel(true);document.getElementById('calendar-url').value='';}}
  else if (form.id === 'settings-form') { const result = await command('settings', { name: values.get('name'), petScale:Number(values.get('petScale')), voice: values.get('voice'), volume: Number(values.get('volume')), leadMinutes: Number(values.get('leadMinutes')), sound: values.has('sound'), motion: values.has('motion'), ambientRotation: values.has('ambientRotation'), ...(state.platform === 'win32' ? { autoStart: values.has('autoStart') } : {}) }); if (result) {panelDrafts.clear();toast('Ajustes guardados');} }
});
api.subscribe('summon',()=>pet?.repeatSummon());
api.subscribe('orientation', yaw => { if (pet) { state.settings.yaw = yaw; pet.setYaw(yaw); } });
api.subscribe('gesture-cancelled', () => { if (gesture) releaseGesture(true); });
api.subscribe('state', applyState);
api.subscribe('voice', async event => {
  if (view !== 'pet' || !event.enabled || (state.demo && !event.preview)) return;
  if (event.type === 'meeting' || event.type === 'meetingWithLink') {
    const voice = event.voice.toLowerCase(), audio = new Audio('/assets/voices/' + voice + (event.type==='meetingWithLink'?'-meetingWithLink.mp3':'-meeting.mp3')); audio.volume = event.volume;
    try { await audio.play(); } catch { chime(event.volume); }
  } else chime(event.volume);
});
let audioContext;
function chime(volume) {
  audioContext ??= new AudioContext();
  audioContext.resume();
  [523.25, 659.25].forEach((hz, i) => {
    const osc = audioContext.createOscillator(), gain = audioContext.createGain(), start = audioContext.currentTime + i * 0.18;
    osc.type = 'sine'; osc.frequency.value = hz; gain.gain.setValueAtTime(0, start); gain.gain.linearRampToValueAtTime(volume * 0.12, start + 0.025); gain.gain.exponentialRampToValueAtTime(0.0001, start + 0.45);
    osc.connect(gain); gain.connect(audioContext.destination); osc.start(start); osc.stop(start + 0.5);
  });
}
function releaseGesture(cancelled = false) {
  if (!gesture) return;
  const pointerId = gesture.pointerId, captor=gesture.captor; gesture = null;
  pet?.endInteraction();
  command('gestureEnd', { cancelled });
  if (captor?.hasPointerCapture(pointerId)) captor.releasePointerCapture(pointerId);
  publishPetShape();
}
if (view === 'pet') {
  root.innerHTML = '<div class="pet-stage" id="pet-stage"></div><div class="pet-menu" hidden></div>';
  petMenu = root.querySelector('.pet-menu'); renderArc(petMenu);
  root.addEventListener('pointerdown', e => {
    if (e.button !== 0) return;
    const control = !!e.target.closest('button');
    if (!control && !pet?.hit(e.clientX, e.clientY)) return;
    if (gesture) releaseGesture(true);
    gesture = { mode: control ? 'control' : e.altKey ? 'rotate' : e.shiftKey ? 'pet' : 'move', pointerId: e.pointerId, captor:control?e.target.closest('button'):root };
    const visualYaw = pet?.beginInteraction(gesture.mode);
    command('gestureStart', { mode: gesture.mode, yaw: visualYaw });
    if(!control)e.preventDefault();
    try{gesture.captor.setPointerCapture(e.pointerId);}catch{releaseGesture(true);}
  });
  window.addEventListener('pointerup', () => releaseGesture());
  window.addEventListener('pointercancel', () => releaseGesture(true));
  root.addEventListener('lostpointercapture', () => releaseGesture(true));
  window.addEventListener('pointermove', e => { if (gesture && !(e.buttons & 1)) releaseGesture(true); });
  window.addEventListener('blur', () => releaseGesture(true));
  document.addEventListener('visibilitychange', () => { if (document.hidden) releaseGesture(true); });
  root.addEventListener('contextmenu', e => { e.preventDefault(); command('toggleMenu'); });
  window.petUIDiagnostics = {
    attachments() {
      const b = petShape.body, r = petMenu.getBoundingClientRect(), timer = root.querySelector('.pet-badge')?.getBoundingClientRect();
      return { sameWindow: petMenu.ownerDocument === root.ownerDocument && !!root.querySelector('#pet-canvas'), menuGap: b.top - (r.top + 177), menuCenterOffset: r.left + 274 - (b.left + b.right) / 2, timerGap: timer ? timer.top - b.bottom : null };
    },
    async cycle(count = 100) {
      for (let i = 0; i < count; i++) {
        await command('gestureStart', { mode: ['move', 'rotate', 'pet', 'control'][i % 4] });
        await command('gestureEnd', { cancelled: true });
      }
      await command('toggleMenu'); await command('toggleMenu');
      return { ready: !!pet, controls: root.querySelectorAll('button').length };
    }
  };
  try { const {createPet}=await import('./pet.js');
    const initial=await api.command('snapshot');
    pet = await createPet(document.getElementById('pet-stage'), publishPetShape, {...initial.settings,testEffects:initial.smokeTest}, info=>api.ready(info),()=>api.command('petPrepared'));api.ready(pet.info); } catch (e) { root.innerHTML = '<div class="pet-error">' + esc(e.message) + '</div>'; api.ready({ ok: false, error: e.message }); }
}
applyState(await api.command('snapshot'));
