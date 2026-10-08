import 'package:flutter/material.dart';
import 'dart:convert';
import 'session_store.dart';
import 'device_lock.dart';
import 'profile_edit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api.dart';
import 'config.dart';
import 'onboarding.dart';
import 'create_collection.dart';
import 'design.dart';

final apiProvider =
    Provider<SendohApi>((ref) => throw StateError('Session required'));
final sendohNavigator = GlobalKey<NavigatorState>();
void main() => runApp(const ProviderScope(child: SendohApp()));
String money(dynamic n) => n == null
    ? 'No target'
    : '${n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')} FCFA';

class SendohApp extends StatelessWidget {
  const SendohApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'Sendoh',
      navigatorKey: sendohNavigator,
      builder: (context, child) => DeviceLock(
          child: child!,
          onSignIn: () =>
              sendohNavigator.currentState?.popUntil((route) => route.isFirst)),
      debugShowCheckedModeBanner: false,
      theme: sendohTheme(),
      home: const Onboarding());
}

class DevelopmentSession extends StatefulWidget {
  const DevelopmentSession({super.key});
  @override
  State<DevelopmentSession> createState() => _DevelopmentSessionState();
}

class _DevelopmentSessionState extends State<DevelopmentSession> {
  final url = TextEditingController(text: SendohConfig.apiBaseUrl),
      token = TextEditingController();
  String? error;
  bool busy = false;
  @override
  void dispose() {
    url.dispose();
    token.dispose();
    super.dispose();
  }

  Future<void> connect() async {
    setState(() {
      busy = true;
      error = null;
    });
    final api = SendohApi(
        url.text.trim().replaceAll(RegExp(r'/$'), ''), token.text.trim());
    try {
      final profile = await api.request('/me');
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ProviderScope(
              overrides: [apiProvider.overrideWithValue(api)],
              child: Shell(name: profile['display_name'] as String))));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Development connection')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text('Use your original token to open existing collections.'),
        const SizedBox(height: 24),
        TextField(
            controller: url,
            decoration: const InputDecoration(labelText: 'API URL')),
        const SizedBox(height: 16),
        TextField(
            controller: token,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Development token')),
        if (error != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(error!,
                  style: const TextStyle(color: SendohColors.red))),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: busy ? null : connect,
            child: Text(busy ? 'Connecting…' : 'Open organizer app'))
      ]));
}

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key, required this.name, this.account = const {}});
  final String name;
  final Map<String, dynamic> account;
  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  int tab = 0;
  late Map<String, dynamic> account = {
    'display_name': widget.name,
    ...widget.account
  };
  String get displayName => account['display_name'] as String;
  late Future<List<dynamic>> items;
  @override
  void initState() {
    super.initState();
    items = ref.read(apiProvider).collections();
  }

  void reload() => setState(() => items = ref.read(apiProvider).collections());
  Future<void> create() async {
    final api = ref.read(apiProvider);
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
            builder: (_) => ProviderScope(
                overrides: [apiProvider.overrideWithValue(api)],
                child: const CreateCollection())));
    if (!mounted || result == null) return;
    reload();
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CollectionCreated(data: result, api: api)));
  }

  void open(Map<String, dynamic> data) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) =>
              CollectionDetail(data: data, api: ref.read(apiProvider))));

  void comingSoon(String feature) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is coming after Collections.')));

  Widget homeAction(
          {required IconData icon,
          required String label,
          required VoidCallback onTap,
          bool primary = false}) =>
      Expanded(
          child: Material(
              color: primary ? SendohColors.teal : SendohColors.surface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 16),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: primary
                                  ? SendohColors.teal
                                  : SendohColors.border)),
                      child: Column(children: [
                        Icon(icon,
                            color: primary ? Colors.white : SendohColors.teal,
                            size: 23),
                        const SizedBox(height: 9),
                        Text(label,
                            style: TextStyle(
                                color:
                                    primary ? Colors.white : SendohColors.ink,
                                fontSize: 12,
                                fontWeight: FontWeight.w600))
                      ])))));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: tab == 0
                ? const SendohBrand()
                : Text(tab == 1 ? 'Activity' : 'Profile')),
        bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (v) => setState(() => tab = v),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home'),
              NavigationDestination(
                  icon: Icon(Icons.history), label: 'Activity'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile')
            ]),
        body: tab == 2
            ? profile()
            : tab == 1
                ? const ActivityView()
                : RefreshIndicator(
                    onRefresh: () async {
                      reload();
                      await items;
                    },
                    child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
                        children: [
                          Row(children: [
                            accountAvatar(24),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  const Text('Welcome back,',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: SendohColors.secondary)),
                                  const SizedBox(height: 4),
                                  Text(displayName,
                                      style: const TextStyle(
                                          fontSize: 21,
                                          fontWeight: FontWeight.w600))
                                ]))
                          ]),
                          const SizedBox(height: 28),
                          const Text('What would you like to do?',
                              style: TextStyle(
                                  fontSize: 13, color: SendohColors.secondary)),
                          const SizedBox(height: 12),
                          Row(children: [
                            homeAction(
                                icon: Icons.groups_outlined,
                                label: 'Collect',
                                onTap: create,
                                primary: true),
                            const SizedBox(width: 10),
                            homeAction(
                                icon: Icons.notifications_none,
                                label: 'Request',
                                onTap: () => comingSoon('Request money')),
                            const SizedBox(width: 10),
                            homeAction(
                                icon: Icons.send_outlined,
                                label: 'Pay',
                                onTap: () => comingSoon('Pay someone')),
                          ]),
                          const SizedBox(height: 30),
                          const Text('Your collections',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 16),
                          FutureBuilder<List<dynamic>>(
                              future: items,
                              builder: (context, s) {
                                if (s.hasError) {
                                  return Column(children: [
                                    const Text(
                                        'Couldn’t load your collections.'),
                                    TextButton(
                                        onPressed: reload,
                                        child: const Text('Try again'))
                                  ]);
                                }
                                if (!s.hasData) {
                                  return const Padding(
                                      padding: EdgeInsets.all(40),
                                      child: Center(
                                          child: CircularProgressIndicator()));
                                }
                                if (s.data!.isEmpty) {
                                  return const EmptyState(
                                      title:
                                          'Your first collection starts here',
                                      message:
                                          'Bring people together for a shared purpose. Create a collection and share one link.');
                                }
                                return Column(
                                    children: s.data!.asMap().entries.map((e) {
                                  final c = Map<String, dynamic>.from(e.value);
                                  return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 14),
                                      child: CollectionCard(
                                          data: c,
                                          featured: e.key == 0,
                                          onTap: () => open(c)));
                                }).toList());
                              }),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                              onPressed: create,
                              style: FilledButton.styleFrom(
                                  backgroundColor: SendohColors.orange,
                                  foregroundColor: SendohColors.ink),
                              icon: const Icon(Icons.add, size: 21),
                              label: const Text('Create collection')),
                        ])),
      );
  Widget accountAvatar(double radius) => account['avatar'] == null
      ? PersonAvatar(displayName, radius: radius)
      : CircleAvatar(
          radius: radius,
          backgroundImage:
              MemoryImage(base64Decode(account['avatar'] as String)));
  Widget profile() => ListView(padding: const EdgeInsets.all(24), children: [
        Center(child: accountAvatar(36)),
        const SizedBox(height: 14),
        Text(displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
        const SizedBox(height: 28),
        if (account['username'] != null)
          Text('@${account['username']}', textAlign: TextAlign.center),
        TextButton(
            onPressed: () async {
              final updated = await Navigator.of(context)
                  .push<Map<String, dynamic>>(MaterialPageRoute(
                      builder: (_) => EditProfile(
                          api: ref.read(apiProvider), account: account)));
              if (mounted && updated != null) setState(() => account = updated);
            },
            child: const Text('Edit profile')),
        ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Device unlock'),
            subtitle:
                const Text('Use biometrics or your device PIN when returning.'),
            onTap: () async {
              try {
                final ok = await authenticateDevice(
                    'Confirm device unlock settings for Sendoh');
                if (!ok) return;
                final enabled = !await SessionStore.locked();
                await SessionStore.setLocked(enabled);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        enabled
                            ? 'Device unlock enabled.'
                            : 'Device unlock disabled.',
                      ),
                    ),
                  );
                }
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Set up a screen lock on this device, then try again.',
                      ),
                    ),
                  );
                }
              }
            }),
        SurfaceCard(
            child: Column(children: [
          const SummaryRow('Account', 'Sendoh member'),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history),
              title: const Text('Activity', style: TextStyle(fontSize: 14)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => tab = 1))
        ])),
        const SizedBox(height: 28),
        OutlinedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              try {
                await ref.read(apiProvider).request('/auth/logout', body: {});
              } catch (_) {
                if (mounted) {
                  messenger.showSnackBar(const SnackBar(
                      content: Text(
                          'Could not reach server. Your session will expire automatically.')));
                }
              }
              await SessionStore.clear();
              if (mounted) {
                navigator.pop();
              }
            },
            child: const Text('Sign out'))
      ]);
}

class CollectionCard extends StatelessWidget {
  const CollectionCard(
      {super.key,
      required this.data,
      required this.onTap,
      this.featured = false});
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final bool featured;
  @override
  Widget build(BuildContext context) {
    final target = data['target_amount'] as int?;
    final collected = (data['collected_amount'] as num).toDouble();
    final color = featured ? Colors.white : SendohColors.ink;
    return Material(
        color: featured ? SendohColors.teal : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color:
                            featured ? SendohColors.teal : SendohColors.border,
                        width: .7)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(data['name'],
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: color))),
                        const SizedBox(width: 8),
                        StatusBadge(
                            data['status'] == 'ACTIVE' ? 'ACTIVE' : 'DRAFT')
                      ]),
                      const SizedBox(height: 24),
                      Wrap(
                          crossAxisAlignment: WrapCrossAlignment.end,
                          spacing: 4,
                          children: [
                            Text(money(data['collected_amount']),
                                style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w600,
                                    color: color)),
                            if (target != null)
                              Text('/ ${money(target)}',
                                  style: TextStyle(fontSize: 12, color: color))
                          ]),
                      const SizedBox(height: 12),
                      if (target != null)
                        ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: LinearProgressIndicator(
                                value: (collected / target)
                                    .clamp(0.0, 1.0)
                                    .toDouble(),
                                minHeight: 7,
                                backgroundColor: featured
                                    ? const Color(0xFF316260)
                                    : SendohColors.tealSoft,
                                color: collected >= target
                                    ? SendohColors.green
                                    : featured
                                        ? const Color(0xFF5DA59B)
                                        : SendohColors.teal)),
                      const SizedBox(height: 14),
                      Text(
                          '${(data['participants'] as List).length} participants · ${displayDate(data['deadline_at'])}',
                          style: TextStyle(fontSize: 12, color: color)),
                    ]))));
  }
}

class ActivityView extends ConsumerStatefulWidget {
  const ActivityView({super.key});
  @override
  ConsumerState<ActivityView> createState() => _ActivityViewState();
}

class _ActivityViewState extends ConsumerState<ActivityView> {
  late Future<dynamic> activity;
  @override
  void initState() {
    super.initState();
    activity = ref.read(apiProvider).request('/me/activity');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
      future: activity,
      builder: (context, s) {
        if (s.hasError) {
          return Center(
              child: TextButton(
                  onPressed: () => setState(() =>
                      activity = ref.read(apiProvider).request('/me/activity')),
                  child: const Text('Couldn’t load activity. Try again')));
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final entries = s.data as List;
        if (entries.isEmpty) {
          return const EmptyState(
              title: 'No activity yet',
              message: 'Updates from your collections will appear here.',
              icon: Icons.history);
        }
        return RefreshIndicator(
            onRefresh: () async {
              setState(() =>
                  activity = ref.read(apiProvider).request('/me/activity'));
              await activity;
            },
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(22),
                children: [
                  const Text('All updates',
                      style: TextStyle(
                          fontSize: 13, color: SendohColors.secondary)),
                  const SizedBox(height: 20),
                  ...entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const CircleAvatar(
                                radius: 18,
                                backgroundColor: SendohColors.tealSoft,
                                child: Icon(Icons.add,
                                    size: 20, color: SendohColors.teal)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(e['message'],
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 5),
                                  Text(displayDate(e['created_at']),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: SendohColors.muted))
                                ]))
                          ])))
                ]));
      });
}

Future<void> copyCollectionLink(BuildContext context, String link) async {
  await Clipboard.setData(ClipboardData(text: link));
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Collection link copied')));
  }
}

class CollectionCreated extends StatelessWidget {
  const CollectionCreated({super.key, required this.data, required this.api});
  final Map<String, dynamic> data;
  final SendohApi api;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(),
      body: SafeArea(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
              children: [
            const SizedBox(height: 20),
            const Center(
                child: CircleAvatar(
                    radius: 38,
                    backgroundColor: SendohColors.teal,
                    child: Icon(Icons.check, color: Colors.white, size: 40))),
            const SizedBox(height: 24),
            const Text('Collection created!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            const Text('Now invite people to contribute.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: SendohColors.secondary)),
            const SizedBox(height: 30),
            SurfaceCard(
                child: Column(children: [
              Row(children: [
                const CollectionSymbol(),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(data['name'],
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)))
              ]),
              const SizedBox(height: 12),
              SummaryRow('Target', money(data['target_amount'])),
              SummaryRow('Deadline', displayDate(data['deadline_at'])),
              SummaryRow(
                  'Participants', '${(data['participants'] as List).length}')
            ])),
            const SizedBox(height: 24),
            const Text('One link for everyone',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            SurfaceCard(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                      child: SelectableText(data['share_url'] ?? '',
                          style: const TextStyle(
                              fontSize: 12, color: SendohColors.teal))),
                  IconButton(
                      tooltip: 'Copy collection link',
                      onPressed: () =>
                          copyCollectionLink(context, data['share_url']),
                      icon: const Icon(Icons.copy_outlined, size: 19))
                ])),
            const SizedBox(height: 22),
            FilledButton.icon(
                onPressed: () => copyCollectionLink(context, data['share_url']),
                icon: const Icon(Icons.link, size: 18),
                label: const Text('Copy collection link')),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            CollectionDetail(data: data, api: api))),
                child: const Text('View collection')),
            const SizedBox(height: 18),
            const Text(
                'Share the copied link in WhatsApp or any messaging app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, height: 1.6, color: SendohColors.muted))
          ])));
}

class CollectionDetail extends StatefulWidget {
  const CollectionDetail({super.key, required this.data, required this.api});
  final Map<String, dynamic> data;
  final SendohApi api;
  @override
  State<CollectionDetail> createState() => _CollectionDetailState();
}

class _CollectionDetailState extends State<CollectionDetail> {
  late Map<String, dynamic> data;
  int tab = 0;
  String filter = 'All';
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    data = widget.data;
  }

  Future<void> refresh() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.request('/collections/${data['id']}');
      if (mounted) setState(() => data = Map<String, dynamic>.from(result));
    } catch (_) {
      if (mounted) setState(() => error = 'Couldn’t refresh this collection.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void participant(Map<String, dynamic> p) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: PersonAvatar(p['name'], radius: 28)),
                    const SizedBox(height: 14),
                    Text(p['name'],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 20),
                    SummaryRow(
                        'Expected',
                        p['expected_amount'] == null
                            ? 'Any amount'
                            : money(p['expected_amount'])),
                    const SummaryRow('Contributed', '0 FCFA'),
                    if (p['expected_amount'] != null)
                      SummaryRow('Remaining', money(p['expected_amount'])),
                    const Center(child: StatusBadge('Pending', pending: true)),
                    const SizedBox(height: 20),
                    const Text('No contributions recorded yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: SendohColors.secondary))
                  ]))));
  @override
  Widget build(BuildContext context) {
    final target = data['target_amount'] as int?;
    final collected = data['collected_amount'] as int;
    final people = data['participants'] as List;
    final pct = target == null ? 0.0 : collected / target * 100;
    return Scaffold(
        appBar: AppBar(title: Text(data['name']), actions: [
          IconButton(
              tooltip: 'Refresh',
              onPressed: busy ? null : refresh,
              icon: const Icon(Icons.refresh, size: 21))
        ]),
        body: RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
                children: [
                  Align(
                      alignment: Alignment.centerRight,
                      child: StatusBadge(
                          data['status'] == 'ACTIVE' ? 'ACTIVE' : 'DRAFT')),
                  const SizedBox(height: 20),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    metric('Target', money(target)),
                    metric('Collected', money(collected)),
                    metric(
                        target != null && collected > target
                            ? 'Above target'
                            : 'Remaining',
                        target == null
                            ? '—'
                            : money((target - collected).abs()))
                  ]),
                  const SizedBox(height: 28),
                  if (target != null) ...[
                    RichText(
                        text: TextSpan(
                            style: const TextStyle(
                                color: SendohColors.secondary, fontSize: 12),
                            children: [
                          TextSpan(
                              text: '${pct.toStringAsFixed(1)}% ',
                              style: const TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w600,
                                  color: SendohColors.teal)),
                          const TextSpan(text: 'of target collected')
                        ])),
                    const SizedBox(height: 12),
                    ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                            value: (pct / 100).clamp(0.0, 1.0).toDouble(),
                            minHeight: 8,
                            backgroundColor: SendohColors.border,
                            color: pct >= 100
                                ? SendohColors.green
                                : SendohColors.teal)),
                    const SizedBox(height: 14)
                  ],
                  Text('${people.length} participants',
                      style: const TextStyle(
                          fontSize: 12, color: SendohColors.secondary)),
                  const SizedBox(height: 20),
                  if (data['share_url'] != null)
                    OutlinedButton.icon(
                        onPressed: () =>
                            copyCollectionLink(context, data['share_url']),
                        icon: const Icon(Icons.share_outlined, size: 18),
                        label: const Text('Copy collection link')),
                  const SizedBox(height: 22),
                  Row(
                      children: ['Overview', 'Contributions']
                          .asMap()
                          .entries
                          .map((e) => Expanded(
                              child: InkWell(
                                  onTap: () => setState(() => tab = e.key),
                                  child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      decoration: BoxDecoration(
                                          border: Border(
                                              bottom: BorderSide(
                                                  color: tab == e.key
                                                      ? SendohColors.teal
                                                      : SendohColors.border,
                                                  width:
                                                      tab == e.key ? 2 : .7))),
                                      child: Text(e.value,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: tab == e.key
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: SendohColors.teal))))))
                          .toList()),
                  const SizedBox(height: 18),
                  if (tab == 0) ...[
                    if ((data['description'] as String).isNotEmpty) ...[
                      Text(data['description'],
                          style: const TextStyle(
                              fontSize: 14,
                              height: 1.7,
                              color: SendohColors.secondary)),
                      const SizedBox(height: 18)
                    ],
                    SummaryRow('Deadline', displayDate(data['deadline_at'])),
                    SummaryRow(
                        'Contribution',
                        data['expected_amount'] == null
                            ? 'Any amount'
                            : money(data['expected_amount'])),
                    const Divider(),
                    const EmptyState(
                        title: 'No contributions yet',
                        message: 'Payment collection is not available yet.',
                        icon: Icons.receipt_long_outlined)
                  ] else ...[
                    SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                            children: ['All', 'Pending', 'Partial', 'Paid']
                                .map((v) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                        label: Text(v,
                                            style:
                                                const TextStyle(fontSize: 12)),
                                        selected: filter == v,
                                        onSelected: (_) =>
                                            setState(() => filter = v))))
                                .toList())),
                    const SizedBox(height: 16),
                    if (people.isEmpty ||
                        filter == 'Paid' ||
                        filter == 'Partial')
                      const EmptyState(
                          title: 'No matching contributions',
                          message:
                              'Participant contributions will appear here.')
                    else
                      ...people.map((raw) {
                        final p = Map<String, dynamic>.from(raw);
                        return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: PersonAvatar(p['name'], radius: 16),
                            title: Text(p['name'],
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w500)),
                            subtitle: Text(
                                p['expected_amount'] == null
                                    ? 'Any amount'
                                    : '0 / ${money(p['expected_amount'])}',
                                style: const TextStyle(fontSize: 12)),
                            trailing:
                                const StatusBadge('Pending', pending: true),
                            onTap: () => participant(p));
                      })
                  ],
                  if (error != null)
                    Text(error!,
                        style: const TextStyle(color: SendohColors.red)),
                ])));
  }

  Widget metric(String label, String value) => Expanded(
      child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 11, color: SendohColors.muted)),
            const SizedBox(height: 7),
            Text(value,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))
          ])));
}
