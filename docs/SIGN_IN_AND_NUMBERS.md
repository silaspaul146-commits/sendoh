# Getting in, and Mobile Money numbers

Sendoh knows you as you: your name and @username. The phone number you sign in with is only a key. The Mobile Money numbers you pay with and get paid on are separate settings you manage.

## Getting in (app)

1. **Welcome:** what Sendoh is for (individually, in person, in groups), then *Get started* or *Sign in*. The language can be chosen here.
2. **Your number:** "Text me a code". The network (MTN or Orange) is shown from the prefix.
3. **SMS code:** six boxes, resend after 60 seconds, "Wrong number?".
4. **Who you are:** name, @username, optional photo, and "I'm 12 or older" (with the parent or guardian note for under-18s).
5. **How you pay and get paid:** the sign-in number is offered as an already verified Mobile Money number; add another (an Orange number, or a parent's MoMo); or skip.

## Mobile Money numbers (Settings)

- Up to **3 numbers**, MTN MoMo or Orange Money, chosen from the prefix (changeable).
- Each number is **verified by an SMS code sent to it**. If it's a parent's phone, the parent reading out the code is their consent. The sign-in number needs no second code.
- One number is the default **to pay with**, and one **to receive on**. The first verified number is both.
- Choosing a receive number records a new receiving destination; anything already quoted keeps the destination it was quoted with.
- Removing a number keeps past records.
- **Checkout** picks from verified numbers (contributions can still use a one-off typed number; person-to-person payments use verified numbers or the sign-in number).

## Changing the sign-in number

Settings → Sign-in number → Change. A code goes to the new number; the change applies only after it is entered. A number already used to sign in to another account is refused.

## Where SMS is used

Sign-in codes, verifying a Mobile Money number, changing the sign-in number, and (next) inviting someone who isn't on Sendoh yet. Receipts, reminders and new rounds stay in the app and push.

## Testing without SMS (staging only)

Set `SENDOH_SHOW_TEST_CODES=1` on the staging backend. Every code request then returns the code to the app, which shows "Testing: your code is 123456" with a **Use it** button. This works only when the server's stage is development or staging: a production server never returns a code, whatever this setting says. Remove the setting once SMS is live.

Real SMS: set `OTP_PROVIDER=infobip` with `INFOBIP_BASE_URL`, `INFOBIP_API_KEY` and `INFOBIP_SENDER`.
