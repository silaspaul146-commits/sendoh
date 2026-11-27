import 'i18n.dart';
import 'person_payments.dart';
import 'home.dart';
import 'coordination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'contribution_checkout.dart';
import 'push_service.dart';
import 'money_requests.dart';
import 'settlement.dart';
import 'near2pay.dart';
import 'account.dart';
import 'settings_ui.dart';
import 'activity_ui.dart';

final apiProvider =
    Provider<SendohApi>((ref) => throw StateError(t('Session required')));
final sendohNavigator = GlobalKey<NavigatorState>();
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadLanguage();
  runApp(const ProviderScope(child: SendohApp()));
}

String money(dynamic n) => n == null ? t('No target') : fcfa(n);

class SendohApp extends StatefulWidget {
  const SendohApp({super.key});
  @override
  State<SendohApp> createState() => _SendohAppState();
}

class _SendohAppState extends State<SendohApp> {
  @override
  void initState() {
    super.initState();
    appLanguage.addListener(_languageChanged);
  }

  @override
  void dispose() {
    appLanguage.removeListener(_languageChanged);
    super.dispose();
  }

  // Every open screen re-reads its words in place: no restart, no lost step.
  void _languageChanged() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) rebuildAll(context);
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'Sendoh',
      navigatorKey: sendohNavigator,
      locale: Locale(appLanguage.value.name),
      supportedLocales: const [Locale('en'), Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
      appBar: AppBar(title: Text(t('Development connection'))),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Text(t('Use your original token to open existing collections.')),
        const SizedBox(height: 24),
        TextField(
            controller: url,
            decoration: const InputDecoration(labelText: 'API URL')),
        const SizedBox(height: 16),
        TextField(
            controller: token,
            obscureText: true,
            decoration: InputDecoration(labelText: t('Development token'))),
        if (error != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(error!,
                  style: const TextStyle(color: SendohColors.red))),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: busy ? null : connect,
            child: Text(busy ? t('Connecting…') : t('Open organizer app')))
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
  late Future<dynamic> homeSummary;
  @override
  void initState() {
    super.initState();
    items = ref.read(apiProvider).collections();
    joinedItems = loadJoined();
    homeInvitations = homeList('/me/invitations');
    homeActivity = homeList('/me/activity');
    homeSummary = ref.read(apiProvider).request('/me/home');
    homeRequests = requestList();
    WidgetsBinding.instance.addObserver(this);
    PushService.updates.addListener(pushUpdated);
    // Push can be off, denied or late. While Home is on screen, check quietly
    // so a confirmed payment still reaches it.
    homeTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => quietRefresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => connectNotifications());
  }

  @override
  void dispose() {
    homeTimer?.cancel();
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

  Timer? homeTimer;
  bool quietRefreshing = false;

  /// Fetch Home in the background and swap it in only when everything arrived:
  /// no spinners, no flashing, and a failed check keeps what is on screen.
  Future<void> quietRefresh() async {
    if (!mounted ||
        quietRefreshing ||
        tab != 0 ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    quietRefreshing = true;
    try {
      final api = ref.read(apiProvider);
      final results = await Future.wait<dynamic>([
        api.collections(),
        loadJoined(),
        api.request('/me/home'),
        requestList(),
      ]);
      if (mounted) {
        setState(() {
          items = Future.value(results[0] as List<dynamic>);
          joinedItems = Future.value(results[1] as List<dynamic>);
          homeSummary = Future.value(results[2]);
          homeRequests = Future.value(results[3] as List<dynamic>);
        });
      }
    } catch (_) {
      // Keep the last known Home; the next check or pull-to-refresh retries.
    } finally {
      quietRefreshing = false;
    }
  }

  void reload() => setState(() {
        items = ref.read(apiProvider).collections();
        joinedItems = loadJoined();
        homeInvitations = homeList('/me/invitations');
        homeActivity = homeList('/me/activity');
        homeSummary = ref.read(apiProvider).request('/me/home');
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
        appBar: tab == 0
            ? null
            : AppBar(
                centerTitle: false,
                toolbarHeight: 76,
                titleSpacing: 20,
                title: Text(
                    tab == 1
                        ? t('Collections')
                        : tab == 2
                            ? t('Activity')
                            : t('Profile'),
                    style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: SendohColors.ink)),
                actions: [
                  IconButton(
                      tooltip: t('Notifications ({unread} unread)',
                          {'unread': unread}),
                      onPressed: openNotifications,
                      icon: Badge(
                          smallSize: 9,
                          isLabelVisible: unread > 0,
                          backgroundColor: SendohColors.teal,
                          child: const Icon(Icons.notifications_outlined,
                              size: 28))),
                  const SizedBox(width: 8),
                ],
              ),
        bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (v) => setState(() => tab = v),
            destinations: [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: t('Home')),
              NavigationDestination(
                  icon: Icon(Icons.groups_outlined), label: t('Collections')),
              NavigationDestination(
                  icon: Icon(Icons.history), label: t('Activity')),
              NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: t('Profile'))
            ]),
        body: tab == 3
            ? profile()
            : tab == 2
                ? const ActivityView()
                : tab == 1
                    ? collectionLibrary()
                    : SafeArea(
                        child: CoordinationHome(
                        onNotifications: openNotifications,
                        unread: unread,
                        peopleGateway: ApiPeopleGateway(
                            ref.read(apiProvider), account['id'] as String),
                        nearby: () =>
                            NearScanScreen(api: ref.read(apiProvider)),
                        requests: homeRequests,
                        onReviewRequest: (item) async {
                          await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => MoneyRequestDetail(
                                      api: ref.read(apiProvider),
                                      id: item['id'])));
                          if (mounted) reload();
                        },
                        onViewRequests: () async {
                          await Navigator.of(context).push(
                              MaterialPageRoute<void>(
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
                        summary: homeSummary,
                        onViewActivity: () => setState(() => tab = 2),
                        onViewInvitations: () async {
                          await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => InvitationsScreen(
                                      api: ref.read(apiProvider))));
                          if (mounted) {
                            reload();
                          }
                        },
                        onReviewInvitation: (item) async {
                          await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => InvitationDetail(
                                      api: ref.read(apiProvider),
                                      invitation: item)));
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
                          await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => InvitationDetail(
                                      api: ref.read(apiProvider),
                                      invitation: item)));
                          if (mounted) {
                            reload();
                          }
                        },
                        onViewJoined: () async {
                          await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => InvitationsScreen(
                                      api: ref.read(apiProvider),
                                      initiallyJoined: true)));
                          if (mounted) {
                            reload();
                          }
                        },
                      )),
      );
  Widget collectionLibrary() => RefreshIndicator(
        onRefresh: () async {
          reload();
          await Future.wait([items, joinedItems]);
        },
        child: ListView(
            padding: const EdgeInsets.all(20),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Text(t('You organise'), style: SendohTextStyles.headingMedium),
              const SizedBox(height: 16),
              FutureBuilder<List<dynamic>>(
                  future: items,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return TextButton(
                          onPressed: reload,
                          child: Text(t('Couldn’t load collections. Retry')));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.data!.isEmpty) {
                      return Text(t('Your collections will appear here.'));
                    }
                    return Column(children: [
                      for (final raw in snapshot.data!)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: HomeCollectionCard(
                                data: Map<String, dynamic>.from(raw),
                                onTap: () =>
                                    open(Map<String, dynamic>.from(raw))))
                    ]);
                  }),
              const SizedBox(height: 12),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('Joined collections and invitations')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) =>
                            InvitationsScreen(api: ref.read(apiProvider))));
                    if (mounted) {
                      reload();
                    }
                  }),
            ]),
      );
  Widget accountAvatar(double radius) => account['avatar'] == null
      ? PersonAvatar(displayName, radius: radius)
      : CircleAvatar(
          radius: radius,
          backgroundImage:
              MemoryImage(base64Decode(account['avatar'] as String)));
  Future<void> signOut() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(apiProvider).request('/auth/logout', body: {});
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
            content: Text(t(
                'Could not reach server. Your session will expire automatically.'))));
      }
    }
    await PushService.detach(deleteToken: true);
    await SessionStore.clear();
    if (mounted) navigator.pop();
  }

  /// Profile, as approved: you on the teal card, then Payments, Account, Help.
  Widget profile() {
    final api = ref.read(apiProvider);
    final navigator = Navigator.of(context);
    return ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          ProfileHeaderCard(
              avatar: accountAvatar(34),
              name: displayName,
              username: account['username'] as String?,
              onEdit: () async {
                final updated =
                    await showEditProfile(context, api: api, account: account);
                if (mounted && updated != null) {
                  setState(() => account = {...account, ...updated});
                }
              }),
          SettingsSection(title: t('Payments'), children: [
            SettingsRow(
                icon: Icons.phone_android,
                title: t('Mobile money numbers'),
                onTap: () => navigator.push(MaterialPageRoute<void>(
                    builder: (_) => MoneyNumbersScreen(api: api)))),
            SettingsRow(
                icon: Icons.request_page_outlined,
                title: t('Money requests'),
                onTap: () => navigator.push(MaterialPageRoute<void>(
                    builder: (_) => MoneyRequestInbox(
                        api: api, userId: account['id'] as String? ?? '')))),
            SettingsRow(
                icon: Icons.swap_horiz,
                title: t('Person payments'),
                onTap: () => navigator.push(MaterialPageRoute<void>(
                    builder: (_) => PersonPaymentHistory(api: api)))),
          ]),
          SettingsSection(title: t('Account'), children: [
            SignInNumberRow(api: api),
            const DeviceUnlockRow(),
            const LanguageRow(),
          ]),
          SettingsSection(children: [
            SettingsRow(
                icon: Icons.help_outline,
                title: t('Help & legal'),
                onTap: () => navigator.push(MaterialPageRoute<void>(
                    builder: (_) => HelpLegalScreen(
                        api: api,
                        onDeleted: () async {
                          await PushService.detach(deleteToken: true);
                          await SessionStore.clear();
                          navigator.popUntil((route) => route.isFirst);
                        })))),
          ]),
          const SizedBox(height: 20),
          TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: SendohColors.secondary),
              onPressed: signOut,
              child: Text(t('Sign out'))),
        ]);
  }
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

Future<void> copyCollectionLink(BuildContext context, String link) async {
  await Clipboard.setData(ClipboardData(text: link));
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t('Collection link copied'))));
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
            Text(t('Collection created!'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text(t('Now invite people to contribute.'),
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
              SummaryRow(t('Target'), money(data['target_amount'])),
              SummaryRow(t('Deadline'), displayDate(data['deadline_at'])),
              SummaryRow(
                  t('Participants'), '${(data['participants'] as List).length}')
            ])),
            const SizedBox(height: 24),
            Text(t('One link for everyone'),
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
                      tooltip: t('Copy collection link'),
                      onPressed: () =>
                          copyCollectionLink(context, data['share_url']),
                      icon: const Icon(Icons.copy_outlined, size: 19))
                ])),
            const SizedBox(height: 22),
            FilledButton.icon(
                onPressed: () => copyCollectionLink(context, data['share_url']),
                icon: const Icon(Icons.link, size: 18),
                label: Text(t('Copy collection link'))),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            CollectionDetail(data: data, api: api))),
                child: Text(t('View collection'))),
            const SizedBox(height: 18),
            Text(t('Share the copied link in WhatsApp or any messaging app.'),
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
  String filter = 'All'; // English key; chips show t(filter)
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    data = widget.data;
    PushService.updates.addListener(paymentUpdate);
    // Without push, a member's confirmed payment still appears within 30 s.
    detailTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => quietCheck());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        refresh();
      }
    });
  }

  void paymentUpdate() {
    if (mounted && !busy) {
      refresh();
    }
  }

  Timer? detailTimer;

  /// Background check: no busy state; a failure keeps what is on screen.
  Future<void> quietCheck() async {
    if (!mounted ||
        busy ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    try {
      final fresh = await widget.api.request('/collections/${data['id']}');
      if (mounted && !busy) {
        setState(() => data = Map<String, dynamic>.from(fresh));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    detailTimer?.cancel();
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
        setState(() => error = t('Couldn’t refresh this collection.'));
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
            ? ContributionCheckout(
                api: widget.api,
                collectionId: data['id'],
                collection: data['name'],
                name: t('your verified profile'),
                expected: data['expected_amount'] as int?)
            : ContributionHistory(
                api: widget.api, collectionId: data['id'], organizer: true)));
    if (mounted) {
      await refresh();
    }
  }

  Future<void> openSettlement() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SettlementScreen(
            api: widget.api,
            collectionId: data['id'],
            collectionName: data['name'])));
    if (mounted) {
      await refresh();
    }
  }

  Future<void> startNextRound() async {
    final opened = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => NextRoundScreen(api: widget.api, data: data)));
    if (mounted && opened == true) {
      await refresh();
      // Guests on the web get no notification: the organizer's message is how they hear.
      if (mounted) await shareNewRound(context, data);
    }
  }

  Future<void> editCash() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => CashRecordsScreen(api: widget.api, data: data)));
    if (mounted && saved == true) {
      await refresh();
    }
  }

  Future<void> remindMembers() async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final preview =
          await widget.api.request('/collections/${data['id']}/reminders');
      if (!mounted) {
        return;
      }
      final count = (preview['eligible_count'] as num).toInt();
      if (count == 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t(
                'No reminders needed. Members already reminded can be reminded again after 24 hours.'))));
        return;
      }
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
                title: Text(count == 1
                    ? t('Remind 1 person?')
                    : t('Remind {count} people?', {'count': count})),
                content: Text(t(
                    'Adds a Sendoh update for joined members with an outstanding contribution.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: Text(t('Cancel'))),
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: Text(t('Send reminders'))),
                ],
              ));
      if (!mounted || confirmed != true) {
        return;
      }
      final result = await widget.api
          .request('/collections/${data['id']}/reminders', body: {});
      if (!mounted) {
        return;
      }
      final sent = (result['reminded_count'] as num).toInt();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sent == 0
              ? t('Everyone is up to date.')
              : (sent == 1
                  ? t('Reminder added to 1 inbox.')
                  : t('Reminder added to {sent} inboxes.', {'sent': sent})))));
    } catch (_) {
      if (mounted) {
        setState(() => error = t(
            'Couldn’t confirm reminders. Try again; recent reminders won’t be repeated.'));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> invitePerson([Map<String, dynamic>? person]) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => InvitePerson(
            api: widget.api, collection: data, participant: person)));
    if (!mounted || changed != true) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            t('Invitation saved. They can review it in their Sendoh app.'))));
    await refresh();
  }

  Future<void> cancelInvitation(Map<String, dynamic> person) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: Text(t('Cancel invitation?')),
                content: Text(t(
                    '{name} will no longer be able to accept this invitation.',
                    {'name': person['name']})),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: Text(t('Keep invitation'))),
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: Text(t('Cancel invitation'))),
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
                title: Text(t('Who is {name}?', {'name': placeholder['name']})),
                children: [
                  Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(t(
                          'Choose the correct joined profile. This replaces the manual name and keeps its expected amount.'))),
                  if (members.isEmpty)
                    Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(t(
                            'Ask them to join using the collection link first.'))),
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
                            t('Expected'),
                            p['expected_amount'] == null
                                ? t('Any amount')
                                : money(p['expected_amount'])),
                        SummaryRow(t('Contributed'),
                            money(p['sandbox_paid_amount'] ?? 0)),
                        if (memberPendingAmount(p) > 0)
                          SummaryRow(t('Awaiting confirmation'),
                              money(memberPendingAmount(p))),
                        if (p['expected_amount'] != null)
                          SummaryRow(
                              t('Remaining'),
                              money(((p['expected_amount'] as int) -
                                      ((p['sandbox_paid_amount'] ?? 0) as int))
                                  .clamp(0, 1000000000000))),
                        SummaryRow(t('Membership'),
                            invitationLabel(p['invitation_state'])),
                        if (p['invitation_state'] == 'UNVERIFIED') ...[
                          Text(
                              t('Manual name only. This is not a verified account.'),
                              textAlign: TextAlign.center),
                          TextButton(
                              onPressed: () {
                                Navigator.pop(sheet);
                                linkManual(p);
                              },
                              child: Text(t('Link to a joined member'))),
                        ],
                        if (p['username'] != null)
                          SummaryRow(
                              t('Verified profile'), '@${p['username']}'),
                        Center(
                            child: StatusBadge(collectionMemberPaymentStatus(p),
                                pending: collectionMemberPaymentStatus(p) !=
                                    'Paid')),
                        const SizedBox(height: 20),
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
                              child: Text(t('Invite this person'))),
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
                                        SnackBar(
                                            content: Text(t(
                                                'Personal invitation link copied'))));
                                  }
                                } catch (e) {
                                  if (sheet.mounted) {
                                    ScaffoldMessenger.of(sheet).showSnackBar(
                                        SnackBar(content: Text('$e')));
                                  }
                                }
                              },
                              child: Text(t('Copy personal invitation link'))),
                          const SizedBox(height: 20),
                          OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () {
                                      Navigator.pop(sheet);
                                      cancelInvitation(p);
                                    },
                              child: Text(t('Cancel invitation'))),
                        ],
                      ])))));
  @override
  Widget build(BuildContext context) {
    final people = data['participants'] as List;
    final visiblePeople = people
        .where((p) =>
            filter == 'All' ||
            collectionMemberPaymentStatus(Map<String, dynamic>.from(p)) ==
                filter)
        .toList();
    final paidCount = people
        .where((p) =>
            collectionMemberPaymentStatus(Map<String, dynamic>.from(p)) ==
            'Paid')
        .length;
    final outstandingCount = people
        .where((p) => ['Unpaid', 'Partial'].contains(
            collectionMemberPaymentStatus(Map<String, dynamic>.from(p))))
        .length;
    return Scaffold(
        appBar: AppBar(title: Text(data['name']), actions: [
          if (data['status'] == 'ACTIVE')
            IconButton(
                tooltip: t('Invite someone'),
                onPressed: busy ? null : () => invitePerson(),
                icon: const Icon(Icons.person_add_outlined)),
          IconButton(
              tooltip: t('Refresh'),
              onPressed: busy ? null : refresh,
              icon: const Icon(Icons.refresh, size: 21))
        ]),
        body: RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
                children: [
                  SettlementSummary(
                      data: data,
                      onReview: busy ? null : openSettlement,
                      onEditCash: busy ? null : editCash,
                      onNextRound: busy ? null : startNextRound),
                  const SizedBox(height: 16),
                  Text(
                      t('{paidCount} paid · {outstandingCount} outstanding', {
                        'paidCount': paidCount,
                        'outstandingCount': outstandingCount
                      }),
                      style: SendohTextStyles.bodyMedium),
                  const SizedBox(height: 12),
                  Row(children: [
                    CoordinationAction(
                        icon: Icons.share_outlined,
                        label: t('Copy link'),
                        onTap: data['share_url'] == null
                            ? null
                            : () =>
                                copyCollectionLink(context, data['share_url'])),
                    CoordinationAction(
                        icon: Icons.person_add_outlined,
                        label: t('Invite'),
                        onTap: busy || data['status'] != 'ACTIVE'
                            ? null
                            : () => invitePerson()),
                    CoordinationAction(
                        icon: Icons.qr_code_2,
                        label: t('Nearby'),
                        onTap: busy || data['status'] != 'ACTIVE'
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) => NearReceiveScreen(
                                        api: widget.api,
                                        collectionId: data['id'],
                                        collectionName: data['name'])))),
                    CoordinationAction(
                        icon: Icons.receipt_long_outlined,
                        label: t('Receipts'),
                        onTap: busy ? null : () => openPayments()),
                  ]),
                  const SizedBox(height: 16),
                  Row(
                      children: [t('Overview'), t('People')]
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
                    SummaryRow(t('Deadline'), displayDate(data['deadline_at'])),
                    SummaryRow(
                        t('Contribution'),
                        data['expected_amount'] == null
                            ? t('Any amount')
                            : money(data['expected_amount'])),
                    SummaryRow(t('Payment environment'), t('Sandbox')),
                    const SizedBox(height: 20),
                    if (data['status'] == 'ACTIVE')
                      FilledButton(
                          onPressed: busy
                              ? null
                              : () => openPayments(contribute: true),
                          child: Text(t('Contribute'))),
                  ] else ...[
                    SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                            children: [
                          'All',
                          'Unpaid',
                          'Partial',
                          'Pending',
                          'Paid'
                        ]
                                .map((v) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                        label: Text(t(v),
                                            style:
                                                const TextStyle(fontSize: 12)),
                                        selected: filter == v,
                                        onSelected: (_) =>
                                            setState(() => filter = v))))
                                .toList())),
                    const SizedBox(height: 16),
                    if (visiblePeople.isEmpty)
                      EmptyState(
                          title: t('No matching contributions'),
                          message:
                              t('Participant contributions will appear here.'))
                    else
                      ...visiblePeople.map((raw) {
                        final p = Map<String, dynamic>.from(raw);
                        return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: MemberAvatar(p, radius: 16),
                            title: Text(p['name'],
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w500)),
                            subtitle: Text(memberContributionLine(p, money),
                                style: const TextStyle(fontSize: 12)),
                            trailing: StatusBadge(
                                collectionMemberPaymentStatus(p),
                                pending:
                                    collectionMemberPaymentStatus(p) != 'Paid'),
                            onTap: () => participant(p));
                      })
                  ],
                  if (tab == 1 && data['status'] == 'ACTIVE') ...[
                    const SizedBox(height: 20),
                    if (outstandingCount > 0)
                      FilledButton(
                          onPressed: busy ? null : remindMembers,
                          child: Text(t('Remind outstanding members'))),
                    const SizedBox(height: 8),
                    OutlinedButton(
                        onPressed: data['share_url'] == null
                            ? null
                            : () =>
                                copyCollectionLink(context, data['share_url']),
                        child: Text(t('Copy collection link'))),
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
