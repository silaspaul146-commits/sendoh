'use client';
import {useEffect,useRef,useState,type FormEvent} from 'react';
import {CollectionIcon,Icon,money,PaymentLogo,Row} from '../../components';

export type CollectionData={name:string;description:string;organizer_name:string;currency:string;target_amount:number|null;collected_amount:number;expected_amount:number|null;mode:string;deadline_at:string|null;status:string};
type Step='collection'|'identity'|'amount'|'review'|'method'|'pay';
const steps:Step[]=['collection','identity','amount','review','method','pay'];
const titles:Record<Step,string>={collection:'',identity:'Identify yourself',amount:'Contribute',review:'Confirm contribution',method:'Choose payment method',pay:'Your payment'};

export default function ContributionFlow({collection:c}:{collection:CollectionData}) {
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
 const identity=(e:FormEvent)=>{e.preventDefault();if(!name.trim()){setError('Enter your name.');return;}if(!/^[26][0-9]{8}$/.test(phone.replace(/\s/g,''))){setError('Enter a valid 9-digit Cameroon phone number.');return;}go('amount');};
 const chooseAmount=(e:FormEvent)=>{e.preventDefault();if(!validAmount){setError('Enter a positive whole FCFA amount.');return;}go('review');};
 const back=()=>go(steps[Math.max(0,steps.indexOf(step)-1)]);
 const collectionLine=<div className="collection-line"><CollectionIcon/><div><strong>{c.name}</strong><span>Organized by {c.organizer_name}</span></div></div>;
 return <section className="screen">
  <header className="screen-header">{step!=='collection'&&<button className="icon-button" aria-label="Go back" onClick={back}><Icon/></button>}<h1 ref={heading} tabIndex={-1}>{step==='collection'?c.name:titles[step]}</h1>{step==='collection'&&<span className="badge">{c.status==='ACTIVE'?'Active':'Closed'}</span>}</header>
  {step==='collection'&&<div className="screen-content">
   {collectionLine}
   <div className="collection-meta">{c.target_amount!==null&&<p>{money(c.target_amount)} target</p>}<p>{c.deadline_at?`Deadline: ${new Date(c.deadline_at).toLocaleDateString('en-GB',{timeZone:'Africa/Douala',day:'numeric',month:'short',year:'numeric'})}`:'No deadline'}</p></div>
   <div className="collection-progress"><div className="progress-label"><span><strong>{new Intl.NumberFormat('en').format(c.collected_amount)}</strong> FCFA collected</span>{c.target_amount!==null&&<b>{Number(percent.toFixed(1))}%</b>}</div>{c.target_amount!==null&&<><progress className={percent>=100?'reached':''} value={Math.min(c.collected_amount,c.target_amount)} max={c.target_amount}/><p>{percent>=100?(percent>100?`${money(c.collected_amount-c.target_amount)} above target`:'Target reached'): `${money(c.target_amount-c.collected_amount)} remaining`}</p></>}</div>
   {c.description&&<div className="purpose"><h2>About this collection</h2><p>{c.description}</p></div>}
   <div className="soft-card"><h2>Contribute to this collection</h2><p>You don’t need a Sendoh account to contribute.</p>{c.expected_amount!==null&&<p className="expectation">{c.mode==='MINIMUM_TOTAL'?'Minimum total':'Expected contribution'}: <strong>{money(c.expected_amount)}</strong></p>}</div>
   <div className="screen-actions"><p className="availability"><Icon name="info" size={16}/>Payments are not available yet.</p><button className="button" disabled={c.status!=='ACTIVE'} onClick={()=>go('identity')}>Continue</button></div>
  </div>}
  {step==='identity'&&<form className="screen-content" onSubmit={identity}>
   <h2 className="question">Who are you contributing as?</h2><p>Enter your details so your contribution can be attributed correctly.</p>
   <label className="field">Full name<input value={name} onChange={e=>{setName(e.target.value);setConfirmed(false)}} autoComplete="name" maxLength={120} required placeholder="Your full name"/></label>
   <label className="field">Phone number<span className="phone-input"><span>+237</span><input value={phone} onChange={e=>{setPhone(e.target.value.replace(/[^0-9\s]/g,''));setConfirmed(false)}} autoComplete="tel-national" inputMode="tel" maxLength={12} required placeholder="670 12 34 56" aria-label="Phone number"/></span></label>
   <p className="helper">Use your own details. Your name and number are not shown to other guests.</p>
   <div className="screen-actions">{error&&<p className="error" role="alert">{error}</p>}<button className="button">Continue</button></div>
  </form>}
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
   <div className="summary"><Row label="Your contribution">{money(n)}</Row><Row label="Provider cost">Not available yet</Row><Row label="Sendoh fee">Not quoted yet</Row><Row label="Total charged" strong>Awaiting quote</Row></div>
   <p className="helper">{money(n)} would go to the collection. You’ll see the fees and exact total before you can pay.</p>
   {note.trim()&&<div className="note"><span>Note</span><p>{note.trim()}</p></div>}
   <label className="confirmation"><input type="checkbox" checked={confirmed} onChange={e=>setConfirmed(e.target.checked)}/><span>I confirm the contributor and contribution amount are correct.</span></label>
   <div className="screen-actions"><button className="button" disabled={!confirmed} onClick={()=>go('method')}>Continue to payment method</button></div>
  </div>}
  {step==='method'&&<div className="screen-content"><p className="center method-hint">Choose how you’d like to pay</p><fieldset className="methods"><legend className="sr-only">Payment method</legend>{(['MTN','ORANGE'] as const).map(m=><label className={`method ${method===m?'chosen':''}`} key={m}><input type="radio" name="method" value={m} checked={method===m} onChange={()=>setMethod(m)}/><PaymentLogo method={m}/><strong>{m==='MTN'?'MTN Mobile Money':'Orange Money'}</strong><span className="radio-mark">{method===m&&<Icon name="check" size={13}/>}</span></label>)}<div className="method other-method"><Icon name="phone"/><div><strong>Other options</strong><small>Coming soon</small></div></div></fieldset><div className="screen-actions"><button className="button" onClick={()=>go('pay')}>Continue</button></div></div>}
  {step==='pay'&&<div className="screen-content payment-final"><div className="pay-context"><h2>{money(n)}</h2><p>Your contribution</p><strong>{name.trim()}</strong><p>for</p><strong>{c.name}</strong><p className="using">Using</p><div className="payment-choice"><PaymentLogo method={method}/><strong>{method==='MTN'?'MTN Mobile Money':'Orange Money'}</strong></div></div><div className="soft-card payment-unavailable" role="status"><Icon name="info"/><div><h2>Payments aren’t available yet</h2><p>No payment has been requested and no money has been charged. Please check with the organizer.</p></div></div><div className="screen-actions"><button className="button" disabled>Payment unavailable</button><button className="button secondary" onClick={()=>go('collection')}>Back to collection</button><button className="text-button" onClick={()=>go('amount')}>Change contribution</button></div></div>}
 </section>;
}
