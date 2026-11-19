const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const Module=require('node:module');
const ts=require('typescript');
const source=path.resolve(__dirname,'../app/c/[token]/contribution-state.ts');
const compiled=ts.transpileModule(fs.readFileSync(source,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;
const loaded=new Module(source,module);loaded._compile(compiled,source);
const {personalContribution:state}=loaded.exports;
test('confirmed partial contribution reduces remaining amount',()=>{
 assert.deepEqual(state({live_available:true,confirmed_amount:400},1000),{paid:400,pending:false,remaining:600,fulfilled:false});
});
test('pending is never interpreted as confirmed money',()=>{
 assert.deepEqual(state({sandbox_payment_pending:true,sandbox_paid_amount:0},1000),{paid:0,pending:true,remaining:1000,fulfilled:false});
});
test('sandbox and live totals are not added together',()=>{
 assert.equal(state({live_available:true,confirmed_amount:200,sandbox_paid_amount:900},1000).remaining,800);
 assert.equal(state({live_available:false,sandbox_paid_amount:1000},1000).fulfilled,true);
});
test('legacy test money never establishes a paid share',()=>{
 assert.equal(state({test_paid_amount:1000},1000).fulfilled,false);
});
test('open contribution has no invented personal target',()=>{
 assert.deepEqual(state({sandbox_paid_amount:1000},null),{paid:1000,pending:false,remaining:null,fulfilled:false});
});
