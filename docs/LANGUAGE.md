# Languages: English and French

Sendoh speaks English and French everywhere: the app, the guest web pages and the landing page. People choose the language themselves:

- **App:** the English · Français switch on the welcome screen, and Profile → Language. The choice is remembered on the phone. Before a choice, the phone's language decides. Switching redraws every open screen in place, so no step or sign-in is lost.
- **Web:** the English · Français switch on every page. The choice is remembered in a cookie. Before a choice, the browser's language decides.

## How text is written

English is the source text and the key. French lives beside it:

- App: `t('Round {round} · Paid', {'round': round})` in `lib/`, French in `lib/i18n_fr.dart`.
- Web: `t('Round {round} · Paid', {round})` (or `k('…')` where text is defined in a list), French in `app/i18n-fr.ts`.

Placeholders like `{amount}` must appear in both languages. Amounts go through the formatter (`coordinationMoney`/`fcfa` in the app, `money` from `useT()` on the web), which writes `48,000 FCFA` in English and `48 000 FCFA` in French.

Keep values that code compares (statuses, filter keys, payment methods) in English, and translate them only where they are shown. A status badge picks its colour from the English meaning, so it stays right in French.

## Checks

These fail CI if any shown text lacks French, or if placeholders differ:

- App: `test/i18n_test.dart` (also checks French on a compact phone at large text size).
- Web: `scripts/test-i18n.cjs`.

Service error messages are translated too: add the backend's English message to the French file.

Long-form pages (privacy, terms, help) are written per language in `apps/guest_web/app/legal.ts` rather than string by string.

Voice in French: warm, clear and brief, with *vous*. "Collecte", "tour" (round), "versement" (payout), "espèces" (cash), "njangi" and "tontine" stay as people say them.
