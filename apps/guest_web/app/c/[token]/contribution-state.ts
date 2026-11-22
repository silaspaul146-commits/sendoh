export type ContributionSummary={live_available?:boolean;confirmed_amount?:number|null;sandbox_paid_amount?:number;payment_pending?:boolean;sandbox_payment_pending?:boolean;sandbox_pending_amount?:number};
export function personalContribution(summary:ContributionSummary|null,expected:number|null){
 const live=summary?.live_available===true;
 const paid=live?(summary?.confirmed_amount??0):(summary?.sandbox_paid_amount??0);
 const pending=live?summary?.payment_pending===true:summary?.sandbox_payment_pending===true;
 // Awaiting confirmation is reported beside paid money and never reduces the remaining share.
 const pendingAmount=pending&&!live?(summary?.sandbox_pending_amount??0):0;
 const remaining=expected!==null&&expected>0?Math.max(0,expected-paid):null;
 return {paid,pending,pendingAmount,remaining,fulfilled:remaining===0&&paid>0};
}

/** Background checks back off so the page stays calm while a payment is confirmed. */
export function nextPollDelay(previous:number){return Math.min(previous*2,60000);}
export const FIRST_POLL_DELAY=5000;
/** After this long a pending payment gets reassurance instead of silence. */
export const SLOW_CONFIRMATION_SECONDS=300;
