'use client';
import {createContext,useContext,useEffect,useState,type ReactNode} from 'react';
import {useRouter} from 'next/navigation';
import {LANG_COOKIE,formatMoney,translate,type Lang,type Vars} from './i18n';

const LangContext=createContext<{lang:Lang;setLang:(l:Lang)=>void}>({lang:'en',setLang:()=>{}});

export function LangProvider({lang:initial,children}:{lang:Lang;children:ReactNode}){
 const [lang,setLangState]=useState<Lang>(initial);
 useEffect(()=>{setLangState(initial);},[initial]);
 useEffect(()=>{document.documentElement.lang=lang;},[lang]);
 function setLang(next:Lang){
  try{document.cookie=`${LANG_COOKIE}=${next}; path=/; max-age=31536000; samesite=lax`;}catch{/* The choice still applies on this page. */}
  setLangState(next);
 }
 return <LangContext.Provider value={{lang,setLang}}>{children}</LangContext.Provider>;
}

/** t(englishText, vars) and money(n), in the reader's chosen language. */
export function useT(){
 const {lang,setLang}=useContext(LangContext);
 return {lang,setLang,t:(text:string,vars?:Vars)=>translate(lang,text,vars),money:(n:number)=>formatMoney(lang,n)};
}

/** English · Français. Always visible; the choice is remembered on this device. */
export function LanguageSwitch(){
 const {lang,setLang}=useT();
 const router=useRouter();
 const choose=(next:Lang)=>{if(next===lang)return;setLang(next);router.refresh();};
 return <div className="lang-switch" role="group" aria-label={lang==='fr'?'Langue':'Language'}>
  <button type="button" aria-pressed={lang==='en'} onClick={()=>choose('en')} lang="en">English</button>
  <button type="button" aria-pressed={lang==='fr'} onClick={()=>choose('fr')} lang="fr">Français</button>
 </div>;
}
