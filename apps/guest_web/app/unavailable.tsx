'use client';
import {GuestChrome,Icon} from './components';
import {useT} from './lang';
export function Unavailable(){const {t}=useT();return <GuestChrome><section className="screen message-screen"><span className="state-icon pending"><Icon name="info" size={34}/></span><h1>{t('Collection temporarily unavailable')}</h1><p>{t('We couldn’t load this collection. Check your connection and try again.')}</p><a className="button" href="">{t('Try again')}</a><a className="text-button" href="/">{t('Learn about Sendoh')}</a></section></GuestChrome>}
