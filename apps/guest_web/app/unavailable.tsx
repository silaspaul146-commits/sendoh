import {Icon} from './components';
export function Unavailable(){return <section className="screen message-screen"><span className="state-icon pending"><Icon name="info" size={34}/></span><h1>Collection temporarily unavailable</h1><p>We couldn’t load this collection. Check your connection and try again.</p><a className="button" href="">Try again</a></section>}
