import type {ReactNode} from 'react';
export function Icon({name='arrow',size=20}:{name?:string,size?:number}) {
 const paths:Record<string,ReactNode>={
  arrow:<><path d="m12 5-7 7 7 7M5 12h14"/></>, people:<><circle cx="9" cy="7" r="3"/><path d="M3 21v-3a6 6 0 0 1 12 0v3M16 4a3 3 0 0 1 0 6m2 5a5 5 0 0 1 3 5"/></>,
  check:<path d="m5 12 4 4L19 6"/>, clock:<><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></>, lock:<><rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3"/></>,
  close:<path d="m6 6 12 12M18 6 6 18"/>, info:<><circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7h.01"/></>, phone:<><rect x="6" y="2" width="12" height="20" rx="2"/><path d="M10 18h4"/></>,
 };
 return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]??paths.info}</svg>;
}
export function Brand(){return <div className="brand" aria-label="Sendoh"><img src="/sendoh-mark.svg" alt="" width="21" height="32"/><span>SENDOH</span></div>}
export function CollectionIcon(){return <span className="collection-icon"><Icon name="people"/></span>}
export const money=(n:number)=>`${new Intl.NumberFormat('en').format(n)} FCFA`;
export function Row({label,children,strong=false}:{label:string,children:ReactNode,strong?:boolean}){return <div className={`summary-row ${strong?'strong':''}`}><span>{label}</span><span>{children}</span></div>}
export function PaymentLogo({method}:{method:'MTN'|'ORANGE'}){return <span className={`provider-logo ${method.toLowerCase()}`} aria-hidden="true">{method==='MTN'?<span>MTN</span>:<><span>Orange</span><small>Money</small></>}</span>}
