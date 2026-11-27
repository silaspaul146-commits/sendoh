'use client';
import {useEffect,useState} from 'react';
import {GuestChrome,Icon} from '../components';
import {useT} from '../lang';
import GuestIdentity,{guestRequest,GuestRequestError} from '../guest-identity';

type Blocker={code:string;message:string;collection_name?:string};
type Check={can_delete:boolean;blockers:Blocker[]};
/** Account deletion on the web, as the app stores require: verify the number, see what goes and what stays, confirm. */
export default function DeleteAccount(){
 const {t}=useT();
 const [check,setCheck]=useState<Check|null>(null),[signedIn,setSignedIn]=useState<boolean|null>(null);
 const [understood,setUnderstood]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState(''),[done,setDone]=useState(false);
 async function load(){
  try{setCheck(await guestRequest({action:'account-check'}));setSignedIn(true);}
  catch(e){if(e instanceof GuestRequestError&&e.status===401)setSignedIn(false);else{setSignedIn(true);setError(e instanceof Error?t(e.message):t('Please try again.'));}}
 }
 useEffect(()=>{void load();},[]); // eslint-disable-line react-hooks/exhaustive-deps
 async function remove(){
  if(busy||!understood)return;setBusy(true);setError('');
  try{await guestRequest({action:'account-delete',confirm:'DELETE'});setDone(true);}
  catch(e){setError(e instanceof Error?t(e.message):t('Please try again.'));await load();}
  finally{setBusy(false);}
 }
 return <GuestChrome><section className="screen"><header className="screen-header"><h1>{t('Delete your Sendoh account')}</h1></header><div className="screen-content">
  {done?<div className="center"><span className="state-icon neutral"><Icon name="check" size={32}/></span><h2>{t('Your account is deleted')}</h2><p>{t('You are signed out everywhere. If you sign in again with this number, you start a new, empty account.')}</p></div>
  :signedIn===null?<p role="status">{t('Checking your account…')}</p>
  :!signedIn?<><p>{t('Verify the phone number of the account you want to delete.')}</p><GuestIdentity onVerified={load}/></>
  :check&&<>
   <div className="soft-card"><h2>{t('What is deleted')}</h2><ul><li>{t('Your name, @username and photo')}</li><li>{t('The phone number you sign in with')}</li><li>{t('Your sessions and notification settings')}</li></ul></div>
   <div className="soft-card"><h2>{t('What is kept')}</h2><p>{t('Payment, payout and cash records stay as financial records, because other people’s receipts depend on them. Your name on them becomes “Deleted user”.')}</p></div>
   {check.can_delete?<>
    <label className="confirmation"><input type="checkbox" checked={understood} onChange={e=>setUnderstood(e.target.checked)}/><span>{t('I understand this cannot be undone.')}</span></label>
    <div className="screen-actions"><button className="button danger" disabled={busy||!understood} onClick={()=>void remove()}>{busy?t('Please wait…'):t('Delete my account')}</button></div>
   </>:<div className="soft-card"><h2>{t('Finish these first')}</h2><ul>{check.blockers.map(b=><li key={b.code+b.message}>{b.code==='COLLECTION_HOLDS_MONEY'?t('Close and settle “{name}” first.',{name:b.collection_name??''}):t(b.message)}</li>)}</ul><p>{t('No money is left without an owner: deletion waits until everything above has finished.')}</p></div>}
  </>}
  {error&&<p className="error" role="alert">{error}</p>}
 </div></section></GuestChrome>;
}
