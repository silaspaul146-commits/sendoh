import {Icon} from './components';
export default function NotFound(){return <section className="screen message-screen"><span className="state-icon neutral"><Icon name="lock" size={32}/></span><h1>This collection isn’t available</h1><p>The link may be incorrect, or the collection may no longer be open.</p><p>Ask the organizer for the current collection link.</p></section>}
