// Generates patch-table.json from the disassembly of the ORIGINAL RoF2 eqgame.exe (orig.dis).
// Each entry: { va, expect, replace, why }  (hex strings, same length)
const fs=require('fs');
const NEW_SLOTS=1440, OLD_SLOTS=720;
const TAIL=0x9950;                 // spellbook array moves to object+TAIL (past the end of the object)
const ALLOC=TAIL+NEW_SLOTS*4;      // 0xAFD0
const le32=v=>{const b=Buffer.alloc(4);b.writeUInt32LE(v>>>0);return b.toString('hex')};
const L=fs.readFileSync(process.argv[2]||'orig.dis','utf8').split('\n').map(l=>l.split('\t'));
const byAddr=new Map();for(const [a,ins,hex] of L)if(ins)byAddr.set(parseInt(a,16),{ins,hex});
const fn=require(process.argv[3]||'./fof.js');
const patches=[];
function add(va,expect,replace,why){patches.push({va:va.toString(16),expect,replace,why})}
// functions whose 0x2d0/0x2cf bounds are the character spellbook (verified by hand)
const BOUND_FNS=new Set(['449cd0','4605d0','4be9d0','5789b0','648200','75b880','75bc00','75bd40','75bf30','75c290','75c340','75c620','75c760','75c820','75ceb0','75d080','75d380','75d480','75ddf0','7eac20','7ebb70','7edaa0','7ee560','7ee880','7ef330']);
for(const [a,{ins,hex}] of byAddr){
  const f=fn(a).toString(16);
  // (1) indexed array accesses and lea/add of the array base: disp/imm 0x2520 -> TAIL
  if(/\+ 0x2520\]/.test(ins)||/^add eax, 0x2520$/.test(ins)){
    const needle=le32(0x2520);const idx=hex.indexOf(needle);
    if(idx<0||idx%2||hex.indexOf(needle,idx+2)>=0)throw new Error('disp lookup '+a.toString(16)+' '+ins+' '+hex);
    add(a,hex,hex.slice(0,idx)+le32(TAIL)+hex.slice(idx+8),'spellbook base 0x2520 -> tail 0x'+TAIL.toString(16)+': '+ins);
  }
  // (2) last-slot constant access (ini writer)
  if(/\[edi \+ 0x305c\]/.test(ins)){
    const needle=le32(0x305c);const idx=hex.indexOf(needle);
    add(a,hex,hex.slice(0,idx)+le32(TAIL+(NEW_SLOTS-1)*4)+hex.slice(idx+8),'last spellbook slot: '+ins);
  }
  // (3) 720 / 719 bounds
  if(BOUND_FNS.has(f)&&!/\[/.test(ins)&&/(, |push )0x(2d0|2cf)$/.test(ins)){
    const v=/0x2d0$/.test(ins)?OLD_SLOTS:OLD_SLOTS-1, nv=v===OLD_SLOTS?NEW_SLOTS:NEW_SLOTS-1;
    if(!hex.endsWith(le32(v)))throw new Error('imm '+a.toString(16)+' '+ins+' '+hex);
    add(a,hex,hex.slice(0,-8)+le32(nv),'slot bound '+v+' -> '+nv+': '+ins+' (fn '+f+')');
  }
}
// (4) allocation sizes of the objects that own the spellbook (see notes)
for(const [va,old] of [[0x7bec13,0x9950],[0x7cd1e5,0x9950],[0x460876,0x3488]]){
  const e=byAddr.get(va);if(!e||e.ins!=='push 0x'+old.toString(16))throw new Error('alloc '+va.toString(16)+' '+(e&&e.ins));
  add(va,e.hex,'68'+le32(ALLOC),'allocate 0x'+ALLOC.toString(16)+' bytes (was 0x'+old.toString(16)+') so the 1440-slot spellbook fits after the object');
}
// (5) UI page limit: 90 pages (left page max 0x58) -> 180 pages (left page max 0xB2)
{ const start=0x75d599, end=0x75d5b3; // 26 bytes, rewritten whole
  let exp='';for(let a=start;a<end;){const e=byAddr.get(a);if(!e)throw new Error('ui '+a.toString(16));exp+=e.hex;a+=e.hex.length/2}
  if(exp.length!==52)throw new Error('ui len '+exp.length);
  const rep='3d'+le32(0xB2)+'7e13'+'b8'+le32(0xB2)+'eb0c'+'90'.repeat(12);
  if(rep.length!==52)throw new Error('ui rep len '+rep.length);
  add(start,exp,rep,'page limit: left page max 0x58 (90 pages) -> 0xB2 (180 pages)');
}
fs.writeFileSync('patch-table.json',JSON.stringify(patches,null,1));
console.log(patches.length,'patches');
const cnt={};for(const p of patches){const k=p.why.split(':')[0].split(' (')[0];cnt[k]=(cnt[k]||0)+1}console.log(cnt);
