import type {Metadata} from 'next';
import {LegalPage} from '../legal-page';
import {legal} from '../legal';
import {serverT} from '../server-lang';
export const metadata:Metadata={title:'Privacy · Confidentialité',alternates:{canonical:'/privacy'}};
export default async function Privacy(){const {lang,t}=await serverT();return <LegalPage doc={legal.privacy[lang]} updatedLabel={t('Last updated')}/>;}
