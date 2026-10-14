'use client';
import {useState} from 'react';
import GuestIdentity,{guestRequest} from '../../guest-identity';
import TestCheckout from '../../test-checkout';
import {CollectionIcon,GuestChrome,money,Row} from '../../components';
export type CollectionData={name:string;description:string;organizer_name:string;currency:string;target_amount:number|null;collected_amount:number;test_collected_amount?:number;expected_amount:number|null;mode:string;deadline_at:string|null;status:string};
export default function ContributionFlow({collection,token}:{collection:CollectionData;token?:string}) {
 const [c,setCollection]=useState(collection);
 const [step,setStep]=useState<'collection'|'identity'|'checkout'>('collection');
 const [name,setName]=useState(''),[phone,setPhone]=useState(''),[verified,setVerified]=useState(false);
 const [busy,setBusy]=useState(false),[error,setError]=useState('');
 const [expected,setExpected]=useState(c.expected_amount);
 async function identityReady(){if(!token)return;const d=await guestRequest({action:'context',token});setName(d.name);setPhone(d.phone);setVerified(true);if(d.participant){setCollection(d.participant.collection);setExpected(d.participant.expected_amount);}}
 async function join(){if(!token||busy)return;setBusy(true);setError('');try{const d=await guestRequest({action:'join',token});setCollection(d.collection);setExpected(d.expected_amount);setStep('checkout');}catch(e){setError(e instanceof Error?e.message:'Please retry.');}finally{setBusy(false);}}
 async function back(){setStep('collection');try{await identityReady();}catch(e){setError(e instanceof Error?e.message:'Refresh this page to reload totals.');}}
 return <GuestChrome><section className="screen">
 {step==='checkout'&&token?<TestCheckout token={token} name={name} collection={c.name} expected={expected} onBack={()=>void back()}/>:<>
  <header className="screen-header"><h1>{step==='collection'?c.name:'Identify yourself'}</h1><span className="badge">{c.status==='ACTIVE'?'Active':'Closed'}</span></header>
  <div className="screen-content">
   {step==='collection'&&<>
    <div className="collection-line"><CollectionIcon/><div><strong>{c.name}</strong><span>Organized by {c.organizer_name}</span></div></div>
    <div className="collection-meta">{c.target_amount!==null&&<p>{money(c.target_amount)} target</p>}<p>{c.deadline_at?`Deadline: ${new Date(c.deadline_at).toLocaleDateString('en-GB',{timeZone:'Africa/Douala'})}`:'No deadline'}</p></div>
    <div className="collection-progress"><Row label="Real collected">{money(c.collected_amount)}</Row><Row label="Test collected (no money)">{money(c.test_collected_amount??0)}</Row>{c.target_amount!==null&&<><progress value={Math.min(c.test_collected_amount??0,c.target_amount)} max={c.target_amount}/><p>Test progress only</p></>}</div>
    {c.description&&<div className="purpose"><h2>About this collection</h2><p>{c.description}</p></div>}
    <div className="soft-card"><h2>Contribute to this collection</h2><p>No app installation needed. Verify your number to contribute as yourself.</p>{c.expected_amount!==null&&<p>{c.mode==='MINIMUM_TOTAL'?'Minimum total':'Expected contribution'}: {money(c.expected_amount)}</p>}</div>
    <div className="screen-actions"><p>Test payments are saved on Sendoh. No real money moves.</p><button className="button" disabled={c.status!=='ACTIVE'||!token} onClick={()=>setStep('identity')}>Continue</button>{!token&&<p>Visual preview only. Open a real collection link to test backend payments.</p>}</div>
   </>}
   {step==='identity'&&(!verified?<GuestIdentity onVerified={identityReady}/>:<>
    <h2>Continue as {name}</h2><p>{phone}</p><p>Your verified profile determines whose contribution is recorded.</p>
    <button className="button" disabled={busy} onClick={join}>{busy?'Opening…':'Join and continue'}</button>
    <button className="text-button" disabled={busy} onClick={async()=>{try{await guestRequest({action:'logout'});setVerified(false);}catch(e){setError(e instanceof Error?e.message:'Please retry.');}}}>Use another number</button>
   </>)}
   {error&&<p className="error" role="alert">{error}</p>}
  </div>
 </>}
 </section></GuestChrome>;
}
