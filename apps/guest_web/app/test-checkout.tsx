'use client';
import {useEffect,useRef,useState} from 'react';
import {guestRequest} from './guest-identity';
import {money,PaymentLogo,Row,Icon} from './components';

type Payment={id:string;reference:string;collection_name:string;payer_name:string;amount:number;fee_amount:number;total_amount:number;method:'MTN'|'ORANGE';note:string;status:'PENDING'|'SUCCEEDED'|'FAILED'|'CANCELLED';created_at:number;completed_at:number|null};
type Stage='amount'|'review'|'method'|'pay'|'result'|'receipt'|'history';
export default function TestCheckout({token,name,collection,expected,onBack}:{token:string;name:string;collection:string;expected:number|null;onBack:()=>void}) {
 const [stage,setStage]=useState<Stage>('amount');
 const [amount,setAmount]=useState(expected?.toString()??'');
 const [note,setNote]=useState(''),[method,setMethod]=useState<'MTN'|'ORANGE'>('MTN');
 const [confirmed,setConfirmed]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const [payment,setPayment]=useState<Payment|null>(null),[rows,setRows]=useState<Payment[]>([]),[cursor,setCursor]=useState<string|null>(null);
 const lock=useRef(false), request=useRef<Record<string,unknown>|null>(null), outcome=useRef<string|null>(null);
 const [lockedRequest,setLockedRequest]=useState(false);
 const [uncertain,setUncertain]=useState(false);
 const n=Number(amount);
 const heading=useRef<HTMLHeadingElement>(null);
 const title={amount:'Contribute',review:'Confirm contribution',method:'Choose payment method',pay:'Test payment',result:'Payment result',receipt:'Test receipt',history:'My test payments'}[stage];
 useEffect(()=>{heading.current?.focus();window.scrollTo({top:0,behavior:'instant'});},[stage]);
 async function run(action:()=>Promise<void>) {
  if(lock.current)return;lock.current=true;setBusy(true);setError('');
  try{await action();}catch(e){setError(e instanceof Error?e.message:'Please retry.');}
  finally{lock.current=false;setBusy(false);}
 }
 function review(){if(!/^\d+$/.test(amount)||!Number.isSafeInteger(n)||n<=0||n>1e12){setError('Enter a positive whole FCFA amount.');return;}setError('');setStage('review');}
 async function create(){await run(async()=>{
  if(!request.current){request.current={action:'payment-create',token,amount:n,note:note.trim(),method,request_key:crypto.randomUUID()};setLockedRequest(true);}
  const data:Payment=await guestRequest(request.current);setPayment(data);setStage(data.status==='PENDING'?'pay':'result');
 });}
 async function finish(status:string){await run(async()=>{
  outcome.current??=status;setUncertain(true);
  const data:Payment=await guestRequest({action:'payment-result',id:payment!.id,status:outcome.current});
  outcome.current=null;setUncertain(false);setPayment(data);setStage('result');
 });}
 async function detail(id:string,receipt=false){await run(async()=>{
  const data:Payment=await guestRequest({action:'payment-detail',id});setPayment(data);
  if(data.status!=='PENDING'){outcome.current=null;setUncertain(false);}
  setStage(data.status==='PENDING'?'pay':receipt&&data.status==='SUCCEEDED'?'receipt':'result');
 });}
 async function history(more=false){await run(async()=>{
  const data=await guestRequest({action:'payment-history',token,...(more&&cursor?{before:cursor}:{})});
  setRows(old=>more?[...old,...data.items]:data.items);setCursor(data.next_cursor);setStage('history');
 });}
 function restart(){request.current=null;outcome.current=null;setLockedRequest(false);setUncertain(false);setPayment(null);setConfirmed(false);setError('');setStage('amount');}
 const methodName=(m:string)=>m==='MTN'?'MTN Mobile Money':'Orange Money';
 return <>
  <header className="screen-header"><h1 ref={heading} tabIndex={-1}>{title}</h1><span className="badge">Test only</span></header>
  <div className="screen-content">
   <p className="helper">No money moves. Attempts and results are saved on Sendoh.</p>
   <p><strong>{payment?.collection_name??collection}</strong><br/>Contributing as {payment?.payer_name??name}</p>
   {busy&&<p role="status">Saving / loading…</p>}
   {error&&<p className="error" role="alert">{error}</p>}
   {stage==='amount'&&<>
    <h2>How much would you like to contribute?</h2>
    {expected!==null&&<p>Expected contribution: {money(expected)}</p>}
    <div className="amount-options">{Array.from(new Set([500,1000,1500,expected??3000])).map(v=><button key={v} disabled={busy} onClick={()=>setAmount(String(v))}>{v.toLocaleString('en')}</button>)}</div>
    <label className="field">Amount (FCFA)<input inputMode="numeric" value={amount} onChange={e=>setAmount(e.target.value)} maxLength={13}/></label>
    <label className="field">Note (optional)<textarea value={note} onChange={e=>setNote(e.target.value)} maxLength={200}/></label>
    <button className="button" disabled={busy} onClick={review}>Continue</button>
   </>}
   {stage==='review'&&<>
    <div className="summary"><Row label="Your contribution">{money(n)}</Row><Row label="Test provider fee">0 FCFA</Row><Row label="Test total" strong>{money(n)}</Row></div>
    <p>The full amount goes to the test collection total. Live fees will be shown before real payments launch.</p>
    {note&&<p>{note}</p>}
    <label className="confirmation"><input type="checkbox" checked={confirmed} onChange={e=>setConfirmed(e.target.checked)}/>I confirm these details.</label>
    <button className="button" disabled={!confirmed||busy} onClick={()=>setStage('method')}>Continue to payment method</button>
    <button className="text-button" onClick={()=>setStage('amount')}>Back</button>
   </>}
   {stage==='method'&&<>
    <fieldset className="methods"><legend>Choose payment method</legend>{(['MTN','ORANGE'] as const).map(m=><label className={`method ${method===m?'chosen':''}`} key={m}><input type="radio" name="method" checked={method===m} disabled={busy||lockedRequest} onChange={()=>setMethod(m)}/><PaymentLogo method={m}/><strong>{methodName(m)}</strong></label>)}</fieldset>
    <button className="button" disabled={busy} onClick={create}>{lockedRequest?'Retry same payment request':'Continue to pay'}</button>
    {!lockedRequest&&<button className="text-button" onClick={()=>setStage('review')}>Back</button>}
   </>}
   {stage==='pay'&&payment&&<>
    <div className="pay-context"><h2>{money(payment.total_amount)}</h2><PaymentLogo method={payment.method}/><strong>{methodName(payment.method)}</strong></div>
    <p>Your pending attempt is saved. Choose a test result below. No mobile money request is sent.</p>
    {uncertain?<button className="button" disabled={busy} onClick={()=>finish(outcome.current!)}>Retry saving the same result</button>:<>
     <button className="button" disabled={busy} onClick={()=>finish('SUCCEEDED')}>Simulate successful payment</button>
     <button className="button secondary" disabled={busy} onClick={()=>finish('FAILED')}>Simulate failed payment</button>
     <button className="text-button" disabled={busy} onClick={()=>finish('CANCELLED')}>Cancel test payment</button>
    </>}
    <button className="text-button" disabled={busy} onClick={()=>detail(payment.id)}>Refresh payment status</button>
   </>}
   {stage==='result'&&payment&&<>
    <div className="center"><Icon name={payment.status==='SUCCEEDED'?'check':'info'} size={48}/><h2>{payment.status==='SUCCEEDED'?'Test contribution successful':`Test payment ${payment.status.toLowerCase()}`}</h2><p>{money(payment.amount)}</p></div>
    <p>{payment.status==='SUCCEEDED'?'Saved. The organizer’s test total and activity have been updated.':'Saved. This attempt did not increase the test total.'} No money moved.</p>
    {payment.status==='SUCCEEDED'?<button className="button" disabled={busy} onClick={()=>detail(payment.id,true)}>View test receipt</button>:<button className="button" disabled={busy} onClick={restart}>Start a new attempt</button>}
   </>}
   {stage==='receipt'&&payment&&<>
    <h2>TEST • Not proof of payment</h2>
    <div className="summary"><Row label="Contributor">{payment.payer_name}</Row><Row label="Collection">{payment.collection_name}</Row><Row label="Amount">{money(payment.amount)}</Row><Row label="Fee">{money(payment.fee_amount)}</Row><Row label="Method">{methodName(payment.method)}</Row><Row label="Reference">{payment.reference}</Row><Row label="Recorded">{new Date(payment.completed_at!*1000).toLocaleString()}</Row></div>
    {payment.note&&<p>{payment.note}</p>}<p>Persisted test receipt. No real funds were received.</p>
    <button className="button secondary" onClick={()=>window.print()}>Print / save receipt</button>
   </>}
   {stage==='history'&&<>
    {!rows.length&&<p>No test payments yet.</p>}
    {rows.map(p=><button className="button secondary" key={p.id} disabled={busy} onClick={()=>detail(p.id,p.status==='SUCCEEDED')}>{money(p.amount)} • {p.status} • {methodName(p.method)}</button>)}
    {cursor&&<button className="text-button" disabled={busy} onClick={()=>history(true)}>Load older payments</button>}
    <button className="button" disabled={busy} onClick={restart}>New test contribution</button>
   </>}
   <div className="screen-actions">
    {stage!=='history'&&<button className="text-button" disabled={busy} onClick={()=>history()}>My saved payments and receipts</button>}
    <button className="button secondary" disabled={busy} onClick={onBack}>View collection</button>
   </div>
  </div>
 </>;
}
