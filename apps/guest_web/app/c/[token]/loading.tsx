'use client';
import {GuestChrome} from '../../components';
import {useT} from '../../lang';
export default function Loading(){const {t}=useT();return <GuestChrome><section className="screen loading-screen" aria-busy="true" aria-label={t('Loading collection')}><div className="skeleton heading"/><div className="skeleton"/><div className="skeleton"/><div className="skeleton large"/><p>{t('Loading collection…')}</p></section></GuestChrome>}
