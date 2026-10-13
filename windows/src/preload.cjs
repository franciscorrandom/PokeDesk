'use strict';
const { contextBridge, ipcRenderer } = require('electron');
const allowed = new Set(['snapshot', 'petPrepared', 'toggleMenu', 'section', 'close', 'gestureStart', 'gestureEnd', 'resetView', 'pet', 'animation', 'notesSave', 'notesArchive', 'timerStart', 'timerToggle', 'timerCancel', 'taskSave', 'taskComplete', 'taskDelete', 'settings', 'calendarAdd', 'calendarRemove', 'calendarSync', 'character', 'repeatSummon', 'pauseNotices', 'join', 'noticeDismiss', 'noticeSnooze', 'voicePreview', 'quit']);
contextBridge.exposeInMainWorld('arcanine', {
  command: (name, payload = {}) => {
    if (!allowed.has(name)) return Promise.reject(new Error('Acción no disponible.'));
    return ipcRenderer.invoke('command', name, payload);
  },
  shape: value => ipcRenderer.send('shape', value),
  ready: value => ipcRenderer.send('renderer-ready', value),
  subscribe: (event, callback) => {
    if (!['state', 'orientation', 'gesture-cancelled', 'voice', 'summon'].includes(event)) throw new Error('Evento no disponible.');
    const listener = (_e, value) => callback(value);
    ipcRenderer.on(event, listener);
    return () => ipcRenderer.removeListener(event, listener);
  }
});
