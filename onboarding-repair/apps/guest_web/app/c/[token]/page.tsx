import {notFound} from 'next/navigation';
export const dynamic='force-dynamic';
export default async function Collection({params}:{params:Promise<{token:string}>}) {
 const {token}=await params;
 const base=process.env.API_INTERNAL_URL??'http://127.0.0.1:8000';
 let response:Response;
 try {response=await fetch(`${base}/api/v1/public/collections/${encodeURIComponent(token)}`,{cache:'no-store',signal:AbortSignal.timeout(10000)});}
 catch {return <><h1>Collection temporarily unavailable</h1><p>We could not reach Sendoh. Please refresh in a moment.</p></>}
 if(response.status===404) notFound();
 if(!response.ok) return <><h1>Unable to load this collection</h1><p>Please refresh in a moment.</p></>;
 const c=await response.json();
 const money=(n:number)=>`${new Intl.NumberFormat('en').format(n)} FCFA`;
 return <><span className="status">Open collection</span><h1>{c.name}</h1><p>Organized by {c.organizer_name}</p><p>{c.description}</p><section><p className="amount">{money(c.collected_amount)}</p><p>{c.target_amount==null?'Contributed · no target':`Contributed toward ${money(c.target_amount)}`}</p>{c.target_amount!=null&&<progress value={c.collected_amount} max={c.target_amount}/>}</section><p>{c.expected_amount==null?'Contribute any amount':`${c.mode==='MINIMUM_TOTAL'?'Minimum total':'Expected total'} per person: ${money(c.expected_amount)}`}</p><p>{c.deadline_at?`Deadline: ${new Date(c.deadline_at).toLocaleDateString('en-GB',{timeZone:'Africa/Douala',day:'numeric',month:'long',year:'numeric'})}`:'No deadline'}</p><div className="notice">Payment collection is not enabled in this development preview. No money can be charged.</div></>;
}
