'use client';
import {GuestChrome,Icon} from './components';
import {useT} from './lang';
export default function NotFound(){const {t}=useT();return <GuestChrome><section className="screen message-screen"><span className="state-icon neutral"><Icon name="lock" size={32}/></span><h1>{t('This collection isn’t available')}</h1><p>{t('The link may be incorrect, or the collection may no longer be open.')}</p><p>{t('Ask the organizer for the current collection link.')}</p><a className="text-button" href="/">{t('Learn about Sendoh')}</a></section></GuestChrome>}
