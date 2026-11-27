import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design.dart';
import 'i18n.dart';
import 'main.dart' show apiProvider;
import 'person_payments.dart';
import 'push_service.dart';
import 'settlement.dart';

/// Activity, as approved: what is still moving on top, then history by day.

enum ActivityKind { person, settlement, update }

class ActivityItem {
  const ActivityItem(
      {required this.kind,
      required this.title,
      required this.at,
      this.subtitle,
      this.amount,
      this.inProgress = false,
      this.data = const {}});
  final ActivityKind kind;
  final String title;
  final String? subtitle;

  /// Already formatted, e.g. "5 000 FCFA".
  final String? amount;
  final DateTime? at;
  final bool inProgress;
  final Map<String, dynamic> data;
}

DateTime? _time(dynamic raw) =>
    raw == null ? null : DateTime.tryParse(raw.toString());

/// Started person payments, sent and received.
List<ActivityItem> personItems(List<dynamic> raw) => [
      for (final r in raw)
        () {
          final item = Map<String, dynamic>.from(r as Map);
          final sent = item['direction'] == 'SENT';
          final quote = Map<String, dynamic>.from(item['quote'] as Map? ?? {});
          final other = sent
              ? '${quote['recipient']?['name'] ?? ''}'
              : '${item['payer']?['name'] ?? t('Someone')}';
          final phase = item['phase'] as String?;
          return ActivityItem(
              kind: ActivityKind.person,
              title: sent
                  ? t('Payment to {name}', {'name': other})
                  : t('Payment from {name}', {'name': other}),
              subtitle: personActivityLine(item).status,
              amount: fcfa(quote['amounts']?['recipient_amount'] ?? 0),
              at: _time(item['created_at']),
              inProgress: phase != 'DELIVERED' && phase != 'FAILED',
              data: item);
        }()
    ];

/// Collection payouts the person organised.
List<ActivityItem> settlementItems(List<dynamic> raw) => [
      for (final r in raw)
        () {
          final s = Map<String, dynamic>.from(r as Map);
          final state = s['state'] as String?;
          final status = switch (state) {
            'DELIVERED' => t('Payout delivered'),
            'REVIEW' => t('Needs attention'),
            _ => t('Sending payout'),
          };
          return ActivityItem(
              kind: ActivityKind.settlement,
              title: '${s['collection_name']}',
              subtitle: t('Round {round} · {status}',
                  {'round': s['round'], 'status': status}),
              amount: fcfa(s['payout_amount'] ?? 0),
              at: _time(s['created_at']),
              inProgress: state != 'DELIVERED',
              data: s);
        }()
    ];

final _contributed = RegExp(r'^(.+) contributed (.+ FCFA) to (.+)$');

/// Collection updates. A contribution reads "Kboy contributed · New TV · 20,000 FCFA".
List<ActivityItem> updateItems(List<dynamic> raw) => [
      for (final r in raw)
        () {
          final e = Map<String, dynamic>.from(r as Map);
          final message =
              '${e['message']}'.replaceFirst(RegExp(r' · Sandbox$'), '');
          final collection = e['collection_name'] as String?;
          final m = _contributed.firstMatch(message);
          return m == null
              ? ActivityItem(
                  kind: ActivityKind.update,
                  title: message,
                  subtitle: collection,
                  at: _time(e['created_at']),
                  data: e)
              : ActivityItem(
                  kind: ActivityKind.update,
                  title: t('{name} contributed', {'name': m.group(1)}),
                  subtitle: collection ?? m.group(3),
                  amount: m.group(2),
                  at: _time(e['created_at']),
                  data: e);
        }()
    ];

/// Today, Yesterday, or the date, in Cameroon time.
String dayHeading(DateTime at, DateTime now) {
  DateTime day(DateTime d) {
    final c = d.toUtc().add(const Duration(hours: 1));
    return DateTime.utc(c.year, c.month, c.day);
  }

  final gap = day(now).difference(day(at)).inDays;
  if (gap == 0) return t('Today');
  if (gap == 1) return t('Yesterday');
  return displayDate(at.toIso8601String());
}

/// Newest first, grouped under day headings.
List<(String, List<ActivityItem>)> byDay(
    List<ActivityItem> items, DateTime now) {
  final sorted = [...items]..sort((a, b) =>
      (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
  final groups = <(String, List<ActivityItem>)>[];
  for (final item in sorted) {
    final heading = item.at == null ? t('Earlier') : dayHeading(item.at!, now);
    if (groups.isEmpty || groups.last.$1 != heading) {
      groups.add((heading, [item]));
    } else {
      groups.last.$2.add(item);
    }
  }
  return groups;
}

class ActivityRow extends StatelessWidget {
  const ActivityRow({super.key, required this.item, this.onTap});
  final ActivityItem item;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Row(children: [
            Icon(
                item.kind == ActivityKind.person
                    ? Icons.person_outline
                    : Icons.groups_outlined,
                size: 28,
                color: SendohColors.ink),
            const SizedBox(width: 16),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(item.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  if (item.subtitle != null && item.subtitle!.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(item.subtitle!,
                            style: const TextStyle(
                                fontSize: 14, color: SendohColors.secondary))),
                ])),
            if (item.amount != null)
              Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(item.amount!,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600))),
          ])));
}

/// The soft teal "In progress" card. Hidden when nothing is moving.
class InProgressCard extends StatelessWidget {
  const InProgressCard({super.key, required this.items, required this.onOpen});
  final List<ActivityItem> items;
  final ValueChanged<ActivityItem> onOpen;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      decoration: BoxDecoration(
          color: const Color(0xFFE3F3F0),
          borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.schedule, size: 26, color: SendohColors.ink),
          const SizedBox(width: 12),
          Text(t('In progress'),
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                  color: const Color(0xFFC9E8E2),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('${items.length}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 4),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: Color(0xFFC9E2DD)),
          ActivityRow(item: items[i], onTap: () => onOpen(items[i])),
        ],
      ]));
}

class ActivityView extends ConsumerStatefulWidget {
  const ActivityView({super.key});
  @override
  ConsumerState<ActivityView> createState() => _ActivityViewState();
}

class _ActivityViewState extends ConsumerState<ActivityView> {
  late Future<List<ActivityItem>> items;

  @override
  void initState() {
    super.initState();
    items = load();
    PushService.updates.addListener(onUpdate);
  }

  @override
  void dispose() {
    PushService.updates.removeListener(onUpdate);
    super.dispose();
  }

  Future<List<ActivityItem>> load() async {
    final api = ref.read(apiProvider);
    // Each part loads on its own: one failing never hides the others.
    Future<List<dynamic>> part(String path, {bool listed = true}) => api
        .request(path)
        .then<List<dynamic>>((v) => listed
            ? List<dynamic>.from((v as Map)['items'] as List? ?? const [])
            : List<dynamic>.from(v as List))
        .catchError((_) => <dynamic>[]);
    final parts = await Future.wait([
      part('/person-payments/activity'),
      part('/me/settlements'),
      api.request('/me/activity').then((v) => List<dynamic>.from(v as List)),
    ]);
    return [
      ...personItems(parts[0]),
      ...settlementItems(parts[1]),
      ...updateItems(parts[2]),
    ];
  }

  void onUpdate() {
    if (mounted) setState(() => items = load());
  }

  Future<void> open(ActivityItem item) async {
    final api = ref.read(apiProvider);
    final navigator = Navigator.of(context);
    switch (item.kind) {
      case ActivityKind.person:
        await navigator.push(MaterialPageRoute<void>(
            builder: (_) =>
                PersonCheckout(api: api, orderId: item.data['id'] as String)));
      case ActivityKind.settlement:
        await navigator.push(MaterialPageRoute<void>(
            builder: (_) => SettlementScreen(
                api: api,
                collectionId: item.data['collection_id'] as String,
                collectionName: item.data['collection_name'] as String,
                round: (item.data['round'] as num).toInt())));
      case ActivityKind.update:
        return;
    }
    onUpdate();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ActivityItem>>(
      future: items,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <ActivityItem>[];
        final moving = all.where((i) => i.inProgress).toList();
        final history = byDay(
            all.where((i) => !i.inProgress).toList(), DateTime.now());
        return RefreshIndicator(
            onRefresh: () async {
              onUpdate();
              await items;
            },
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData)
                    const LinearProgressIndicator(),
                  if (snapshot.hasError) ...[
                    Text(t(
                        'Couldn’t load activity. Your records are still saved.')),
                    TextButton(
                        onPressed: onUpdate, child: Text(t('Try again'))),
                  ] else if (snapshot.hasData && all.isEmpty)
                    EmptyState(
                        title: t('Nothing here yet'),
                        message: t(
                            'Payments and collection updates will show up here.'),
                        icon: Icons.history),
                  if (moving.isNotEmpty) ...[
                    InProgressCard(items: moving, onOpen: open),
                    const SizedBox(height: 12),
                  ],
                  for (final (heading, group) in history) ...[
                    Padding(
                        padding: const EdgeInsets.only(top: 20, bottom: 4),
                        child: Text(heading,
                            style: const TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w800))),
                    for (final item in group) ...[
                      ActivityRow(
                          item: item,
                          onTap: item.kind == ActivityKind.update
                              ? null
                              : () => open(item)),
                      const Divider(height: 1),
                    ],
                  ],
                ]));
      });
}
