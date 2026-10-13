import Invitation from './invitation';
export const dynamic='force-dynamic';
export const metadata={title:'Your invitation | Sendoh',robots:{index:false,follow:false}};
export default async function Page({params,searchParams}:{params:Promise<{id:string}>,searchParams:Promise<{v?:string}>}) {
 const {id}=await params; const {v}=await searchParams;
 return <Invitation id={id} version={Number(v)}/>;
}
