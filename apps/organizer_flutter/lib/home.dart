import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'coordination.dart';
import 'design.dart';
import 'people_flows.dart';
import 'settlement.dart' show previousRoundLine;

/// Presentation only. Shell retains fetching, identity and navigation ownership.
class CoordinationHome extends StatefulWidget {
  const CoordinationHome({
    super.key,
    required this.name,
    required this.avatar,
    required this.owned,
    required this.joined,
    required this.onRefresh,
    required this.onCreate,
    required this.onOpenOwned,
    required this.onOpenJoined,
    required this.onViewJoined,
    this.invitations,
    this.recentActivity,
    this.onReviewInvitation,
    this.onViewInvitations,
    this.onViewActivity,
    this.peopleGateway,
    this.nearby,
    this.summary,
    this.onViewRequests,
    this.requests,
    this.onReviewRequest,
    this.onNotifications,
    this.unread = 0,
  });
  final VoidCallback? onNotifications;
  final int unread;
  final Future<List<dynamic>>? requests;
  final ValueChanged<Map<String, dynamic>>? onReviewRequest;
  final PeopleFlowGateway? peopleGateway;

  /// Builds the Near2Pay scanner; null keeps Near2Pay as a planned action.
  final Widget Function()? nearby;

  /// GET /me/home: collected this month (not a wallet) and confirmed contributions.
  final Future<dynamic>? summary;
  final VoidCallback? onViewRequests;
  final Future<List<dynamic>>? invitations, recentActivity;
  final ValueChanged<Map<String, dynamic>>? onReviewInvitation;
  final VoidCallback? onViewInvitations, onViewActivity;
  final String name;
  final Widget avatar;
  final Future<List<dynamic>> owned, joined;
  final Future<void> Function() onRefresh;
  final VoidCallback onCreate, onViewJoined;
  final ValueChanged<Map<String, dynamic>> onOpenOwned, onOpenJoined;

  @override
  State<CoordinationHome> createState() => _CoordinationHomeState();
}

class _CoordinationHomeState extends State<CoordinationHome> {
  Future<void> refresh() async {
    try {
      await widget.onRefresh();
    } catch (_) {
      /* Section retry remains available. */
    }
  }

  void viewOwned(List<dynamic> entries) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Your collections')),
          body: ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: entries.length,
            separatorBuilder: (_, index) => const SizedBox(height: 12),
            itemBuilder: (_, index) {
              final data = Map<String, dynamic>.from(entries[index]);
              return HomeCollectionCard(
                data: data,
                onTap: () => widget.onOpenOwned(data),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget attention() => FutureBuilder<List<dynamic>>(
        future: widget.requests,
        builder: (context, requests) => FutureBuilder<List<dynamic>>(
          future: widget.invitations,
          builder: (context, invites) {
            final pending = (requests.data ?? [])
                .where(
                  (r) =>
                      r['direction'] == 'RECEIVED' && r['status'] == 'PENDING',
                )
                .toList();
            final invitations = invites.data ?? [];
            if (requests.hasError || invites.hasError) {
              return _SectionMessage(
                text: 'Some updates couldn’t load.',
                onRetry: refresh,
              );
            }
            if (pending.isEmpty && invitations.isEmpty) {
              return const SizedBox.shrink();
            }
            final isRequest = pending.isNotEmpty;
            final item = Map<String, dynamic>.from(
              isRequest ? pending.first : invitations.first,
            );
            final total = pending.length + invitations.length;
            return Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle(title: 'Needs your attention', count: total),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: SendohColors.tealSoft,
                      child: Icon(
                        Icons.notifications_outlined,
                        color: SendohColors.teal,
                      ),
                    ),
                    title: Text(
                      isRequest
                          ? '${item['requester']['name']} requested ${coordinationMoney(item['amount'])}'
                          : item['collection']['name'] as String,
                      style: SendohTextStyles.bodyMedium,
                    ),
                    subtitle: Text(
                      isRequest
                          ? item['reason'] as String
                          : '${item['collection']['organizer_name'] ?? 'Organizer'} invited you',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      if (isRequest) {
                        widget.onReviewRequest?.call(item);
                      } else {
                        widget.onReviewInvitation?.call(item);
                      }
                    },
                  ),
                  if (total > 1)
                    Wrap(
                      spacing: 8,
                      children: [
                        if (pending.isNotEmpty)
                          TextButton(
                            onPressed: widget.onViewRequests,
                            child: Text('Requests (${pending.length})'),
                          ),
                        if (invitations.isNotEmpty)
                          TextButton(
                            onPressed: widget.onViewInvitations,
                            child: Text('Invitations (${invitations.length})'),
                          ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      );

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          key: const PageStorageKey('coordination-home'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sendoh',
                    style: TextStyle(
                      color: SendohColors.teal,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                if (widget.onNotifications != null)
                  IconButton(
                    tooltip: 'Notifications (${widget.unread} unread)',
                    onPressed: widget.onNotifications,
                    icon: Badge(
                      isLabelVisible: widget.unread > 0,
                      backgroundColor: SendohColors.orange,
                      child: const Icon(Icons.notifications_outlined),
                    ),
                  ),
                widget.avatar,
              ],
            ),
            const SizedBox(height: 16),
            Text(
              homeGreeting(widget.name, DateTime.now()),
              style: SendohTextStyles.displayLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'Bring your people together.',
              style: TextStyle(fontSize: 16, color: SendohColors.secondary),
            ),
            const SizedBox(height: 18),
            MonthSummaryCard(summary: widget.summary),
            const SizedBox(height: 14),
            HomeActionBar(
              onCollect: widget.onCreate,
              gateway: widget.peopleGateway,
              nearby: widget.nearby,
            ),
            attention(),
            const SizedBox(height: 24),
            FutureBuilder<List<dynamic>>(
              future: widget.owned,
              builder: (context, snapshot) {
                final entries = snapshot.data ?? [];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionTitle(
                      title: 'Your collections',
                      action: entries.length > 1
                          ? TextButton(
                              onPressed: () => viewOwned(entries),
                              child: Text('See all ${entries.length}'),
                            )
                          : null,
                    ),
                    const SizedBox(height: 8),
                    if (snapshot.hasError)
                      _SectionMessage(
                        text: 'Your collections couldn’t load.',
                        onRetry: refresh,
                      )
                    else if (!snapshot.hasData)
                      const _LoadingSection()
                    else if (entries.isEmpty)
                      const _SectionMessage(
                        text: 'Create a collection and invite your people.',
                      )
                    else
                      CollectionDeck(
                          entries: entries, onOpen: widget.onOpenOwned),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _SectionTitle(
              title: 'You joined',
              action: TextButton(
                onPressed: widget.onViewJoined,
                child: const Text('View all'),
              ),
            ),
            FutureBuilder<List<dynamic>>(
              future: widget.joined,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _SectionMessage(
                    text: 'Joined collections couldn’t load.',
                    onRetry: refresh,
                  );
                }
                if (!snapshot.hasData) {
                  return const _LoadingSection();
                }
                if (snapshot.data!.isEmpty) {
                  return const Text(
                    'Collections you join will appear here.',
                    style: SendohTextStyles.caption,
                  );
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final raw in snapshot.data!)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: HomeJoinedCircle(
                            item: Map<String, dynamic>.from(raw),
                            onTap: () => widget
                                .onOpenJoined(Map<String, dynamic>.from(raw)),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            if (widget.onViewRequests != null)
              RequestSummary(
                requests: widget.requests,
                onOpen: widget.onViewRequests!,
              ),
            if (widget.summary != null)
              RecentContributions(
                summary: widget.summary!,
                onViewAll: widget.onViewActivity,
              ),
          ],
        ),
      );
}

/// "Good morning, Alain": warm, with the first name only.
String homeGreeting(String name, DateTime now) {
  final first = name.trim().split(RegExp(r'\s+')).first;
  final part = now.hour < 12
      ? 'Good morning'
      : now.hour < 18
          ? 'Good afternoon'
          : 'Good evening';
  return first.isEmpty ? part : '$part, $first';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String shortDate(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  return d == null ? '' : '${d.day} ${_months[d.month - 1]} ${d.year}';
}

String timeAgo(int seconds, DateTime now) {
  final diff = now.millisecondsSinceEpoch ~/ 1000 - seconds;
  if (diff < 60) return 'just now';
  if (diff < 3600) return '${diff ~/ 60} min ago';
  if (diff < 86400) return '${diff ~/ 3600} h ago';
  return '${diff ~/ 86400} d ago';
}

/// Money collected for my groups this month. Not a balance Sendoh holds.
class MonthSummaryCard extends StatelessWidget {
  const MonthSummaryCard({super.key, required this.summary});
  final Future<dynamic>? summary;
  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
        future: summary,
        builder: (context, snapshot) {
          final data = snapshot.data is Map
              ? Map<String, dynamic>.from(
                  (snapshot.data as Map)['collected_this_month'] as Map)
              : null;
          final amount = (data?['amount'] as num?)?.toInt();
          final groups = (data?['collections'] as num?)?.toInt() ?? 0;
          return Semantics(
            container: true,
            label: amount == null
                ? 'Collected this month, loading'
                : 'Collected this month, ${coordinationMoney(amount)}',
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0B5D4F),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Collected this month',
                          style:
                              TextStyle(color: Color(0xFFE6F2EF), fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            amount == null ? '—' : coordinationMoney(amount),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          snapshot.hasError
                              ? 'Couldn’t load this month'
                              : amount == null
                                  ? ' '
                                  : groups == 0
                                      ? 'Nothing confirmed yet this month'
                                      : 'Across $groups collection${groups == 1 ? '' : 's'}',
                          style: const TextStyle(
                              color: Color(0xFFCFE3DE), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const CircleAvatar(
                    radius: 24,
                    backgroundColor: Color(0x22FFFFFF),
                    child: Icon(Icons.groups_outlined, color: Colors.white),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

/// "Marie contributed": only payments the provider confirmed.
class RecentContributions extends StatelessWidget {
  const RecentContributions({super.key, required this.summary, this.onViewAll});
  final Future<dynamic> summary;
  final VoidCallback? onViewAll;
  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
        future: summary,
        builder: (context, snapshot) {
          final recent = snapshot.data is Map
              ? ((snapshot.data as Map)['recent'] as List? ?? const [])
              : const [];
          if (recent.isEmpty) {
            return const SizedBox.shrink();
          }
          final now = DateTime.now();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              _SectionTitle(
                title: 'Recent activity',
                action: onViewAll == null
                    ? null
                    : TextButton(
                        onPressed: onViewAll, child: const Text('See all')),
              ),
              for (final raw in recent.take(3))
                Builder(builder: (context) {
                  final r = Map<String, dynamic>.from(raw as Map);
                  final name = '${r['name']}';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: PersonAvatar(name, radius: 20),
                    title: Text('$name contributed',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${r['collection_name']}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('+${coordinationMoney(r['amount'])}',
                            style: const TextStyle(
                                color: SendohColors.teal,
                                fontWeight: FontWeight.w700)),
                        Text(timeAgo((r['at'] as num).toInt(), now),
                            style: SendohTextStyles.caption),
                      ],
                    ),
                  );
                }),
            ],
          );
        },
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.count, this.action});
  final String title;
  final int? count;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              count == null ? title : '$title · $count',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          if (action != null) action!,
        ],
      );
}

class _SectionMessage extends StatelessWidget {
  const _SectionMessage({required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SendohColors.surface,
          border: Border.all(color: SendohColors.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style:
                  const TextStyle(height: 1.5, color: SendohColors.secondary),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      );
}

class _LoadingSection extends StatelessWidget {
  const _LoadingSection();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child:
              CircularProgressIndicator(semanticsLabel: 'Loading collections'),
        ),
      );
}

class HomeCollectionCard extends StatelessWidget {
  const HomeCollectionCard({
    super.key,
    required this.data,
    required this.onTap,
    this.featured = false,
  });
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  /// Kept for the deck API; every card now uses the approved white surface.
  final bool featured;

  Future<void> copyLink(BuildContext context, String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Collection link copied')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = CollectionTotals.fromCollection(data);
    final actual = totals.raised;
    final target = totals.target;
    final hasTarget = target != null && target > 0;
    final percent = hasTarget ? (actual * 100 ~/ target).clamp(0, 100) : null;
    final rawTotals = data['totals'];
    final people = (data['participants'] as List? ?? [])
        .map((p) => Map<String, dynamic>.from(p as Map))
        .where((p) => MemberPosition.fromMember(p).paid > 0)
        .toList();
    final contributors = rawTotals is Map
        ? (rawTotals['contributors'] as num?)?.toInt() ?? people.length
        : people.length;
    final share = data['share_url'] as String?;
    final deadline = shortDate(data['deadline_at'] as String?);
    final (String label, Color dot) = switch (data['status']) {
      'CLOSED' => ('Closed', SendohColors.secondary),
      'SETTLED' => ('Settled', SendohColors.teal),
      'DRAFT' => ('Draft', SendohColors.secondary),
      _ => ('Active', SendohColors.green),
    };
    return Semantics(
      button: true,
      label: 'Open ${data['name']}',
      child: Material(
        color: SendohColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: SendohColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F0EC),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.groups_outlined,
                          color: SendohColors.teal),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['name'] as String,
                              style: SendohTextStyles.titleSmall),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F0EC),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              CircleAvatar(radius: 3.5, backgroundColor: dot),
                              const SizedBox(width: 6),
                              // Shrinks instead of overflowing on narrow phones with large text.
                              Flexible(
                                child: Text(label,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ]),
                          ),
                        ],
                      ),
                    ),
                    if (share != null)
                      IconButton(
                        tooltip: 'Copy collection link',
                        onPressed: () => copyLink(context, share),
                        icon: const Icon(Icons.link, color: SendohColors.ink),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(coordinationMoney(actual),
                    style:
                        SendohTextStyles.displayLarge.copyWith(fontSize: 26)),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        hasTarget
                            ? 'of ${coordinationMoney(target)}${showingProviderTest(data) ? ' · Sandbox' : ''}'
                            : showingProviderTest(data)
                                ? 'collected · Sandbox'
                                : 'collected · No target',
                        style: SendohTextStyles.bodyMedium
                            .copyWith(color: SendohColors.secondary),
                      ),
                    ),
                    if (percent != null)
                      Text('$percent%',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                if (hasTarget) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: totals.progress),
                      duration: Duration(
                        milliseconds:
                            MediaQuery.disableAnimationsOf(context) ? 0 : 280,
                      ),
                      builder: (context, progress, child) =>
                          LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        color: SendohColors.orange,
                        backgroundColor: const Color(0xFFE8E6E1),
                        semanticsLabel: 'Collection progress',
                        semanticsValue: '$percent percent',
                      ),
                    ),
                  ),
                ],
                if (totals.pending > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                      '${coordinationMoney(totals.pending)} awaiting confirmation',
                      style: SendohTextStyles.caption),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (people.isNotEmpty)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        for (final person in people.take(4))
                          Padding(
                            padding: const EdgeInsets.only(right: 2),
                            child: MemberAvatar(person, radius: 13),
                          ),
                        if (contributors > 4)
                          Text('+${contributors - 4}',
                              style: SendohTextStyles.caption),
                      ]),
                    Text(
                      contributors == 1
                          ? '1 contributor'
                          : '$contributors contributors',
                      style: SendohTextStyles.caption,
                    ),
                    if (deadline.isNotEmpty)
                      Text('Ends $deadline', style: SendohTextStyles.caption),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeJoinedCircle extends StatelessWidget {
  const HomeJoinedCircle({super.key, required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final collection = Map<String, dynamic>.from(item['collection']);
    final name = collection['name'] as String;
    final joinedCollection = Map<String, dynamic>.from(item['collection']);
    final round = (joinedCollection['round'] as num?)?.toInt() ?? 1;
    // "Round 2 · 5,000 FCFA expected" never hides "Round 1 · Paid".
    final status = joinedCollection['recurring'] == true && round > 1
        ? 'Round $round · ${joinedPersonalStatus(item)}'
        : joinedPersonalStatus(item);
    final previous = item['previous_round'] as Map?;
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final initials =
        words.take(2).map((w) => w.characters.first).join().toUpperCase();
    final width =
        (MediaQuery.sizeOf(context).width - 40).clamp(200.0, 320.0).toDouble();
    final target = (collection['target_amount'] as num?)?.toInt();
    final hasTotal = CollectionTotals.fromCollection(collection).known;
    final total = displayedCollectionAmount(collection);
    final groupStatus = collection['status'] == 'CLOSED'
        ? 'Collection closed'
        : collection['status'] == 'SETTLED'
            ? 'Collection settled'
            : collection['status'] == 'CANCELLED'
                ? 'Collection cancelled'
                : target != null && target > 0 && hasTotal
                    ? 'Group: ${(total * 100 / target).clamp(0, 100).floor()}% collected'
                    : 'Collection open';
    return SizedBox(
        width: width,
        child: Material(
          color: SendohColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: SendohColors.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                          backgroundColor: SendohColors.tealSoft,
                          child: Text(initials.isEmpty ? 'G' : initials,
                              style: const TextStyle(
                                  color: SendohColors.teal,
                                  fontWeight: FontWeight.w600))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(name, style: SendohTextStyles.titleSmall),
                            const SizedBox(height: 4),
                            Text(status, style: SendohTextStyles.bodyMedium),
                            const SizedBox(height: 4),
                            Text(groupStatus, style: SendohTextStyles.caption),
                            if (previous != null)
                              Text(previousRoundLine(previous),
                                  style: SendohTextStyles.caption),
                          ])),
                    ]),
              )),
        ));
  }
}

class HomeActionBar extends StatelessWidget {
  const HomeActionBar(
      {super.key, required this.onCollect, this.gateway, this.nearby});
  final PeopleFlowGateway? gateway;
  final Widget Function()? nearby;
  final VoidCallback onCollect;

  void openPeople(BuildContext context, PeopleIntent intent,
      {bool near = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => near
            ? nearby?.call() ?? PeopleFlow(nearby: true, gateway: gateway)
            : PeopleFlow(
                intent: intent, gateway: gateway, nearbyBuilder: nearby),
      ),
    );
  }

  /// Send: to someone by their Sendoh username, or to someone standing nearby.
  Future<void> send(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        builder: (sheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading:
                  const Icon(Icons.alternate_email, color: SendohColors.teal),
              title: const Text('Send to a Sendoh user'),
              subtitle: const Text('Find them by their username'),
              onTap: () {
                Navigator.pop(sheet);
                openPeople(context, PeopleIntent.pay);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.qr_code_scanner, color: SendohColors.teal),
              title: const Text('Pay someone nearby'),
              subtitle: const Text('Scan their Near2Pay code'),
              onTap: () {
                Navigator.pop(sheet);
                openPeople(context, PeopleIntent.pay, near: true);
              },
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Action(
            icon: Icons.add,
            label: 'New collection',
            onTap: onCollect,
          ),
          const SizedBox(width: 10),
          _Action(
            icon: Icons.description_outlined,
            label: 'Request',
            onTap: () => openPeople(context, PeopleIntent.request),
            planned: gateway == null,
          ),
          const SizedBox(width: 10),
          _Action(
            icon: Icons.send_outlined,
            label: 'Send',
            onTap: () => send(context),
            planned: gateway == null,
          ),
        ],
      );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.planned = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool planned;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Semantics(
          button: true,
          label: planned ? '$label, view availability details' : label,
          child: Material(
            color: const Color(0xFFE8F0EC),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(0xFF0B5D4F),
                      child: Icon(icon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF0B3B33),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// A deck sizes to its active card, including large text. No fixed card height.
class CollectionDeck extends StatefulWidget {
  const CollectionDeck({
    super.key,
    required this.entries,
    required this.onOpen,
  });
  final List<dynamic> entries;
  final ValueChanged<Map<String, dynamic>> onOpen;
  @override
  State<CollectionDeck> createState() => _CollectionDeckState();
}

class _CollectionDeckState extends State<CollectionDeck>
    with SingleTickerProviderStateMixin {
  int index = 0;
  double offset = 0;
  bool settling = false;
  late final AnimationController motion;
  String identity(dynamic row) => '${row['id'] ?? row['name']}';

  @override
  void initState() {
    super.initState();
    motion = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CollectionDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    motion.stop();
    settling = false;
    offset = 0;
    if (oldWidget.entries.isNotEmpty && index < oldWidget.entries.length) {
      final id = identity(oldWidget.entries[index]);
      final found = widget.entries.indexWhere((row) => identity(row) == id);
      index = found < 0 ? 0 : found;
    } else {
      index = 0;
    }
  }

  Future<void> settle(double destination, {int delta = 0}) async {
    if (settling || (offset == destination && delta == 0)) {
      return;
    }
    final start = offset;
    final reduced = MediaQuery.disableAnimationsOf(context);
    settling = true;
    void tick() {
      if (mounted) {
        setState(
          () => offset = start +
              (destination - start) *
                  Curves.easeOutCubic.transform(motion.value),
        );
      }
    }

    motion.duration = Duration(milliseconds: reduced ? 0 : 180);
    motion.addListener(tick);
    try {
      await motion.forward(from: 0).orCancel;
      if (!mounted) {
        return;
      }
      setState(() {
        index = (index + delta).clamp(0, widget.entries.length - 1).toInt();
        offset = 0;
        settling = false;
      });
    } on TickerCanceled {
      // Refresh and disposal cancel a transition without changing selection.
    } finally {
      motion.removeListener(tick);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final data = Map<String, dynamic>.from(widget.entries[index]);
    final layers = (widget.entries.length - 1).clamp(0, 2).toInt();
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final direction = offset == 0 ? 1 : ((offset < 0) != rtl ? 1 : -1);
    final neighbour = index + direction;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fraction = (offset.abs() / width).clamp(0.0, 1.0);
        void move(int delta) =>
            settle((delta == 1) != rtl ? -width : width, delta: delta);
        return Semantics(
          label: 'Collection ${index + 1} of ${widget.entries.length}',
          container: true,
          explicitChildNodes: true,
          value: '${index + 1} of ${widget.entries.length}',
          increasedValue: index < widget.entries.length - 1
              ? '${index + 2} of ${widget.entries.length}'
              : null,
          decreasedValue:
              index > 0 ? '$index of ${widget.entries.length}' : null,
          onIncrease: index < widget.entries.length - 1 ? () => move(1) : null,
          onDecrease: index > 0 ? () => move(-1) : null,
          child: GestureDetector(
            onHorizontalDragStart: settling ? null : (_) {},
            onHorizontalDragUpdate: (details) {
              if (settling) {
                return;
              }
              final next = offset + details.delta.dx;
              final delta = (next < 0) != rtl ? 1 : -1;
              final valid =
                  index + delta >= 0 && index + delta < widget.entries.length;
              setState(
                () =>
                    offset = valid ? next : next.clamp(-24.0, 24.0).toDouble(),
              );
            },
            onHorizontalDragCancel: () => settle(0),
            onHorizontalDragEnd: (details) {
              if (settling) {
                return;
              }
              final velocity = details.primaryVelocity ?? 0;
              final travel = velocity.abs() > 450 ? velocity : offset;
              final delta = (travel < 0) != rtl ? 1 : -1;
              if ((offset.abs() > width * .18 || velocity.abs() > 450) &&
                  index + delta >= 0 &&
                  index + delta < widget.entries.length) {
                move(delta);
              } else {
                settle(0);
              }
            },
            child: ClipRect(
              child: Stack(
                children: [
                  for (var layer = layers; layer >= 1; layer--)
                    Positioned(
                      top: layer * 5.0,
                      bottom: (layers - layer) * 5.0,
                      left: layer * 8.0,
                      right: (layers - layer) * 8.0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: SendohColors.surface,
                          border: Border.all(color: SendohColors.border),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  if (offset != 0 &&
                      neighbour >= 0 &&
                      neighbour < widget.entries.length)
                    Positioned.fill(
                      child: ExcludeSemantics(
                        child: IgnorePointer(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: layers * 8.0,
                              bottom: layers * 5.0,
                            ),
                            child: ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.topCenter,
                                minHeight: 0,
                                maxHeight: double.infinity,
                                child: Transform.scale(
                                  scale: .96 + .04 * fraction,
                                  alignment: Alignment.topCenter,
                                  child: HomeCollectionCard(
                                    data: Map<String, dynamic>.from(
                                      widget.entries[neighbour],
                                    ),
                                    featured: true,
                                    onTap: () {},
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.only(
                      right: layers * 8.0,
                      bottom: layers * 5.0,
                    ),
                    child: Transform.translate(
                      key: const ValueKey('collection-deck-motion'),
                      offset: Offset(offset, 0),
                      child: HomeCollectionCard(
                        key: ValueKey(identity(data)),
                        data: data,
                        featured: true,
                        onTap: () {
                          if (!settling && offset == 0) {
                            widget.onOpen(data);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String joinedPersonalStatus(Map<String, dynamic> item) {
  final c = Map<String, dynamic>.from(item['collection']);
  if (c['status'] == 'CLOSED') {
    return 'Closed';
  }
  if (c['status'] == 'SETTLED') {
    return 'Settled';
  }
  if (c['status'] == 'CANCELLED') {
    return 'Cancelled';
  }
  return MemberPosition.fromJoined(item).personalLine(coordinationMoney);
}

class RequestSummary extends StatelessWidget {
  const RequestSummary({
    super.key,
    required this.requests,
    required this.onOpen,
  });
  final Future<List<dynamic>>? requests;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
        future: requests,
        builder: (context, snapshot) {
          final sent = (snapshot.data ?? [])
              .where(
                  (r) => r['direction'] == 'SENT' && r['status'] == 'PENDING')
              .toList();
          final people = sent.map((r) => r['recipient']['id']).toSet().length;
          final total = sent.fold<int>(
            0,
            (sum, r) => sum + (r['amount'] as num).toInt(),
          );
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: SendohColors.border),
              ),
              tileColor: SendohColors.surface,
              leading: const Icon(Icons.swap_horiz, color: SendohColors.teal),
              title: Text(
                sent.isEmpty
                    ? 'Your money requests'
                    : 'Waiting on $people ${people == 1 ? 'person' : 'people'}',
                style: SendohTextStyles.bodyMedium,
              ),
              subtitle: snapshot.hasError
                  ? const Text('Open to retry loading requests')
                  : sent.isEmpty
                      ? null
                      : Text(
                          '${coordinationMoney(total)} outstanding${(snapshot.data?.length ?? 0) >= 100 ? ' · recent requests' : ''}',
                        ),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpen,
            ),
          );
        },
      );
}
