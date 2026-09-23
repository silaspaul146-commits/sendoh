import {notFound} from 'next/navigation';
import ContributionFlow from '../c/[token]/contribution-flow';
import {Brand,Icon,money,Row} from '../components';
export const dynamic='force-dynamic';
const sample={name:'Department Activity',description:'End of semester department activity contribution.',organizer_name:'Kboy',currency:'XAF',target_amount:100000,collected_amount:76500,expected_amount:3000,mode:'EXPECTED_TOTAL',deadline_at:'2026-10-30T22:59:00Z',status:'ACTIVE'};
const states:Record<string,{title:string;icon:string;className:string;text:string}>={
 processing:{title:'Confirm on your phone',icon:'phone',className:'neutral',text:'Follow the Mobile Money prompt on your phone to authorize the payment. Never share your PIN.'},
 pending:{title:'Payment pending',icon:'clock',className:'pending',text:'We’re waiting for confirmation. Don’t pay again while this payment is pending.'},
 unknown:{title:'We’re checking your payment',icon:'info',className:'pending',text:'The payment status is not confirmed yet. Please don’t start another payment.'},
 successful:{title:'Contribution successful!',icon:'check',className:'success',text:'Your contribution has been confirmed.'},
 failed:{title:'Payment failed',icon:'close',className:'failed',text:'This payment was not completed. Review your details before trying again.'},
};
export default async function DesignPreview({searchParams}:{searchParams:Promise<{state?:string}>}){
 if(process.env.SENDOH_DESIGN_PREVIEW!=='1')notFound();
 const {state='collection'}=await searchParams;const s=states[state];
 return <><div className="preview-label">Design review · sample data only · no payment is made</div><nav className="preview-controls" aria-label="Preview screen">{['collection','welcome',...Object.keys(states),'receipt'].map(v=><a href={`?state=${v}`} key={v}>{v}</a>)}</nav>
 {state==='collection'?<ContributionFlow collection={sample}/>:state==='welcome'?<section className="screen message-screen preview-welcome"><Brand/><p>Organize money. Together.</p><div className="welcome-art"><img className="preview-asset" src="/welcome-community.png" alt="Three people using phones"/></div><button disabled className="button">Create account</button><button disabled className="button secondary">I already have an account</button></section>:state==='receipt'?<section className="screen"><header className="screen-header"><h1>Receipt</h1></header><div className="screen-content"><div className="preview-label">SAMPLE RECEIPT · NOT PROOF OF PAYMENT</div><p>Contribution to</p><h2>Department Activity</h2><div className="summary"><Row label="Contributing as">Sarah N.</Row><Row label="Contribution">{money(3000)}</Row><Row label="Provider cost">Example only</Row><Row label="Sendoh fee">Example only</Row><Row label="Payment method">MTN Mobile Money</Row><Row label="Reference">SAMPLE-SD-82931</Row></div><p className="helper">This screen is a design fixture. A real receipt requires a verified provider payment.</p></div></section>:s?<section className="screen message-screen"><span className={`state-icon ${s.className}`}><Icon name={s.icon} size={38}/></span><h1>{s.title}</h1><p>{s.text}</p><strong className="state-amount">{money(3000)}</strong><p>to Department Activity</p><p className="helper">Reference: SAMPLE-SD-82931</p><a className="button secondary" href="?state=collection">View sample collection</a></section>:notFound()}
 </>;
}
