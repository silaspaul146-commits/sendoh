# Sendoh coordination UX update

## Product intent

Sendoh is the coordination layer around group contributions: know the purpose,
who is involved, where the group stands, and what you should do next.
Home prioritizes collections you organize. Joined collections sit beneath them
in a horizontal shelf, with View all opening the joined list directly.

This is a frontend update on top of Backend Payments Update, not a new payment
provider. No database migration or environment changes are required. Keep the
existing staging test-payment settings. Install the newly built APK.

## Implemented flow

| Surface | Experience |
| --- | --- |
| Home | Profile greeting, orange Create collection action, organized collections, horizontal joined shelf, invitations |
| Organizer card | Teal featured card, actual total and target, separate test total, real participant avatars, deadline |
| Collection | Group progress, Copy link / Invite / Receipts, test contribution action, People first, About second |
| Joined collection | Organizer context, shared progress, personal expected amount, deadline, contribution and personal receipts |
| Contribution | Amount presets, visible four-step progress, review, provider selection, backend test result and receipt |
| Guest web | Same teal progress treatment, verified contributor context, visible checkout steps, clear back navigation |
| Activity | Refreshable organizer updates, distinct test-record styling, push-triggered refresh; joined alerts remain in Notifications |

Teal #0B3D3B establishes hierarchy. Existing brand orange #E8A33D emphasizes
creation and progress. Cream #FBF9F6 provides the background. Text stays dark on
orange for legibility. Existing logo artwork is unchanged. No invented avatars,
contributions or successful real-payment states are inserted.

Home refreshes owned and joined collections after returning from their screens.
Joined cards have a bounded width and natural height (including larger text),
not a fixed-height clipping carousel. Cards are tappable, not decorative.
Public guest pages still do not expose a selectable roster of other people's
names. Verified identity determines attribution. A member's view does not gain
organizer permissions just to resemble a board.

## UI boards reviewed and scope differences

Reviewed the supplied overview, creation/share, existing-user/auth, contribution/
management, activity/cash, requests/P2P and settlement boards, alongside existing
DECISIONS, UI_FIDELITY_UPDATE, EXPERIENCE_UPDATE and Backend Payments documentation.
Older docs describe earlier increments; this document describes this patch.

This is an implementation alignment, not a claim of pixel-perfect device parity.
Some boards use a brighter orange; this patch preserves the approved existing
brand token and launcher. Cash recording at reconciliation, pause/close/settle,
contact import, full activity filters/export, Requests/P2P/Near2P, real SMS and
CamPay remain separate implementation work. The previous decisions specify cash
at final reconciliation and CamPay last. Inactive Request/Pay home shortcuts
were removed rather than presented as working features. No automatic keepalive,
authentication changes or SMS delivery changes are included.

## Install

Extract the ZIP. From the extracted Sendoh_Coordination_UX_Update folder:

```powershell
python .\Sendoh_Coordination_UX_Update.py --project C:\Users\IHIMBRU\Desktop\sendoh --check
python .\Sendoh_Coordination_UX_Update.py --project C:\Users\IHIMBRU\Desktop\sendoh --apply
```

Unknown edits cause a conflict and no writes. Use --export proposed-update to
inspect them. Formatting-only Dart differences and the known formatter-import /
previous invitation-test wording corrections are accepted. Backups are automatic.

## Run locally (Flutter 3.35.7, same as CI)

```powershell
cd C:\Users\IHIMBRU\Desktop\sendoh\apps\organizer_flutter
dart format lib/coordination.dart lib/design.dart lib/main.dart lib/invitations.dart lib/payment_demo.dart test/invitations_test.dart
dart fix --apply --code=curly_braces_in_flow_control_structures
flutter analyze
flutter test
cd ..\guest_web
npm run typecheck
npm run build
```

The package includes the payment formatter fix and updates the existing invitation
wording assertion. Test scrolling follows the new content height.
Source/diff and packaging checks were performed here. Runtime analysis, tests,
web build and device visual verification are left to you as requested; they have
not been claimed as passing.

## Acceptance on device

1. Home: own collections first, joined shelf below. Swipe between multiple joined
   collections; View all must open Joined, not pending invitations.
2. Open an organized collection: People selected; avatars/counts reflect backend
   data; Copy link, Invite and Receipts work. Empty/error states remain usable.
3. Open joined collection, complete a test contribution, return Home. Test totals
   refresh, actual total stays unchanged; personal receipt exists on the backend.
4. Repeat in the guest web flow; identity is yours, not another participant's.
5. Check long collection names, a narrow phone and large text. Verify no clipped
   actions and that the horizontal shelf still scrolls.
6. Confirm a push update refreshes collection/activity information. Denied OS
   notification permission must never prevent using the app.

After checks pass:

```powershell
cd C:\Users\IHIMBRU\Desktop\sendoh
Get-Content .\sendoh-coordination-ux-paths.txt | ForEach-Object { git add -- $_ }
git diff --cached --stat
git commit -m "Make Sendoh collections a clearer coordination experience"
git push
```

Vercel builds the guest changes. GitHub Actions builds the new Android artifact.
Download sendoh-android-staging from the successful run, extract and install the
APK. Existing Render backend remains compatible; this package has no backend edits.
