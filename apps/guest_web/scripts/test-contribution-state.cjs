const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const Module=require('node:module');
const ts=require('typescript');
const source=path.resolve(__dirname,'../app/c/[token]/contribution-state.ts');
const compiled=ts.transpileModule(fs.readFileSync(source,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;
const loaded=new Module(source,module);loaded._compile(compiled,source);
const {personalContribution:state,nextPollDelay,FIRST_POLL_DELAY}=loaded.exports;
test('contract position is authoritative',()=>{
 const position={state:'CONFIRMING',membership:'ACCEPTED',environment:'SANDBOX',confirmed_amount:2000,pending_amount:1000,expected_amount:5000,remaining_amount:3000};
 assert.deepEqual(state({position,sandbox_paid_amount:9999},5000),{paid:2000,cash:0,pending:true,pendingAmount:1000,remaining:3000,fulfilled:false});
 assert.equal(state({position:{...position,state:'FULFILLED',pending_amount:0,confirmed_amount:5000,remaining_amount:0}},5000).fulfilled,true);
});
test('collection totals come from the contract, never the simulator',()=>{
 const {collectionTotals}=loaded.exports;
 assert.deepEqual(collectionTotals({totals:{environment:'SANDBOX',confirmed_amount:30000,pending_amount:1000,target_amount:50000,remaining_amount:20000,target_reached:false,cash_amount:null}}),{confirmed:30000,cash:0,raised:30000,pending:1000,sandbox:true});
 assert.equal(collectionTotals({collected_amount:0,sandbox_collected_amount:1000,test_collected_amount:5000}).confirmed,1000);
});
test('pending is never interpreted as confirmed money',()=>{
 assert.deepEqual(state({sandbox_payment_pending:true,sandbox_paid_amount:0,sandbox_pending_amount:1000},1000),{paid:0,cash:0,pending:true,pendingAmount:1000,remaining:1000,fulfilled:false});
});
test('older backend uses provider sandbox money only',()=>{
 assert.equal(state({live_available:false,sandbox_paid_amount:1000},1000).fulfilled,true);
});
test('legacy test money never establishes a paid share',()=>{
 assert.equal(state({test_paid_amount:1000},1000).fulfilled,false);
});
test('open contribution has no invented personal target',()=>{
 assert.deepEqual(state({sandbox_paid_amount:1000},null),{paid:1000,cash:0,pending:false,pendingAmount:0,remaining:null,fulfilled:false});
});
test('confirmed and awaiting money are reported separately',()=>{
 const s=state({sandbox_paid_amount:2000,sandbox_payment_pending:true,sandbox_pending_amount:1000},5000);
 assert.equal(s.paid,2000);assert.equal(s.pendingAmount,1000);assert.equal(s.remaining,3000);assert.equal(s.fulfilled,false);
});
test('background checks back off to at most one per minute',()=>{
 let d=FIRST_POLL_DELAY;const seen=[];for(let i=0;i<6;i++){seen.push(d);d=nextPollDelay(d);}
 assert.deepEqual(seen,[5000,10000,20000,40000,60000,60000]);
});
test('recorded cash is reported beside Mobile Money, never merged',()=>{
 const {collectionTotals}=loaded.exports;
 const t=collectionTotals({totals:{environment:'SANDBOX',confirmed_amount:48000,pending_amount:0,cash_amount:6000,raised_amount:54000,target_amount:50000,remaining_amount:0,target_reached:true}});
 assert.deepEqual(t,{confirmed:48000,cash:6000,raised:54000,pending:0,sandbox:true});
 const position={state:'FULFILLED',membership:'ACCEPTED',environment:'SANDBOX',confirmed_amount:4000,pending_amount:0,cash_amount:1000,paid_amount:5000,expected_amount:5000,remaining_amount:0};
 const s=state({position},5000);
 assert.equal(s.paid,4000);assert.equal(s.cash,1000);assert.equal(s.fulfilled,true);
});
