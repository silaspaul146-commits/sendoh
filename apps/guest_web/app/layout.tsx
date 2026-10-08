import './style.css';
import type {Metadata, Viewport} from 'next';

const siteUrl=process.env.NEXT_PUBLIC_SITE_URL??'https://sendoh.vercel.app';
export const metadata:Metadata={
 metadataBase:new URL(siteUrl),
 title:{default:'Sendoh · Organize money together',template:'%s · Sendoh'},
 description:'Collections, requests and person-to-person money flows for Cameroon. Explore Sendoh early access; payments are not yet enabled.',
 applicationName:'Sendoh',
 robots:{index:true,follow:true},
 openGraph:{
  type:'website',url:'/',siteName:'Sendoh',title:'Sendoh · Organize money together',
  description:'Collect together. Request simply. Send with confidence. Cameroon early access.',
  images:[{url:'/opengraph-image',width:1200,height:630,alt:'Sendoh · Collections, Requests, P2P and Near2P'}],
 },
 twitter:{card:'summary_large_image',title:'Sendoh · Organize money together',description:'Collections, Requests, P2P and Near2P. Cameroon early access.',images:['/opengraph-image']},
};
export const viewport:Viewport={width:'device-width',initialScale:1,themeColor:'#FBF9F6'};
export default function Layout({children}:{children:React.ReactNode}){return <html lang="en"><body>{children}</body></html>}
