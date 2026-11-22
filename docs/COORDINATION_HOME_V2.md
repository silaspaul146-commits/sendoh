# Sendoh: coordination Home and flow direction

## Product definition

Sendoh coordinates money between people. Collections are the entry wedge, with
Requests, P2P and Near2P forming the broader experience. It is not a wallet.

This revision is grounded in the supplied source documents:
- Sendoh_Brand_Visual_Identity_System-1.docx, sections 1, 8, 9, 16, 17 and 22.
- Sendoh_V1_UX_Architecture-1.docx, sections 2–6, 8–10, 18–24 and 34.
- Sendoh_V1_Requirements_Specification-2.docx, sections 3, 26, 27 and 32.
- Current project DECISIONS.md and later invitation/payment implementation notes.

The original documents are preserved. This is the implementation/design addendum.
Latest decisions continue to override older cash, fee and identity proposals:
cash at final reconciliation; no wallet or user reversal flow; settlement fees
from the collection; verified attribution; CamPay integration last.

## Why three navigation destinations

Both Brand section 16 and UX Architecture section 4 explicitly prescribe Home,
Activity, Profile. They explicitly place Collect, Request and Pay within Home
rather than adding permanent tabs for each transaction type. Three tabs do not
mean three capabilities. Home is the action hub, Activity the ongoing record and
response surface, Profile the account area. Keep them unless usability evidence
shows that a new persistent area is needed.

Near2P belongs under Pay as identity discovery, not a separate money rail. QR
comes first, with optional consented proximity later. After resolving identity,
the user can Pay or Request. Scanning must never itself initiate a payment.

## Home layout

1. Quiet brand/app bar, notifications, invitations; compact name and avatar.
2. Collect / Request / Pay action row. Orange only for Collect; teal for the other
   actions. This intentionally moves actions higher than UX section 6's original
   fourth position so broader capabilities are discoverable without scrolling.
3. Needs your attention. In this build: up to two pending invitations, each opening
   its actual invitation detail. View all opens the inbox. Never infer an unpaid
   balance from an expected amount alone. Future request/payment attention will
   require authoritative state and actionable routes.
4. You organize. Two initial previews, first teal and second quieter; View all
   expands the list. Confirmed actual totals only. Teal progress while incomplete,
   green on target reached, explicit excess above target.
5. You joined. Horizontal row of 56px circles with collection initials and short
   names, about 88px per item at normal text size. Whole item is tappable. Tooltip
   and accessibility label retain the full name. No story rings, invented unread
   markers or implied payment progress. Tap opens existing personal collection
   context. View all opens the full joined list.
6. Recent activity. Up to three existing organizer events. View all opens Activity.
   Broader requests/P2P and participant events await the unified feed contract.

No wallet balance, charts, promotional slogans, decorative gradients or duplicate
invitations button. Warm neutrals stay subtle. Major amounts remain legible; long
names wrap, circle labels truncate accessibly and large text increases item width.

## Copy and simulation

Home no longer displays 'Not real funds' or repeated test-total lines. It uses only
collected_amount, never test_collected_amount. Test events are omitted from the
Home summary, but remain in Activity and payment history. Test mode identification
remains at payment/review/receipt boundaries. No simulated amount is relabelled
as a confirmed payment. No provider integration is enabled by this presentation
change.

## Flow sketch

Home → Collect → Purpose/details → Participants/expectations → Review → Create
→ Invite/share → Collection management.

Collection management → Overview / Contributions / Activity / Manage.
Manage → Invite, remind, edit where permitted, close → Final reconciliation/cash
→ Settlement review and fee → Confirm → Provider-confirmed settlement record.
Target reached does not automatically close a collection.

Home attention / invitation / joined circle → Personal collection context
→ Choose amount → Review contribution + fees → Authorize → Provider verification
→ Receipt. Joining is never a payment. Public guest entry converges here after
identity verification; existing signed-in identity must not be re-entered.

Home → Request → Identify person → Amount/reason/expiry → Review → Send
→ Recipient Pay or Decline → Shared request status and record.

Home → Pay → Identify person (Sendoh identity / link / QR) → Confirm recipient
→ Amount/note → Review total/fees → Authorize → Verified result → Receipt.

Pay → Near2P → Scan QR → Resolve person → Confirm identity → Pay or Request
→ Reuse the same downstream workflow. Optional proximity discovery comes later.

Activity → Needs a response / Recent events → Related collection/request/payment.
Profile → Identity / Security / Settings / History.

All payment paths converge on identity, intent, authorization, provider
verification, reconciliation, record and notification. No client-only success.

## Implemented versus planned

Implemented now: compact Home actions, availability sheets, real pending-invitation
reads and direct routing, organized previews, circular joined shortcuts, actual
progress, recent organizer activity, refresh on return and push, existing three-tab
navigation. Existing creation, invitations and contribution routes are preserved.

Request and Pay show Soon and explain availability when opened. Near2P is described
inside Pay. Request creation/delivery, P2P identity/payment endpoints, QR scanning,
proximity, expanded management, unified activity and live provider integration
are not implemented by this update. The sketch describes their intended flows;
it is not a claim of completion. No user data is collected in unavailable flows.

## Verification and remaining gate

Dart grammar parsing, source inspection, package integrity and updater checks are
performed here. Included widget tests cover current routing, circles, preview
expansion, narrow/large-text cards, real/test total separation and unavailable Pay.
Flutter analyzer, widget runtime tests and device visual comparison still must run
locally/CI; no Flutter SDK is installed here. The interactive sketch is a separate
HTML design aid, not a rendered Flutter screenshot.
