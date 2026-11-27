import type {Metadata} from 'next';
import DeleteAccount from './delete-account';
export const dynamic='force-dynamic';
export const metadata:Metadata={title:'Delete account · Supprimer le compte',robots:{index:true,follow:false}};
export default function Page(){return <DeleteAccount/>;}
