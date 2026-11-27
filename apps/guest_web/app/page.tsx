import type {Metadata} from 'next';
export const metadata:Metadata={alternates:{canonical:'/'},robots:{index:true,follow:true}};
import Image from 'next/image';
import {Brand, Icon} from './components';
import {LanguageSwitch} from './lang';
import {serverT} from './server-lang';
import {k} from './i18n';

const benefits = [
  ['link', k('One link for everyone'), k('Share a collection on WhatsApp. People open the link and contribute from their browser, without installing anything.')],
  ['people', k('Know who has contributed'), k('See who has paid, who is still pending and how much remains, without asking for screenshots.')],
  ['receipt', k('One clear record'), k('Mobile Money, cash recorded by the organizer and every receipt, together in one place.')],
];

const features = [
  [k('Collections'), k('Create a collection, share one link and see who has paid.')],
  [k('Requests'), k('Ask someone for an exact amount, with a reason they can see.')],
  [k('Send'), k('Find the right person by @username and check their name before you pay.')],
  [k('Near2Pay'), k('Pay someone next to you by scanning their code. No number to type.')],
];

const steps = [
  ['01', k('Create a collection'), k('Set the purpose, target, deadline and contribution rule.')],
  ['02', k('Share one link'), k('Send the collection link to your group on WhatsApp or any messaging app.')],
  ['03', k('Contribute simply'), k('Contributors verify their number, choose an amount and see the fees before approving.')],
  ['04', k('Close and settle'), k('The organizer sees progress as it happens, then closes once and receives one payout.')],
];

const njangi = [
  k('Members carry over to the next round'),
  k('Choose who receives each round'),
  k('Cash and Mobile Money recorded separately'),
  k('Close once: the payout is sent once'),
];

export default async function Home() {
  const {t} = await serverT();
  return (
    <div className="marketing-page">
      <header className="marketing-nav">
        <Brand />
        <div className="marketing-nav-end">
          <LanguageSwitch />
          <span className="early-badge">{t('Cameroon early access')}</span>
        </div>
      </header>

      <main className="marketing-main">
        <section className="marketing-hero">
          <div className="hero-copy">
            <p className="hero-kicker">{t('YOUR PEOPLE. YOUR PLANS. ONE SENDOH.')}</p>
            <h1>{t('Collect together. Request simply. Send with confidence.')}</h1>
            <p className="hero-lead">
              {t('For the njangi, the family celebration and everyday plans with friends: Sendoh brings group collections, money requests and person-to-person payments together, with one clear record everyone can trust.')}
            </p>
            <div className="hero-actions">
              <a className="button marketing-primary" href="#how-it-works">
                {t('See how Sendoh works')} <Icon name="arrow-right" size={18} />
              </a>
              <a className="button marketing-secondary" href="#collection-link">
                {t('Received a collection link?')}
              </a>
            </div>
            <div className="hero-trust">
              <span><Icon name="check" size={16} /> {t('No app needed to contribute')}</span>
              <span><Icon name="check" size={16} /> {t('MTN MoMo and Orange Money')}</span>
              <span><Icon name="check" size={16} /> {t('Built for Cameroon · FCFA')}</span>
            </div>
          </div>
          <div className="hero-visual" aria-label={t('Friends coordinating a collection together')}>
            <span className="hero-orbit orbit-one" />
            <span className="hero-orbit orbit-two" />
            <Image src="/welcome-community.png" alt={t('Three friends using Sendoh together')} width={740} height={560} priority />
            <div className="hero-float float-progress">
              <span className="float-icon"><Icon name="people" size={19} /></span>
              <span><strong>{t('Everyone stays aligned')}</strong><small>{t('One shared collection record')}</small></span>
            </div>
            <div className="hero-float float-status">
              <span className="status-dot" />
              <span><strong>{t('Clear progress')}</strong><small>{t('Paid · Partial · Pending')}</small></span>
            </div>
          </div>
        </section>

        <section className="problem-strip" aria-label={t('The problem Sendoh solves')}>
          <p>{t('Less chasing.')}</p><span />
          <p>{t('Fewer screenshots.')}</p><span />
          <p>{t('Clearer contributions.')}</p>
        </section>

        <section className="marketing-section njangi-section">
          <div className="section-heading">
            <p className="section-kicker">{t('NJANGI AND TONTINE')}</p>
            <h2>{t('Your njangi, round after round.')}</h2>
            <p>{t('Run a recurring collection in rounds. Each round has its own total, its own payout and its own receipt, and an earlier round’s record never changes.')}</p>
          </div>
          <ul className="njangi-list">
            {njangi.map((line) => <li key={line}><Icon name="check" size={18} /><span>{t(line)}</span></li>)}
          </ul>
        </section>

        <section className="marketing-section benefits-section">
          <div className="section-heading">
            <p className="section-kicker">{t('ONE IDENTITY. FOUR WAYS TO MOVE MONEY.')}</p>
            <h2>{t('Everything you organize with the people you know.')}</h2>
          </div>
          <div className="step-grid">
            {features.map(([title, text]) => <article className="step-card" key={title}>
              <div><h3>{t(title)}</h3><p>{t(text)}</p></div>
            </article>)}
          </div>
        </section>

        <section className="marketing-section benefits-section">
          <div className="section-heading">
            <p className="section-kicker">{t('WHY SENDOH')}</p>
            <h2>{t('Group contributions should feel coordinated, not complicated.')}</h2>
            <p>{t('Sendoh replaces scattered messages, manual totals and repeated follow-ups with a simple shared flow.')}</p>
          </div>
          <div className="benefit-grid">
            {benefits.map(([icon, title, text]) => (
              <article className="benefit-card" key={title}>
                <span className="benefit-icon"><Icon name={icon} size={25} /></span>
                <h3>{t(title)}</h3>
                <p>{t(text)}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="marketing-section how-section" id="how-it-works">
          <div className="section-heading compact">
            <p className="section-kicker">{t('HOW IT WORKS')}</p>
            <h2>{t('From collection to clear record.')}</h2>
          </div>
          <div className="step-grid">
            {steps.map(([number, title, text]) => (
              <article className="step-card" key={number}>
                <span>{number}</span>
                <div><h3>{t(title)}</h3><p>{t(text)}</p></div>
              </article>
            ))}
          </div>
        </section>

        <section className="marketing-section trust-section">
          <div>
            <p className="section-kicker">{t('DESIGNED FOR TRUST')}</p>
            <h2>{t('Money you can follow, from approval to receipt.')}</h2>
          </div>
          <div className="trust-points">
            <p><Icon name="shield" size={21} /><span><strong>{t('Identity before payment')}</strong>{t('Every contributor verifies their phone number, so the organizer knows who paid.')}</span></p>
            <p><Icon name="receipt" size={21} /><span><strong>{t('Amounts and fees separated')}</strong>{t('You see the contribution, the fees and the total before you approve.')}</span></p>
            <p><Icon name="clock" size={21} /><span><strong>{t('No false success')}</strong>{t('A payment counts only after Mobile Money confirms it.')}</span></p>
          </div>
        </section>

        <section className="early-section" id="early-access">
          <div>
            <span className="early-mark"><Icon name="phone" size={25} /></span>
            <p className="section-kicker">{t('SENDOH EARLY ACCESS')}</p>
            <h2>{t('Sendoh is in early access in Cameroon.')}</h2>
            <p>{t('During the pilot, Mobile Money runs in test mode with our payment partner MeSomb: no real money moves yet. We’ll announce here when real payments open. The Android app is coming to Google Play.')}</p>
          </div>
          <aside id="collection-link">
            <strong>{t('Received a Sendoh collection link?')}</strong>
            <p>{t('Open the exact link your organizer shared. You can contribute from your browser, no app needed.')}</p>
          </aside>
        </section>
      </main>

      <footer className="marketing-footer">
        <Brand />
        <p>{t('Organize money. Together.')}</p>
        <nav className="footer-links" aria-label={t('Sendoh information')}>
          <a href="/support">{t('Help')}</a>
          <a href="/privacy">{t('Privacy')}</a>
          <a href="/terms">{t('Terms')}</a>
          <a href="/delete-account">{t('Delete account')}</a>
        </nav>
        <small>{t('Early access · Cameroon')}</small>
      </footer>
    </div>
  );
}
