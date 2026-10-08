import {ImageResponse} from 'next/og';
import {readFile} from 'node:fs/promises';
import path from 'node:path';

export const runtime = 'nodejs';
export const alt = 'Sendoh: Collections, Requests, P2P and Near2P. Cameroon early access.';
export const size = {width: 1200, height: 630};
export const contentType = 'image/png';

export default async function SocialImage() {
  const [mark, people] = await Promise.all([
    readFile(path.join(process.cwd(), 'public/sendoh-mark.svg')),
    readFile(path.join(process.cwd(), 'public/welcome-community.png')),
  ]);
  return new ImageResponse(
    <div style={{display:'flex', width:'100%', height:'100%', background:'#FBF9F6',
      color:'#0B3D3B', padding:60, fontFamily:'sans-serif', position:'relative'}}>
      <div style={{display:'flex', flexDirection:'column', width:660}}>
        <div style={{display:'flex', alignItems:'center', gap:20}}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={`data:image/svg+xml;base64,${mark.toString('base64')}`} alt="" width={55} height={75}/>
          <span style={{fontSize:46, fontWeight:700}}>SENDOH</span>
        </div>
        <div style={{display:'flex', marginTop:28, color:'#C56C15', fontSize:25}}>Organize money. Together.</div>
        <div style={{display:'flex', flexDirection:'column', marginTop:20, fontSize:50, fontWeight:700, lineHeight:1.12}}>
          <div style={{display:'flex'}}>Collect together.</div>
          <div style={{display:'flex'}}>Request simply.</div>
          <div style={{display:'flex'}}>Send with confidence.</div>
        </div>
        <div style={{display:'flex', marginTop:28, fontSize:24}}>Collections · Requests · P2P · Near2P</div>
        <div style={{display:'flex', marginTop:22, fontSize:19, color:'#586B68'}}>
          Cameroon early access · Payments not yet enabled
        </div>
      </div>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={`data:image/png;base64,${people.toString('base64')}`} alt="" width={550} height={460}
        style={{position:'absolute', right:-40, bottom:0, objectFit:'contain'}}/>
    </div>, size,
  );
}
