/** Backend payment-state contract for one member (see services/backend/app/contribution_state.py). */
export type Position={state:string;membership:string;environment:string;confirmed_amount:number;pending_amount:number;cash_amount?:number;paid_amount?:number;expected_amount:number|null;remaining_amount:number|null};
/** Backend payment-state contract for one collection. */
export type Totals={environment:string;confirmed_amount:number;pending_amount:number;raised_amount?:number;target_amount:number|null;remaining_amount:number|null;target_reached:boolean;cash_amount:number|null};
export type ContributionSummary={position?:Position;live_available?:boolean;confirmed_amount?:number|null;sandbox_paid_amount?:number;payment_pending?:boolean;sandbox_payment_pending?:boolean;sandbox_pending_amount?:number};
export function personalContribution(summary:ContributionSummary|null,expected:number|null){
 const p=summary?.position;
 if(p){
  // The contract is authoritative; awaiting money never reduces the remaining share.
  const remaining=p.remaining_amount;
  // paid: confirmed Mobile Money; cash: recorded by the organizer, shown separately.
  return {paid:p.confirmed_amount,cash:p.cash_amount??0,pending:p.state==='CONFIRMING',pendingAmount:p.pending_amount,
   remaining,fulfilled:p.state==='FULFILLED'};
 }
 // Older backend: provider sandbox fields only. Legacy simulator money is never counted.
 const paid=summary?.sandbox_paid_amount??0;
 const pending=summary?.sandbox_payment_pending===true;
 const pendingAmount=pending?(summary?.sandbox_pending_amount??0):0;
 const remaining=expected!==null&&expected>0?Math.max(0,expected-paid):null;
 return {paid,cash:0,pending,pendingAmount,remaining,fulfilled:remaining===0&&paid>0};
}

/** Collection totals: confirmed money only drives progress. */
export function collectionTotals(c:{totals?:Totals;collected_amount?:number;sandbox_collected_amount?:number}){
 if(c.totals){const cash=c.totals.cash_amount??0;return {confirmed:c.totals.confirmed_amount,cash,raised:c.totals.confirmed_amount+cash,pending:c.totals.pending_amount,sandbox:c.totals.environment==='SANDBOX'};}
 const live=c.collected_amount??0;
 const confirmed=live>0?live:(c.sandbox_collected_amount??0);
 return {confirmed,cash:0,raised:confirmed,pending:0,sandbox:live===0};
}

/** Background checks back off so the page stays calm while a payment is confirmed. */
export function nextPollDelay(previous:number){return Math.min(previous*2,60000);}
export const FIRST_POLL_DELAY=5000;
/** After this long a pending payment gets reassurance instead of silence. */
export const SLOW_CONFIRMATION_SECONDS=300;
