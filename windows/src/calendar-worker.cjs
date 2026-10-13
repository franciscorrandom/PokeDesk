'use strict';
const {parentPort,workerData}=require('node:worker_threads');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const {MAX_CALENDAR_BYTES,sizeError}=require('./calendar-payload.cjs');
const formats=new Map();
function nativeTimestamp(json,zone) {
  try {
    const p=JSON.parse(json), target=Date.UTC(p.year,p.month-1,p.day,p.hour,p.minute,p.second);
    if (!formats.has(zone)) formats.set(zone,new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}));
    const formatter=formats.get(zone);
    const wall=ms=>{ const a=Object.fromEntries(formatter.formatToParts(ms).map(p=>[p.type,p.value])); return Date.UTC(+a.year,+a.month-1,+a.day,+a.hour,+a.minute,+a.second); };
    let guess=target;
    for(let i=0;i<4;i++){ const difference=target-wall(guess); if(!difference) return guess/1000; guess+=difference; }
    return guess/1000;
  } catch {return NaN;}
}
function parse(text,now,timezone) {
  if(Buffer.byteLength(text)>MAX_CALENDAR_BYTES)throw sizeError();
  if(!text.includes('BEGIN:VCALENDAR'))throw new Error('INVALID_CALENDAR');
  const context=vm.createContext({nativeTimestamp});
  for(const file of ['ical.js','reader.js']) vm.runInContext(fs.readFileSync(path.join(__dirname,'../assets/calendar',file),'utf8'),context,{timeout:5000});
  context.input=text;context.begin=now/1000;context.end=(now+7*86400000)/1000;context.zone=timezone;
  return JSON.parse(vm.runInContext('readCalendar(input,begin,end,zone)',context,{timeout:5000}));
}
if(parentPort) {
  try {parentPort.postMessage({value:parse(workerData.text,workerData.now,workerData.timezone)});}
  catch {parentPort.postMessage({error:'No pude interpretar las fechas o repeticiones del calendario. Revisa el enlace iCal y sus zonas horarias.'});}
}
module.exports={parse,nativeTimestamp};
