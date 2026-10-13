'use client';
import GuestIdentity,{guestRequest} from '../../guest-identity';
import {useEffect,useRef,useState,type FormEvent} from 'react';
import {CollectionIcon,GuestChrome,Icon,money,PaymentLogo,Row} from '../../components';

export type CollectionData={name:string;description:string;organizer_name:string;currency:string;target_amount:number|null;collected_amount:number;expected_amount:number|null;mode:string;deadline_at:string|null;status:string};
type Step='collection'|'identity'|'amount'|'review'|'method'|'pay'|'result'|'receipt';
const steps:Step[]=['collection','identity','amount','review','method','pay'];
const titles:Record<Step,string>={collection:'',identity:'Identify yourself',amount:'Contribute',review:'Confirm contribution',method:'Choose payment method',pay:'Your payment',result:'Demo result',receipt:'Demo receipt'};

export default function ContributionFlow({collection:c,token}:{collection:CollectionData;token?:string}) {
 const [outcome,setOutcome]=useState('success');
 const [reference,setReference]=useState('');
 const [joining,setJoining]=useState(false);
 const [verified,setVerified]=useState(false);
 const [step,setStep]=useState<Step>('collection');
 const [name,setName]=useState(''); const [phone,setPhone]=useState('');
 const [amount,setAmount]=useState(c.expected_amount?.toString()??''); const [note,setNote]=useState('');
 const [confirmed,setConfirmed]=useState(false); const [method,setMethod]=useState<'MTN'|'ORANGE'>('MTN');
 const [error,setError]=useState(''); const heading=useRef<HTMLHeadingElement>(null); const firstRender=useRef(true);
 const n=Number(amount); const validAmount=/^[0-9]+$/.test(amount)&&Number.isSafeInteger(n)&&n>0&&n<=1_000_000_000_000;
 const percent=c.target_amount?100*c.collected_amount/c.target_amount:0;
 const suggested=Array.from(new Set([500,1000,1500,...(c.expected_amount?[c.expected_amount]:[3000])]));
 const go=(next:Step)=>{setStep(next);setError('');};
 useEffect(()=>{if(firstRender.current){firstRender.current=false;return;} heading.current?.focus();window.scrollTo({top:0,behavior:'instant'});},[step]);
 async function identityReady() {
  if(!token)return;
  const data=await guestRequest({action:'context',token});
  setName(data.name);setPhone(data.phone.replace(/^\+237/,''));setVerified(true);
 }
 async function join() {
  if(!token||joining)return;
  setJoining(true);setError('');
  try {await guestRequest({action:'join',token});go('amount');}
  catch(e){setError(e instanceof Error?e.message:'Please retry.');}
  finally{setJoining(false);}
 }
 function simulate(value:string) {setOutcome(value);setReference('DEMO-'+Date.now().toString(36).toUpperCase());go('result');}
 const chooseAmount=(e:FormEvent)=>{e.preventDefault();if(!validAmount){setError('Enter a positive whole FCFA amount.');return;}go('review');};
 const back=()=>go(steps[Math.max(0,steps.indexOf(step)-1)]);
 const collectionLine=<div className="collection-line"><CollectionIcon/><div><strong>{c.name}</strong><span>Organized by {c.organizer_name}</span></div></div>;
 return <GuestChrome><section className="screen">
  <header className="screen-header">{step!=='collection'&&<button className="icon-button" aria-label="Go back" onClick={back}><Icon/></button>}<h1 ref={heading} tabIndex={-1}>{step==='collection'?c.name:titles[step]}</h1>{step==='collection'&&<span className="badge">{c.status==='ACTIVE'?'Active':'Closed'}</span>}</header>
  {step==='collection'&&<div className="screen-content">
   {collectionLine}
   <div className="collection-meta">{c.target_amount!==null&&<p>{money(c.target_amount)} target</p>}<p>{c.deadline_at?`Deadline: ${new Date(c.deadline_at).toLocaleDateString('en-GB',{timeZone:'Africa/Douala',day:'numeric',month:'short',year:'numeric'})}`:'No deadline'}</p></div>
   <div className="collection-progress"><div className="progress-label"><span><strong>{new Intl.NumberFormat('en').format(c.collected_amount)}</strong> FCFA collected</span>{c.target_amount!==null&&<b>{Number(percent.toFixed(1))}%</b>}</div>{c.target_amount!==null&&<><progress className={percent>=100?'reached':''} value={Math.min(c.collected_amount,c.target_amount)} max={c.target_amount}/><p>{percent>=100?(percent>100?`${money(c.collected_amount-c.target_amount)} above target`:'Target reached'): `${money(c.target_amount-c.collected_amount)} remaining`}</p></>}</div>
   {c.description&&<div className="purpose"><h2>About this collection</h2><p>{c.description}</p></div>}
   <div className="soft-card"><h2>Contribute to this collection</h2><p>No app installation needed. Verify your number to join as yourself.</p>{c.expected_amount!==null&&<p className="expectation">{c.mode==='MINIMUM_TOTAL'?'Minimum total':'Expected contribution'}: <strong>{money(c.expected_amount)}</strong></p>}</div>
   <div className="screen-actions"><p className="availability"><Icon name="info" size={16}/>Demo payments only. No money will move.</p><button className="button" disabled={c.status!=='ACTIVE'} onClick={()=>go('identity')}>Continue</button></div>
  </div>}
  {step==='identity'&&<div className="screen-content">
   {token ? <>{!verified ? <GuestIdentity onVerified={identityReady}/> : <>
    <h2>Continue as {name}</h2><p>+237 {phone}</p>
    <p>This joins the collection as you. If the organizer already added your name manually, ask them to link that entry to your profile.</p>
    <button className="button" disabled={joining} onClick={join}>{joining?'Joining…':'Join and continue'}</button>
    <button className="text-button" onClick={async()=>{await guestRequest({action:'logout'});setVerified(false);}}>Use another number</button>
   </>}</> : <><h2>Design preview</h2><p>No identity is verified in this preview.</p><button className="button" onClick={()=>{setName('Demo contributor');go('amount');}}>Try demo flow</button></>}
   {error&&<p className="error" role="alert">{error}</p>}
  </div>}
  {step==='amount'&&<form className="screen-content" onSubmit={chooseAmount}>
   <h2 className="question">How much would you like to contribute?</h2>
   {c.expected_amount!==null?<p>Expected contribution: <strong>{money(c.expected_amount)}</strong></p>:<p>You can contribute any amount.</p>}
   <div className="amount-options" role="group" aria-label="Suggested amounts">{suggested.map(value=><button type="button" aria-pressed={amount===String(value)} className={amount===String(value)?'selected':''} key={value} onClick={()=>{setAmount(String(value));setConfirmed(false)}}>{value.toLocaleString('en')}</button>)}</div>
   <label className="field">Amount (FCFA)<input inputMode="numeric" value={amount} onChange={e=>{setAmount(e.target.value);setConfirmed(false)}} maxLength={13} required aria-describedby="amount-help" placeholder="Enter an amount"/></label>
   <p className="helper" id="amount-help">You can contribute less or more than the expected amount.</p>
   <label className="field">Note <span className="optional">(optional)</span><textarea value={note} onChange={e=>setNote(e.target.value)} maxLength={200} rows={3} placeholder="What’s this contribution for?"/></label>
   <div className="screen-actions">{error&&<p className="error" role="alert">{error}</p>}<button className="button">Continue</button></div>
  </form>}
  {step==='review'&&<div className="screen-content">
   <p className="eyebrow">Contributing as</p><div className="identity-line"><span className="avatar">{name.trim().slice(0,1).toUpperCase()}</span><div><strong>{name.trim()}</strong><small>+237 {phone.replace(/\s/g,'')}</small></div><button className="text-button" onClick={()=>go('identity')}>Edit</button></div>
   <p className="helper">For {c.name}</p>
   <div className="summary"><Row label="Your contribution">{money(n)}</Row><Row label="Demo provider cost">0 FCFA</Row><Row label="Demo total" strong>{money(n)}</Row></div>
   <p className="helper">{money(n)} would go to the collection. This demo uses zero fees. Live provider pricing will be shown before real payment; collection settlement fees are separate.</p>
   {note.trim()&&<div className="note"><span>Note</span><p>{note.trim()}</p></div>}
   <label className="confirmation"><input type="checkbox" checked={confirmed} onChange={e=>setConfirmed(e.target.checked)}/><span>I confirm the contributor and contribution amount are correct.</span></label>
   <div className="screen-actions"><button className="button" disabled={!confirmed} onClick={()=>go('method')}>Continue to payment method</button></div>
  </div>}
  {step==='method'&&<div className="screen-content"><p className="center method-hint">Choose how you’d like to pay</p><fieldset className="methods"><legend className="sr-only">Payment method</legend>{(['MTN','ORANGE'] as const).map(m=><label className={`method ${method===m?'chosen':''}`} key={m}><input type="radio" name="method" value={m} checked={method===m} onChange={()=>setMethod(m)}/><PaymentLogo method={m}/><strong>{m==='MTN'?'MTN Mobile Money':'Orange Money'}</strong><span className="radio-mark">{method===m&&<Icon name="check" size={13}/>}</span></label>)}<div className="method other-method"><Icon name="phone"/><div><strong>Other options</strong><small>Coming soon</small></div></div></fieldset><div className="screen-actions"><button className="button" onClick={()=>go('pay')}>Continue</button></div></div>}
  {step==='pay'&&<div className="screen-content payment-final">
   <div className="pay-context"><h2>{money(n)}</h2><p>For {c.name}</p><strong>{name}</strong><div className="payment-choice"><PaymentLogo method={method}/><strong>{method==='MTN'?'MTN Mobile Money':'Orange Money'}</strong></div></div>
   <div className="soft-card"><h2>Payment demo</h2><p>No provider request is sent. No money moves and the collection total stays unchanged.</p></div>
   <div className="screen-actions"><button className="button" onClick={()=>simulate('success')}>Simulate successful payment</button><button className="button secondary" onClick={()=>simulate('failed')}>Simulate failed payment</button><button className="text-button" onClick={()=>simulate('cancelled')}>Cancel</button></div>
  </div>}
  {step==='result'&&<div className="screen-content center"><h2>{outcome==='success'?'Demo contribution successful':outcome==='failed'?'Demo payment failed':'Demo payment cancelled'}</h2><p>{money(n)} for {c.name}</p><p>No money was charged. This is a simulation.</p><div className="screen-actions">{outcome==='success'?<button className="button" onClick={()=>go('receipt')}>View demo receipt</button>:<button className="button" onClick={()=>go('pay')}>Try again</button>}<button className="button secondary" onClick={()=>go('collection')}>View collection</button></div></div>}
  {step==='receipt'&&<div className="screen-content"><h2>DEMO • Not proof of payment</h2><div className="summary"><Row label="Contributor">{name}</Row><Row label="Collection">{c.name}</Row><Row label="Demo amount">{money(n)}</Row><Row label="Method">{method==='MTN'?'MTN Mobile Money':'Orange Money'}</Row><Row label="Demo reference">{reference}</Row></div><p>This preview is not saved as a contribution and cannot be used as a payment receipt.</p><button className="button" onClick={()=>go('collection')}>Back to collection</button></div>}
 </section></GuestChrome>;
}
