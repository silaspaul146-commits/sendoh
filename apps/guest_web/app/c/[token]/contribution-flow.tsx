'use client';
import {useEffect,useRef,useState} from 'react';
import GuestIdentity,{guestRequest,GuestRequestError} from '../../guest-identity';
import ProviderCheckout from '../../test-checkout';
import {GuestChrome,money} from '../../components';
import {personalContribution,type ContributionSummary} from './contribution-state';
export type CollectionData={name:string;description:string;organizer_name:string;currency:string;target_amount:number|null;collected_amount:number;test_collected_amount?:number;sandbox_collected_amount?:number;expected_amount:number|null;mode:string;deadline_at:string|null;status:string};
export default function ContributionFlow({collection,token}:{collection:CollectionData;token?:string}) {
 const [c,setCollection]=useState(collection);
 const contextVersion=useRef(0);
 const collected=c.collected_amount>0?c.collected_amount:(c.sandbox_collected_amount??0);
 const [step,setStep]=useState<'collection'|'identity'|'checkout'>('collection');
 const [name,setName]=useState(''),[phone,setPhone]=useState(''),[verified,setVerified]=useState(false);
 const [busy,setBusy]=useState(false),[error,setError]=useState('');
 const [expected,setExpected]=useState(c.expected_amount);
 const [summary,setSummary]=useState<ContributionSummary|null>(null);
 const personal=personalContribution(summary,expected);
 function acceptContext(d:any){
  setName(d.name);setPhone(d.phone);setVerified(Boolean(d.name));
  if(d.participant){setCollection(d.participant.collection);setExpected(d.participant.expected_amount);setSummary(d.participant.contribution_summary??null);}
  else {setSummary(null);setExpected(c.expected_amount);}
 }
 function forgetIdentity(){contextVersion.current++;setVerified(false);setSummary(null);setName('');setPhone('');}
 async function identityReady(){if(!token)return;const version=++contextVersion.current;const d=await guestRequest({action:'context',token});if(version===contextVersion.current)acceptContext(d);return d;}
 useEffect(()=>{
  if(!token)return;
  let active=true;const version=++contextVersion.current;
  void guestRequest({action:'context',token}).then(d=>{if(active&&version===contextVersion.current)acceptContext(d);}).catch(()=>{/* Public collection remains usable; Continue checks the session. */});
  return()=>{active=false;};
  // Revalidate only when opening a different shared link.
  // eslint-disable-next-line react-hooks/exhaustive-deps
 },[token]);
 async function continueContribution(){
  if(!token||busy)return;setBusy(true);setError('');
  try{const d=await identityReady();setStep(d?.name&&d?.participant?.invitation_state==='ACCEPTED'?'checkout':'identity');}
  catch(e){if(e instanceof GuestRequestError&&e.status===401){forgetIdentity();setStep('identity');}else{setError(e instanceof Error?e.message:'Please reconnect.');}}
  finally{setBusy(false);}
 }
 async function join(){if(!token||busy)return;setBusy(true);setError('');try{const d=await guestRequest({action:'join',token});setCollection(d.collection);setExpected(d.expected_amount);setSummary(d.contribution_summary??null);setStep('checkout');}catch(e){if(e instanceof GuestRequestError&&e.status===401){forgetIdentity();}setError(e instanceof Error?e.message:'Please retry.');}finally{setBusy(false);}}
 async function back(){setStep('collection');try{await identityReady();}catch(e){if(e instanceof GuestRequestError&&e.status===401)forgetIdentity();setError(e instanceof Error?e.message:'Refresh this page to reload totals.');}}
 return <GuestChrome><section className="screen">
 {step==='checkout'&&token?<ProviderCheckout token={token} name={name} collection={c.name} expected={personal.remaining===0?null:personal.remaining??expected} onBack={()=>void back()}/>:<>
  <header className="screen-header"><h1>{step==='collection'?c.name:'Your contribution'}</h1>{step==='identity'&&<button className="icon-button" aria-label="Back to collection" onClick={()=>setStep('collection')}>←</button>}</header>
  <div className="screen-content">
   {step==='collection'&&<>
    <p>Organized by {c.organizer_name}</p>
    <div className="collection-progress coordination-progress" aria-label="Group collection progress">
     <strong className="collection-amount">{money(collected)}</strong>
     {c.target_amount!==null&&c.target_amount>0?<><p>of {money(c.target_amount)}</p><progress aria-label="Collection progress" value={Math.min(collected,c.target_amount)} max={c.target_amount}/><p>{collected>=c.target_amount?'Target reached':`${money(c.target_amount-collected)} remaining`}</p></>:<p>Collected</p>}
     {(c.sandbox_collected_amount??0)>0&&c.collected_amount===0&&<small>Sandbox</small>}
    </div>
    {verified&&summary&&<div className="personal-contribution" aria-live="polite"><strong>{personal.pending?'Your payment is being confirmed':personal.fulfilled?'Your part paid':personal.paid>0?`${money(personal.paid)} contributed`:'Your contribution'}</strong><p>{personal.pending?'Check its status before paying again.':personal.fulfilled?'Your contribution is recorded.':personal.remaining!==null?`${money(personal.remaining)} remaining`:'Any amount welcome'}</p></div>}
    {c.description&&<details className="guest-details"><summary>About this collection</summary><p>{c.description}</p></details>}
    {c.deadline_at&&<p className="helper">Due {new Date(c.deadline_at).toLocaleDateString('en-GB',{timeZone:'Africa/Douala'})}</p>}
    {!summary&&expected!==null&&<p>{c.mode==='MINIMUM_TOTAL'?'Minimum contribution':'Expected contribution'}: {money(expected)}</p>}
    <div className="screen-actions">
     <button className="button" disabled={busy||c.status!=='ACTIVE'||!token} onClick={()=>void continueContribution()}>{personal.pending?'Check contribution':personal.fulfilled?'Your contributions':'Contribute'}</button>
     <p className="helper center">{verified?`Contributing as ${name}`:'No app download needed'}</p>
     {verified&&<button className="text-button" disabled={busy} onClick={()=>setStep('identity')}>Use another number</button>}
     {!token&&<p>Visual preview. Open a collection link to contribute.</p>}
    </div>
   </>}
   {step==='identity'&&(!verified?<GuestIdentity onVerified={async()=>{await identityReady();}}/>:<>
    <div className="contribution-context"><span className="avatar" aria-hidden="true">{name.slice(0,1).toUpperCase()}</span><div><h2>{name}</h2><p>{phone}</p></div></div>
    <p>Your contribution will be recorded under this profile.</p>
    <button className="button" disabled={busy} onClick={join}>{busy?'Opening…':'Join and continue'}</button>
    <button className="text-button" disabled={busy} onClick={async()=>{try{await guestRequest({action:'logout'});forgetIdentity();}catch(e){setError(e instanceof Error?e.message:'Please retry.');}}}>Use another number</button>
   </>)}
   {error&&<p className="error" role="alert">{error}</p>}
  </div>
 </>}
 </section></GuestChrome>;
}
