import {GuestChrome} from './components';
import type {LegalDoc} from './legal';
import {UPDATED} from './legal';

/** One calm reading layout for policies, in the reader's language. */
export function LegalPage({doc,updatedLabel}:{doc:LegalDoc;updatedLabel:string}){
 return <GuestChrome><article className="screen legal">
  <header className="screen-header"><h1>{doc.title}</h1></header>
  <div className="screen-content">
   <p className="helper">{updatedLabel} {UPDATED}</p>
   <p>{doc.intro}</p>
   {doc.sections.map(s=><section key={s.heading}><h2>{s.heading}</h2>{s.body.length>1?<ul>{s.body.map(b=><li key={b}>{b}</li>)}</ul>:<p>{s.body[0]}</p>}</section>)}
  </div>
 </article></GuestChrome>;
}
