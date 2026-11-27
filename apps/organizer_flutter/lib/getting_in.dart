import 'package:flutter/material.dart';

import 'account.dart' show LanguageToggle, openSendohPage;
import 'design.dart';
import 'i18n.dart';
import 'money_numbers.dart';

/// Getting in, as approved: a welcome that says what Sendoh is for, then four
/// short steps (number, SMS code, who you are, how you pay and get paid).

/// Step 0: what Sendoh is, in three ways of moving money.
class WelcomeStep extends StatelessWidget {
  const WelcomeStep(
      {super.key,
      required this.onStart,
      required this.onSignIn,
      this.busy = false});
  final VoidCallback onStart, onSignIn;
  final bool busy;

  Widget mode(IconData icon, String title, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: SendohColors.surface,
            border: Border.all(color: SendohColors.border),
            borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: SendohColors.tealSoft,
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: SendohColors.teal, size: 21)),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                Text(text,
                    style: const TextStyle(
                        fontSize: 13, color: SendohColors.secondary)),
              ])),
        ]),
      );

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Align(alignment: Alignment.centerRight, child: LanguageToggle()),
        const SizedBox(height: 24),
        const Align(alignment: Alignment.centerLeft, child: SendohBrand()),
        const SizedBox(height: 24),
        Text(t('Money between people, finally coordinated.'),
            style: const TextStyle(
                fontSize: 32,
                height: 1.1,
                fontWeight: FontWeight.w900,
                color: SendohColors.ink)),
        const SizedBox(height: 12),
        Text(t('Ask, pay and collect with the people you know. Everyone sees who has paid and what is left.'),
            style: const TextStyle(
                fontSize: 16, height: 1.5, color: SendohColors.secondary)),
        const SizedBox(height: 24),
        mode(Icons.person_outline, t('Individually'),
            t('Request or send to a friend')),
        const SizedBox(height: 10),
        mode(Icons.phone_iphone, t('In person'),
            t('Scan a code, pay the right person')),
        const SizedBox(height: 10),
        mode(Icons.groups_outlined, t('In groups'),
            t('One link, everyone stays aligned')),
        const SizedBox(height: 28),
        FilledButton(
            onPressed: busy ? null : onStart, child: Text(t('Get started'))),
        const SizedBox(height: 8),
        TextButton(
            onPressed: busy ? null : onSignIn,
            child: Text(t('I already have an account · Sign in'))),
        const SizedBox(height: 4),
        Text(t('For everyone aged 12 and over'),
            textAlign: TextAlign.center, style: SendohTextStyles.caption),
      ]);
}

/// The frame shared by steps 1–4: back, "Step n of 4", a title, a line, the form, the action.
class StepFrame extends StatelessWidget {
  const StepFrame(
      {super.key,
      required this.step,
      required this.title,
      required this.lead,
      required this.children,
      required this.action,
      this.footer});
  final int step;
  final String title, lead;
  final List<Widget> children;
  final Widget action;
  final Widget? footer;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('Step {step} of 4', {'step': step}),
            style: SendohTextStyles.caption),
        const SizedBox(height: 16),
        Text(title,
            style: const TextStyle(
                fontSize: 28, height: 1.15, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Text(lead,
            style: const TextStyle(
                fontSize: 15, height: 1.55, color: SendohColors.secondary)),
        const SizedBox(height: 24),
        ...children,
        const SizedBox(height: 32),
        if (footer != null) ...[footer!, const SizedBox(height: 12)],
        action,
      ]);
}

/// Step 1 hint under the number: which network it is, and that wallets come later.
class NetworkHint extends StatelessWidget {
  const NetworkHint({super.key, required this.digits});
  final String digits;
  @override
  Widget build(BuildContext context) {
    final network = networkOf(digits);
    if (digits.length < 3 || network == null) return const SizedBox(height: 12);
    return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          NetworkBadge(network),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
                  t('{network} number. You can add Mobile Money numbers later.',
                      {'network': network == 'MTN' ? 'MTN' : 'Orange'}),
                  style: const TextStyle(
                      fontSize: 13, color: SendohColors.secondary))),
        ]));
  }
}

/// Step 1 footer: terms, privacy and the under-18 note.
class TermsNote extends StatelessWidget {
  const TermsNote({super.key});
  @override
  Widget build(BuildContext context) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(t('By continuing you accept the'),
              style: SendohTextStyles.caption),
          TextButton(
              onPressed: () => openSendohPage('/terms'),
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32)),
              child: Text(t('Terms'))),
          Text(t('and'), style: SendohTextStyles.caption),
          TextButton(
              onPressed: () => openSendohPage('/privacy'),
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32)),
              child: Text(t('Privacy policy'))),
          Text(
              t('Under 18? Use Sendoh with a parent or guardian’s permission.'),
              style: SendohTextStyles.caption),
        ],
      );
}

/// Step 4: the sign-in number offered as a verified Mobile Money number,
/// adding another, or skipping for now.
class WalletStep extends StatelessWidget {
  const WalletStep(
      {super.key,
      required this.signInMasked,
      required this.network,
      required this.useSignIn,
      required this.onToggle,
      required this.added,
      required this.onAdd,
      required this.onDone,
      required this.onSkip,
      this.busy = false});
  final String? signInMasked, network;
  final bool useSignIn, busy;
  final ValueChanged<bool> onToggle;
  final List<Map<String, dynamic>> added;
  final VoidCallback onAdd, onDone, onSkip;

  @override
  Widget build(BuildContext context) => StepFrame(
        step: 4,
        title: t('How do you pay and get paid?'),
        lead: t(
            'Add the Mobile Money numbers you use. You can change them anytime in Settings.'),
        action:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FilledButton(
              onPressed: busy ? null : onDone,
              child: Text(busy ? t('Please wait…') : t('Done'))),
          TextButton(
              onPressed: busy ? null : onSkip, child: Text(t('Skip for now'))),
        ]),
        children: [
          if (network != null && signInMasked != null)
            Material(
                color: SendohColors.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                        color:
                            useSignIn ? SendohColors.teal : SendohColors.border,
                        width: useSignIn ? 2 : 1)),
                child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: busy ? null : () => onToggle(!useSignIn),
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                NetworkBadge(network),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(
                                          '${walletLabel(network)} · $signInMasked',
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700)),
                                      Text(t('Your sign-in number'),
                                          style: SendohTextStyles.caption),
                                    ])),
                                Icon(
                                    useSignIn
                                        ? Icons.check_circle
                                        : Icons.radio_button_off,
                                    color: SendohColors.teal),
                              ]),
                              const SizedBox(height: 10),
                              Text(
                                  t('Already verified by the code you just entered. Use it to pay and to receive?'),
                                  style: SendohTextStyles.bodyMedium),
                            ])))),
          for (final n in added) ...[
            const SizedBox(height: 10),
            SurfaceCard(
                padding: EdgeInsets.zero,
                child: MoneyNumberTile(
                    number: n, trailing: const SizedBox.shrink())),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: busy ? null : onAdd,
              icon: const Icon(Icons.add),
              label: Text(t('Add another number'))),
          const SizedBox(height: 6),
          Text(t('An Orange Money number, or a parent’s MoMo'),
              textAlign: TextAlign.center, style: SendohTextStyles.caption),
        ],
      );
}
