#!/usr/bin/env node
// Applies the 1440-slot spellbook patch to a RoF2 eqgame.exe. Never changes the original: writes eqgame_1440.exe next to it.
//   node patch-eqgame.js --stock <eqgame.exe>   stock exe: applies the 4GB patch AND the spellbook patch
//   node patch-eqgame.js --4gb   <eqgame.exe>   exe that already has the 4GB patch: spellbook patch only (4GB flag stays)
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { build, hasLaa, Refusal } = require('./spellbook-patch');

const [, , mode, inPath] = process.argv;
const md5 = b => crypto.createHash('md5').update(b).digest('hex');
const stop = msg => { console.error('\nSTOPPED: ' + msg + '\nYour original file was not changed.\n'); process.exit(1); };

if (!['--stock', '--4gb'].includes(mode) || !inPath) {
  console.error('Usage:\n  node patch-eqgame.js --stock <eqgame.exe>   stock exe: 4GB patch + spellbook patch\n  node patch-eqgame.js --4gb   <eqgame.exe>   exe that already has the 4GB patch: spellbook patch only');
  process.exit(2);
}
if (!fs.existsSync(inPath)) stop('Could not find the file: ' + inPath);
const table = JSON.parse(fs.readFileSync(path.join(__dirname, 'patch-table.json'), 'utf8'));
const buf = fs.readFileSync(inPath);
console.log('File: ' + path.resolve(inPath) + '\nSize: ' + buf.length + ' bytes\nMD5:  ' + md5(buf) + '\n');

let patched;
try {
  const laa = hasLaa(buf);
  if (mode === '--4gb' && !laa) stop('This exe does NOT have the 4GB patch, and this option needs it. Use --stock (4GB patch + spellbook) instead.');
  if (mode === '--stock' && laa) console.log('Note: this exe already has the 4GB patch. That is fine; it will keep it.\n');
  patched = build(buf, table, mode === '--stock');
} catch (e) {
  if (e instanceof Refusal) stop(e.message);
  throw e;
}
const outPath = path.join(path.dirname(path.resolve(inPath)), 'eqgame_1440.exe');
if (fs.existsSync(outPath)) stop('There is already a file named eqgame_1440.exe in that folder. Move or rename it first, so nothing is overwritten.');
fs.writeFileSync(outPath, patched);
const outMd5 = md5(patched);
console.log('DONE\nNew file: ' + outPath + '\nMD5:      ' + outMd5);
if (outMd5 === 'f10534e3ae4ebe64f6dc9d56459c8ecd') console.log('This is identical to the tested 4GB 1440-slot client.');
if (outMd5 === '03b11a34694500b2c38d8aea746d1ae0') console.log('This is identical to the tested standard 1440-slot client (no 4GB flag).');
console.log('\nYour original eqgame.exe was NOT changed. To use the new one, rename it to eqgame.exe where the game expects it.\nThe server needs the matching one-line change, and players need this client before the server is switched.');
