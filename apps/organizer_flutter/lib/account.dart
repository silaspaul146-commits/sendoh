import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'config.dart';
import 'design.dart';
import 'i18n.dart';

/// Opens a page of the Sendoh website (help, privacy, terms) in the browser.
Future<void> openSendohPage(String path) =>
    launchUrl(Uri.parse('${SendohConfig.webBaseUrl}$path'),
        mode: LaunchMode.externalApplication);

/// The message an organizer sends when a new round opens, in their language.
String newRoundMessage(Map data) {
  final expected = data['expected_amount'];
  return [
    t('{collection} · Round {round} is open.',
        {'collection': data['name'] ?? '', 'round': data['round'] ?? ''}),
    if (expected != null)
      t('Your share: {amount}.', {'amount': fcfa(expected)}),
    t('Contribute here: {link}', {'link': data['share_url'] ?? ''}),
  ].join(' ');
}

/// Offers WhatsApp (or copying the link) right after a round opens.
Future<void> shareNewRound(BuildContext context, Map data,
    {Future<bool> Function(Uri)? launch}) async {
  final link = data['share_url'] as String?;
  if (link == null || link.isEmpty) return;
  final message = newRoundMessage(data);
  await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
              child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      t('Round {round} is open',
                          {'round': data['round'] ?? ''}),
                      style: SendohTextStyles.headingMedium),
                  const SizedBox(height: 8),
                  Text(
                      t('Members who use the link are not notified automatically. Tell your group: the link stays the same.'),
                      style: SendohTextStyles.bodyMedium),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                      icon: const Icon(Icons.chat_outlined),
                      onPressed: () async {
                        Navigator.pop(sheet);
                        final uri = Uri.parse(
                            'https://wa.me/?text=${Uri.encodeComponent(message)}');
                        await (launch ??
                            (u) => launchUrl(u,
                                mode: LaunchMode.externalApplication))(uri);
                      },
                      label: Text(t('Share on WhatsApp'))),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: message));
                        if (sheet.mounted) Navigator.pop(sheet);
                      },
                      label: Text(t('Copy message'))),
                  TextButton(
                      onPressed: () => Navigator.pop(sheet),
                      child: Text(t('Later'))),
                ]),
          )));
}

/// English · Français, always shown in each language's own name.
class LanguageChoice extends StatelessWidget {
  const LanguageChoice({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguage,
      // Label above, choices below: fits a small phone at large text sizes.
      builder: (context, current, _) =>
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(Icons.translate, color: SendohColors.secondary)),
            const SizedBox(width: 16),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(t('Language'), style: SendohTextStyles.bodyMedium),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final (language, label) in const [
                      (AppLanguage.en, 'English'),
                      (AppLanguage.fr, 'Français')
                    ])
                      ChoiceChip(
                          label: Text(label),
                          selected: current == language,
                          onSelected: (_) => chooseLanguage(language)),
                  ]),
                ])),
          ]));
}

/// The compact English · Français switch for the welcome screen.
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguage,
      builder: (context, current, _) => SegmentedButton<AppLanguage>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: AppLanguage.en, label: Text('English')),
            ButtonSegment(value: AppLanguage.fr, label: Text('Français')),
          ],
          selected: {current},
          onSelectionChanged: (s) => chooseLanguage(s.first)));
}

/// Help, privacy and terms: the same pages as on the website.
class AboutLinks extends StatelessWidget {
  const AboutLinks({super.key, this.open = openSendohPage});
  final Future<void> Function(String path) open;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final (icon, label, path) in [
          (Icons.help_outline, t('Help'), '/support'),
          (Icons.privacy_tip_outlined, t('Privacy'), '/privacy'),
          (Icons.description_outlined, t('Terms of use'), '/terms'),
        ])
          ListTile(
              leading: Icon(icon),
              title: Text(label),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => open(path)),
      ]);
}

/// Deleting the account: what goes, what stays, and nothing while money is moving.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen(
      {super.key, required this.api, required this.onDeleted});
  final SendohApi api;

  /// Signs the device out and returns to the welcome screen.
  final Future<void> Function() onDeleted;
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  Map<String, dynamic>? check;
  String? error;
  bool understood = false, busy = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await widget.api.request('/me/account/deletion');
      if (mounted) setState(() => check = Map<String, dynamic>.from(data));
    } catch (e) {
      if (mounted) {
        setState(() => error = t('Could not check your account. Try again.'));
      }
    }
  }

  String blockerText(Map b) => switch (b['code']) {
        'PAYMENT_CONFIRMING' =>
          t('A payment you made is still being confirmed.'),
        'TRANSFER_IN_PROGRESS' =>
          t('A payment to or from you is still on its way.'),
        'PAYOUT_IN_PROGRESS' => t('A collection payout is still being sent.'),
        'COLLECTION_HOLDS_MONEY' => t('Close and settle “{name}” first.',
            {'name': b['collection_name'] ?? ''}),
        _ => t((b['message'] as String?) ?? ''),
      };

  Future<void> delete() async {
    if (busy || !understood) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api
          .request('/me/account/delete', body: {'confirm': 'DELETE'});
      await widget.onDeleted();
    } catch (e) {
      if (mounted) {
        setState(() => error = t(
            'Your account was not deleted. Check what is still in progress, then try again.'));
        await load();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = check;
    final blockers = (c?['blockers'] as List? ?? const [])
        .map((b) => Map<String, dynamic>.from(b as Map))
        .toList();
    return Scaffold(
        appBar: AppBar(title: Text(t('Delete account'))),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          if (c == null && error == null)
            const Center(child: CircularProgressIndicator())
          else if (c != null) ...[
            SurfaceCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(t('What is deleted'),
                      style: SendohTextStyles.headingMedium),
                  const SizedBox(height: 8),
                  for (final line in [
                    t('Your name, @username and photo'),
                    t('The phone number you sign in with'),
                    t('Your sessions and notification settings'),
                  ])
                    Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('• $line',
                            style: SendohTextStyles.bodyMedium)),
                ])),
            const SizedBox(height: 12),
            SurfaceCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(t('What is kept'),
                      style: SendohTextStyles.headingMedium),
                  const SizedBox(height: 8),
                  Text(
                      t('Payment, payout and cash records stay as financial records, because other people’s receipts depend on them. Your name on them becomes “Deleted user”.'),
                      style: SendohTextStyles.bodyMedium),
                ])),
            const SizedBox(height: 20),
            if (blockers.isNotEmpty) ...[
              Text(t('Finish these first'),
                  style: SendohTextStyles.headingMedium),
              const SizedBox(height: 8),
              for (final b in blockers)
                Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• ${blockerText(b)}',
                        style: SendohTextStyles.bodyMedium)),
              const SizedBox(height: 8),
              Text(
                  t('No money is left without an owner: deletion waits until everything above has finished.'),
                  style: SendohTextStyles.caption),
            ] else ...[
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: understood,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => understood = v == true),
                  title: Text(t('I understand this cannot be undone.'))),
              const SizedBox(height: 12),
              FilledButton(
                  style:
                      FilledButton.styleFrom(backgroundColor: SendohColors.red),
                  onPressed: busy || !understood ? null : delete,
                  child:
                      Text(busy ? t('Please wait…') : t('Delete my account'))),
            ],
          ],
          if (error != null)
            Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(error!,
                    style: const TextStyle(color: SendohColors.red))),
        ]));
  }
}
