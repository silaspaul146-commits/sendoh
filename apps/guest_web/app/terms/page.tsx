import type {Metadata} from 'next';
import {LegalPage} from '../legal-page';
import {legal} from '../legal';
import {serverT} from '../server-lang';
export const metadata:Metadata={title:'Terms · Conditions',alternates:{canonical:'/terms'}};
export default async function Terms(){const {lang,t}=await serverT();return <LegalPage doc={legal.terms[lang]} updatedLabel={t('Last updated')}/>;}
