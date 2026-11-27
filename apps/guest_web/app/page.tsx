import type {Metadata} from 'next';
export const metadata:Metadata={alternates:{canonical:'/'},robots:{index:true,follow:true}};
import Image from 'next/image';
import './landing.css';
import {Brand, Icon} from './components';
import {LanguageSwitch} from './lang';
import {serverT} from './server-lang';
import {k} from './i18n';
import {founder, supportEmail, supportWhatsApp} from './legal';

/** Three ways people move money together. Sendoh coordinates all three. */
const modes = [
  ['person', k('Individually'), k('Ask a friend to pay you back, or send money to someone by their @username. They see who you are and why before anything moves.')],
  ['phone', k('In person'), k('Standing next to someone? Scan their Sendoh code and pay. No number to type, no wrong recipient.')],
  ['people', k('In groups'), k('One link for the whole group. Everyone sees what has been raised, who has paid and what is left. No more screenshots in the chat.')],
];

/** Real moments, the way people in Cameroon live them. */
const moments = [
  [k('Christmas outing with friends'), k('Ten friends, 5,000 FCFA each, one link in the class WhatsApp group.')],
  [k('Weddings and family events'), k('Collect for the dot, the outfits or the reception, and keep a record the whole family can trust.')],
  [k('Bereavement and support'), k('When someone needs help fast, collect from everyone with one link and send it in one payout.')],
  [k('Class and association dues'), k('Members pay their share; the treasurer sees who is up to date without a notebook.')],
  [k('Njangi and tontine'), k('Run contributions in rounds. Each round has its own total and payout, and past rounds never change.')],
  [k('Everyday paybacks'), k('The taxi, the lunch, the shared gift. Request the exact amount with a reason they can see.')],
];

const steps = [
  ['1', k('Create'), k('Name what you are collecting for, set a target or a share per person, and a date.')],
  ['2', k('Share one link'), k('Send it on WhatsApp. People contribute from their browser with MTN MoMo or Orange Money. No app needed.')],
  ['3', k('Follow and close'), k('Watch it fill up as payments are confirmed. Record cash given in person. Close once and receive one payout.')],
];

const trust = [
  ['shield', k('People, not numbers'), k('Everyone has a verified name and @username, so you always know who paid and who you are paying.')],
  ['receipt', k('Fees before you approve'), k('The amount, the fee and the total are shown before any payment. No surprises after.')],
  ['clock', k('Confirmed means confirmed'), k('A payment only counts once MTN MoMo or Orange Money confirms it. Nobody is marked paid by mistake.')],
  ['check', k('Cash counted honestly'), k('Money given in person is recorded separately from Mobile Money, so totals always add up.')],
];

export default async function Home() {
  const {t, money} = await serverT();
  const wa = supportWhatsApp.replace(/[^0-9]/g, '');
  const contact = wa ? `https://wa.me/${wa}` : supportEmail ? `mailto:${supportEmail}` : '/support';
  return (
    <div className="lp">
      <header className="lp-nav">
        <a href="/" aria-label={t('Sendoh home')}><Brand /></a>
        <nav className="lp-nav-links" aria-label={t('Sendoh information')}>
          <a href="#how">{t('How it works')}</a>
          <a href="#moments">{t('Use cases')}</a>
          <a href="#invest">{t('Partners and investors')}</a>
        </nav>
        <div className="lp-nav-end">
          <LanguageSwitch />
          <a className="lp-btn lp-btn-small" href={contact}>{t('Talk to us')}</a>
        </div>
      </header>

      <main>
        <section className="lp-hero">
          <div className="lp-hero-copy">
            <p className="lp-kicker">{t('YOUR PEOPLE. YOUR PLANS. ONE SENDOH.')}</p>
            <h1>{t('Money between people, finally coordinated.')}</h1>
            <p className="lp-lead">{t('Collect for a Christmas outing, ask a friend to pay you back, pay someone standing right next to you. Sendoh shows everyone who has paid, what is left and where the money goes, with MTN MoMo and Orange Money.')}</p>
            <div className="lp-actions">
              <a className="lp-btn" href="#how">{t('See how it works')} <Icon name="arrow-right" size={18} /></a>
              <a className="lp-btn lp-btn-ghost" href="#link">{t('I received a link')}</a>
            </div>
            <ul className="lp-proof">
              <li><Icon name="check" size={16} /> {t('MTN MoMo and Orange Money')}</li>
              <li><Icon name="check" size={16} /> {t('English and French')}</li>
              <li><Icon name="check" size={16} /> {t('No app needed to contribute')}</li>
            </ul>
          </div>

          <div className="lp-phone" aria-label={t('A Sendoh collection on a phone')}>
            <div className="lp-phone-screen">
              <p className="lp-phone-eyebrow">{t('Collection')}</p>
              <p className="lp-phone-title">{t('Christmas outing')} 🎄</p>
              <p className="lp-phone-sub">{t('Organized by {organizer}', {organizer: 'Nadège'})}</p>
              <div className="lp-phone-total">
                <strong>{money(38000)}</strong>
                <span>{t('of {target}', {target: money(50000)})}</span>
              </div>
              <div className="lp-bar" role="img" aria-label={t('{percent} percent collected', {percent: 76})}><i><span style={{width: '76%'}} /></i></div>
              <p className="lp-phone-note">{t('{amount} remaining', {amount: money(12000)})} · {t('8 of 10 paid')}</p>
              <ul className="lp-members">
                {[['Nadège', k('Paid')], ['Brenda', k('Paid')], ['Rita', k('Paid')], ['Carine', k('Pending')], ['Joëlle', k('Unpaid')]].map(([name, status]) => (
                  <li key={name}><span className="lp-avatar">{name[0]}</span><span>{name}</span><em className={`lp-chip ${status.toLowerCase()}`}>{t(status)}</em></li>
                ))}
              </ul>
            </div>
            <div className="lp-float lp-float-top"><span className="lp-dot" />{t('Brenda contributed {amount}', {amount: money(5000)})}</div>
            <div className="lp-float lp-float-bottom"><Icon name="check" size={16} />{t('Confirmed by MTN MoMo')}</div>
          </div>
        </section>

        <section className="lp-strip" aria-label={t('The problem Sendoh solves')}>
          <p>{t('Less chasing.')}</p><span aria-hidden="true" />
          <p>{t('Fewer screenshots.')}</p><span aria-hidden="true" />
          <p>{t('No more “who has paid?”')}</p>
        </section>

        <section className="lp-section">
          <div className="lp-heading">
            <p className="lp-kicker">{t('ONE SENDOH. EVERY WAY MONEY MOVES BETWEEN PEOPLE.')}</p>
            <h2>{t('Individually, in person or in groups.')}</h2>
            <p>{t('Sendoh is not a wallet and not just a tontine app. It is the place where money between people gets organized, so everyone sees the same thing.')}</p>
          </div>
          <div className="lp-modes">
            {modes.map(([icon, title, text]) => (
              <article key={title} className="lp-card">
                <span className="lp-icon"><Icon name={icon} size={24} /></span>
                <h3>{t(title)}</h3>
                <p>{t(text)}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="lp-section lp-moments" id="moments">
          <div className="lp-heading">
            <p className="lp-kicker">{t('FOR EVERY MOMENT')}</p>
            <h2>{t('From a secondary-school outing to a family wedding.')}</h2>
            <p>{t('If people put money together for something, Sendoh makes it clear. Anyone aged 12 and over can take part.')}</p>
          </div>
          <div className="lp-grid">
            {moments.map(([title, text]) => (
              <article key={title} className="lp-moment">
                <h3>{t(title)}</h3>
                <p>{t(text)}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="lp-section lp-how" id="how">
          <div className="lp-heading">
            <p className="lp-kicker">{t('HOW IT WORKS')}</p>
            <h2>{t('Three steps. One clear record.')}</h2>
          </div>
          <ol className="lp-steps">
            {steps.map(([n, title, text]) => (
              <li key={n}><span className="lp-step-n">{n}</span><div><h3>{t(title)}</h3><p>{t(text)}</p></div></li>
            ))}
          </ol>
          <div className="lp-how-visual">
            <Image src="/welcome-community.png" alt={t('Three friends using Sendoh together')} width={740} height={560} />
          </div>
        </section>

        <section className="lp-section">
          <div className="lp-heading">
            <p className="lp-kicker">{t('DESIGNED FOR TRUST')}</p>
            <h2>{t('Money you can follow, from approval to receipt.')}</h2>
          </div>
          <div className="lp-trust">
            {trust.map(([icon, title, text]) => (
              <article key={title}><span className="lp-icon"><Icon name={icon} size={22} /></span><div><h3>{t(title)}</h3><p>{t(text)}</p></div></article>
            ))}
          </div>
        </section>

        <section className="lp-section lp-local">
          <div>
            <p className="lp-kicker">{t('BUILT IN CAMEROON, FOR CAMEROON')}</p>
            <h2>{t('Made for how we really do money.')}</h2>
            <p>{t('Mobile Money is how Cameroon pays. Group money is how Cameroon lives: family, friends, school, church, association. Sendoh is built around both, in English and French, in FCFA, and it works from a WhatsApp link.')}</p>
          </div>
          <ul>
            <li><strong>MTN MoMo</strong><span>{t('and Orange Money')}</span></li>
            <li><strong>FCFA</strong><span>{t('amounts and fees shown clearly')}</span></li>
            <li><strong>FR · EN</strong><span>{t('your choice, anytime')}</span></li>
            <li><strong>12+</strong><span>{t('for students and families too')}</span></li>
          </ul>
        </section>

        <section className="lp-section lp-invest" id="invest">
          <div className="lp-heading">
            <p className="lp-kicker">{t('PARTNERS AND INVESTORS')}</p>
            <h2>{t('The coordination layer for money between people.')}</h2>
            <p>{t('Mobile Money moved payments onto the phone. What happens around those payments, the asking, the chasing, the counting, still happens in chats and notebooks. Sendoh brings it into one place people trust.')}</p>
          </div>
          <div className="lp-invest-grid">
            <article><h3>{t('The opportunity')}</h3><p>{t('Every collection, payback and shared expense starts as a conversation. Sendoh turns that conversation into a clear record, with the payment inside it.')}</p></article>
            <article><h3>{t('How Sendoh earns')}</h3><p>{t('A small, transparent fee when a collection pays out or money is sent, always shown before anyone approves. No fee on cash.')}</p></article>
            <article><h3>{t('Where we are')}</h3><p>{t('Collections, requests, sending and in-person payments are built, with MTN MoMo and Orange Money through our payment partner MeSomb. We are now onboarding our first groups in Cameroon.')}</p></article>
          </div>
          <a className="lp-btn" href={contact}>{t('Talk to the founder')} <Icon name="arrow-right" size={18} /></a>
        </section>

        <section className="lp-cta" id="link">
          <div>
            <h2>{t('Received a Sendoh link?')}</h2>
            <p>{t('Open the exact link you were sent. You can contribute from your browser in a minute, no app needed.')}</p>
          </div>
          <div>
            <h2>{t('Want to organize with Sendoh?')}</h2>
            <p>{t('The Sendoh app is coming to Android first. Tell us about your group and we will get you started.')}</p>
            <a className="lp-btn lp-btn-light" href={contact}>{t('Get started with us')}</a>
          </div>
        </section>
      </main>

      <footer className="lp-footer">
        <div>
          <Brand />
          <p>{t('Organize money. Together.')}</p>
          <small>{t('Founded by {founder} · Cameroon', {founder})}</small>
        </div>
        <nav aria-label={t('Sendoh information')}>
          <a href="/support">{t('Help')}</a>
          <a href="/privacy">{t('Privacy')}</a>
          <a href="/terms">{t('Terms')}</a>
          <a href="/delete-account">{t('Delete account')}</a>
        </nav>
      </footer>
    </div>
  );
}
