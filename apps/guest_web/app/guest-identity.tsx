'use client';
import {useState, type FormEvent} from 'react';

export async function guestRequest(input:Record<string,unknown>) {
 const response=await fetch('/api/guest',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(input)});
 const data=await response.json();
 if(!response.ok) throw new Error(data.error?.message ?? 'Please try again.');
 return data;
}
export default function GuestIdentity({onVerified}:{onVerified:()=>Promise<void>}) {
 const [phone,setPhone]=useState(''), [code,setCode]=useState(''), [name,setName]=useState('');
 const [challenge,setChallenge]=useState(''), [step,setStep]=useState('phone');
 const [busy,setBusy]=useState(false), [error,setError]=useState(''), [delivery,setDelivery]=useState('');
 const [resendAt,setResendAt]=useState(0);
 async function submit(e:FormEvent) {
  e.preventDefault(); if(busy)return;
  setBusy(true);setError('');
  try {
   const normalized='+237'+phone.replace(/\s/g,'');
   if(step==='phone') {
    const data=await guestRequest({action:'code',phone:normalized});
    setChallenge(data.challenge_id);setDelivery(data.delivery);setResendAt(Date.now()+data.resend_after*1000);setStep('code');
   } else if(step==='code') {
    const data=await guestRequest({action:'verify',phone:normalized,code,challenge_id:challenge});
    if(data.user.display_name) {setStep('ready');await onVerified();} else setStep('name');
   } else if(step==='name') {
    await guestRequest({action:'name',name:name.trim()});setStep('ready');await onVerified();
   } else {await onVerified();}
  } catch(e) {setError(e instanceof Error?e.message:'Please try again.');}
  finally{setBusy(false);}
 }
 return <form onSubmit={submit}>
  <h2 className="question">{step==='name'?'What should we call you?':step==='code'?'Verify your number':step==='ready'?'Your number is verified':'Continue with your phone'}</h2>
  <p>Your verified number connects you to your invitation. No app installation is needed.</p>
  <p className="helper">We keep a verified identity so the organizer can recognise you. You can complete a Sendoh profile later.</p>
  {step==='phone'&&<label className="field">Phone number<span className="phone-input"><span>+237</span><input value={phone} onChange={e=>setPhone(e.target.value.replace(/[^0-9]/g,''))} pattern="[26][0-9]{8}" maxLength={9} inputMode="tel" autoComplete="tel-national" required disabled={busy}/></span></label>}
  {step==='code'&&<><label className="field">Verification code<input value={code} onChange={e=>setCode(e.target.value.replace(/[^0-9]/g,''))} pattern="[0-9]{6}" maxLength={6} autoComplete="one-time-code" inputMode="numeric" required disabled={busy}/></label><p className="helper">{delivery==='sms'?'Check your SMS messages.':'Testing mode: ask the test administrator for your code. SMS delivery is not active.'}</p><button type="button" className="text-button" disabled={busy} onClick={()=>{if(Date.now()<resendAt){setError('Please wait 60 seconds before requesting another code.');return;}setStep('phone');setCode('');setError('');}}>Change number or request another code</button></>}
  {step==='name'&&<label className="field">Your name<input value={name} onChange={e=>setName(e.target.value)} maxLength={120} required autoComplete="name" disabled={busy}/></label>}
  {step==='ready'&&<button type="button" className="text-button" disabled={busy} onClick={async()=>{setBusy(true);try{await guestRequest({action:'logout'});setStep('phone');setCode('');setError('');}catch{setError('Could not sign out. Please retry.');}finally{setBusy(false);}}}>Use another phone number</button>}
  {error&&<p className="error" role="alert">{error}</p>}
  <div className="screen-actions"><button className="button" disabled={busy}>{busy?'Please wait…':step==='phone'?'Get verification code':'Continue'}</button></div>
 </form>;
}
