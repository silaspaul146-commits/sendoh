import {notFound} from 'next/navigation';
import ContributionFlow from './contribution-flow';
import {Unavailable} from '../../unavailable';
export const dynamic='force-dynamic';
export default async function Collection({params}:{params:Promise<{token:string}>}) {
 const {token}=await params;
 const base=process.env.API_INTERNAL_URL??'http://127.0.0.1:8000';
 let response:Response;
 try {response=await fetch(`${base}/api/v1/public/collections/${encodeURIComponent(token)}`,{cache:'no-store',signal:AbortSignal.timeout(10000)});}
 catch {return <Unavailable/>}
 if(response.status===404) notFound();
 if(!response.ok) return <Unavailable/>;
 return <ContributionFlow collection={await response.json()}/>;
}
