'use client';
import {useState,useEffect} from 'react';
import {GuestChrome,money} from '../../components';
import GuestIdentity,{guestRequest} from '../../guest-identity';
type InvitationData={invitation_state:string,participant_name:string,expected_amount:number|null,share_url:string|null,collection:{name:string,organizer_name:string,description:string}};
export default function Invitation({id,version}:{id:string,version:number}) {
 const [item,setItem]=useState<InvitationData|null>(null), [error,setError]=useState(''), [busy,setBusy]=useState(false);
 const [checking,setChecking]=useState(true);
 async function load(){const data=await guestRequest({action:'invitation',id,version});setItem(data);setError('');}
 useEffect(()=>{load().catch(()=>{}).finally(()=>setChecking(false));},[id,version]); // Existing browser session may already be verified.
 async function respond(decision:string){setBusy(true);setError('');try{setItem(await guestRequest({action:'respond',id,version,decision}));}catch(e){setError(e instanceof Error?e.message:'Please retry.');}finally{setBusy(false);}}
 return <GuestChrome><section className="screen"><header className="screen-header"><h1>Your invitation</h1></header><div className="screen-content">
 {!Number.isInteger(version)||version<1?<p>This link is incomplete. Ask the organizer for a new invitation link.</p>:checking?<p role="status">Opening your invitation…</p>:!item?<GuestIdentity onVerified={load}/>:<>
 <h2 className="question">{item.collection.name}</h2><p>Organized by {item.collection.organizer_name}</p><p>{item.collection.description}</p>
 <div className="soft-card"><h2>{item.participant_name}</h2><p>{item.expected_amount===null?'Contribute any amount':`Your expected amount: ${money(item.expected_amount)}`}</p><p>Status: {item.invitation_state.toLowerCase()}</p></div>
 {item.invitation_state==='PENDING'?<><p>Joining adds you to this collection. It does not make a payment.</p><div className="screen-actions"><button className="button" disabled={busy} onClick={()=>respond('accept')}>Join collection</button><button className="button secondary" disabled={busy} onClick={()=>respond('decline')}>Decline invitation</button></div></>:<p>{item.invitation_state==='ACCEPTED'?'You have joined. Payments are not available yet.':'This invitation is no longer pending.'}</p>}
 {item.share_url&&<a className="button secondary" href={item.share_url}>View collection</a>}
 <button className="text-button" disabled={busy} onClick={async()=>{setBusy(true);try{await guestRequest({action:'logout'});setItem(null);}catch{setError('Could not sign out. Please retry.');}finally{setBusy(false);}}}>Use another phone number</button>
 </>}{error&&<p className="error" role="alert">{error}</p>}</div></section></GuestChrome>;
}
