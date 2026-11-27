import './style.css';
import type {Metadata, Viewport} from 'next';
import {LangProvider} from './lang';
import {getLang} from './server-lang';

const siteUrl=process.env.NEXT_PUBLIC_SITE_URL??'https://sendoh.vercel.app';
const copy={
 en:{title:'Sendoh · Organize money together',description:'Group collections, njangi rounds, money requests and person-to-person payments for Cameroon. Early access: payments run in test mode.',social:'Collect together. Request simply. Send with confidence. Cameroon early access.'},
 fr:{title:'Sendoh · Organisez l’argent ensemble',description:'Collectes de groupe, tours de njangi, demandes d’argent et paiements entre personnes pour le Cameroun. Accès anticipé : les paiements sont en mode test.',social:'Collectez ensemble. Demandez simplement. Envoyez en confiance. Accès anticipé au Cameroun.'},
};
export async function generateMetadata():Promise<Metadata>{
 const c=copy[await getLang()];
 return {
  metadataBase:new URL(siteUrl),
  title:{default:c.title,template:'%s · Sendoh'},
  description:c.description,
  applicationName:'Sendoh',
  verification:{google:'PvBmCQJVWMxyjK-kuk40C-GX0mNjb8o0__ClLV_8GPY'},
  // Kept out of search during early access; switch on at public launch.
  robots:{index:false,follow:false},
  openGraph:{type:'website',url:'/',siteName:'Sendoh',title:c.title,description:c.social,
   images:[{url:'/opengraph-image',width:1200,height:630,alt:'Sendoh'}]},
  twitter:{card:'summary_large_image',title:c.title,description:c.social,images:['/opengraph-image']},
 };
}
export const viewport:Viewport={width:'device-width',initialScale:1,themeColor:'#FBF9F6'};
export default async function Layout({children}:{children:React.ReactNode}){
 const lang=await getLang();
 return <html lang={lang}><body><LangProvider lang={lang}>{children}</LangProvider></body></html>;
}
