# Getting in, and Mobile Money numbers

Sendoh knows you as you: your name and @username. The phone number you sign in with is only a key. The Mobile Money numbers you pay with and get paid on are separate settings you manage.

## Getting in (app)

Each screen holds one idea and as little text as possible.

1. **Welcome:** the Sendoh mark, "Organize money. Together.", the group picture, *Create account* and *I already have an account*. A small switch at the top changes the language.
2. **Your phone number** (1 of 4): +237 field; the MTN or Orange mark appears once the prefix is known. *Send code* waits for nine digits. Terms and privacy sit in one line underneath.
3. **Enter the code** (2 of 4): six boxes, *Resend code* after 60 seconds, *Change number*.
4. **Your profile** (3 of 4): optional photo, name, @username, and one tick: "I'm at least 12 and, if under 18, have a parent or guardian's permission." *Continue* waits for all three.
5. **Mobile money** (4 of 4): the sign-in number, already verified, ticked to pay and receive; *Add another number*; or *Skip for now*.

## Mobile Money numbers (Profile → Mobile money numbers)

- Up to **3 numbers**, MTN MoMo or Orange Money, chosen from the prefix (changeable).
- Each number is **verified by an SMS code sent to it**. If it's a parent's phone, the parent reading out the code is their consent. The sign-in number needs no second code.
- One number is the default **to pay with**, and one **to receive on**. The first verified number is both.
- Choosing a receive number records a new receiving destination; anything already quoted keeps the destination it was quoted with.
- Removing a number keeps past records.
- **Checkout** picks from verified numbers (contributions can still use a one-off typed number; person-to-person payments use verified numbers or the sign-in number).

## Changing the sign-in number

Profile → Sign-in number. A code goes to the new number; the change applies only after it is entered. A number already used to sign in to another account is refused.

## Where SMS is used

Sign-in codes, verifying a Mobile Money number, changing the sign-in number, and (next) inviting someone who isn't on Sendoh yet. Receipts, reminders and new rounds stay in the app and push.

## Testing without SMS (staging only)

Set `SENDOH_SHOW_TEST_CODES=1` on the staging backend. Every code request then returns the code to the app, which shows "Testing: your code is 123456" with a **Use it** button. This works only when the server's stage is development or staging: a production server never returns a code, whatever this setting says. Remove the setting once SMS is live.

Real SMS: set `OTP_PROVIDER=infobip` with `INFOBIP_BASE_URL`, `INFOBIP_API_KEY` and `INFOBIP_SENDER`.
