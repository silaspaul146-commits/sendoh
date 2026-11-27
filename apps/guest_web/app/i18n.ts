import {FR} from './i18n-fr';

export type Lang='en'|'fr';
export type Vars=Record<string,string|number>;
export const LANG_COOKIE='sendoh_lang';
export const LANGS:Lang[]=['en','fr'];

/** Marks text for translation where it is defined (arrays, maps); t() translates it where shown. */
export const k=(text:string)=>text;

/** English source text is the key. Missing French falls back to English, never to a blank. */
export function translate(lang:Lang,text:string,vars?:Vars){
 let out=lang==='fr'?(FR[text]??text):text;
 if(vars)for(const [name,value] of Object.entries(vars))out=out.split(`{${name}}`).join(String(value));
 return out;
}

/** 10,000 FCFA in English; 10 000 FCFA in French. */
export function formatMoney(lang:Lang,n:number){return `${new Intl.NumberFormat(lang==='fr'?'fr-FR':'en').format(n)} FCFA`;}

/** A saved choice wins; otherwise the browser's first preference between French and English. */
export function pickLang(saved?:string|null,accept?:string|null):Lang{
 if(saved==='fr'||saved==='en')return saved;
 for(const part of (accept??'').split(',')){
  const tag=part.trim().slice(0,2).toLowerCase();
  if(tag==='fr'||tag==='en')return tag;
 }
 return 'en';
}
