import './style.css';
import type {Metadata, Viewport} from 'next';
import {LangProvider} from './lang';
import {getLang} from './server-lang';

const siteUrl=process.env.NEXT_PUBLIC_SITE_URL??'https://sendoh.vercel.app';
const copy={
 en:{title:'Sendoh · Organize money. Together.',description:'Sendoh coordinates money between people in Cameroon: requests, payments in person and group collections with MTN MoMo and Orange Money. Everyone sees who has paid and what is left.',social:'Money between people, finally coordinated. Individually, in person or in groups.'},
 fr:{title:'Sendoh · Organisez l’argent. Ensemble.',description:'Sendoh coordonne l’argent entre les personnes au Cameroun : demandes, paiements en personne et collectes de groupe avec MTN MoMo et Orange Money. Chacun voit qui a payé et ce qu’il reste.',social:'L’argent entre proches, enfin coordonné. Individuellement, en personne ou en groupe.'},
}
export async function generateMetadata():Promise<Metadata>{
 const c=copy[await getLang()];
 return {
  metadataBase:new URL(siteUrl),
  title:{default:c.title,template:'%s · Sendoh'},
  description:c.description,
  applicationName:'Sendoh',
  verification:{google:'PvBmCQJVWMxyjK-kuk40C-GX0mNjb8o0__ClLV_8GPY'},
  // Inner pages stay out of search; the landing page opts in itself.
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
