// Every English string shown through t() or marked with k() has a French translation,
// with the same {placeholders}. Run: node scripts/test-i18n.cjs
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const ts=require('typescript');
const root=path.resolve(__dirname,'../app');
function files(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?files(path.join(dir,e.name)):/\.(tsx?|ts)$/.test(e.name)?[path.join(dir,e.name)]:[]);}
function load(file){const out=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;const m={exports:{}};new Function('exports','require','module',out)(m.exports,require,m);return m.exports;}
const FR=load(path.join(root,'i18n-fr.ts')).FR;
/** Literal arguments of t(...) and k(...), including both sides of a ternary or a lookup map. */
function keys(){
 const found=new Set();
 for(const file of files(root)){
  if(/i18n(-fr)?\.ts$|legal\.ts$/.test(file))continue;
  const src=fs.readFileSync(file,'utf8');
  const call=/\b[tk]\(/g;let m;
  while((m=call.exec(src))){
   let depth=1,i=m.index+m[0].length,start=i;
   for(;i<src.length&&depth>0;i++){const c=src[i];if(c==='('||c==='{'||c==='[')depth++;else if(c===')'||c==='}'||c===']')depth--;else if(depth===1&&c===',')break;else if(c==="'"){i++;while(i<src.length&&src[i]!=="'")i+=src[i]==='\\'?2:1;}}
   const arg=src.slice(start,i);
   for(const lit of arg.matchAll(/'((?:[^'\\]|\\.)*)'/g)){const s=lit[1];if(/[a-z]/.test(s)&&(/^[A-Z{]/.test(s)||/\s/.test(s)))found.add(s);}
  }
 }
 return [...found].sort();
}
test('every shown string has French',()=>{
 const missing=keys().filter(k=>!(k in FR));
 assert.deepEqual(missing,[],'Missing French:\n'+missing.join('\n'));
});
test('placeholders match between English and French',()=>{
 for(const [en,fr] of Object.entries(FR)){
  const names=s=>(s.match(/\{\w+\}/g)??[]).sort().join(',');
  assert.equal(names(fr),names(en),`Placeholders differ for: ${en}`);
 }
});
if(process.argv.includes('--list'))console.log(JSON.stringify(keys().filter(k=>!(k in FR)),null,1));
