'use strict';
const {Worker}=require('node:worker_threads');
const path=require('node:path');
const {randomUUID}=require('node:crypto');
function calendarAddress(value) {
  try {
    const text=String(value).trim().replace(/^webcal:\/\//,'https://'), u=new URL(text);
    if(text.length>4096 || u.protocol!=='https:' || !['calendar.google.com','www.google.com'].includes(u.hostname.toLowerCase()) || u.username || u.password || u.port || u.hash || !u.pathname.startsWith('/calendar/ical/') || !u.pathname.endsWith('.ics')) throw 0;
    return u.href;
  } catch { throw new Error('Pega la dirección secreta en formato iCal de Google Calendar: un enlace HTTPS que termine en .ics.'); }
}
function meetingLink(text) {
  const hosts=['meet.google.com','zoom.us','teams.microsoft.com','teams.live.com','teams.cloud.microsoft','webex.com'];
  for(const match of String(text).matchAll(/https:\/\/[^\s<>"]+/g)) {
    try {const u=new URL(match[0].replace(/[),.;]+$/,'')); if(!u.username&&!u.password&&hosts.some(h=>u.hostname===h||u.hostname.endsWith('.'+h))) return u.href;} catch {}
  }
  return null;
}
function parseCalendarWorker(text,now=Date.now(),timezone=Intl.DateTimeFormat().resolvedOptions().timeZone) {
  return new Promise((resolve,reject)=>{
    const worker=new Worker(path.join(__dirname,'calendar-worker.cjs'),{workerData:{text,now,timezone},resourceLimits:{maxOldGenerationSizeMb:96}});
    const timer=setTimeout(()=>{worker.terminate();reject(new Error('El calendario tardó demasiado en procesarse.'));},12000);
    worker.once('message',v=>{clearTimeout(timer);worker.terminate();v.error?reject(new Error(v.error)):resolve(v.value);});
    worker.once('error',()=>{clearTimeout(timer);reject(new Error('No pude leer el calendario.'));});
    worker.once('exit',code=>{clearTimeout(timer);if(code) reject(new Error('No pude terminar de leer el calendario.'));});
  });
}
const parseQueue=[];let activeParsers=0;
function parseCalendar(text,now=Date.now(),timezone=Intl.DateTimeFormat().resolvedOptions().timeZone) {
  return new Promise((resolve,reject)=>{parseQueue.push({text,now,timezone,resolve,reject});drainParsers();});
}
function drainParsers() {
  while(activeParsers<2&&parseQueue.length){const item=parseQueue.shift();activeParsers++;parseCalendarWorker(item.text,item.now,item.timezone).then(item.resolve,item.reject).finally(()=>{activeParsers--;drainParsers();});}
}

class Calendars {
  constructor(vault,fetcher=fetch) {this.vault=vault;this.fetcher=fetcher;this.raw=new Map();this.validators=new Map();this.epoch=new Map();this.abort=new Set();}
  cancel(){for(const a of this.abort)a.abort();this.abort.clear();}
  async download(url,id,name,now,conditional=true) {
    const epoch=this.epoch.get(id)??0, controller=new AbortController(), timeout=setTimeout(()=>controller.abort(),30000);
    this.abort.add(controller);
    let parsed;
    try {
      const headers={Accept:'text/calendar'};
      if(conditional){ const v=this.validators.get(id);if(v?.etag)headers['If-None-Match']=v.etag;if(v?.modified)headers['If-Modified-Since']=v.modified;}
      let response;
      for(let redirect=0;redirect<5;redirect++) {
        response=await this.fetcher(url,{headers,redirect:'manual',signal:controller.signal});
        if(![301,302,303,307,308].includes(response.status))break;
        url=calendarAddress(new URL(response.headers.get('location'),url).href);
      }
      let text;
      if(response.status===304 && this.raw.has(id)) text=this.raw.get(id);
      else {
        if(response.status!==200)throw new Error([401,403,404].includes(response.status)?'Google no permitió leer el calendario. Comprueba si cambió el enlace iCal.':'Google Calendar no está disponible. Volveré a intentarlo.');
        const reader=response.body.getReader(),chunks=[];let size=0;
        for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>10*1024*1024){await reader.cancel();throw new Error('El calendario es demasiado grande.');}chunks.push(value);}
        text=new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks));
      }
      parsed=await parseCalendar(text,now);
      if((this.epoch.get(id)??0)!==epoch)throw new Error('La conexión cambió durante la actualización.');
      this.raw.set(id,text); if(response.status===200)this.validators.set(id,{etag:response.headers.get('etag'),modified:response.headers.get('last-modified')});
    } catch(e) {
      // Fetch errors can contain the private URL. Never forward their original text.
      if(e instanceof TypeError || e.name==='AbortError') throw new Error('No pude contactar con Google Calendar. Revisa tu conexión; volveré a intentarlo.');
      throw e;
    } finally {clearTimeout(timeout);this.abort.delete(controller);}
    const title=String(name||parsed.name).trim().slice(0,100);
    return {id,name:title,updatedAt:now,events:parsed.events.map(e=>({id:id+'/'+e.id,title:String(e.title).slice(0,300),start:e.start*1000,end:e.end*1000,allDay:e.allDay,calendarName:title,feedId:id,link:meetingLink(e.links)}))};
  }
  async connect(address,name,now=Date.now()) {
    const url=calendarAddress(address),id=randomUUID(),snapshot=await this.download(url,id,name,now,false);
    const links=await this.vault.read()??{};links[id]=url;await this.vault.write(links);return snapshot;
  }
  async fetch(feed,now=Date.now()) {
    const links=await this.vault.read()??{};if(!links[feed.id])throw new Error('Este calendario necesita su enlace iCal. Pégalo de nuevo en Ajustes.');
    return this.download(calendarAddress(links[feed.id]),feed.id,feed.name,now);
  }
  async remove(id) {const links=await this.vault.read()??{};delete links[id];await this.vault.write(links);this.epoch.set(id,(this.epoch.get(id)??0)+1);this.raw.delete(id);this.validators.delete(id);}
}
module.exports={calendarAddress,meetingLink,parseCalendar,Calendars};
