/// Close a collection and send its Mobile Money to the organizer.
///
/// Answers three questions: How much did we raise? What will reach my phone?
/// Did my contribution count? All figures come from the server.
library;

import 'i18n.dart';
import 'config.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'contribution_checkout.dart' show paymentKey;
import 'coordination.dart' show coordinationMoney;
import 'design.dart';
import 'payment_state.dart';
import 'person_payments.dart' show ReceivingDetails;

String walletName(Object? method) =>
    method == 'ORANGE' ? t('Orange Money') : 'MTN MoMo';

/// Organizer's collection-page card: raised, split by source, and the next step.
class SettlementSummary extends StatelessWidget {
  const SettlementSummary(
      {super.key,
      required this.data,
      required this.onReview,
      required this.onEditCash,
      this.onNextRound});
  final Map<String, dynamic> data;
  final VoidCallback? onReview, onEditCash;

  /// Shown only for a settled recurring collection.
  final VoidCallback? onNextRound;

  @override
  Widget build(BuildContext context) {
    final totals = CollectionTotals.fromCollection(data);
    final status = data['status'];
    final open = status == 'ACTIVE';
    final recurring = data['recurring'] == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (recurring)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(t('Round {round}', {'round': data['round'] ?? 1}),
                style: SendohTextStyles.caption)),
      SurfaceCard(
          color: SendohColors.teal,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                t('{amount} raised',
                    {'amount': coordinationMoney(totals.raised)}),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700)),
            if (totals.target != null && totals.target! > 0) ...[
              const SizedBox(height: 4),
              Text(
                  t('Goal {amount}',
                      {'amount': coordinationMoney(totals.target)}),
                  style:
                      const TextStyle(color: Color(0xFFE6FFFA), fontSize: 13)),
              const SizedBox(height: 12),
              ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                      value: totals.progress,
                      minHeight: 7,
                      color: SendohColors.orange,
                      backgroundColor: const Color(0xFF316260))),
            ],
            if (totals.pending > 0) ...[
              const SizedBox(height: 10),
              Text(
                  t('{amount} awaiting confirmation',
                      {'amount': coordinationMoney(totals.pending)}),
                  style:
                      const TextStyle(color: Color(0xFFE6FFFA), fontSize: 12)),
            ],
          ])),
      const SizedBox(height: 8),
      SummaryRow(t('Mobile Money'), coordinationMoney(totals.confirmed)),
      SummaryRow(t('Cash recorded'), coordinationMoney(totals.cash)),
      if (open && totals.targetReached)
        Padding(
            padding: EdgeInsets.only(top: 4),
            child: Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge(t('Target reached')))),
      if (open)
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: onEditCash, child: Text(t('Edit cash records')))),
      const SizedBox(height: 4),
      if (recurring && status == 'SETTLED') ...[
        FilledButton(
            onPressed: onNextRound, child: Text(t('Start next round'))),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onReview, child: Text(t('View settlement'))),
      ] else
        FilledButton(
            onPressed: onReview,
            child: Text(open ? t('Review settlement') : t('View settlement'))),
    ]);
  }
}

/// Record cash members handed over in person. Shown separately everywhere.
class CashRecordsScreen extends StatefulWidget {
  const CashRecordsScreen({super.key, required this.api, required this.data});
  final SendohApi api;
  final Map<String, dynamic> data;
  @override
  State<CashRecordsScreen> createState() => _CashRecordsScreenState();
}

class _CashRecordsScreenState extends State<CashRecordsScreen> {
  late final List<Map<String, dynamic>> members = (widget.data['participants']
          as List)
      .map((p) => Map<String, dynamic>.from(p))
      .where((p) =>
          !['DECLINED', 'CANCELLED', 'EXPIRED'].contains(p['invitation_state']))
      .toList();
  late final Map<String, TextEditingController> fields = {
    for (final p in members)
      p['id'] as String: TextEditingController(
          text: MemberPosition.fromMember(p).cash == 0
              ? ''
              : '${MemberPosition.fromMember(p).cash}')
  };
  bool busy = false;
  String? error;

  @override
  void dispose() {
    for (final f in fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    final entries = <Map<String, dynamic>>[];
    for (final p in members) {
      final text = fields[p['id']]!.text.trim().replaceAll(',', '');
      final amount = text.isEmpty ? 0 : int.tryParse(text);
      if (amount == null || amount < 0 || amount > 1000000000) {
        setState(() => error = t('Enter whole FCFA amounts.'));
        return;
      }
      if (amount != MemberPosition.fromMember(p).cash) {
        entries.add({'participant_id': p['id'], 'amount': amount});
      }
    }
    if (entries.isNotEmpty) {
      final names = {for (final m in members) m['id']: m['name']};
      final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
                title: Text(t('Record this cash?')),
                content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in entries)
                        Text(
                            '${names[e['participant_id']]} · ${e['amount'] == 0 ? 'remove cash' : coordinationMoney(e['amount'])}'),
                      const SizedBox(height: 12),
                      Text(
                          t('Each member sees it as cash recorded by you, separate from Mobile Money.'),
                          style: SendohTextStyles.caption),
                    ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(d, false),
                      child: Text(t('Edit'))),
                  TextButton(
                      onPressed: () => Navigator.pop(d, true),
                      child: Text(t('Record cash'))),
                ],
              ));
      if (ok != true) {
        return;
      }
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (entries.isNotEmpty) {
        // Replaces each member's cash amount: saving twice records nothing twice.
        await widget.api.request('/collections/${widget.data['id']}/cash',
            body: {'entries': entries});
      }
      if (mounted) {
        Navigator.pop(context, true);
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

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(t('Cash received'))),
      body: ListView(padding: const EdgeInsets.all(22), children: [
        Text(
            t('Add money members gave you in person. It stays labelled as cash you recorded, separate from Mobile Money.'),
            style: SendohTextStyles.bodyMedium),
        const SizedBox(height: 16),
        ...members.map((p) {
          final position = MemberPosition.fromMember(p);
          return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(p['name'] as String,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500)),
                      Text(
                          t('{amount} by Mobile Money', {
                                'amount': coordinationMoney(position.confirmed)
                              }) +
                              (position.expected == null
                                  ? ''
                                  : ' · ${t('{amount} expected', {
                                          'amount': coordinationMoney(
                                              position.expected)
                                        })}'),
                          style: SendohTextStyles.caption),
                    ])),
                const SizedBox(width: 12),
                SizedBox(
                    width: 110,
                    child: TextField(
                        controller: fields[p['id']],
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: t('Cash'),
                            hintText: '0',
                            semanticCounterText:
                                t('Cash from {name}', {'name': p['name']})))),
              ]));
        }),
        if (error != null)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!,
                  style: const TextStyle(color: SendohColors.red))),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? t('Saving…') : t('Save cash records'))),
      ]));
}

/// Review, then the same screen follows the payout: Sending → Delivered.
class SettlementScreen extends StatefulWidget {
  const SettlementScreen(
      {super.key,
      required this.api,
      required this.collectionId,
      required this.collectionName,
      this.round});
  final SendohApi api;
  final String collectionId, collectionName;

  /// Open a specific round's receipt (e.g. from Activity). Null: the current round.
  final int? round;
  @override
  State<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends State<SettlementScreen> {
  Map<String, dynamic>? overview;
  String? error;
  bool busy = false, showFees = false;

  /// One key per review: a retried "Close and send" replays, never sends twice.
  final String requestKey = paymentKey();
  Timer? poll;
  Duration pollDelay = const Duration(seconds: 5);

  String get path => '/collections/${widget.collectionId}/settlement';
  Map<String, dynamic>? get settlement =>
      overview?['settlement'] as Map<String, dynamic>?;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    poll?.cancel();
    super.dispose();
  }

  Future<void> load({bool lookup = false}) async {
    try {
      final data = await widget.api
          .request(lookup ? '$path/refresh' : path, body: lookup ? {} : null);
      if (mounted) {
        setState(() {
          overview = Map<String, dynamic>.from(data);
          error = null;
        });
        schedule();
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    }
  }

  /// Quiet checks while sending; a lookup never sends money.
  void schedule() {
    poll?.cancel();
    if (settlement?['state'] == 'SENDING') {
      poll = Timer(pollDelay, () async {
        await load(lookup: true);
        final next = pollDelay.inSeconds * 2;
        pollDelay = Duration(seconds: next > 60 ? 60 : next);
      });
    }
  }

  Future<void> closeAndSend() async {
    final quote = overview?['quote'] as Map?;
    if (busy || quote == null) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.api.request(path, key: requestKey, body: {
        'consent': 'CLOSE_AND_SEND',
        'payout_amount': quote['payout_amount']
      });
      if (mounted) {
        setState(() => overview = Map<String, dynamic>.from(data));
        schedule();
      }
    } on ApiException catch (e) {
      // A conflict may mean the payout already exists: show its real state.
      await load();
      if (mounted) {
        setState(() => error = t(e.message));
      }
    } catch (_) {
      // Unknown outcome: read the saved state; the same key replays safely.
      await load();
      if (mounted && settlement == null) {
        setState(() => error = t(
            'Couldn’t confirm. Try again: the same request is reused, so nothing is sent twice.'));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Map<String, dynamic> get receiver =>
      Map<String, dynamic>.from((overview?['beneficiary'] as Map?) ??
          const {'is_you': true, 'name': null});

  /// Who receives this round: the organizer or a joined member.
  Future<void> chooseBeneficiary() async {
    try {
      final data =
          await widget.api.request('/collections/${widget.collectionId}');
      if (!mounted) {
        return;
      }
      final members = (data['participants'] as List)
          .map((p) => Map<String, dynamic>.from(p))
          .where((p) =>
              p['invitation_state'] == 'ACCEPTED' && p['user_id'] != null)
          .toList();
      final picked = await showModalBottomSheet<String>(
          context: context,
          builder: (sheet) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                ListTile(
                    title: Text(t('Who receives this round?'),
                        style: SendohTextStyles.titleSmall)),
                ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(t('You')),
                    onTap: () => Navigator.pop(sheet, '')),
                ...members.map((m) => ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(m['name'] as String),
                    onTap: () => Navigator.pop(sheet, m['id'] as String))),
              ])));
      if (picked == null) {
        return;
      }
      final result = await widget.api.request(
          '/collections/${widget.collectionId}/beneficiary',
          body: {'participant_id': picked.isEmpty ? null : picked});
      if (mounted) {
        setState(() => overview = Map<String, dynamic>.from(result));
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    }
  }

  Future<void> addReceivingDetails() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ReceivingDetails(api: widget.api)));
    await load();
  }

  /// An earlier round's settlement, unchanged since it was closed.
  Map<String, dynamic>? get pastReceipt {
    final o = overview;
    if (o == null || widget.round == null || widget.round == o['round']) {
      return null;
    }
    return (o['history'] as List? ?? [])
        .map((h) => Map<String, dynamic>.from(h as Map))
        .where((h) => h['round'] == widget.round)
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final s = pastReceipt ?? settlement;
    return Scaffold(
        appBar: AppBar(
            title: Text(s == null
                ? t('Review settlement')
                : '${widget.collectionName}${s['round'] != null && (overview?['recurring'] == true) ? ' · Round ${s['round']}' : ''}')),
        body: RefreshIndicator(
            onRefresh: () => load(lookup: s != null),
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(22),
                children: [
                  if (overview == null && error == null)
                    const LinearProgressIndicator(),
                  if (overview != null) ...(s == null ? review() : status(s)),
                  if (error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(error!,
                            style: const TextStyle(color: SendohColors.red))),
                  const SizedBox(height: 16),
                  if (!SendohConfig.paymentsLive)
                    Text(t('Sandbox · no real money moves'),
                        textAlign: TextAlign.center,
                        style: SendohTextStyles.caption),
                ])));
  }

  List<Widget> review() {
    final o = overview!;
    final quote = o['quote'] as Map?;
    final destination = o['destination'] as Map?;
    final raised = Map<String, dynamic>.from(o['raised'] as Map);
    final blockers = (o['blockers'] as List).cast<Map>();
    final needsDetails =
        blockers.any((b) => b['code'] == 'RECEIVING_DETAILS_NEEDED');
    return [
      if (quote != null) ...[
        Text(
            receiver['is_you'] == true
                ? t('You receive')
                : t('{name} receives', {'name': receiver['name']}),
            style: SendohTextStyles.bodyMedium),
        const SizedBox(height: 4),
        Text(coordinationMoney(quote['payout_amount']),
            style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: SendohColors.teal)),
        if (destination != null)
          Text('${walletName(destination['method'])} ${destination['masked']}',
              style: SendohTextStyles.bodyMedium),
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: busy ? null : chooseBeneficiary,
                child: Text(t('Change who receives')))),
        const SizedBox(height: 4),
        const Divider(),
        // The arithmetic, from the backend's accounting records and fee quote.
        SummaryRow(t('Group total'), coordinationMoney(raised['total'])),
        SummaryRow(
            t('Cash already with you'), coordinationMoney(raised['cash'])),
        Text(t('Not sent again. No fee on cash.'),
            style: SendohTextStyles.caption),
        SummaryRow(t('Confirmed Mobile Money'),
            coordinationMoney(quote['mobile_money'])),
        SummaryRow(t('MeSomb fees, already deducted'),
            '− ${coordinationMoney(num.tryParse('${quote['provider_fees']}')?.round())}'),
        SummaryRow(t('Sendoh settlement fee'),
            '− ${coordinationMoney(quote['sendoh_fee'])}'),
        if ((quote['payout_cost'] as num) > 0)
          SummaryRow(
              t('Payout cost'), '− ${coordinationMoney(quote['payout_cost'])}'),
        SummaryRow(t('Payout'), coordinationMoney(quote['payout_amount']),
            bold: true),
        const Divider(),
      ] else ...[
        Text(
            t('{amount} raised',
                {'amount': coordinationMoney(raised['total'])}),
            style: SendohTextStyles.headingMedium),
        SummaryRow(t('Confirmed Mobile Money'),
            coordinationMoney(raised['mobile_money'])),
        SummaryRow(
            t('Cash already with you'), coordinationMoney(raised['cash'])),
      ],
      // Name who is still confirming: the final settlement waits for them.
      for (final pending in (raised['pending'] as List? ?? const []))
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                t('Waiting for {name} · {amount} confirming', {
                  'name': pending['name'],
                  'amount': coordinationMoney(pending['amount'])
                }),
                style: SendohTextStyles.bodyMedium)),
      if (quote == null)
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: busy ? null : chooseBeneficiary,
                child: Text(receiver['is_you'] == true
                    ? t('You receive this round · Change')
                    : t('{name} receives this round · Change',
                        {'name': receiver['name']})))),
      if (blockers.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SurfaceCard(
                color: SendohColors.amberSoft,
                child: Text(blockers.first['message'] as String,
                    style: SendohTextStyles.bodyMedium))),
      const SizedBox(height: 24),
      if (needsDetails)
        FilledButton(
            onPressed: addReceivingDetails,
            child: Text(t('Add receiving number')))
      else
        FilledButton(
            onPressed: busy || quote == null || blockers.isNotEmpty
                ? null
                : closeAndSend,
            child: Text(busy ? t('Sending…') : t('Close and send'))),
    ];
  }

  List<Widget> status(Map<String, dynamic> s) {
    final state = s['state'];
    final last3 =
        (s['destination'] as String? ?? '').replaceAll('•', '').trim();
    final amount = coordinationMoney(s['payout_amount']);
    final (IconData icon, Color color, String heading, String body) =
        switch (state) {
      'DELIVERED' => (
          Icons.check_circle_outline,
          SendohColors.green,
          receiver['is_you'] == true
              ? t('Delivered to {method}', {'method': walletName(s['method'])})
              : t('Delivered to {name}', {'name': receiver['name']}),
          t('{collectionName} is settled.',
              {'collectionName': widget.collectionName})
        ),
      'REVIEW' => (
          Icons.info_outline,
          SendohColors.red,
          t('Payout needs attention'),
          s['review_reason'] == 'PAYOUT_FAILED_FUNDS_RETAINED'
              ? t('MeSomb couldn’t deliver to this number. The money is held safely and nobody is charged again.')
              : t('We’re checking this payout with MeSomb. Nothing will be sent twice.')
        ),
      _ => (
          Icons.schedule,
          SendohColors.teal,
          receiver['is_you'] == true
              ? t('Sending to {method}', {'method': walletName(s['method'])})
              : t('Sending to {name}', {'name': receiver['name']}),
          t('{collectionName} is closed. We’ll notify you when it arrives.',
              {'collectionName': widget.collectionName})
        ),
    };
    final amounts =
        Map<String, dynamic>.from((s['amounts'] as Map?) ?? const {});
    final delivered = state == 'DELIVERED';
    return [
      // Two separate events: the collection closed; the payout delivered.
      SurfaceCard(
          child: Column(children: [
        Row(children: [
          const Icon(Icons.check_circle, color: SendohColors.teal, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
                  s['round'] != null && overview?['recurring'] == true
                      ? t('Round {round} closed · no new contributions',
                          {'round': s['round']})
                      : t('Collection closed · no new contributions'),
                  style: SendohTextStyles.bodyMedium)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Icon(delivered ? Icons.check_circle : Icons.schedule,
              color: delivered ? SendohColors.teal : SendohColors.secondary,
              size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
                  delivered
                      ? t('Payout delivered')
                      : state == 'REVIEW'
                          ? t('Payout needs attention')
                          : t('Payout sending'),
                  style: SendohTextStyles.bodyMedium)),
        ]),
      ])),
      const SizedBox(height: 24),
      Icon(icon, size: 56, color: color),
      const SizedBox(height: 12),
      Text(heading,
          textAlign: TextAlign.center, style: SendohTextStyles.titleSmall),
      const SizedBox(height: 8),
      Text(amount,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: SendohColors.teal)),
      Text(t('Number ending in {last3}', {'last3': last3}),
          textAlign: TextAlign.center, style: SendohTextStyles.bodyMedium),
      const SizedBox(height: 20),
      Text(body,
          textAlign: TextAlign.center, style: SendohTextStyles.bodyMedium),
      const SizedBox(height: 16),
      if (amounts.isNotEmpty) ...[
        SummaryRow(
            t('Group total'),
            coordinationMoney(amounts['raised_total'] ??
                ((amounts['mobile_money'] as num? ?? 0) +
                    (amounts['cash'] as num? ?? 0)))),
        SummaryRow(t('Cash already with organizer'),
            coordinationMoney(amounts['cash'])),
        SummaryRow(t('Confirmed Mobile Money'),
            coordinationMoney(amounts['mobile_money'])),
        SummaryRow(t('Fees'), '− ${coordinationMoney(amounts['fees_total'])}'),
        SummaryRow(t('Payout'), amount, bold: true),
      ],
      Text(
          t('Reference: {reference}', {
            'reference':
                (s['reference'] as String).substring(0, 8).toUpperCase()
          }),
          textAlign: TextAlign.center,
          style: SendohTextStyles.caption),
      const SizedBox(height: 28),
      // Deliberately no second Send button: an unresolved payout is only looked up.
      OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('Back to collection'))),
    ];
  }
}

/// A member's own share: Mobile Money and recorded cash, never merged silently.
class MemberShareCard extends StatefulWidget {
  const MemberShareCard({super.key, required this.api, required this.item});
  final SendohApi api;
  final Map<String, dynamic> item;
  @override
  State<MemberShareCard> createState() => _MemberShareCardState();
}

class _MemberShareCardState extends State<MemberShareCard> {
  bool flagged = false, busy = false;

  Future<void> flag() async {
    setState(() => busy = true);
    try {
      await widget.api.request(
          '/collections/${widget.item['collection_id']}/cash/flag',
          body: {});
      if (mounted) {
        setState(() => flagged = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MemberPosition.fromJoined(widget.item);
    final c = Map<String, dynamic>.from(widget.item['collection'] as Map);
    final organizer = c['organizer_name'] ?? t('the organizer');
    final handle = c['organizer_handle'] as String?;
    final fulfilled = p.state == 'FULFILLED';
    final round = (c['round'] as num?)?.toInt() ?? 1;
    final showRound = c['recurring'] == true && round > 1;
    final previous = widget.item['previous_round'] as Map?;
    return SurfaceCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (showRound)
        Text(t('Round {round} · Your share', {'round': round}),
            style: SendohTextStyles.caption),
      if (fulfilled)
        Row(children: [
          const Icon(Icons.check_circle, color: SendohColors.teal, size: 22),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
                  t('Your {amount} share is paid',
                      {'amount': coordinationMoney(p.expected)}),
                  style: SendohTextStyles.titleSmall
                      .copyWith(color: SendohColors.teal))),
        ])
      else
        Text(p.expected == null ? t('Your contribution') : t('Your share'),
            style: SendohTextStyles.caption),
      const SizedBox(height: 6),
      Text(coordinationMoney(p.paid),
          style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: SendohColors.teal)),
      if (!fulfilled && p.remaining != null && p.remaining! > 0)
        Text(t('{amount} left', {'amount': coordinationMoney(p.remaining)}),
            style: SendohTextStyles.bodyMedium),
      const SizedBox(height: 8),
      SummaryRow(t('Mobile Money'), coordinationMoney(p.confirmed)),
      if (p.pending > 0)
        SummaryRow(t('Awaiting confirmation'), coordinationMoney(p.pending)),
      if (p.cash > 0) ...[
        SummaryRow(t('Cash recorded by {organizer}', {'organizer': organizer}),
            coordinationMoney(p.cash)),
        Text(
            t('Cash entry wrong? Contact {organizer}{value}.', {
              'organizer': organizer,
              'value': handle == null ? '' : ' ($handle)'
            }),
            style: SendohTextStyles.caption),
        TextButton(
            onPressed: busy || flagged ? null : flag,
            child: Text(flagged
                ? t('{organizer} has been told', {'organizer': organizer})
                : t('Flag a cash error'))),
      ],
      // An earlier round stays paid: a new share never hides it.
      if (previous != null)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(previousRoundLine(previous),
                style: SendohTextStyles.bodyMedium)),
      if (c['status'] == 'SETTLED')
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                t('Settlement delivered to {organizer}.',
                    {'organizer': organizer}),
                style: SendohTextStyles.bodyMedium)),
    ]));
  }
}

/// "Round 1 · Paid": the member's earlier round, from the snapshot taken at close.
String previousRoundLine(Map previous) {
  final round = previous['round'];
  final paid = ((previous['confirmed'] as num?) ?? 0) +
      ((previous['cash'] as num?) ?? 0);
  return switch (previous['state']) {
    'FULFILLED' || 'CONTRIBUTED' => t('Round {round} · Paid', {'round': round}),
    'PARTIAL' => t('Round {round} · {amount} of {amount2}', {
        'round': round,
        'amount': coordinationMoney(paid),
        'amount2': coordinationMoney(previous['expected'])
      }),
    _ => t('Round {round} · Not paid', {'round': round}),
  };
}

/// Review the next round before opening it: members, share, who receives, due date.
class NextRoundScreen extends StatefulWidget {
  const NextRoundScreen({super.key, required this.api, required this.data});
  final SendohApi api;
  final Map<String, dynamic> data;
  @override
  State<NextRoundScreen> createState() => _NextRoundScreenState();
}

class _NextRoundScreenState extends State<NextRoundScreen> {
  late final int next = ((widget.data['round'] as num?)?.toInt() ?? 1) + 1;
  late final bool hasShare = widget.data['mode'] != 'ANY_AMOUNT';
  late final share =
      TextEditingController(text: '${widget.data['expected_amount'] ?? ''}');
  late final List<Map<String, dynamic>> members =
      (widget.data['participants'] as List)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .where((p) => p['invitation_state'] == 'ACCEPTED')
          .toList();

  /// '' = the organizer receives; otherwise a joined member's participant id.
  String receiver = '';
  DateTime? due;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    share.dispose();
    super.dispose();
  }

  Future<void> open() async {
    final amount = int.tryParse(share.text.trim().replaceAll(',', ''));
    if (hasShare && (amount == null || amount <= 0)) {
      setState(() => error = t('Enter each member’s share in whole FCFA.'));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // from_round makes a repeated tap a safe replay, not a skipped round.
      await widget.api
          .request('/collections/${widget.data['id']}/rounds', body: {
        'from_round': next - 1,
        'beneficiary_participant_id': receiver,
        if (hasShare) 'expected_amount': amount,
        if (due != null)
          'deadline_at': DateTime.utc(due!.year, due!.month, due!.day, 22, 59)
              .toIso8601String(),
      });
      if (mounted) {
        Navigator.pop(context, true);
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

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(t('Round {next}', {'next': next}))),
      body: ListView(padding: const EdgeInsets.all(22), children: [
        Text(t('{length} members carry forward', {'length': members.length}),
            style: SendohTextStyles.titleSmall),
        Text(members.map((m) => m['name']).join(', '),
            style: SendohTextStyles.caption),
        const SizedBox(height: 16),
        if (hasShare)
          TextField(
              controller: share,
              enabled: !busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: t('Each member’s share'), suffixText: 'FCFA')),
        const SizedBox(height: 16),
        Text(t('Who receives this round'), style: SendohTextStyles.caption),
        DropdownButton<String>(
            isExpanded: true,
            value: receiver,
            items: [
              DropdownMenuItem(value: '', child: Text(t('You'))),
              ...members.where((m) => m['user_id'] != null).map((m) =>
                  DropdownMenuItem(
                      value: m['id'] as String,
                      child: Text(m['name'] as String))),
            ],
            onChanged: busy ? null : (v) => setState(() => receiver = v ?? '')),
        const SizedBox(height: 8),
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t('Due date')),
            subtitle: Text(due == null
                ? t('No due date')
                : '${due!.day}/${due!.month}/${due!.year}'),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: busy
                ? null
                : () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                        context: context,
                        initialDate: due ?? now.add(const Duration(days: 30)),
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 730)));
                    if (picked != null) {
                      setState(() => due = picked);
                    }
                  }),
        const SizedBox(height: 8),
        Text(
            t('Everyone starts Round {next} at 0 FCFA. Round {value} records and receipts stay as they are.',
                {'next': next, 'value': next - 1}),
            style: SendohTextStyles.bodyMedium),
        if (error != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!,
                  style: const TextStyle(color: SendohColors.red))),
        const SizedBox(height: 20),
        FilledButton(
            onPressed: busy ? null : open,
            child: Text(
                busy ? t('Opening…') : t('Open Round {next}', {'next': next}))),
      ]));
}
