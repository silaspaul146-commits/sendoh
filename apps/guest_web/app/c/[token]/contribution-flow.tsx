'use client';
import {useEffect,useRef,useState} from 'react';
import GuestIdentity,{guestRequest,GuestRequestError} from '../../guest-identity';
import ProviderCheckout from '../../test-checkout';
import {GuestChrome} from '../../components';
import {useT} from '../../lang';
import {personalContribution,collectionTotals,type ContributionSummary,type Totals} from './contribution-state';
export type CollectionData={name:string;description:string;organizer_name:string;currency:string;target_amount:number|null;collected_amount:number;sandbox_collected_amount?:number;totals?:Totals;expected_amount:number|null;mode:string;deadline_at:string|null;status:string;recurring?:boolean;round?:number};
/** The member's earlier round, from the record taken when it closed. */
type PreviousRound={round:number;state:string;confirmed:number;cash:number;expected:number|null;delivered:boolean};
export default function ContributionFlow({collection,token}:{collection:CollectionData;token?:string}) {
 const {t,money,lang}=useT();
 const [c,setCollection]=useState(collection);
 const contextVersion=useRef(0);
 const totals=collectionTotals(c),collected=totals.raised;
 const closed=c.status==='CLOSED'||c.status==='SETTLED';
 const round=c.round??1,recurring=c.recurring===true;
 const [step,setStep]=useState<'collection'|'identity'|'checkout'>('collection');
 const [name,setName]=useState(''),[phone,setPhone]=useState(''),[verified,setVerified]=useState(false);
 const [busy,setBusy]=useState(false),[error,setError]=useState('');
 const [expected,setExpected]=useState(c.expected_amount);
 const [summary,setSummary]=useState<ContributionSummary|null>(null);
 const [previous,setPrevious]=useState<PreviousRound|null>(null);
 const personal=personalContribution(summary,expected);
 function acceptContext(d:any){
  setName(d.name);setPhone(d.phone);setVerified(Boolean(d.name));
  if(d.participant){setCollection(d.participant.collection);setExpected(d.participant.expected_amount);setSummary(d.participant.contribution_summary??null);setPrevious(d.participant.previous_round??null);}
  else {setSummary(null);setPrevious(null);setExpected(c.expected_amount);}
 }
 function forgetIdentity(){contextVersion.current++;setVerified(false);setSummary(null);setPrevious(null);setName('');setPhone('');}
 async function identityReady(){if(!token)return;const version=++contextVersion.current;const d=await guestRequest({action:'context',token});if(version===contextVersion.current)acceptContext(d);return d;}
 useEffect(()=>{
  if(!token)return;
  let active=true;const version=++contextVersion.current;
  void guestRequest({action:'context',token}).then(d=>{if(active&&version===contextVersion.current)acceptContext(d);}).catch(()=>{/* Public collection remains usable; Continue checks the session. */});
  return()=>{active=false;};
  // Revalidate only when opening a different shared link.
  // eslint-disable-next-line react-hooks/exhaustive-deps
 },[token]);
 const fail=(e:unknown,fallback:string)=>setError(e instanceof Error?t(e.message):t(fallback));
 async function continueContribution(){
  if(!token||busy)return;setBusy(true);setError('');
  try{const d=await identityReady();setStep(d?.name&&d?.participant?.invitation_state==='ACCEPTED'?'checkout':'identity');}
  catch(e){if(e instanceof GuestRequestError&&e.status===401){forgetIdentity();setStep('identity');}else{fail(e,'Please reconnect.');}}
  finally{setBusy(false);}
 }
 async function join(){if(!token||busy)return;setBusy(true);setError('');try{const d=await guestRequest({action:'join',token});setCollection(d.collection);setExpected(d.expected_amount);setSummary(d.contribution_summary??null);setPrevious(d.previous_round??null);setStep('checkout');}catch(e){if(e instanceof GuestRequestError&&e.status===401){forgetIdentity();}fail(e,'Please retry.');}finally{setBusy(false);}}
 async function back(){setStep('collection');try{await identityReady();}catch(e){if(e instanceof GuestRequestError&&e.status===401)forgetIdentity();fail(e,'Refresh this page to reload totals.');}}
 function previousLine(p:PreviousRound){
  const paid=(p.confirmed??0)+(p.cash??0);
  if(p.state==='FULFILLED'||p.state==='CONTRIBUTED')return t('Round {round} · Paid',{round:p.round});
  if(p.state==='PARTIAL')return t('Round {round} · {paid} of {expected}',{round:p.round,paid:money(paid),expected:money(p.expected??0)});
  return t('Round {round} · Not paid',{round:p.round});
 }
 const shareTitle=personal.pending?t('Your payment is being confirmed'):personal.fulfilled?t('Your {amount} share is paid',{amount:money(expected??0)}):personal.paid>0?t('{amount} contributed',{amount:money(personal.paid)}):t('Your contribution');
 const shareBody=personal.pending?`${personal.pendingAmount>0?t('{amount} awaiting confirmation.',{amount:money(personal.pendingAmount)})+' ':''}${t('Check its status before paying again.')}`:personal.fulfilled?(personal.cash>0?t('{mobile} Mobile Money · {cash} cash recorded by {organizer}',{mobile:money(personal.paid),cash:money(personal.cash),organizer:c.organizer_name}):t('Your contribution is recorded.')):personal.remaining!==null?t('{amount} remaining',{amount:money(personal.remaining)}):t('Any amount welcome');
 return <GuestChrome><section className="screen">
 {step==='checkout'&&token?<ProviderCheckout token={token} name={name} collection={c.name} round={recurring?round:undefined} expected={personal.remaining===0?null:personal.remaining??expected} start={personal.fulfilled&&!personal.pending?'history':undefined} onBack={()=>void back()}/>:<>
  <header className="screen-header"><h1>{step==='collection'?c.name:t('Your contribution')}</h1>{step==='identity'&&<button className="icon-button" aria-label={t('Back to collection')} onClick={()=>setStep('collection')}>←</button>}</header>
  <div className="screen-content">
   {step==='collection'&&<>
    <p>{t('Organized by {organizer}',{organizer:c.organizer_name})}</p>
    {recurring&&<p className="round-line"><span className="badge">{t('Round {round}',{round})}</span> {t('Recurring collection · each round is counted on its own')}</p>}
    <div className="collection-progress coordination-progress" aria-label={t('Group collection progress')}>
     <strong className="collection-amount">{money(collected)}</strong>
     {c.target_amount!==null&&c.target_amount>0?<><p>{t('of {target}',{target:money(c.target_amount)})}</p><progress aria-label={t('Collection progress')} value={Math.min(collected,c.target_amount)} max={c.target_amount}/><p>{collected>=c.target_amount?t('Target reached'):t('{amount} remaining',{amount:money(c.target_amount-collected)})}</p></>:<p>{t('Collected')}</p>}
     {totals.cash>0&&<p className="helper">{t('{mobile} Mobile Money · {cash} cash recorded by {organizer}',{mobile:money(totals.confirmed),cash:money(totals.cash),organizer:c.organizer_name})}</p>}
     {totals.pending>0&&<p className="helper">{t('{amount} awaiting confirmation',{amount:money(totals.pending)})}</p>}
     {closed&&<p><strong>{c.status==='SETTLED'?(recurring?t('Round {round} settled · delivered to {organizer}',{round,organizer:c.organizer_name}):t('Settled · delivered to {organizer}',{organizer:c.organizer_name})):(recurring?t('Round {round} closed · no new contributions',{round}):t('Closed · no new contributions'))}</strong></p>}
     {closed&&recurring&&<p className="helper">{t('The next round opens when {organizer} starts it. This link stays the same.',{organizer:c.organizer_name})}</p>}
     {totals.sandbox&&collected>0&&<small>{t('Sandbox')}</small>}
    </div>
    {verified&&summary&&<div className="personal-contribution" aria-live="polite">{recurring&&round>1&&<p className="helper">{t('Round {round} · Your share',{round})}</p>}<strong>{shareTitle}</strong><p>{shareBody}</p>{previous&&<p className="previous-round">{previousLine(previous)}</p>}</div>}
    {c.description&&<details className="guest-details"><summary>{t('About this collection')}</summary><p>{c.description}</p></details>}
    {c.deadline_at&&<p className="helper">{t('Due {date}',{date:new Date(c.deadline_at).toLocaleDateString(lang==='fr'?'fr-FR':'en-GB',{timeZone:'Africa/Douala'})})}</p>}
    {!summary&&expected!==null&&<p>{c.mode==='MINIMUM_TOTAL'?t('Minimum contribution: {amount}',{amount:money(expected)}):t('Expected contribution: {amount}',{amount:money(expected)})}</p>}
    <div className="screen-actions">
     <button className="button" disabled={busy||c.status!=='ACTIVE'||!token} onClick={()=>void continueContribution()}>{personal.pending?t('Check contribution'):personal.fulfilled?t('Your contributions'):t('Contribute')}</button>
     <p className="helper center">{verified?t('Contributing as {name}',{name}):t('No app download needed')}</p>
     {verified&&<button className="text-button" disabled={busy} onClick={()=>setStep('identity')}>{t('Use another number')}</button>}
     {!token&&<p>{t('Visual preview. Open a collection link to contribute.')}</p>}
    </div>
   </>}
   {step==='identity'&&(!verified?<GuestIdentity onVerified={async()=>{await identityReady();}}/>:<>
    <div className="contribution-context"><span className="avatar" aria-hidden="true">{name.slice(0,1).toUpperCase()}</span><div><h2>{name}</h2><p>{phone}</p></div></div>
    <p>{t('Your contribution will be recorded under this profile.')}</p>
    <button className="button" disabled={busy} onClick={join}>{busy?t('Opening…'):t('Join and continue')}</button>
    <button className="text-button" disabled={busy} onClick={async()=>{try{await guestRequest({action:'logout'});forgetIdentity();}catch(e){fail(e,'Please retry.');}}}>{t('Use another number')}</button>
   </>)}
   {error&&<p className="error" role="alert">{error}</p>}
  </div>
 </>}
 </section></GuestChrome>;
}
