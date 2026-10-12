'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const { defaults, validateState } = require('./core.cjs');
class Store {
  constructor(file) { this.file = file; this.state = defaults(); this.writeQueue = Promise.resolve(); this.error = ''; }
  async load() {
    try { this.state = validateState(JSON.parse(await fs.readFile(this.file, 'utf8'))); }
    catch (e) {
      if (e.code !== 'ENOENT') {
        this.error = 'No se pudieron leer los datos guardados. El archivo original se conservó: ' + e.message;
        throw new Error(this.error);
      }
    }
    return this.state;
  }
  async update(mutator) {
    const operation = this.writeQueue.then(async () => {
      const next = structuredClone(this.state);
      const result = mutator(next);
      await fs.mkdir(path.dirname(this.file), { recursive: true });
      const temp = this.file + '.tmp';
      await fs.writeFile(temp, JSON.stringify({ ...next, cache: defaults().cache }, null, 2), { mode: 0o600 });
      await fs.rename(temp, this.file);
      this.state = next;
      return result;
    });
    this.writeQueue = operation.catch(() => {});
    return operation;
  }
}
class TokenVault {
  constructor(file, safeStorage) { this.file = file; this.safeStorage = safeStorage; }
  async write(value) {
    if (!await this.safeStorage.isAsyncEncryptionAvailable()) throw new Error('Windows no permitió guardar la conexión de forma segura.');
    const data = await this.safeStorage.encryptStringAsync(JSON.stringify(value));
    await fs.mkdir(path.dirname(this.file), { recursive: true });
    await fs.writeFile(this.file + '.tmp', data, { mode: 0o600 });
    await fs.rename(this.file + '.tmp', this.file);
  }
  async read() {
    let data;
    try { data = await fs.readFile(this.file); } catch (e) { if (e.code === 'ENOENT') return null; throw e; }
    const { result, shouldReEncrypt } = await this.safeStorage.decryptStringAsync(data);
    const value = JSON.parse(result);
    if (shouldReEncrypt) await this.write(value);
    return value;
  }
  async clear() { await fs.rm(this.file, { force: true }); }
}
module.exports = { Store, TokenVault };
