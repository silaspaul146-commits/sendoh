import './style.css';
import type {Metadata, Viewport} from 'next';

const siteUrl=process.env.NEXT_PUBLIC_SITE_URL??'https://sendoh.vercel.app';
export const metadata:Metadata={
 metadataBase:new URL(siteUrl),
 title:{default:'Sendoh · Organize money together',template:'%s · Sendoh'},
 description:'Create, share and track group collections with one clear Sendoh link. Built for communities in Cameroon.',
 applicationName:'Sendoh',
 robots:{index:true,follow:true},
 openGraph:{
  type:'website',url:'/',siteName:'Sendoh',title:'Sendoh · Organize money together',
  description:'One link for group collections. Clear contributions. Less chasing.',
  images:[{url:'/sendoh-social-card.png',width:1200,height:630,alt:'Sendoh · Organize money together'}],
 },
 twitter:{card:'summary_large_image',title:'Sendoh · Organize money together',description:'One link for group collections. Clear contributions. Less chasing.',images:['/sendoh-social-card.png']},
};
export const viewport:Viewport={width:'device-width',initialScale:1,themeColor:'#FBF9F6'};
export default function Layout({children}:{children:React.ReactNode}){return <html lang="en"><body>{children}</body></html>}
