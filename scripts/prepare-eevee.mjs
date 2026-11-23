#!/usr/bin/env node
/** Keep the exact attributed Eevee reference ready for Python authoring.
 * This source already embeds PNG textures and uncompressed glTF geometry.
 * No image editing, npm packages, decoder or runtime dependency is needed.
 */
import {readFile,writeFile} from 'node:fs/promises';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const raw=await readFile(resolve(root,'Models/Eevee/eevee-original.glb'));
const digest=createHash('sha256').update(raw).digest('hex');
if(digest!=='e556fd1be296ca85e3cef875c905e23695ea59eccbfa073574cfc08f9e9ecbeb') throw new Error('Unexpected Eevee source; inspect attribution and model before authoring.');
const length=raw.readUInt32LE(12);const document=JSON.parse(raw.subarray(20,20+length).toString());
if(document.skins[0].joints.length!==57 || (document.extensionsRequired||[]).length) throw new Error('Unexpected Eevee reference rig.');
await writeFile(resolve(root,'Models/Eevee/eevee-decoded.glb'),raw);
console.log('Eevee reference copied intact: original pose, colors, PNG textures and 57-joint rig.');
