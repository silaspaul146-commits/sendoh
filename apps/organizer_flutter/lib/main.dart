import 'home.dart';
import 'coordination.dart';
import 'package:flutter/material.dart';
import 'dart:async';
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
import 'invitations.dart';
import 'notifications.dart';
import 'payment_demo.dart';
import 'push_service.dart';
import 'people_flows.dart';
import 'money_requests.dart';

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
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ProviderScope(
              overrides: [apiProvider.overrideWithValue(api)],
              child: Shell(name: profile['display_name'] as String))));
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
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

class _ShellState extends ConsumerState<Shell> with WidgetsBindingObserver {
  int tab = 0;
  int unread = 0;
  bool notificationsOpen = false;
  late Map<String, dynamic> account = {
    'display_name': widget.name,
    ...widget.account
  };
  String get displayName => account['display_name'] as String;
  late Future<List<dynamic>> items;
  late Future<List<dynamic>> joinedItems;
  late Future<List<dynamic>> homeInvitations, homeActivity, homeRequests;
  @override
  void initState() {
    super.initState();
    items = ref.read(apiProvider).collections();
    joinedItems = loadJoined();
    homeInvitations = homeList('/me/invitations');
    homeActivity = homeList('/me/activity');
    homeRequests = requestList();
    WidgetsBinding.instance.addObserver(this);
    PushService.updates.addListener(pushUpdated);
    WidgetsBinding.instance.addPostFrameCallback((_) => connectNotifications());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PushService.updates.removeListener(pushUpdated);
    unawaited(PushService.detach());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      connectNotifications();
      reload();
    }
  }

  Future<void> connectNotifications() async {
    if (!mounted) {
      return;
    }
    final api = ref.read(apiProvider);
    try {
      final id = account['id'] as String? ?? '';
      if (id.isNotEmpty) {
        await PushService.attach(api, id);
      }
    } catch (_) {/* Retry on the next resume; the inbox still works. */}
    if (!mounted) {
      return;
    }
    await refreshUnread();
    if (mounted && PushService.pendingOpen) {
      PushService.pendingOpen = false;
      await openNotifications();
    }
  }

  Future<void> refreshUnread() async {
    try {
      final data = await ref.read(apiProvider).request('/me/notifications');
      if (mounted) {
        setState(() => unread = data['unread_count'] as int);
      }
    } catch (_) {/* Manual inbox refresh displays actionable errors. */}
  }

  void pushUpdated() {
    reload();
    refreshUnread();
    if (PushService.pendingOpen && mounted && !notificationsOpen) {
      PushService.pendingOpen = false;
      openNotifications();
    }
  }

  Future<void> openNotifications() async {
    if (!mounted || notificationsOpen) {
      return;
    }
    notificationsOpen = true;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(
            api: ref.read(apiProvider),
            userId: account['id'] as String? ?? '',
            initialNotificationId: PushService.pendingNotificationId)));
    notificationsOpen = false;
    PushService.pendingNotificationId = null;
    if (mounted) {
      await refreshUnread();
      reload();
    }
  }

  Future<List<dynamic>> requestList() {
    final result = ref
        .read(apiProvider)
        .request('/money-requests')
        .then((value) => List<dynamic>.from(value['items']));
    unawaited(result.then<void>((_) {},
        onError: (Object error, StackTrace stack) {}));
    return result;
  }

  Future<List<dynamic>> loadJoined() async => List<dynamic>.from(
      await ref.read(apiProvider).request('/me/joined-collections'));
  Future<List<dynamic>> homeList(String path) {
    final result = ref
        .read(apiProvider)
        .request(path)
        .then((value) => List<dynamic>.from(value));
    // Home may be off-screen when a refresh completes. Keep the error available
    // for FutureBuilder while preventing an unobserved background error.
    unawaited(result.then<void>((_) {},
        onError: (Object error, StackTrace stack) {}));
    return result;
  }

  void reload() => setState(() {
        items = ref.read(apiProvider).collections();
        joinedItems = loadJoined();
        homeInvitations = homeList('/me/invitations');
        homeActivity = homeList('/me/activity');
        homeRequests = requestList();
      });
  Future<void> create() async {
    final api = ref.read(apiProvider);
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
            builder: (_) => ProviderScope(
                overrides: [apiProvider.overrideWithValue(api)],
                child: const CreateCollection())));
    if (!mounted || result == null) {
      return;
    }
    reload();
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CollectionCreated(data: result, api: api)));
  }

  Future<void> open(Map<String, dynamic> data) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            CollectionDetail(data: data, api: ref.read(apiProvider))));
    if (mounted) {
      reload();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: tab == 0
                ? const SendohBrand()
                : Text(tab == 1 ? 'Activity' : 'Profile'),
            actions: [
              if (tab == 0)
                IconButton(
                    tooltip: 'Near2Pay',
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => PeopleFlow(
                                nearby: true,
                                gateway: ApiPeopleGateway(ref.read(apiProvider),
                                    account['id'] as String))))),
              IconButton(
                  tooltip: 'Notifications ($unread unread)',
                  onPressed: openNotifications,
                  icon: Badge(
                      isLabelVisible: unread > 0,
                      label: Text(unread > 99 ? '99+' : '$unread'),
                      child: const Icon(Icons.notifications_outlined))),
              IconButton(
                  tooltip: 'Invitations and joined collections',
                  onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute<void>(
                              builder: (_) => InvitationsScreen(
                                  api: ref.read(apiProvider))))
                          .then((_) {
                        if (mounted) {
                          reload();
                        }
                      }),
                  icon: const Icon(Icons.mail_outline)),
            ]),
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
                : CoordinationHome(
                    peopleGateway: ApiPeopleGateway(
                        ref.read(apiProvider), account['id'] as String),
                    requests: homeRequests,
                    onReviewRequest: (item) async {
                      await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => MoneyRequestDetail(
                              api: ref.read(apiProvider), id: item['id'])));
                      if (mounted) reload();
                    },
                    onViewRequests: () async {
                      await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => MoneyRequestInbox(
                              api: ref.read(apiProvider),
                              userId: account['id'] as String)));
                      if (mounted) reload();
                    },
                    name: displayName,
                    avatar: accountAvatar(22),
                    owned: items,
                    joined: joinedItems,
                    invitations: homeInvitations,
                    recentActivity: homeActivity,
                    onViewActivity: () => setState(() => tab = 1),
                    onViewInvitations: () async {
                      await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) =>
                              InvitationsScreen(api: ref.read(apiProvider))));
                      if (mounted) {
                        reload();
                      }
                    },
                    onReviewInvitation: (item) async {
                      await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => InvitationDetail(
                              api: ref.read(apiProvider), invitation: item)));
                      if (mounted) {
                        reload();
                      }
                    },
                    onRefresh: () async {
                      reload();
                      await Future.wait([
                        items,
                        joinedItems,
                        homeInvitations,
                        homeActivity,
                        homeRequests,
                        refreshUnread()
                      ]);
                    },
                    onCreate: create,
                    onOpenOwned: open,
                    onOpenJoined: (item) async {
                      await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => InvitationDetail(
                              api: ref.read(apiProvider), invitation: item)));
                      if (mounted) {
                        reload();
                      }
                    },
                    onViewJoined: () async {
                      await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => InvitationsScreen(
                              api: ref.read(apiProvider),
                              initiallyJoined: true)));
                      if (mounted) {
                        reload();
                      }
                    },
                  ),
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
              if (mounted && updated != null) {
                setState(() => account = updated);
              }
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
                if (!ok) {
                  return;
                }
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
              await PushService.detach(deleteToken: true);
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
  Widget build(BuildContext context) => Material(
        color: featured ? SendohColors.teal : SendohColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
                color: featured ? SendohColors.teal : SendohColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(data['name'] as String,
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: featured
                                        ? Colors.white
                                        : SendohColors.ink))),
                        const SizedBox(width: 8),
                        StatusBadge(data['status'] as String)
                      ]),
                      const SizedBox(height: 20),
                      CollectionProgress(data: data, dark: featured),
                      const SizedBox(height: 20),
                      PeoplePreview(
                          people: data['participants'] as List? ?? [],
                          dark: featured),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                            child: Text(displayDate(data['deadline_at']),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: featured
                                        ? Colors.white
                                        : SendohColors.secondary))),
                        Icon(Icons.arrow_forward,
                            size: 18,
                            color: featured
                                ? SendohColors.orange
                                : SendohColors.teal)
                      ]),
                    ]))),
      );
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
    PushService.updates.addListener(onUpdate);
  }

  void onUpdate() {
    if (mounted) {
      setState(() => activity = ref.read(apiProvider).request('/me/activity'));
    }
  }

  Future<void> refresh() async {
    onUpdate();
    await activity;
  }

  @override
  void dispose() {
    PushService.updates.removeListener(onUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
      future: activity,
      builder: (context, snapshot) {
        final entries = snapshot.hasData ? snapshot.data as List : <dynamic>[];
        return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(22),
                children: [
                  const Text('Your group, in the loop.',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: SendohColors.teal)),
                  const SizedBox(height: 8),
                  const Text(
                      'Updates from collections you organize. Invitations and joined-group alerts are in Notifications.',
                      style: TextStyle(
                          height: 1.6, color: SendohColors.secondary)),
                  const SizedBox(height: 24),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const LinearProgressIndicator(),
                  if (snapshot.hasError) ...[
                    const Text(
                        'Couldn’t load activity. Your records are still saved.'),
                    TextButton(
                        onPressed: onUpdate, child: const Text('Try again')),
                  ] else if (snapshot.hasData && entries.isEmpty)
                    const EmptyState(
                        title: 'Your story starts here',
                        message:
                            'Create a collection and invite your group. Updates will appear here as things happen.',
                        icon: Icons.history),
                  if (!snapshot.hasError)
                    ...entries.map((raw) {
                      final e = Map<String, dynamic>.from(raw);
                      final test = (e['message'] as String).startsWith('TEST:');
                      return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SurfaceCard(
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                CircleAvatar(
                                    radius: 19,
                                    backgroundColor: test
                                        ? SendohColors.amberSoft
                                        : SendohColors.tealSoft,
                                    child: Icon(
                                        test
                                            ? Icons.receipt_long_outlined
                                            : Icons.groups_outlined,
                                        size: 20,
                                        color: test
                                            ? SendohColors.amber
                                            : SendohColors.teal)),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(e['message'] as String,
                                          style: const TextStyle(
                                              fontSize: 14,
                                              height: 1.5,
                                              fontWeight: FontWeight.w500)),
                                      const SizedBox(height: 6),
                                      Text(displayDate(e['created_at']),
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: SendohColors.muted))
                                    ])),
                              ])));
                    }),
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
  int tab = 1;
  String filter = 'All';
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    data = widget.data;
    PushService.updates.addListener(paymentUpdate);
  }

  void paymentUpdate() {
    if (mounted && !busy) {
      refresh();
    }
  }

  @override
  void dispose() {
    PushService.updates.removeListener(paymentUpdate);
    super.dispose();
  }

  Future<void> refresh() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.request('/collections/${data['id']}');
      if (mounted) {
        setState(() => data = Map<String, dynamic>.from(result));
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Couldn’t refresh this collection.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> openPayments({bool contribute = false}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => contribute
            ? PaymentDemo(
                api: widget.api,
                collectionId: data['id'],
                collection: data['name'],
                name: 'your verified profile',
                expected: data['expected_amount'] as int?)
            : TestPaymentHistory(
                api: widget.api, collectionId: data['id'], organizer: true)));
    if (mounted) {
      await refresh();
    }
  }

  Future<void> invitePerson([Map<String, dynamic>? person]) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => InvitePerson(
            api: widget.api, collection: data, participant: person)));
    if (!mounted || changed != true) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Invitation saved. They can review it in their Sendoh app.')));
    await refresh();
  }

  Future<void> cancelInvitation(Map<String, dynamic> person) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: const Text('Cancel invitation?'),
                content: Text(
                    '${person['name']} will no longer be able to accept this invitation.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Keep invitation')),
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('Cancel invitation')),
                ]));
    if (!mounted || confirmed != true) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.request(
          '/collections/${data['id']}/invitations/${person['id']}/cancel',
          body: {});
      if (mounted) {
        await refresh();
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> linkManual(Map<String, dynamic> placeholder) async {
    final members = (data['participants'] as List)
        .where((p) => p['invitation_state'] == 'ACCEPTED')
        .toList();
    final chosen = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialog) => SimpleDialog(
                title: Text('Who is ${placeholder['name']}?'),
                children: [
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'Choose the correct joined profile. This replaces the manual name and keeps its expected amount.')),
                  if (members.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                            'Ask them to join using the collection link first.')),
                  ...members.map((p) => SimpleDialogOption(
                      onPressed: () =>
                          Navigator.pop(dialog, Map<String, dynamic>.from(p)),
                      child: Text(
                          '${p['name']} ${p['username'] == null ? '' : '@${p['username']}'}'))),
                ]));
    if (chosen == null || !mounted) {
      return;
    }
    try {
      await widget.api.request(
          '/collections/${data['id']}/participants/${placeholder['id']}/link/${chosen['id']}',
          body: {});
      await refresh();
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    }
  }

  void participant(Map<String, dynamic> p) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: MemberAvatar(p, radius: 28)),
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
                        SummaryRow('Test contributed',
                            money(p['test_paid_amount'] ?? 0)),
                        if (p['expected_amount'] != null)
                          SummaryRow(
                              'Test remaining',
                              money(((p['expected_amount'] as int) -
                                      ((p['test_paid_amount'] ?? 0) as int))
                                  .clamp(0, 1000000000000))),
                        SummaryRow('Membership',
                            invitationLabel(p['invitation_state'])),
                        if (p['invitation_state'] == 'UNVERIFIED') ...[
                          const Text(
                              'Manual name only. This is not a verified account.',
                              textAlign: TextAlign.center),
                          TextButton(
                              onPressed: () {
                                Navigator.pop(sheet);
                                linkManual(p);
                              },
                              child: const Text('Link to a joined member')),
                        ],
                        if (p['username'] != null)
                          SummaryRow('Verified profile', '@${p['username']}'),
                        const Center(
                            child: StatusBadge('Unpaid', pending: true)),
                        const SizedBox(height: 20),
                        const Text('No contributions recorded yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13, color: SendohColors.secondary)),
                        if (data['status'] == 'ACTIVE' &&
                            !['PENDING', 'ACCEPTED', 'DECLINED']
                                .contains(p['invitation_state'])) ...[
                          const SizedBox(height: 20),
                          FilledButton(
                              onPressed: busy
                                  ? null
                                  : () {
                                      Navigator.pop(sheet);
                                      invitePerson(p);
                                    },
                              child: const Text('Invite this person')),
                        ],
                        if (p['invitation_state'] == 'PENDING') ...[
                          TextButton(
                              onPressed: () async {
                                try {
                                  final link = await widget.api.request(
                                      '/collections/${data['id']}/invitations/${p['id']}/link');
                                  await Clipboard.setData(ClipboardData(
                                      text: link['url'] as String));
                                  if (sheet.mounted) {
                                    ScaffoldMessenger.of(sheet).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Personal invitation link copied')));
                                  }
                                } catch (e) {
                                  if (sheet.mounted) {
                                    ScaffoldMessenger.of(sheet).showSnackBar(
                                        SnackBar(content: Text('$e')));
                                  }
                                }
                              },
                              child:
                                  const Text('Copy personal invitation link')),
                          const SizedBox(height: 20),
                          OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () {
                                      Navigator.pop(sheet);
                                      cancelInvitation(p);
                                    },
                              child: const Text('Cancel invitation')),
                        ],
                      ])))));
  @override
  Widget build(BuildContext context) {
    final people = data['participants'] as List;
    final visiblePeople = people
        .where((p) =>
            filter == 'All' || (p['test_payment_status'] ?? 'Unpaid') == filter)
        .toList();
    return Scaffold(
        appBar: AppBar(title: Text(data['name']), actions: [
          if (data['status'] == 'ACTIVE')
            IconButton(
                tooltip: 'Invite someone',
                onPressed: busy ? null : () => invitePerson(),
                icon: const Icon(Icons.person_add_outlined)),
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
                  SurfaceCard(
                      color: SendohColors.teal,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Expanded(
                                  child: Text('Your group’s progress',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600))),
                              StatusBadge(data['status'] as String)
                            ]),
                            const SizedBox(height: 20),
                            CollectionProgress(data: data, dark: true),
                            const SizedBox(height: 20),
                            PeoplePreview(people: people, dark: true),
                          ])),
                  const SizedBox(height: 16),
                  Row(children: [
                    CoordinationAction(
                        icon: Icons.share_outlined,
                        label: 'Copy link',
                        onTap: data['share_url'] == null
                            ? null
                            : () =>
                                copyCollectionLink(context, data['share_url'])),
                    CoordinationAction(
                        icon: Icons.person_add_outlined,
                        label: 'Invite',
                        onTap: busy || data['status'] != 'ACTIVE'
                            ? null
                            : () => invitePerson()),
                    CoordinationAction(
                        icon: Icons.receipt_long_outlined,
                        label: 'Receipts',
                        onTap: busy ? null : () => openPayments()),
                  ]),
                  const SizedBox(height: 16),
                  const Text(
                      'One link for the whole group. Everyone joins as themselves.',
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: SendohColors.secondary)),
                  const SizedBox(height: 16),
                  if (data['status'] == 'ACTIVE')
                    FilledButton.icon(
                        onPressed:
                            busy ? null : () => openPayments(contribute: true),
                        icon: const Icon(Icons.add_card_outlined),
                        label: const Text('Make a test contribution')),
                  const SizedBox(height: 8),
                  const Text('Test mode · No real money moves.',
                      style:
                          TextStyle(fontSize: 12, color: SendohColors.amber)),
                  const SizedBox(height: 20),
                  Row(
                      children: ['About', 'People']
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
                        title: 'A shared view for your group',
                        message:
                            'Use People to see who has joined and Receipts to follow test contributions. No real funds are collected yet.',
                        icon: Icons.receipt_long_outlined)
                  ] else ...[
                    SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                            children: ['All', 'Unpaid', 'Partial', 'Paid']
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
                    if (visiblePeople.isEmpty)
                      const EmptyState(
                          title: 'No matching contributions',
                          message:
                              'Participant contributions will appear here.')
                    else
                      ...visiblePeople.map((raw) {
                        final p = Map<String, dynamic>.from(raw);
                        return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: MemberAvatar(p, radius: 16),
                            title: Text(p['name'],
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w500)),
                            subtitle: Text(
                                '${invitationLabel(p['invitation_state'])}\nTest: ${money(p['test_paid_amount'] ?? 0)} / ${p['expected_amount'] == null ? 'Any amount' : money(p['expected_amount'])}',
                                style: const TextStyle(fontSize: 12)),
                            trailing: StatusBadge(
                                'Test ${p['test_payment_status'] ?? 'Unpaid'}',
                                pending: (p['test_paid_amount'] ?? 0) == 0),
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
