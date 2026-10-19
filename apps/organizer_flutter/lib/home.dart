import 'package:flutter/material.dart';
import 'coordination.dart';
import 'design.dart';
import 'people_flows.dart';

/// Presentation only. Shell retains fetching, identity and navigation ownership.
class CoordinationHome extends StatefulWidget {
  const CoordinationHome(
      {super.key,
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
      this.onViewRequests,
      this.requests,
      this.onReviewRequest,
      this.onNotifications,
      this.unread = 0});
  final VoidCallback? onNotifications;
  final int unread;
  final Future<List<dynamic>>? requests;
  final ValueChanged<Map<String, dynamic>>? onReviewRequest;
  final PeopleFlowGateway? peopleGateway;
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
    } catch (_) {/* Section retry remains available. */}
  }

  void viewOwned(List<dynamic> entries) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Your collections')),
              body: ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: entries.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 12),
                  itemBuilder: (_, index) {
                    final data = Map<String, dynamic>.from(entries[index]);
                    return HomeCollectionCard(
                        data: data, onTap: () => widget.onOpenOwned(data));
                  }),
            )));
  }

  Widget attention() => FutureBuilder<List<dynamic>>(
        future: widget.requests,
        builder: (context, requests) => FutureBuilder<List<dynamic>>(
          future: widget.invitations,
          builder: (context, invites) {
            final pending = (requests.data ?? [])
                .where((r) =>
                    r['direction'] == 'RECEIVED' && r['status'] == 'PENDING')
                .toList();
            final invitations = invites.data ?? [];
            if (requests.hasError || invites.hasError) {
              return _SectionMessage(
                  text: 'Some updates couldn’t load.', onRetry: refresh);
            }
            if (pending.isEmpty && invitations.isEmpty) {
              return const SizedBox.shrink();
            }
            final isRequest = pending.isNotEmpty;
            final item = Map<String, dynamic>.from(
                isRequest ? pending.first : invitations.first);
            final total = pending.length + invitations.length;
            return Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionTitle(
                          title: 'Needs your attention', count: total),
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                              backgroundColor: SendohColors.tealSoft,
                              child: Icon(Icons.notifications_outlined,
                                  color: SendohColors.teal)),
                          title: Text(
                              isRequest
                                  ? '${item['requester']['name']} requested ${coordinationMoney(item['amount'])}'
                                  : item['collection']['name'] as String,
                              style: SendohTextStyles.bodyMedium),
                          subtitle: Text(isRequest
                              ? item['reason'] as String
                              : '${item['collection']['organizer_name'] ?? 'Organizer'} invited you'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            if (isRequest) {
                              widget.onReviewRequest?.call(item);
                            } else {
                              widget.onReviewInvitation?.call(item);
                            }
                          }),
                      if (total > 1)
                        Wrap(spacing: 8, children: [
                          if (pending.isNotEmpty)
                            TextButton(
                                onPressed: widget.onViewRequests,
                                child: Text('Requests (${pending.length})')),
                          if (invitations.isNotEmpty)
                            TextButton(
                                onPressed: widget.onViewInvitations,
                                child: Text(
                                    'Invitations (${invitations.length})')),
                        ]),
                    ]));
          },
        ),
      );

  @override
  Widget build(BuildContext context) => RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
          key: const PageStorageKey('coordination-home'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          children: [
            Row(children: [
              widget.avatar,
              const SizedBox(width: 12),
              Expanded(
                  child: Text('Hi, ${widget.name}',
                      style: SendohTextStyles.headingMedium)),
              if (widget.onNotifications != null)
                IconButton(
                    tooltip: 'Notifications (${widget.unread} unread)',
                    onPressed: widget.onNotifications,
                    icon: Badge(
                        isLabelVisible: widget.unread > 0,
                        backgroundColor: SendohColors.orange,
                        child: const Icon(Icons.notifications_outlined))),
            ]),
            const SizedBox(height: 16),
            HomeActionBar(
                onCollect: widget.onCreate, gateway: widget.peopleGateway),
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
                            title: 'You organize',
                            action: entries.length > 1
                                ? TextButton(
                                    onPressed: () => viewOwned(entries),
                                    child: Text('View all ${entries.length}'))
                                : null),
                        const SizedBox(height: 8),
                        if (snapshot.hasError)
                          _SectionMessage(
                              text: 'Your collections couldn’t load.',
                              onRetry: refresh)
                        else if (!snapshot.hasData)
                          const _LoadingSection()
                        else if (entries.isEmpty)
                          const _SectionMessage(
                              text:
                                  'Create a collection and invite your people.')
                        else
                          CollectionDeck(
                              entries: entries, onOpen: widget.onOpenOwned),
                      ]);
                }),
            const SizedBox(height: 16),
            _SectionTitle(
                title: 'You joined',
                action: TextButton(
                    onPressed: widget.onViewJoined,
                    child: const Text('View all'))),
            FutureBuilder<List<dynamic>>(
                future: widget.joined,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _SectionMessage(
                        text: 'Joined collections couldn’t load.',
                        onRetry: refresh);
                  }
                  if (!snapshot.hasData) {
                    return const _LoadingSection();
                  }
                  if (snapshot.data!.isEmpty) {
                    return const Text('Collections you join will appear here.',
                        style: SendohTextStyles.caption);
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
                                      onTap: () => widget.onOpenJoined(
                                          Map<String, dynamic>.from(raw)))),
                          ]));
                }),
            if (widget.onViewRequests != null)
              RequestSummary(
                  requests: widget.requests, onOpen: widget.onViewRequests!),
          ]));
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.count, this.action});
  final String title;
  final int? count;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: Text(count == null ? title : '$title · $count',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700))),
        if (action != null) action!,
      ]);
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
            borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text,
              style:
                  const TextStyle(height: 1.5, color: SendohColors.secondary)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
        ]),
      );
}

class _LoadingSection extends StatelessWidget {
  const _LoadingSection();
  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.symmetric(vertical: 30),
      child: Center(
          child: CircularProgressIndicator(
              semanticsLabel: 'Loading collections')));
}

class HomeCollectionCard extends StatelessWidget {
  const HomeCollectionCard(
      {super.key,
      required this.data,
      required this.onTap,
      this.featured = false});
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final actual = (data['collected_amount'] as num? ?? 0).toInt();
    final target = (data['target_amount'] as num?)?.toInt();
    final people = data['participants'] as List? ?? [];
    final ink = featured ? SendohColors.surface : SendohColors.ink;
    final status = switch (data['status']) {
      'ACTIVE' => 'OPEN',
      'CLOSED' => 'CLOSED',
      'SETTLED' => 'SETTLED',
      'DRAFT' => 'DRAFT',
      _ => '${data['status'] ?? 'OPEN'}',
    };
    return Semantics(
        button: true,
        label: 'Open ${data['name']}',
        child: Material(
          color: featured ? SendohColors.teal : SendohColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                  color: featured ? SendohColors.teal : SendohColors.border)),
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
                              Expanded(
                                  child: Text(data['name'] as String,
                                      style: SendohTextStyles.titleSmall
                                          .copyWith(color: ink))),
                              const SizedBox(width: 8),
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 5),
                                  decoration: BoxDecoration(
                                      color: SendohColors.surface,
                                      borderRadius: BorderRadius.circular(28)),
                                  child: Text(status,
                                      style: SendohTextStyles.badgeLabel)),
                            ]),
                        const SizedBox(height: 12),
                        Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            children: [
                              Text(coordinationMoney(actual),
                                  style: SendohTextStyles.headingMedium
                                      .copyWith(color: ink)),
                              Text(
                                  target != null && target > 0
                                      ? '/ ${coordinationMoney(target)}'
                                      : 'collected · No target',
                                  style: SendohTextStyles.caption
                                      .copyWith(color: ink)),
                            ]),
                        if (target != null && target > 0) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                  value: (actual / target)
                                      .clamp(0.0, 1.0)
                                      .toDouble(),
                                  minHeight: 4,
                                  color: SendohColors.orange,
                                  backgroundColor: featured
                                      ? const Color(0x33FFFFFF)
                                      : SendohColors.tealSoft,
                                  semanticsLabel: 'Collection progress',
                                  semanticsValue:
                                      '${(actual / target * 100).round()} percent')),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (people.isNotEmpty)
                                Wrap(
                                    spacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      for (final person in people.take(3))
                                        MemberAvatar(
                                            Map<String, dynamic>.from(person),
                                            radius: 12),
                                      Text('${people.length} people',
                                          style: SendohTextStyles.caption
                                              .copyWith(color: ink)),
                                    ]),
                              if (target != null && target > 0)
                                Text(
                                    actual >= target
                                        ? 'Target reached'
                                        : '${coordinationMoney(target - actual)} to go',
                                    style: SendohTextStyles.caption
                                        .copyWith(color: ink)),
                            ]),
                      ]))),
        ));
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
    final status = joinedPersonalStatus(item);
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final initials =
        words.take(2).map((w) => w.characters.first).join().toUpperCase();
    final width = MediaQuery.textScalerOf(context)
        .scale(88)
        .clamp(88.0, 150.0)
        .toDouble();
    return Semantics(
      button: true,
      label:
          'Open $name, organized by ${collection['organizer_name'] ?? 'Organizer'}',
      child: Tooltip(
          message: name,
          child: SizedBox(
              width: width,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onTap,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 4),
                      child: Column(children: [
                        CircleAvatar(
                            radius: 28,
                            backgroundColor: SendohColors.tealSoft,
                            child: Text(initials.isEmpty ? 'G' : initials,
                                textScaler: TextScaler.noScaling,
                                style: const TextStyle(
                                    color: SendohColors.teal,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600))),
                        const SizedBox(height: 8),
                        Text(name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text(status, style: SendohTextStyles.caption),
                      ])),
                ),
              ))),
    );
  }
}

class HomeActionBar extends StatelessWidget {
  const HomeActionBar({super.key, required this.onCollect, this.gateway});
  final PeopleFlowGateway? gateway;
  final VoidCallback onCollect;

  void showPlannedFlow(BuildContext context, bool pay) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PeopleFlow(
            intent: pay ? PeopleIntent.pay : PeopleIntent.request,
            gateway: gateway)));
  }

  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Action(
            icon: Icons.add,
            label: 'Collect',
            onTap: onCollect,
            creation: true),
        _Action(
            icon: Icons.call_received,
            label: 'Request',
            onTap: () => showPlannedFlow(context, false),
            planned: gateway == null),
        _Action(
            icon: Icons.north_east,
            label: 'Pay',
            onTap: () => showPlannedFlow(context, true),
            planned: true),
        _Action(
            icon: Icons.qr_code_scanner,
            label: 'Near2Pay',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => PeopleFlow(nearby: true, gateway: gateway))),
            planned: true),
      ]);
}

class _Action extends StatelessWidget {
  const _Action(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.creation = false,
      this.planned = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool creation, planned;
  @override
  Widget build(BuildContext context) => Expanded(
          child: Semantics(
        button: true,
        label: planned ? '$label, coming soon, view details' : label,
        child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(children: [
                  CircleAvatar(
                      radius: 25,
                      backgroundColor: creation
                          ? SendohColors.orange
                          : SendohColors.tealSoft,
                      child: Icon(icon,
                          color:
                              creation ? SendohColors.ink : SendohColors.teal,
                          size: 23)),
                  const SizedBox(height: 8),
                  Text(label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  if (planned)
                    const Text('Soon',
                        style: TextStyle(
                            fontSize: 11, color: SendohColors.secondary)),
                ]),
              ),
            )),
      ));
}

/// A deck sizes to its active card, including large text. No fixed card height.
class CollectionDeck extends StatefulWidget {
  const CollectionDeck(
      {super.key, required this.entries, required this.onOpen});
  final List<dynamic> entries;
  final ValueChanged<Map<String, dynamic>> onOpen;
  @override
  State<CollectionDeck> createState() => _CollectionDeckState();
}

class _CollectionDeckState extends State<CollectionDeck> {
  int index = 0;
  String identity(dynamic row) => '${row['id'] ?? row['name']}';
  @override
  void didUpdateWidget(covariant CollectionDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries.isNotEmpty && index < oldWidget.entries.length) {
      final id = identity(oldWidget.entries[index]);
      final found = widget.entries.indexWhere((row) => identity(row) == id);
      index = found < 0 ? 0 : found;
    } else {
      index = 0;
    }
  }

  void move(int delta) {
    final next = (index + delta).clamp(0, widget.entries.length - 1).toInt();
    if (next != index) {
      setState(() => index = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final data = Map<String, dynamic>.from(widget.entries[index]);
    final layers = (widget.entries.length - 1).clamp(0, 2).toInt();
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Semantics(
          label: 'Collection ${index + 1} of ${widget.entries.length}',
          onIncrease: index < widget.entries.length - 1 ? () => move(1) : null,
          onDecrease: index > 0 ? () => move(-1) : null,
          child: GestureDetector(
              onHorizontalDragEnd: (details) {
                final speed = details.primaryVelocity ?? 0;
                final distance = dragDistance;
                dragDistance = 0;
                if (speed.abs() < 80 && distance.abs() < 40) {
                  return;
                }
                final direction = speed.abs() >= 80 ? speed : distance;
                final rtl = Directionality.of(context) == TextDirection.rtl;
                move((direction < 0) != rtl ? 1 : -1);
              },
              onHorizontalDragUpdate: (details) {
                dragDistance += details.delta.dx;
              },
              onHorizontalDragStart: (_) {
                dragDistance = 0;
              },
              onHorizontalDragCancel: () {
                dragDistance = 0;
              },
              child: Stack(children: [
                for (var layer = layers; layer >= 1; layer--)
                  Positioned(
                      top: layer * 5.0,
                      bottom: (layers - layer) * 5.0,
                      left: layer * 8.0,
                      right: (layers - layer) * 8.0,
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              color: SendohColors.tealSoft,
                              border: Border.all(
                                  color: SendohColors.teal.withAlpha(46)),
                              borderRadius: BorderRadius.circular(20)))),
                Padding(
                    padding: EdgeInsets.only(
                        right: layers * 8.0, bottom: layers * 5.0),
                    child: AnimatedSize(
                        duration:
                            Duration(milliseconds: reducedMotion ? 0 : 180),
                        alignment: Alignment.topCenter,
                        child: AnimatedSwitcher(
                            duration:
                                Duration(milliseconds: reducedMotion ? 0 : 180),
                            child: HomeCollectionCard(
                                key: ValueKey(identity(data)),
                                data: data,
                                featured: true,
                                onTap: () => widget.onOpen(data))))),
              ]))),
      if (widget.entries.length > 1)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
              tooltip: 'Previous collection',
              onPressed: index > 0 ? () => move(-1) : null,
              icon: const Icon(Icons.chevron_left)),
          Semantics(
              liveRegion: true,
              child: Text('${index + 1} / ${widget.entries.length}',
                  style: SendohTextStyles.caption)),
          IconButton(
              tooltip: 'Next collection',
              onPressed:
                  index < widget.entries.length - 1 ? () => move(1) : null,
              icon: const Icon(Icons.chevron_right)),
        ]),
    ]);
  }

  double dragDistance = 0;
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
  final summary = item['contribution_summary'] as Map?;
  final expected = (item['expected_amount'] as num?)?.toInt();
  // Only a server-confirmed live ledger may establish paid / remaining states.
  if (summary?['live_available'] == true) {
    final confirmed = (summary?['confirmed_amount'] as num?)?.toInt();
    if (summary?['payment_pending'] == true) {
      return 'Payment pending';
    }
    if (confirmed != null) {
      if (expected != null && expected > 0) {
        if (confirmed >= expected) {
          return 'Your part done ✓';
        }
        return '${coordinationMoney(expected - confirmed)} remaining';
      }
      return confirmed > 0
          ? '${coordinationMoney(confirmed)} contributed'
          : 'Any amount welcome';
    }
  }
  final testPaid = (summary?['test_paid_amount'] as num?)?.toInt() ?? 0;
  if (testPaid > 0) {
    return '${coordinationMoney(testPaid)} · test';
  }
  return expected != null && expected > 0
      ? '${coordinationMoney(expected)} expected'
      : 'Any amount welcome';
}

class RequestSummary extends StatelessWidget {
  const RequestSummary(
      {super.key, required this.requests, required this.onOpen});
  final Future<List<dynamic>>? requests;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
      future: requests,
      builder: (context, snapshot) {
        final sent = (snapshot.data ?? [])
            .where((r) => r['direction'] == 'SENT' && r['status'] == 'PENDING')
            .toList();
        final people = sent.map((r) => r['recipient']['id']).toSet().length;
        final total =
            sent.fold<int>(0, (sum, r) => sum + (r['amount'] as num).toInt());
        return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: SendohColors.border)),
              tileColor: SendohColors.surface,
              leading: const Icon(Icons.swap_horiz, color: SendohColors.teal),
              title: Text(
                  sent.isEmpty
                      ? 'Your money requests'
                      : 'Waiting on $people ${people == 1 ? 'person' : 'people'}',
                  style: SendohTextStyles.bodyMedium),
              subtitle: snapshot.hasError
                  ? const Text('Open to retry loading requests')
                  : sent.isEmpty
                      ? null
                      : Text(
                          '${coordinationMoney(total)} outstanding${(snapshot.data?.length ?? 0) >= 100 ? ' · recent requests' : ''}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpen,
            ));
      });
}
