import type {Metadata} from 'next';
import {GuestChrome} from '../components';
import {faqs,supportEmail,supportWhatsApp} from '../legal';
import {serverT} from '../server-lang';
export const metadata:Metadata={title:'Help · Aide',alternates:{canonical:'/support'}};
export default async function Support(){
 const {lang,t}=await serverT();
 const wa=supportWhatsApp.replace(/[^0-9]/g,'');
 return <GuestChrome><article className="screen legal">
  <header className="screen-header"><h1>{t('Help')}</h1></header>
  <div className="screen-content">
   <section className="soft-card">
    <h2>{t('Contact Sendoh')}</h2>
    {wa||supportEmail?<>
     <p>{t('Tell us the collection name and the payment reference from your receipt. Never send us a sign-in code or your Mobile Money PIN.')}</p>
     <div className="screen-actions">
      {wa&&<a className="button" href={`https://wa.me/${wa}`}>{t('Message us on WhatsApp')}</a>}
      {supportEmail&&<a className="button secondary" href={`mailto:${supportEmail}`}>{supportEmail}</a>}
     </div>
    </>:<p>{t('Our support contacts will be published here before the public launch. Until then, contact the organizer who shared your link.')}</p>}
   </section>
   <h2>{t('Common questions')}</h2>
   {faqs[lang].map(f=><details className="guest-details" key={f.q}><summary>{f.q}</summary><p>{f.a}</p></details>)}
  </div>
 </article></GuestChrome>;
}
