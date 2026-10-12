'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
async function main() {
  for (const [source, target] of [['Assets','assets'],['docs','assets/credits']]) {
    const from = path.resolve(root, '..', source), to = path.join(root, target);
    await fs.mkdir(to, {recursive:true});
    if (source === 'Assets') {
      for (const name of ['arcanine','mewtwo','pikachu','charizard']) {
        await fs.copyFile(path.join(from,name+'-biblioteca.glb'),path.join(to,name+'.glb'));
        await fs.copyFile(path.join(from,'preview-'+name+'.png'),path.join(to,'preview-'+name+'.png'));
      }
      await fs.cp(path.join(from,'Voices'),path.join(to,'voices'),{recursive:true});
      await fs.cp(path.join(from,'Calendar'),path.join(to,'calendar'),{recursive:true});
      await fs.copyFile(path.join(from,'PokeDesk.icns'),path.join(to,'PokeDesk.icns'));
      // Repackage the existing PNG icon sizes as ICO, without redrawing the artwork.
      const icns=await fs.readFile(path.join(from,'PokeDesk.icns')),images=[];
      for(let p=8;p<icns.length;) {
        const type=icns.toString('ascii',p,p+4),length=icns.readUInt32BE(p+4);
        if(['icp4','icp5','icp6','ic07','ic08'].includes(type))images.push(icns.subarray(p+8,p+length));
        p+=length;
      }
      const header=Buffer.alloc(6+images.length*16);header.writeUInt16LE(1,2);header.writeUInt16LE(images.length,4);
      let offset=header.length;
      images.forEach((png,i)=>{const p=6+i*16;header[p]=png.readUInt32BE(16)%256;header[p+1]=png.readUInt32BE(20)%256;header.writeUInt16LE(1,p+4);header.writeUInt16LE(32,p+6);header.writeUInt32LE(png.length,p+8);header.writeUInt32LE(offset,p+12);offset+=png.length;});
      await fs.writeFile(path.join(to,'PokeDesk.ico'),Buffer.concat([header,...images]));
      await fs.writeFile(path.join(to,'PokeDesk.png'),images.at(-1));
    } else await fs.copyFile(path.join(from,'CREDITOS.md'),path.join(to,'CREDITOS.md'));
  }
  for (const name of ['loaders/GLTFLoader.js','utils/BufferGeometryUtils.js','utils/SkeletonUtils.js']) {
    const out=path.join(root,'src/renderer/vendor/three-addons',name);
    await fs.mkdir(path.dirname(out),{recursive:true});
    await fs.copyFile(path.join(root,'node_modules/three/examples/jsm',name),out);
  }
  await fs.copyFile(path.join(root,'node_modules/three/LICENSE'),path.join(root,'src/renderer/vendor/three-addons/LICENSE'));
  console.log('PokéDesk: cuatro modelos, voces, lector iCal y licencias incluidos.');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
