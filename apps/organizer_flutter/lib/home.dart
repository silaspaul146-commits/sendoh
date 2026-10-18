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
      this.onReviewRequest});
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
  bool showAll = false;

  Future<void> refresh() async {
    try {
      await widget.onRefresh();
    } catch (_) {
      // Each section displays its own failure and retry action.
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          key: const PageStorageKey('coordination-home'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(children: [
              widget.avatar,
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Welcome back',
                        style: TextStyle(
                            color: SendohColors.secondary, fontSize: 12)),
                    Text(widget.name,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700)),
                  ])),
            ]),
            const SizedBox(height: 20),
            HomeActionBar(
                onCollect: widget.onCreate, gateway: widget.peopleGateway),
            if (widget.onViewRequests != null)
              Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      onPressed: widget.onViewRequests,
                      child: const Text('Your money requests'))),
            const SizedBox(height: 24),
            if (widget.invitations != null) ...[
              _SectionTitle(
                  title: 'Needs your attention',
                  action: TextButton(
                      onPressed: widget.onViewInvitations,
                      child: const Text('View all'))),
              FutureBuilder<List<dynamic>>(
                  future: widget.invitations,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _SectionMessage(
                          text: 'Invitations couldn’t load.', onRetry: refresh);
                    }
                    if (!snapshot.hasData) {
                      return const _LoadingSection();
                    }
                    if (snapshot.data!.isEmpty) {
                      return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No invitations waiting for a response.',
                              style: TextStyle(color: SendohColors.secondary)));
                    }
                    return Column(
                        children: snapshot.data!.take(2).map((raw) {
                      final item = Map<String, dynamic>.from(raw);
                      final collection =
                          Map<String, dynamic>.from(item['collection']);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                            backgroundColor: SendohColors.amberSoft,
                            child: Icon(Icons.mail_outline,
                                color: SendohColors.amber)),
                        title: Text(collection['name'] as String,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            '${collection['organizer_name'] ?? 'Organizer'} invited you'),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: widget.onReviewInvitation == null
                            ? null
                            : () => widget.onReviewInvitation!(item),
                      );
                    }).toList());
                  }),
              const SizedBox(height: 24),
            ],
            if (widget.requests != null)
              FutureBuilder<List<dynamic>>(
                  future: widget.requests,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _SectionMessage(
                          text: 'Money requests couldn’t load.',
                          onRetry: refresh);
                    }
                    if (!snapshot.hasData) return const _LoadingSection();
                    final rows = snapshot.data!
                        .where((r) =>
                            r['direction'] == 'RECEIVED' &&
                            r['status'] == 'PENDING')
                        .take(2)
                        .toList();
                    if (rows.isEmpty) return const SizedBox.shrink();
                    return Column(children: [
                      _SectionTitle(title: 'Requests to review'),
                      ...rows.map((raw) {
                        final r = Map<String, dynamic>.from(raw);
                        return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(
                                backgroundColor: SendohColors.tealSoft,
                                child: Icon(Icons.call_received,
                                    color: SendohColors.teal)),
                            title: Text(
                                '${r['requester']['name']} requested ${coordinationMoney(r['amount'])}'),
                            subtitle: Text(r['reason']),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: widget.onReviewRequest == null
                                ? null
                                : () => widget.onReviewRequest!(r));
                      }),
                      const SizedBox(height: 24),
                    ]);
                  }),
            FutureBuilder<List<dynamic>>(
                future: widget.owned,
                builder: (context, snapshot) {
                  final entries = snapshot.data ?? <dynamic>[];
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionTitle(
                            title: 'You organize',
                            count: snapshot.hasData ? entries.length : null,
                            action: entries.length > 2
                                ? TextButton(
                                    onPressed: () =>
                                        setState(() => showAll = !showAll),
                                    child: Text(
                                        showAll ? 'Show less' : 'View all'))
                                : null),
                        const SizedBox(height: 10),
                        if (snapshot.hasError)
                          _SectionMessage(
                              text: 'Your collections couldn’t load.',
                              onRetry: refresh)
                        else if (!snapshot.hasData)
                          const _LoadingSection()
                        else if (entries.isEmpty)
                          const _SectionMessage(
                              text:
                                  'Bring your group together. Create a collection, then invite people with one link.')
                        else
                          ...entries
                              .take(showAll ? entries.length : 2)
                              .toList()
                              .asMap()
                              .entries
                              .map((entry) {
                            final data = Map<String, dynamic>.from(entry.value);
                            return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: HomeCollectionCard(
                                    data: data,
                                    featured: entry.key == 0,
                                    onTap: () => widget.onOpenOwned(data)));
                          }),
                      ]);
                }),
            const SizedBox(height: 12),
            _SectionTitle(
                title: 'You joined',
                action: TextButton(
                    onPressed: widget.onViewJoined,
                    child: const Text('View all'))),
            const SizedBox(height: 10),
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
                    return const _SectionMessage(
                        text:
                            'Collections you join appear here. Open an invitation from the envelope above, or join through a collection link.');
                  }
                  return SingleChildScrollView(
                    key: const PageStorageKey('joined-home-shelf'),
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
                        ]),
                  );
                }),
            if (widget.recentActivity != null) ...[
              const SizedBox(height: 24),
              _SectionTitle(
                  title: 'Recent activity',
                  action: TextButton(
                      onPressed: widget.onViewActivity,
                      child: const Text('View all'))),
              FutureBuilder<List<dynamic>>(
                  future: widget.recentActivity,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _SectionMessage(
                          text: 'Recent activity couldn’t load.',
                          onRetry: refresh);
                    }
                    if (!snapshot.hasData) {
                      return const _LoadingSection();
                    }
                    final entries = snapshot.data!
                        .where((e) =>
                            !(e['message'] as String).startsWith('TEST:'))
                        .take(3)
                        .toList();
                    if (entries.isEmpty) {
                      return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Collection updates will appear here.',
                              style: TextStyle(color: SendohColors.secondary)));
                    }
                    return Column(
                        children: entries
                            .map((e) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.history,
                                      color: SendohColors.teal),
                                  title: Text(e['message'] as String,
                                      style: const TextStyle(fontSize: 14)),
                                  subtitle: Text(displayDate(e['created_at'])),
                                  onTap: widget.onViewActivity,
                                ))
                            .toList());
                  }),
            ],
          ],
        ),
      );
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
                    fontSize: 18, fontWeight: FontWeight.w700))),
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
        padding: const EdgeInsets.all(18),
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
    final people = data['participants'] as List?;
    final ink = featured ? Colors.white : SendohColors.ink;
    final secondary =
        featured ? const Color(0xFFD1E4E0) : SendohColors.secondary;
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
                  padding: const EdgeInsets.all(18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: Text(data['name'] as String,
                                      style: TextStyle(
                                          color: ink,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700))),
                              const SizedBox(width: 8),
                              StatusBadge(data['status'] as String),
                            ]),
                        const SizedBox(height: 14),
                        Text(coordinationMoney(actual),
                            style: TextStyle(
                                color: ink,
                                fontSize: featured ? 26 : 22,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                            target != null && target > 0
                                ? 'collected of ${coordinationMoney(target)}'
                                : 'collected · No target set',
                            style: TextStyle(fontSize: 12, color: secondary)),
                        if (target != null && target > 0) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                  value: (actual / target)
                                      .clamp(0.0, 1.0)
                                      .toDouble(),
                                  minHeight: 6,
                                  semanticsLabel: 'Collection progress',
                                  semanticsValue:
                                      '${(actual / target * 100).round()} percent',
                                  color: actual >= target
                                      ? SendohColors.green
                                      : (featured
                                          ? const Color(0xFF73C5BD)
                                          : SendohColors.teal),
                                  backgroundColor: featured
                                      ? const Color(0xFF316260)
                                      : SendohColors.tealSoft)),
                        ],
                        if (target != null &&
                            target > 0 &&
                            actual >= target) ...[
                          const SizedBox(height: 8),
                          Text(
                              actual == target
                                  ? 'Target reached'
                                  : '${coordinationMoney(actual - target)} above target',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ink)),
                        ],
                        const SizedBox(height: 14),
                        if (featured &&
                            people != null &&
                            people.isNotEmpty) ...[
                          PeoplePreview(people: people, dark: true),
                          const SizedBox(height: 12),
                        ],
                        Row(children: [
                          Icon(Icons.schedule_outlined,
                              size: 15, color: secondary),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(
                                  data['deadline_at'] == null
                                      ? 'No deadline'
                                      : 'Due ${displayDate(data['deadline_at'])}',
                                  style: TextStyle(
                                      color: secondary, fontSize: 12))),
                          Icon(Icons.arrow_forward_rounded,
                              color: ink, size: 18),
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
