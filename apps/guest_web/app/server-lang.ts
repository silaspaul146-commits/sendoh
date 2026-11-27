import {cookies,headers} from 'next/headers';
import {LANG_COOKIE,pickLang,translate,formatMoney,type Lang,type Vars} from './i18n';

/** The reader's language on the server: their saved choice, else their browser's. */
export async function getLang():Promise<Lang>{
 const saved=(await cookies()).get(LANG_COOKIE)?.value;
 const accept=(await headers()).get('accept-language');
 return pickLang(saved,accept);
}

export async function serverT(){
 const lang=await getLang();
 return {lang,t:(text:string,vars?:Vars)=>translate(lang,text,vars),money:(n:number)=>formatMoney(lang,n)};
}
