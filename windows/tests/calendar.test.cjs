const test=require('node:test'),assert=require('node:assert/strict');
const {calendarAddress,meetingLink,parseCalendar,Calendars}=require('../src/calendar.cjs');
const {defaults,saveTask,checkReminders}=require('../src/core.cjs');
const now=Date.parse('2026-10-08T12:00:00Z');
const ics=body=>'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//PokéDesk//Test//ES\r\nX-WR-CALNAME:Trabajo\r\n'+body.replaceAll('\n','\r\n')+'\r\nEND:VCALENDAR\r\n';
const event=(extra='',start='20261009T150000Z',end='20261009T160000Z')=>'BEGIN:VEVENT\nUID:team\nDTSTART:'+start+'\nDTEND:'+end+'\nSUMMARY:Equipo\nDESCRIPTION:Entrar https://meet.google.com/abc-defg-hij\n'+extra+'END:VEVENT';
test('Validar enlaces iCal y videoconferencias sin aceptar dominios parecidos',()=>{
  assert.ok(calendarAddress('webcal://calendar.google.com/calendar/ical/test/private-fake/basic.ics').startsWith('https://'));
  for(const s of ['http://calendar.google.com/calendar/ical/a/basic.ics','https://calendar.google.com.evil.test/calendar/ical/a/basic.ics','https://user:pass@calendar.google.com/calendar/ical/a/basic.ics','https://calendar.google.com/calendar/embed','https://localhost/calendar/ical/a.ics'])assert.throws(()=>calendarAddress(s));
  assert.equal(meetingLink('https://zoom.us.evil.test/a'),null);assert.equal(meetingLink('https://company.zoom.us/j/123'),'https://company.zoom.us/j/123');
});
test('Expandir recurrencias, exclusiones, cancelaciones y excepciones movidas',async()=>{
  const daily=event('RRULE:FREQ=DAILY;COUNT=12\nEXDATE:20261010T150000Z\nRDATE:20261009T180000Z\n');
  const cancelled='BEGIN:VEVENT\nUID:team\nRECURRENCE-ID:20261011T150000Z\nSTATUS:CANCELLED\nEND:VEVENT';
  const moved=event('RECURRENCE-ID:20261012T150000Z\n','20261012T180000Z','20261012T190000Z');
  const result=await parseCalendar(ics(daily+'\n'+cancelled+'\n'+moved),now,'America/Santiago');
  assert.equal(result.events.length,5);assert.ok(result.events.some(e=>e.start===Date.parse('2026-10-12T18:00:00Z')/1000));
  assert.ok(!result.events.some(e=>e.start===Date.parse('2026-10-11T15:00:00Z')/1000));
});
test('IANA sin VTIMEZONE respeta Chile y cambios de hora de Nueva York',async()=>{
  const chile='BEGIN:VEVENT\nUID:chile\nDTSTART;TZID=America/Santiago:20261009T090000\nDTEND;TZID=America/Santiago:20261009T100000\nSUMMARY:Chile\nEND:VEVENT';
  const result=await parseCalendar(ics(chile),now,'America/Santiago');assert.equal(result.events[0].start,Date.parse('2026-10-09T12:00:00Z')/1000);
  const dst='BEGIN:VEVENT\nUID:dst\nDTSTART;TZID=America/New_York:20261031T090000\nDTEND;TZID=America/New_York:20261031T100000\nRRULE:FREQ=DAILY;COUNT=3\nSUMMARY:Cambio\nEND:VEVENT';
  const r=await parseCalendar(ics(dst),Date.parse('2026-10-30T00:00:00Z'),'America/Santiago');
  assert.equal(r.events[0].start,Date.parse('2026-10-31T13:00:00Z')/1000);assert.equal(r.events[1].start,Date.parse('2026-11-01T14:00:00Z')/1000);
});
test('Un 304 vuelve a expandir el feed; un error conserva los recursos anteriores',async()=>{
  const requests=[],answers=[new Response(ics(event('RRULE:FREQ=DAILY;COUNT=12\n')),{headers:{ETag:'test-v1'}}),new Response(null,{status:304}),new Response(null,{status:403})];
  const vault={value:null,async read(){return this.value;},async write(v){this.value=v;}};
  const service=new Calendars(vault,async(url,opts)=>{requests.push(opts);return answers.shift();});
  const first=await service.connect('https://calendar.google.com/calendar/ical/test/private-fake/basic.ics','Trabajo',now);
  const later=await service.fetch(first,now+6*86400000);assert.ok(later.events.some(e=>e.start>Date.parse('2026-10-19T00:00:00Z')));
  assert.equal(requests[1].headers['If-None-Match'],'test-v1');await assert.rejects(service.fetch(first,now),/permitió/);
  await service.remove(first.id);assert.equal(Object.keys(vault.value).length,0);
});
test('El lector no bloquea el hilo principal ni expone el enlace en errores',async()=>{
  let responsive=false;setTimeout(()=>{responsive=true;},0);await parseCalendar(ics(event()),now);assert.equal(responsive,true);
  const vault={async read(){return {};},async write(){}};
  const service=new Calendars(vault,async()=>{throw new TypeError('request failed private-secret-url');});
  await assert.rejects(service.connect('https://calendar.google.com/calendar/ical/test/private-secret/basic.ics','Trabajo',now),e=>!e.message.includes('private-secret'));
});
test('Una tarea de una sola vez recuerda tras suspensión, respeta completado y no se repite',()=>{
  const s=defaults(),created=new Date(2026,9,8,8).getTime(),later=new Date(2026,9,8,11).getTime();
  const task=saveTask(s,{title:'Entregar',time:'09:00',repeat:false},created);
  assert.equal(checkReminders(s,later).length,1);assert.equal(checkReminders(s,later+86400000).length,0);
  s.reminders={};task.completedAt=later;assert.equal(checkReminders(s,later+1000).length,0);
});
test('Una tarea de una vez no vuelve a avisar después de limpiar el historial de la semana',()=>{
  const s=defaults(),created=new Date(2026,9,8,8).getTime(),first=new Date(2026,9,8,11).getTime();
  saveTask(s,{title:'Una vez',time:'09:00',repeat:false},created);
  assert.equal(checkReminders(s,first).length,1);
  checkReminders(s,first+9*86400000);
  assert.equal(checkReminders(s,first+9*86400000+1000).length,0);
});
