import 'package:flutter/material.dart';

import 'account.dart' show DeleteAccountScreen, openSendohPage;
import 'api.dart';
import 'design.dart';
import 'device_lock.dart';
import 'i18n.dart';
import 'money_numbers.dart';
import 'session_store.dart';

/// Profile, as approved: who you are on a teal card, then short grouped rows.

/// The teal card: photo, name, @username, Edit.
class ProfileHeaderCard extends StatelessWidget {
  const ProfileHeaderCard(
      {super.key,
      required this.avatar,
      required this.name,
      this.username,
      required this.onEdit});
  final Widget avatar;
  final String name;
  final String? username;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0B5E57), Color(0xFF0A4F4A)])),
          child: Stack(children: [
            // Quiet rings, as on the approved card.
            for (final r in const [150.0, 110.0, 70.0])
              Positioned(
                  right: -r / 2 + 10,
                  bottom: -r / 2 + 10,
                  child: Container(
                      width: r,
                      height: r,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: .06),
                              width: 14)))),
            Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 8, 20),
                child: Row(children: [
                  Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: avatar),
                  const SizedBox(width: 16),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                        if (username != null)
                          Text('@$username',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white.withValues(alpha: .85))),
                      ])),
                  TextButton.icon(
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.white),
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      label: Text(t('Edit'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700))),
                ])),
          ])));
}

/// A section title and its white card of rows.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, this.title, required this.children});
  final String? title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null)
          Padding(
              padding: const EdgeInsets.fromLTRB(4, 28, 4, 12),
              child: Text(title!,
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: SendohColors.ink)))
        else
          const SizedBox(height: 20),
        SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 72),
                children[i],
              ]
            ])),
      ]);
}

/// One row: a soft teal icon tile, the label, an optional value, then a chevron.
class SettingsRow extends StatelessWidget {
  const SettingsRow(
      {super.key,
      required this.icon,
      required this.title,
      this.value,
      this.trailing,
      this.onTap});
  final IconData icon;
  final String title;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: SendohColors.tealSoft,
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: SendohColors.ink, size: 22)),
            const SizedBox(width: 14),
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500))),
            if (value != null)
              Padding(
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: Text(value!,
                      style: const TextStyle(
                          fontSize: 15, color: SendohColors.secondary))),
            trailing ??
                const Icon(Icons.chevron_right, color: SendohColors.ink),
          ])));
}

/// Settings › Mobile money numbers, on its own page.
class MoneyNumbersScreen extends StatelessWidget {
  const MoneyNumbersScreen({super.key, required this.api});
  final SendohApi api;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(t('Mobile money numbers'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        MoneyNumbersSection(api: api, showTitle: false),
      ]));
}

/// The sign-in number row, showing which number it is.
class SignInNumberRow extends StatefulWidget {
  const SignInNumberRow({super.key, required this.api});
  final SendohApi api;
  @override
  State<SignInNumberRow> createState() => _SignInNumberRowState();
}

class _SignInNumberRowState extends State<SignInNumberRow> {
  String? masked;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await widget.api.request('/me/money-numbers');
      final m = r['sign_in_masked'] as String?;
      if (mounted) setState(() => masked = m?.replaceFirst('+237 ', ''));
    } catch (_) {/* The row still opens the change screen. */}
  }

  @override
  Widget build(BuildContext context) => SettingsRow(
      icon: Icons.key_outlined,
      title: t('Sign-in number'),
      value: masked,
      onTap: () async {
        final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
                builder: (_) => ChangeSignInNumberScreen(api: widget.api)));
        if (changed == true) await load();
      });
}

/// Device unlock as a switch: on or off, confirmed with the device lock.
class DeviceUnlockRow extends StatefulWidget {
  const DeviceUnlockRow({super.key});
  @override
  State<DeviceUnlockRow> createState() => _DeviceUnlockRowState();
}

class _DeviceUnlockRowState extends State<DeviceUnlockRow> {
  bool? on;

  @override
  void initState() {
    super.initState();
    SessionStore.locked().then((v) {
      if (mounted) setState(() => on = v);
    });
  }

  Future<void> toggle() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await authenticateDevice(
          t('Confirm device unlock settings for Sendoh'));
      if (!ok) return;
      final enabled = !(on ?? false);
      await SessionStore.setLocked(enabled);
      if (mounted) setState(() => on = enabled);
    } catch (_) {
      messenger.showSnackBar(SnackBar(
          content:
              Text(t('Set up a screen lock on this device, then try again.'))));
    }
  }

  @override
  Widget build(BuildContext context) => SettingsRow(
      icon: Icons.fingerprint,
      title: t('Device unlock'),
      onTap: on == null ? null : toggle,
      trailing: Switch(
          value: on ?? false,
          onChanged: on == null ? null : (_) => toggle()));
}

/// Language: the current one, changed from a short sheet.
class LanguageRow extends StatelessWidget {
  const LanguageRow({super.key});

  static const names = {AppLanguage.en: 'English', AppLanguage.fr: 'Français'};

  Future<void> choose(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: SendohColors.canvas,
      builder: (sheet) => SafeArea(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final entry in names.entries)
                  ListTile(
                      title: Text(entry.value,
                          style: const TextStyle(fontSize: 17)),
                      trailing: appLanguage.value == entry.key
                          ? const Icon(Icons.check, color: SendohColors.teal)
                          : null,
                      onTap: () {
                        Navigator.pop(sheet);
                        chooseLanguage(entry.key);
                      }),
              ]))));

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguage,
      builder: (context, current, _) => SettingsRow(
          icon: Icons.language,
          title: t('Language'),
          value: names[current],
          onTap: () => choose(context)));
}

/// Help, privacy, terms, and deleting the account.
class HelpLegalScreen extends StatelessWidget {
  const HelpLegalScreen(
      {super.key, required this.api, required this.onDeleted});
  final SendohApi api;
  final Future<void> Function() onDeleted;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(t('Help & legal'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        SettingsSection(children: [
          SettingsRow(
              icon: Icons.help_outline,
              title: t('Help'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => openSendohPage('/support')),
          SettingsRow(
              icon: Icons.privacy_tip_outlined,
              title: t('Privacy'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => openSendohPage('/privacy')),
          SettingsRow(
              icon: Icons.description_outlined,
              title: t('Terms of use'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => openSendohPage('/terms')),
        ]),
        const SizedBox(height: 24),
        TextButton(
            style: TextButton.styleFrom(foregroundColor: SendohColors.red),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    DeleteAccountScreen(api: api, onDeleted: onDeleted))),
            child: Text(t('Delete account'))),
      ]));
}
