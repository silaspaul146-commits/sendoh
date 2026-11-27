import {NextRequest, NextResponse} from 'next/server';

export const dynamic = 'force-dynamic';
const cookie = 'sendoh_guest_session';
// A narrow server proxy keeps access tokens out of browser JavaScript and URLs.
export async function POST(request: NextRequest) {
  if (request.headers.get('origin') !== new URL(request.url).origin) {
    return NextResponse.json({error:{message:'Please reopen this page and try again.'}}, {status:403});
  }
  if (Number(request.headers.get('content-length') ?? 0) > 8192) {
    return new NextResponse(null, {status:413});
  }
  let input;
  try {
    const text = await request.text();
    if (text.length > 8192) return new NextResponse(null, {status:413});
    input = JSON.parse(text);
  } catch { return new NextResponse(null,{status:400}); }
  if (!input || typeof input !== 'object' || Array.isArray(input)) return new NextResponse(null,{status:400});
  const {action, phone, code, challenge_id, name, id, version, decision, token, amount, method: paymentMethod, payer_phone, request_key, before} = input;
  let path = '', body: unknown;
  let method = 'POST';
  const publicAction = action === 'code' || action === 'verify';
  const session = request.cookies.get(cookie)?.value;
  if (!publicAction && !session) return NextResponse.json({error:{message:'Verify your phone to continue.'}}, {status:401});
  switch (action) {
    case 'code': path='/auth/code'; body={phone}; break;
    case 'verify': path='/auth/verify'; body={phone,code,challenge_id}; break;
    case 'name': path='/me/profile'; body={display_name:name}; break;
    case 'invitation':
      if (typeof id !== 'string' || !Number.isInteger(version) || version < 1) return new NextResponse(null,{status:400});
      path=`/me/invitations/${encodeURIComponent(id)}?version=${version}`; method='GET'; break;
    case 'respond':
      if (typeof id !== 'string' || !Number.isInteger(version) || version < 1) return new NextResponse(null,{status:400});
      path=`/me/invitations/${encodeURIComponent(id)}/respond`; body={decision,version}; break;
    case 'join':
      if (typeof token !== 'string') return new NextResponse(null,{status:400});
      path=`/me/guest-collections/${encodeURIComponent(token)}/join`; body={}; break;
    case 'context':
      if (typeof token !== 'string') return new NextResponse(null,{status:400});
      path=`/me/guest-collections/${encodeURIComponent(token)}`; method='GET'; break;
    case 'payment-quote':
    case 'payment-create':
      if (typeof token !== 'string' ||
          (action === 'payment-create' && (typeof request_key !== 'string' ||
          request_key.length < 8 || request_key.length > 120)) ||
          !Number.isSafeInteger(amount) || amount <= 0 || amount > 1000000000 ||
          !['MTN','ORANGE'].includes(paymentMethod) || typeof payer_phone !== 'string' ||
          !/^(?:\+?237)?6[0-9]{8}$/.test(payer_phone)) {
        return new NextResponse(null,{status:400});
      }
      // A quote creates nothing and charges nothing; only payment-create starts a payment.
      path=action === 'payment-quote' ? '/provider-payments/quote' : '/provider-payments';
      body={collection_token:token,amount,method:paymentMethod,payer_phone}; break;
    case 'payment-refresh':
      if (typeof id !== 'string') return new NextResponse(null,{status:400});
      path=`/provider-payments/${encodeURIComponent(id)}/refresh`; body={}; break;
    case 'payment-detail':
      if (typeof id !== 'string') return new NextResponse(null,{status:400});
      path=`/provider-payments/${encodeURIComponent(id)}`; method='GET'; break;
    case 'payment-history':
      if (typeof token !== 'string') return new NextResponse(null,{status:400});
      path=`/me/provider-payments?payer_only=true&collection_token=${encodeURIComponent(token)}${typeof before === 'string' ? '&before='+encodeURIComponent(before) : ''}`; method='GET'; break;
    case 'logout': path='/auth/logout'; body={}; break;
    case 'account-check': path='/me/account/deletion'; method='GET'; break;
    case 'account-delete':
      // Only the exact confirmation word deletes; the backend checks it again.
      if (input.confirm !== 'DELETE') return new NextResponse(null,{status:400});
      path='/me/account/delete'; body={confirm:'DELETE'}; break;
    default: return new NextResponse(null,{status:400});
  }
  try {
    const base = process.env.API_INTERNAL_URL;
    if (!base) throw new Error('Missing backend');
    const upstream = await fetch(`${base}/api/v1${path}`, {
      method, cache:'no-store', signal:AbortSignal.timeout(15000),
      headers:{'Content-Type':'application/json', ...(!publicAction ? {Authorization:`Bearer ${session}`} : {}), ...(action === 'payment-create' ? {'Idempotency-Key': request_key as string} : {})},
      ...(method === 'POST' ? {body:JSON.stringify(body)} : {}),
    });
    const data = await upstream.json();
    const result = NextResponse.json(action === 'verify' && upstream.ok ? {user:data.user} : data,
      {status:upstream.status, headers:{'Cache-Control':'no-store'}});
    if (action === 'verify' && upstream.ok) {
      result.cookies.set(cookie, data.access_token, {httpOnly:true,secure:request.nextUrl.protocol==='https:',sameSite:'strict',path:'/',maxAge:data.expires_in});
    }
    if (action === 'logout' || upstream.status === 401 || (action === 'account-delete' && upstream.ok)) result.cookies.delete(cookie);
    return result;
  } catch { return NextResponse.json({error:{message:'Sendoh is taking a little longer. Please try again.'}},{status:503}); }
}
