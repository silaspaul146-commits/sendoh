import './style.css';
import {Brand} from './components';
export const metadata={title:'Sendoh · Collections',description:'Organize money. Together.',robots:{index:false,follow:false}};
export const viewport={width:'device-width',initialScale:1,themeColor:'#FBF9F6'};
export default function Layout({children}:{children:React.ReactNode}){return <html lang="en"><body><div className="site-brand"><Brand/><p>Organize money. Together.</p></div><main id="main">{children}</main><footer className="site-footer">Organize money. Together.</footer></body></html>}
