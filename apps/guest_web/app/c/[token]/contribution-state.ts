export type ContributionSummary={live_available?:boolean;confirmed_amount?:number|null;sandbox_paid_amount?:number;payment_pending?:boolean;sandbox_payment_pending?:boolean};
export function personalContribution(summary:ContributionSummary|null,expected:number|null){
 const live=summary?.live_available===true;
 const paid=live?(summary?.confirmed_amount??0):(summary?.sandbox_paid_amount??0);
 const pending=live?summary?.payment_pending===true:summary?.sandbox_payment_pending===true;
 const remaining=expected!==null&&expected>0?Math.max(0,expected-paid):null;
 return {paid,pending,remaining,fulfilled:remaining===0&&paid>0};
}
