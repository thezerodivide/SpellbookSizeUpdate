// Builds a 1440-slot-spellbook eqgame.exe from a RoF2 eqgame.exe (kept for compatibility; see patcher/ for the friendlier tool).
//   node build-spellbook-patch.js <eqgame.exe> <patch-table.json> <output.exe> [--laa]
// --laa sets the large-address-aware (4GB) bit. Without it the bit is left exactly as the input has it.
const fs = require('fs');
const crypto = require('crypto');
const { build, Refusal } = require('./patcher/spellbook-patch');
const [, , inPath, tablePath, outPath, ...flags] = process.argv;
const md5 = b => crypto.createHash('md5').update(b).digest('hex');
const buf = fs.readFileSync(inPath);
const table = JSON.parse(fs.readFileSync(tablePath, 'utf8'));
let raw;
try { raw = build(buf, table, flags.includes('--laa')); }
catch (e) { if (e instanceof Refusal) { console.error('Refused: ' + e.message); process.exit(1); } throw e; }
fs.writeFileSync(outPath, raw);
console.log('input  md5', md5(buf));
console.log('output md5', md5(raw), 'size', raw.length);
console.log('patches', table.length, '+ 2 hooks');
