const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const characters = require('../src/renderer/characters.json');

function glb(id) {
  const raw = fs.readFileSync(path.join(__dirname, '../assets', id + '.glb'));
  assert.equal(raw.toString('ascii', 0, 4), 'glTF');
  assert.equal(raw.readUInt32LE(4), 2);
  assert.equal(raw.readUInt32LE(8), raw.length);
  const length = raw.readUInt32LE(12);
  const doc = JSON.parse(raw.subarray(20, 20 + length).toString('utf8'));
  const binary = raw.subarray(28 + length);
  function read(index) {
    const accessor = doc.accessors[index], view = doc.bufferViews[accessor.bufferView];
    assert.equal(accessor.componentType, 5126, 'Animation samples must be portable float32 values');
    const width = {SCALAR: 1, VEC3: 3, VEC4: 4}[accessor.type];
    assert.ok(width);
    const offset = (view.byteOffset ?? 0) + (accessor.byteOffset ?? 0);
    return Array.from({length: accessor.count}, (_, row) => Array.from({length: width}, (_, col) =>
      binary.readFloatLE(offset + row * (view.byteStride ?? width * 4) + col * 4)));
  }
  return {raw, doc, read};
}

test('Windows distribuye los nueve GLB actuales, incluido el Eevee de referencia con 57 articulaciones', () => {
  const expectedJoints = {arcanine: 85, mewtwo: 77, pikachu: 49, charizard: 87,
    lucario: 86, gengar: 65, bulbasaur: 72, dragonite: 80, eevee: 57};
  assert.deepEqual(characters.map(c => c.id).sort(), Object.keys(expectedJoints).sort());
  for (const {id} of characters) {
    const {raw, doc} = glb(id);
    // Catch an outdated generated copy before producing a Windows installer.
    assert.deepEqual(raw, fs.readFileSync(path.join(__dirname, '../../Assets', id + '-biblioteca.glb')));
    assert.equal(new Set(doc.skins.flatMap(s => s.joints)).size, expectedJoints[id], id);
    assert.ok(!doc.extensionsRequired?.some(e => ['KHR_draco_mesh_compression', 'EXT_texture_webp'].includes(e)), id);
    assert.ok([...doc.buffers, ...doc.images].every(item => !item.uri), id);
    assert.ok(doc.images.every(image => ['image/png', 'image/jpeg'].includes(image.mimeType)), id);
    if (id === 'eevee') {
      assert.match(doc.asset.extras.author, /nguyenlouis32/);
      assert.match(doc.asset.extras.source, /e93d3b389ea04c9ca8e532b7471a1cb0$/);
    }
  }
});

test('Los 83 clips distribuidos conservan duración, muestras finitas y cierres continuos', () => {
  let count = 0;
  for (const character of characters) {
    const {doc, read} = glb(character.id);
    assert.deepEqual(doc.animations.map(a => a.name).sort(), character.clips.map(c => c.id).sort());
    for (const clip of doc.animations) {
      count++;
      const expected = character.clips.find(c => c.id === clip.name);
      for (const channel of clip.channels) {
        const sampler = clip.samplers[channel.sampler];
        const times = read(sampler.input).map(row => row[0]), values = read(sampler.output);
        assert.equal(times.length, values.length);
        assert.equal(times[0], 0);
        assert.ok(Math.abs(times.at(-1) - expected.duration) < .0001, character.id + '/' + clip.name);
        assert.ok(times.every((value, i) => Number.isFinite(value) && (!i || value > times[i - 1])));
        assert.ok(values.every(row => row.every(Number.isFinite)));
        // A full turn may close at -q, which represents the same rotation as q.
        const seamless = channel.target.path === 'rotation'
          ? Math.abs(values[0].reduce((dot, value, i) => dot + value * values.at(-1)[i], 0)) > .9999
          : values[0].every((value, i) => Math.abs(value - values.at(-1)[i]) < .0001);
        assert.ok(seamless, character.id + '/' + clip.name + ': open loop');
      }
    }
  }
  assert.equal(count, 83);
});
