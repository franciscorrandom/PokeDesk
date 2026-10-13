'use strict';
const MAX_CALENDAR_BYTES=50*1024*1024;
const sizeError=()=>new Error('El calendario supera el límite de 50 MB. Reduce su historial o conecta un calendario del trabajo más acotado.');
function decodeCalendar(data,contentType='') {
  if(data.byteLength>MAX_CALENDAR_BYTES)throw sizeError();
  const charset=String(contentType).match(/charset\s*=\s*["']?([^;"'\s]+)/i)?.[1]?.toLowerCase();
  const utf16=data[0]===0xff&&data[1]===0xfe?'utf-16le':data[0]===0xfe&&data[1]===0xff?'utf-16be':null;
  const decode=(bytes,encoding)=>{try{return new TextDecoder(encoding,{fatal:true}).decode(bytes);}catch{return null;}};
  let text=decode(data,utf16||(['utf-16le','utf-16be'].includes(charset)?charset:'utf-8'));
  if(text===null){
    const unfolded=Buffer.allocUnsafe(data.byteLength);let write=0;
    for(let i=0;i<data.byteLength;i++){
      if(data[i]===13&&data[i+1]===10&&[9,32].includes(data[i+2]))i+=2;
      else unfolded[write++]=data[i];
    }
    text=decode(unfolded.subarray(0,write),'utf-8');
    if(text===null&&['iso-8859-1','latin1','latin-1','windows-1252','cp1252'].includes(charset))text=decode(data,charset);
  }
  if(text===null||text.includes('\0'))throw new Error('Google entregó un calendario con una codificación de texto no compatible. Comprueba la dirección secreta iCal o vuelve a generarla.');
  text=text.replace(/^\uFEFF/,'');
  if(!text.includes('BEGIN:VCALENDAR'))throw new Error('El enlace devolvió una página u otro archivo en lugar de un calendario iCal. Revisa la dirección secreta y si tu organización permite compartir el calendario por iCal.');
  return text;
}
async function readCalendarResponse(response) {
  if(Number(response.headers.get('content-length'))>MAX_CALENDAR_BYTES){await response.body?.cancel();throw sizeError();}
  const reader=response.body?.getReader();
  if(!reader)throw new Error('Google entregó una respuesta vacía en lugar de un calendario.');
  const chunks=[];let size=0;
  try{
    for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>MAX_CALENDAR_BYTES){await reader.cancel();throw sizeError();}chunks.push(value);}
  }finally{reader.releaseLock();}
  return decodeCalendar(Buffer.concat(chunks,size),response.headers.get('content-type'));
}
module.exports={MAX_CALENDAR_BYTES,sizeError,decodeCalendar,readCalendarResponse};
