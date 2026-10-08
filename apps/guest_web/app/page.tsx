import Image from 'next/image';
import {Brand, Icon} from './components';

const benefits = [
  {
    icon: 'link',
    title: 'One link for everyone',
    text: 'Share a collection through WhatsApp. Contributors open the link and contribute without creating an account.',
  },
  {
    icon: 'people',
    title: 'Know who has contributed',
    text: 'See who has paid, who is still pending and how much remains without asking for screenshots.',
  },
  {
    icon: 'receipt',
    title: 'One clear record',
    text: 'Keep digital contributions, organizer-recorded cash and collection activity together in one place.',
  },
];

const steps = [
  ['01', 'Create a collection', 'Set the purpose, target, deadline and contribution rule.'],
  ['02', 'Share one link', 'Send the collection link to your group on WhatsApp or any messaging app.'],
  ['03', 'Contribute simply', 'Guests identify themselves, choose an amount and review everything before paying.'],
  ['04', 'Track clearly', 'The organizer sees progress, outstanding contributions and activity as it happens.'],
];

export default function Home() {
  return (
    <div className="marketing-page">
      <header className="marketing-nav">
        <Brand />
        <span className="early-badge">Cameroon early access</span>
      </header>

      <main className="marketing-main">
        <section className="marketing-hero">
          <div className="hero-copy">
            <p className="hero-kicker">GROUP MONEY, WITHOUT THE GROUP CONFUSION</p>
            <h1>Collect money together without chasing screenshots.</h1>
            <p className="hero-lead">
              Sendoh gives organizers one place to create a collection, share it,
              track contributions and keep everyone aligned.
            </p>
            <div className="hero-actions">
              <a className="button marketing-primary" href="#how-it-works">
                See how Sendoh works <Icon name="arrow-right" size={18} />
              </a>
              <a className="button marketing-secondary" href="#early-access">
                Early-access information
              </a>
            </div>
            <div className="hero-trust">
              <span><Icon name="check" size={16} /> No account needed to contribute</span>
              <span><Icon name="check" size={16} /> Built for FCFA collections</span>
            </div>
          </div>
          <div className="hero-visual" aria-label="Friends coordinating a collection together">
            <span className="hero-orbit orbit-one" />
            <span className="hero-orbit orbit-two" />
            <Image
              src="/welcome-community.png"
              alt="Three friends using Sendoh together"
              width={740}
              height={560}
              priority
            />
            <div className="hero-float float-progress">
              <span className="float-icon"><Icon name="people" size={19} /></span>
              <span><strong>Everyone stays aligned</strong><small>One shared collection record</small></span>
            </div>
            <div className="hero-float float-status">
              <span className="status-dot" />
              <span><strong>Clear progress</strong><small>Paid · Partial · Pending</small></span>
            </div>
          </div>
        </section>

        <section className="problem-strip" aria-label="The problem Sendoh solves">
          <p>Less chasing.</p><span />
          <p>Fewer screenshots.</p><span />
          <p>Clearer contributions.</p>
        </section>

        <section className="marketing-section benefits-section">
          <div className="section-heading">
            <p className="section-kicker">WHY SENDOH</p>
            <h2>Group contributions should feel coordinated, not complicated.</h2>
            <p>
              Sendoh replaces scattered messages, manual totals and repeated follow-ups
              with a simple shared flow.
            </p>
          </div>
          <div className="benefit-grid">
            {benefits.map((benefit) => (
              <article className="benefit-card" key={benefit.title}>
                <span className="benefit-icon"><Icon name={benefit.icon} size={25} /></span>
                <h3>{benefit.title}</h3>
                <p>{benefit.text}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="marketing-section how-section" id="how-it-works">
          <div className="section-heading compact">
            <p className="section-kicker">HOW IT WORKS</p>
            <h2>From collection to clear record.</h2>
          </div>
          <div className="step-grid">
            {steps.map(([number, title, text]) => (
              <article className="step-card" key={number}>
                <span>{number}</span>
                <div><h3>{title}</h3><p>{text}</p></div>
              </article>
            ))}
          </div>
        </section>

        <section className="marketing-section trust-section">
          <div>
            <p className="section-kicker">DESIGNED FOR TRUST</p>
            <h2>Money information stays clear at every step.</h2>
          </div>
          <div className="trust-points">
            <p><Icon name="shield" size={21} /><span><strong>Identity before payment</strong>Contributors confirm who they are before money moves.</span></p>
            <p><Icon name="receipt" size={21} /><span><strong>Amounts and fees separated</strong>The contribution, provider cost and total are shown clearly.</span></p>
            <p><Icon name="clock" size={21} /><span><strong>No false success</strong>A payment is successful only after provider confirmation.</span></p>
          </div>
        </section>

        <section className="early-section" id="early-access">
          <div>
            <span className="early-mark"><Icon name="phone" size={25} /></span>
            <p className="section-kicker">SENDOH EARLY ACCESS</p>
            <h2>Collections are now being tested in Cameroon.</h2>
            <p>
              Organizers can create and share collections today. Mobile Money payment
              collection is being prepared and will only be enabled after provider verification is complete.
            </p>
          </div>
          <aside>
            <strong>Received a Sendoh collection link?</strong>
            <p>Open the exact link your organizer shared. You will go directly to that collection.</p>
          </aside>
        </section>
      </main>

      <footer className="marketing-footer">
        <Brand />
        <p>Organize money. Together.</p>
        <small>Early access · Cameroon</small>
      </footer>
    </div>
  );
}
