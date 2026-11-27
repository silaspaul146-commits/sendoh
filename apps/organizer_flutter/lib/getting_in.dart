import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account.dart' show openSendohPage;
import 'design.dart';
import 'i18n.dart';
import 'money_numbers.dart';

/// Getting in: the welcome with the group, then four short steps
/// (number, code, profile, Mobile Money). One idea per screen, little text.

/// Step 0: the brand, the promise and the people. Nothing to read.
class WelcomeStep extends StatelessWidget {
  const WelcomeStep(
      {super.key,
      required this.onStart,
      required this.onSignIn,
      this.busy = false,
      this.notice,
      this.extra});
  final VoidCallback onStart, onSignIn;
  final bool busy;

  /// A saved-session message or retry, shown above the brand when present.
  final Widget? notice;

  /// Development-only tools, under the buttons.
  final Widget? extra;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: ConstrainedBox(
              constraints: BoxConstraints(
                  minHeight: (box.maxHeight - 32).clamp(0, double.infinity)),
              child: IntrinsicHeight(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    const Align(
                        alignment: Alignment.centerRight,
                        child: LanguageSwitch()),
                    if (notice != null) notice!,
                    const Spacer(),
                    const SendohBrand(vertical: true),
                    const SizedBox(height: 14),
                    Text(t('Organize money. Together.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16, color: SendohColors.secondary)),
                    const SizedBox(height: 36),
                    Semantics(
                        label: t('Three friends coordinating money together'),
                        image: true,
                        child: SizedBox(
                            height: 240,
                            child: Image.asset('assets/welcome-community.png',
                                fit: BoxFit.contain,
                                excludeFromSemantics: true))),
                    const SizedBox(height: 40),
                    FilledButton(
                        onPressed: busy ? null : onStart,
                        child: Text(t('Create account'))),
                    const SizedBox(height: 12),
                    OutlinedButton(
                        onPressed: busy ? null : onSignIn,
                        child: Text(t('I already have an account'))),
                    if (extra != null) extra!,
                    const Spacer(),
                  ])))));
}

/// The quiet language switch: shows the other language, one tap to change.
class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguage,
      builder: (context, current, _) => TextButton.icon(
          style: TextButton.styleFrom(
              foregroundColor: SendohColors.secondary,
              minimumSize: const Size(0, 40)),
          onPressed: () => chooseLanguage(
              current == AppLanguage.en ? AppLanguage.fr : AppLanguage.en),
          icon: const Icon(Icons.language, size: 18),
          label: Text(current == AppLanguage.en ? 'Français' : 'English')));
}

/// Back, "Sendoh", "n of 4": the top of every step.
class StepHeader extends StatelessWidget {
  const StepHeader({super.key, required this.step, this.onBack});
  final int step;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => SizedBox(
      height: 56,
      child: Row(children: [
        if (onBack != null)
          IconButton(
              tooltip: t('Back'),
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_ios_new, size: 20))
        else
          const SizedBox(width: 12),
        const SizedBox(width: 4),
        const Text('Sendoh',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: SendohColors.ink)),
        const Spacer(),
        Text(t('{step} of 4', {'step': step}),
            style: const TextStyle(fontSize: 15, color: SendohColors.ink)),
        const SizedBox(width: 12),
      ]));
}

/// One step: a title, at most one short line, the form, the action.
class StepFrame extends StatelessWidget {
  const StepFrame(
      {super.key,
      required this.title,
      required this.children,
      required this.action,
      this.lead,
      this.footer});
  final String title;
  final String? lead;
  final List<Widget> children;
  final Widget action;
  final Widget? footer;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 20),
        Text(title,
            style: const TextStyle(
                fontSize: 32,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: SendohColors.ink)),
        if (lead != null) ...[
          const SizedBox(height: 10),
          Text(lead!,
              style: const TextStyle(
                  fontSize: 15, height: 1.45, color: SendohColors.secondary)),
        ],
        const SizedBox(height: 32),
        ...children,
        const SizedBox(height: 36),
        action,
        if (footer != null) ...[const SizedBox(height: 16), footer!],
      ]);
}

/// A label above a field, as in the approved designs.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: SendohColors.ink)));
}

/// Nine digits, nothing else.
final phoneDigits = <TextInputFormatter>[
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(9),
];

/// The +237 number field with the network mark once it is known.
class PhoneField extends StatelessWidget {
  const PhoneField(
      {super.key,
      required this.controller,
      this.enabled = true,
      this.onChanged,
      this.autofocus = false});
  final TextEditingController controller;
  final bool enabled, autofocus;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) {
    final network = networkOf(controller.text);
    return TextField(
        controller: controller,
        enabled: enabled,
        autofocus: autofocus,
        keyboardType: TextInputType.phone,
        onChanged: onChanged,
        autofillHints: const [AutofillHints.telephoneNumberNational],
        inputFormatters: phoneDigits,
        style: const TextStyle(fontSize: 18, letterSpacing: .5),
        decoration: InputDecoration(
            hintText: '6XX XX XX XX',
            prefixIcon: Container(
                width: 76,
                alignment: Alignment.center,
                margin: const EdgeInsets.only(right: 10),
                decoration: const BoxDecoration(
                    border: Border(
                        right: BorderSide(color: SendohColors.border))),
                child: const Text('+237',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
            suffixIcon: network == null
                ? null
                : Padding(
                    padding: const EdgeInsets.all(10),
                    child: NetworkBadge(network))));
  }
}

/// Terms and privacy, one quiet line under the first action.
class TermsNote extends StatelessWidget {
  const TermsNote({super.key});
  @override
  Widget build(BuildContext context) {
    const link = TextStyle(
        color: SendohColors.teal,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.underline);
    return Text.rich(
        TextSpan(style: SendohTextStyles.caption, children: [
          TextSpan(text: '${t('By continuing, you accept our')} '),
          TextSpan(
              text: t('Terms'),
              style: link,
              recognizer: TapGestureRecognizer()
                ..onTap = () => openSendohPage('/terms')),
          TextSpan(text: ' ${t('and')} '),
          TextSpan(
              text: t('Privacy policy'),
              style: link,
              recognizer: TapGestureRecognizer()
                ..onTap = () => openSendohPage('/privacy')),
          const TextSpan(text: '.'),
        ]),
        textAlign: TextAlign.center);
  }
}

/// Step 4: the sign-in number, already verified, ready to pay and receive.
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

  Widget numberCard(
          {required Widget badge,
          required String title,
          required String detail,
          Widget? trailing,
          VoidCallback? onTap,
          bool selected = false}) =>
      Material(
          color: SendohColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                  color: selected ? SendohColors.teal : SendohColors.border,
                  width: selected ? 1.6 : 1)),
          child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    badge,
                    const SizedBox(width: 14),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(title,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(detail, style: SendohTextStyles.caption),
                        ])),
                    if (trailing != null) trailing,
                  ]))));

  @override
  Widget build(BuildContext context) => StepFrame(
        title: t('Mobile money'),
        lead: t('Where you pay from and get paid.'),
        action:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FilledButton(
              onPressed: busy ? null : onDone,
              child: Text(busy ? t('Please wait…') : t('Continue'))),
          const SizedBox(height: 4),
          TextButton(
              onPressed: busy ? null : onSkip, child: Text(t('Skip for now'))),
        ]),
        children: [
          if (network != null && signInMasked != null)
            numberCard(
                badge: NetworkBadge(network),
                title: '${walletLabel(network)} · $signInMasked',
                detail: t('Pay and receive'),
                selected: useSignIn,
                onTap: busy ? null : () => onToggle(!useSignIn),
                trailing: Checkbox(
                    value: useSignIn,
                    onChanged: busy ? null : (v) => onToggle(v == true))),
          for (final n in added) ...[
            const SizedBox(height: 10),
            numberCard(
                badge: NetworkBadge(n['method'] as String?),
                title: '${walletLabel(n['method'] as String?)} · ${n['masked']}',
                detail: n['verified'] == true
                    ? t('Verified')
                    : t('Waiting for its code'),
                trailing: n['verified'] == true
                    ? const Icon(Icons.check_circle, color: SendohColors.teal)
                    : null),
          ],
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: busy ? null : onAdd,
                  icon: const Icon(Icons.add),
                  label: Text(t('Add another number')))),
        ],
      );
}
