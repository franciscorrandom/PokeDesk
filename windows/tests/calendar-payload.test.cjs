const test=require('node:test'),assert=require('node:assert/strict');
const {decodeCalendar,readCalendarResponse,MAX_CALENDAR_BYTES}=require('../src/calendar-payload.cjs');
const {Calendars}=require('../src/calendar.cjs');
const simple='BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:office\r\nDTSTART:20261013T150000Z\r\nDTEND:20261013T160000Z\r\nSUMMARY:Café\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';
test('UTF-8, BOM, UTF-16 y caracteres divididos en líneas plegadas conservan el texto',()=>{
  assert.equal(decodeCalendar(Buffer.from(simple)),simple);
  assert.equal(decodeCalendar(Buffer.concat([Buffer.from([239,187,191]),Buffer.from(simple)])),simple);
  assert.equal(decodeCalendar(Buffer.concat([Buffer.from([255,254]),Buffer.from(simple,'utf16le')])),simple);
  const folded=Buffer.concat([Buffer.from('BEGIN:VCALENDAR\r\nSUMMARY:Caf'),Buffer.from([195,13,10,32,169]),Buffer.from('\r\nEND:VCALENDAR\r\n')]);
  assert.ok(decodeCalendar(folded).includes('Café'));
  assert.throws(()=>decodeCalendar(Buffer.from([255,128])),/codificación/);
  assert.throws(()=>decodeCalendar(Buffer.from('<html>Google Workspace</html>')),/organización/);
});
test('Se cancela el cuerpo al superar el límite, incluso sin Content-Length',async()=>{
  let cancelled=false;
  const body=new ReadableStream({start(c){const chunk=new Uint8Array(1024*1024);for(let i=0;i<51;i++)c.enqueue(chunk);},cancel(){cancelled=true;}});
  await assert.rejects(readCalendarResponse(new Response(body)),/50 MB/);assert.equal(cancelled,true);
  let headerCancelled=false;
  const headerResponse=new Response(new ReadableStream({cancel(){headerCancelled=true;}}),{headers:{'Content-Length':String(MAX_CALENDAR_BYTES+1)}});
  await assert.rejects(readCalendarResponse(headerResponse),/50 MB/);assert.equal(headerCancelled,true);
});
test('Un calendario de más de 10 MB se conecta sin bloquear la UI y no pierde su caché tras un error',async()=>{
  const big=simple.replace('VERSION:2.0','VERSION:2.0\r\nX-ARCHIVE-NOTE:'+ 'x'.repeat(11*1024*1024));
  const answers=[new Response(big,{headers:{ETag:'large-v1'}}),new Response('<html>Access denied</html>'),new Response(null,{status:304})];
  const vault={value:{},async read(){return this.value;},async write(v){this.value=v;}};
  const service=new Calendars(vault,async()=>answers.shift());
  let responsive=false;setTimeout(()=>{responsive=true;},0);
  const feed=await service.connect('https://calendar.google.com/calendar/ical/example/private-test/basic.ics','Trabajo',Date.parse('2026-10-13T00:00:00Z'));
  assert.equal(feed.events.length,1);assert.equal(responsive,true);
  await assert.rejects(service.fetch(feed),/organización/);
  assert.equal(Object.keys(vault.value).length,1);
  const cached=await service.fetch(feed,Date.parse('2026-10-13T00:00:00Z'));assert.equal(cached.events.length,1);
});
