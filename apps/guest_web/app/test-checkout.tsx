'use client';
import {useEffect,useRef,useState} from 'react';
import {guestRequest} from './guest-identity';
import {money,PaymentLogo,Row,Icon} from './components';
import {FIRST_POLL_DELAY,nextPollDelay,SLOW_CONFIRMATION_SECONDS,personalContribution,pendingCopy,type ContributionSummary,type Phase} from './c/[token]/contribution-state';

type Payment={id:string;reference:string;amount:number;method:'MTN'|'ORANGE';status:'PENDING'|'SUCCEEDED'|'FAILED'|'REFUNDED';phase?:Phase;payer_masked?:string|null;mode:string;created_at:number;updated_at:number};
/** The backend's review terms: nothing is created or charged by a quote. */
type Quote={credited_to:{name:string;collection:string;organizer:string};method:'MTN'|'ORANGE';payer_masked:string;contribution:number;payer_fees:number;total:number;fees_from:string};
type Stage='amount'|'review'|'pay'|'result'|'receipt'|'history';
type Draft={action:'payment-create';token:string;amount:number;method:'MTN'|'ORANGE';payer_phone:string;request_key:string;id?:string};
export default function ProviderCheckout({token,name,collection,expected,start,onBack}:{token:string;name:string;collection:string;expected:number|null;start?:'history';onBack:()=>void}) {
 const [stage,setStage]=useState<Stage>('amount');
 const [amount,setAmount]=useState(expected?.toString()??''),[phone,setPhone]=useState('');
 const [method,setMethod]=useState<'MTN'|'ORANGE'>('MTN');
 const [ready,setReady]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const [payment,setPayment]=useState<Payment|null>(null),[rows,setRows]=useState<Payment[]>([]);
 const [cursor,setCursor]=useState<string|null>(null),[locked,setLocked]=useState(false);
 const [quote,setQuote]=useState<Quote|null>(null),[standing,setStanding]=useState<string|null>(null);
 const lock=useRef(false),draft=useRef<Draft|null>(null),storageKey=useRef<string|null>(null);
 const unresolvedId=useRef<string|null>(null);
 const alive=useRef(true),heading=useRef<HTMLHeadingElement>(null);
 const title={amount:'Contribute',review:'Review contribution',pay:'Payment status',result:'Payment result',receipt:'Contribution receipt',history:'Your contributions'}[stage];
 const methodName=(m:string)=>m==='MTN'?'MTN MoMo':'Orange Money';
 useEffect(()=>{heading.current?.focus();},[stage]);
 function present(p:Payment,receipt=false) {
  if(!alive.current)return;
  if(p.status==='PENDING')unresolvedId.current=p.id;
  else if(unresolvedId.current===p.id)unresolvedId.current=null;
  setPayment(p);
  setStage(p.status==='PENDING'?'pay':receipt&&p.status==='SUCCEEDED'?'receipt':'result');
  if(p.status==='SUCCEEDED')void standingAfter();
 }
 /** After a verified contribution, say where Marie's own share stands, from the server. */
 async function standingAfter(){
  try{
   const d=await guestRequest({action:'context',token});
   const part=d.participant;if(!part||!alive.current)return;
   const s=personalContribution((part.contribution_summary??null) as ContributionSummary|null,part.expected_amount??null);
   setStanding(s.fulfilled?'Your share is paid':s.remaining!==null&&s.remaining>0?`${money(s.remaining)} left`:`${money(s.paid+s.cash)} contributed`);
  }catch{/* The collection page shows it on return. */}
 }
 async function loadQuote(){
  setQuote(await guestRequest({action:'payment-quote',token,amount:Number(amount),method,payer_phone:phone.trim()}));
 }
 async function run(action:()=>Promise<void>) {
  if(lock.current)return; lock.current=true;setBusy(true);setError('');
  try {await action();} catch(e){if(alive.current)setError(e instanceof Error?e.message:'Please try again.');}
  finally{lock.current=false;if(alive.current)setBusy(false);}
 }
 async function restore() {
  await run(async()=>{
   const context=await guestRequest({action:'context',token});
   storageKey.current='sendoh-provider:'+context.user_id+':'+token;
   const saved=sessionStorage.getItem(storageKey.current);
   if(!saved)setPhone(context.phone??'');
   if(saved){
    const envelope=JSON.parse(saved) as Draft;
    if(envelope.token!==token || typeof envelope.request_key!=='string' ||
       !Number.isSafeInteger(envelope.amount) || typeof envelope.payer_phone!=='string' ||
       !['MTN','ORANGE'].includes(envelope.method)) throw new Error('Your saved payment could not be read. Check your contribution history before retrying.');
    draft.current=envelope;setLocked(true);setAmount(String(envelope.amount));
    setPhone(envelope.payer_phone);setMethod(envelope.method);setStage('review');
    try{setQuote(await guestRequest({action:'payment-quote',token,amount:envelope.amount,method:envelope.method,payer_phone:envelope.payer_phone}));}catch{/* Recovery still works without it. */}
    if(envelope.id)present(await guestRequest({action:'payment-detail',id:envelope.id}));
   }
   const history=await guestRequest({action:'payment-history',token});
   const pending=(history.items as Payment[]).find(p=>p.status==='PENDING');
   if(pending && !draft.current?.id)present(pending);
   // A returning contributor whose part is paid sees their record, not a blank amount form.
   else if(!saved && start==='history' && alive.current){
    setRows(history.items);setCursor(history.next_cursor??null);setStage('history');
   }
   if(alive.current)setReady(true);
  });
 }
 useEffect(()=>{
  alive.current=true;void restore();
  return()=>{alive.current=false;};
  // This component is mounted for one collection and authenticated guest.
  // eslint-disable-next-line react-hooks/exhaustive-deps
 },[token]);
 useEffect(()=>{
  if(!payment || payment.status!=='PENDING' || stage!=='pay')return;
  // Quiet background checks: no busy state, no disabled buttons, no error flashes.
  // "Check status" remains the explicit, visible check.
  const id=payment.id;let delay=FIRST_POLL_DELAY,stopped=false;
  let timer:ReturnType<typeof setTimeout>|undefined;
  const schedule=()=>{if(!stopped)timer=setTimeout(()=>void tick(),delay);};
  async function tick(){
   if(stopped)return;
   if(document.visibilityState==='visible'&&!lock.current){
    try{const p=await guestRequest({action:'payment-refresh',id});if(!stopped)present(p);}
    catch{/* The next check, or Check status, retries. */}
   }
   delay=nextPollDelay(delay);schedule();
  }
  // Coming back from the Mobile Money prompt checks straight away.
  const onVisible=()=>{
   if(document.visibilityState!=='visible'||stopped)return;
   clearTimeout(timer);delay=FIRST_POLL_DELAY;void tick();
  };
  document.addEventListener('visibilitychange',onVisible);
  schedule();
  return()=>{stopped=true;clearTimeout(timer);document.removeEventListener('visibilitychange',onVisible);};
 },[payment?.id,payment?.status,stage]);
 function review(){
  if(!/^\d+$/.test(amount)||!Number.isSafeInteger(Number(amount))||Number(amount)<=0||Number(amount)>1000000000){
   setError('Enter a positive whole FCFA amount.');return;
  }
  if(!/^(?:\+?237)?6[0-9]{8}$/.test(phone.trim())){
   setError('Enter the Mobile Money number that will authorise this contribution.');return;
  }
  setError('');
  void run(async()=>{await loadQuote();setStage('review');});
 }
 async function submit(){await run(async()=>{
  if(!ready||!storageKey.current)return;
  if(!draft.current){
   draft.current={action:'payment-create',token,amount:Number(amount),method,
    payer_phone:phone.trim(),request_key:crypto.randomUUID()};
  }
  // Persist before dispatch; a timeout reuses this exact attempt and body.
  sessionStorage.setItem(storageKey.current,JSON.stringify(draft.current));
  setLocked(true);
  const {id:_id,...body}=draft.current;
  const result:Payment=await guestRequest(body);
  present(result);
  draft.current.id=result.id;
  sessionStorage.setItem(storageKey.current,JSON.stringify(draft.current));
 });}
 async function detail(id:string,receipt=false){await run(async()=>{
  present(await guestRequest({action:'payment-detail',id}),receipt);
 });}
 async function history(more=false){await run(async()=>{
  const data=await guestRequest({action:'payment-history',token,...(more&&cursor?{before:cursor}:{})});
  setRows(old=>more?[...old,...data.items]:data.items);setCursor(data.next_cursor??null);setStage('history');
 });}
 function restart(){
  if(unresolvedId.current){void detail(unresolvedId.current);return;}
  if(draft.current && draft.current.id!==payment?.id){
   if(draft.current.id){void detail(draft.current.id);}
   else {setStage('review');}
   return;
  }
  if(!payment || payment.status==='PENDING')return;
  if(storageKey.current)sessionStorage.removeItem(storageKey.current);
  draft.current=null;setLocked(false);setPayment(null);setError('');setStage('amount');
 }
 return <>
  <header className="screen-header"><h1 ref={heading} tabIndex={-1}>{title}</h1><span className="badge">Sandbox</span></header>
  <div className="screen-content">
   <div className="contribution-context"><span className="avatar" aria-hidden="true">{name.slice(0,1).toUpperCase()}</span><p><strong>{collection}</strong><br/>Contributing as {name}</p></div>
   {busy&&<p role="status">Checking your contribution…</p>}
   {error&&<p className="error" role="alert">{error}</p>}
   {!ready&&!busy&&<button className="button" onClick={()=>void restore()}>Reconnect</button>}
   {stage==='amount'&&<>
    <h2>Your contribution</h2>
    {expected!==null&&<p>Suggested contribution: {money(expected)}</p>}
    <label className="field">Amount (FCFA)<input inputMode="numeric" value={amount} disabled={busy||!ready} onChange={e=>setAmount(e.target.value)} maxLength={10}/></label>
    <fieldset className="methods"><legend>Pay with Mobile Money</legend>{(['MTN','ORANGE'] as const).map(m=><label className={`method ${method===m?'chosen':''}`} key={m}><input type="radio" name="method" checked={method===m} disabled={busy||!ready} onChange={()=>setMethod(m)}/><PaymentLogo method={m}/><strong>{methodName(m)}</strong></label>)}</fieldset>
    <label className="field">Mobile Money number<input inputMode="tel" autoComplete="tel" value={phone} disabled={busy||!ready} onChange={e=>setPhone(e.target.value)} placeholder="+237" maxLength={13}/></label>
    <button className="button" disabled={busy||!ready} onClick={review}>Review contribution</button>
   </>}
   {stage==='review'&&<>
    {quote?<>
     <div className="review-amount">{money(quote.total)}</div>
     <div className="summary">
      <Row label="Credited to">{quote.credited_to.name} · {quote.credited_to.collection}</Row>
      <Row label="Organizer">{quote.credited_to.organizer}</Row>
      <Row label="Pay with">{methodName(quote.method)} {quote.payer_masked}</Row>
      <Row label="Contribution">{money(quote.contribution)}</Row>
      <Row label="Fees">{money(quote.payer_fees)}</Row>
      <Row label="Total to approve" strong>{money(quote.total)}</Row>
     </div>
     {quote.fees_from==='COLLECTION_PROCEEDS'&&<p className="helper">MeSomb’s processing fee is taken from the collection, not added to your total.</p>}
    </>:<p role="status">Getting your payment details…</p>}
    <button className="button" disabled={busy||!ready||!quote} onClick={submit}>{locked?'Recover this contribution':quote?`Approve ${money(quote.total)}`:'Approve'}</button>
    {!locked&&<button className="text-button" disabled={busy} onClick={()=>setStage('amount')}>Edit details</button>}
   </>}
   {stage==='pay'&&payment&&<>
    {(()=>{const copy=pendingCopy(payment,methodName(payment.method));return <>
     <div className="center" aria-live="polite"><Icon name="info" size={40}/><h2>{copy.title}</h2><p>{money(payment.amount)}{payment.payer_masked?` · ${methodName(payment.method)} ${payment.payer_masked}`:''}</p></div>
     <p role="status">{copy.body}</p>
    </>;})()}
    <p className="helper">You can return to this link to check your contribution.</p>
    <button className="button" disabled={busy} onClick={()=>void run(async()=>present(await guestRequest({action:'payment-refresh',id:payment.id})))}>Check status</button>
   </>}
   {stage==='result'&&payment&&<>
    <div className="center"><Icon name={payment.status==='SUCCEEDED'?'check':'info'} size={48}/><h2>{payment.status==='SUCCEEDED'?'Contribution confirmed':payment.status==='REFUNDED'?'Contribution refunded':'Payment unsuccessful'}</h2><p>{money(payment.amount)}</p>{payment.status==='SUCCEEDED'&&standing&&<p><strong>{standing}</strong></p>}</div>
    <p>{payment.status==='SUCCEEDED'?'Your contribution is recorded in the collection.':payment.status==='REFUNDED'?'This contribution no longer counts toward the collection.':'This attempt has not increased the collection total.'}</p>
    {payment.status==='SUCCEEDED'?<button className="button" disabled={busy} onClick={()=>void detail(payment.id,true)}>View receipt</button>:<button className="button" disabled={busy} onClick={restart}>Make another contribution</button>}
    {payment.status==='SUCCEEDED'&&<button className="text-button" disabled={busy} onClick={restart}>Make another contribution</button>}
   </>}
   {stage==='receipt'&&payment&&<>
    <h2>{money(payment.amount)}</h2>
    <div className="summary"><Row label="Contributor">{name}</Row><Row label="Collection">{collection}</Row><Row label="Status">Confirmed</Row><Row label="Method">{methodName(payment.method)}{payment.payer_masked?` ${payment.payer_masked}`:''}</Row><Row label="Reference">{payment.reference}</Row><Row label="Last verified">{new Date(payment.updated_at*1000).toLocaleString()}</Row></div>
    <p className="helper">Sandbox receipt</p>
    <button className="button secondary" onClick={()=>window.print()}>Print / save receipt</button>
   </>}
   {stage==='history'&&<>
    {!rows.length&&<p>No contributions yet.</p>}
    {rows.map(p=><button className="button secondary" key={p.id} disabled={busy} onClick={()=>void detail(p.id,p.status==='SUCCEEDED')}>{money(p.amount)} · {{PENDING:'Confirming',SUCCEEDED:'Confirmed',FAILED:'Unsuccessful',REFUNDED:'Refunded'}[p.status]} · {methodName(p.method)}</button>)}
    {cursor&&<button className="text-button" disabled={busy} onClick={()=>void history(true)}>Load older contributions</button>}
    {locked&&!payment&&<button className="button" disabled={busy} onClick={()=>setStage('review')}>Recover saved contribution</button>}
    {payment&&payment.status!=='PENDING'&&<button className="text-button" disabled={busy} onClick={restart}>Make another contribution</button>}
    {!payment&&!locked&&!rows.some(p=>p.status==='PENDING')&&<button className="text-button" disabled={busy||!ready} onClick={()=>setStage('amount')}>Make another contribution</button>}
   </>}
   <div className="screen-actions">
    {stage!=='history'&&<button className="text-button" disabled={busy||!ready} onClick={()=>void history()}>Your contributions and receipts</button>}
    <button className="button secondary" disabled={busy} onClick={onBack}>Back to collection</button>
   </div>
  </div>
 </>;
}
