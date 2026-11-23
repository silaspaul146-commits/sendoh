/// Close a collection and send its Mobile Money to the organizer.
///
/// Answers three questions: How much did we raise? What will reach my phone?
/// Did my contribution count? All figures come from the server.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'contribution_checkout.dart' show paymentKey;
import 'coordination.dart' show coordinationMoney;
import 'design.dart';
import 'payment_state.dart';
import 'person_payments.dart' show ReceivingDetails;

String walletName(Object? method) =>
    method == 'ORANGE' ? 'Orange Money' : 'MTN MoMo';

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
            child: Text('Round ${data['round'] ?? 1}',
                style: SendohTextStyles.caption)),
      SurfaceCard(
          color: SendohColors.teal,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${coordinationMoney(totals.raised)} raised',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700)),
            if (totals.target != null && totals.target! > 0) ...[
              const SizedBox(height: 4),
              Text('Goal ${coordinationMoney(totals.target)}',
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
              Text('${coordinationMoney(totals.pending)} awaiting confirmation',
                  style:
                      const TextStyle(color: Color(0xFFE6FFFA), fontSize: 12)),
            ],
          ])),
      const SizedBox(height: 8),
      SummaryRow('Mobile Money', coordinationMoney(totals.confirmed)),
      SummaryRow('Cash recorded', coordinationMoney(totals.cash)),
      if (open && totals.targetReached)
        const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge('Target reached'))),
      if (open)
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: onEditCash, child: const Text('Edit cash records'))),
      const SizedBox(height: 4),
      if (recurring && status == 'SETTLED') ...[
        FilledButton(
            onPressed: onNextRound, child: const Text('Start next round')),
        const SizedBox(height: 8),
        OutlinedButton(
            onPressed: onReview, child: const Text('View settlement')),
      ] else
        FilledButton(
            onPressed: onReview,
            child: Text(open ? 'Review settlement' : 'View settlement')),
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
        setState(() => error = 'Enter whole FCFA amounts.');
        return;
      }
      if (amount != MemberPosition.fromMember(p).cash) {
        entries.add({'participant_id': p['id'], 'amount': amount});
      }
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (entries.isNotEmpty) {
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
      appBar: AppBar(title: const Text('Cash received')),
      body: ListView(padding: const EdgeInsets.all(22), children: [
        const Text(
            'Add money members gave you in person. It stays labelled as cash you recorded, separate from Mobile Money.',
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
                          '${coordinationMoney(position.confirmed)} by Mobile Money'
                          '${position.expected == null ? '' : ' · ${coordinationMoney(position.expected)} expected'}',
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
                            labelText: 'Cash',
                            hintText: '0',
                            semanticCounterText: 'Cash from ${p['name']}'))),
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
            child: Text(busy ? 'Saving…' : 'Save cash records')),
      ]));
}

/// Review, then the same screen follows the payout: Sending → Delivered.
class SettlementScreen extends StatefulWidget {
  const SettlementScreen(
      {super.key,
      required this.api,
      required this.collectionId,
      required this.collectionName});
  final SendohApi api;
  final String collectionId, collectionName;
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
        setState(() => error = e.message);
      }
    } catch (_) {
      // Unknown outcome: read the saved state; the same key replays safely.
      await load();
      if (mounted && settlement == null) {
        setState(() => error =
            'Couldn’t confirm. Try again: the same request is reused, so nothing is sent twice.');
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
                const ListTile(
                    title: Text('Who receives this round?',
                        style: SendohTextStyles.titleSmall)),
                ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('You'),
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

  @override
  Widget build(BuildContext context) {
    final s = settlement;
    return Scaffold(
        appBar: AppBar(
            title:
                Text(s == null ? 'Review settlement' : widget.collectionName)),
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
                  const Text('Sandbox · no real money moves',
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
                ? 'You receive'
                : '${receiver['name']} receives',
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
                child: const Text('Change who receives'))),
        const SizedBox(height: 4),
        const Divider(),
        SummaryRow(
            'Mobile Money collected', coordinationMoney(quote['mobile_money'])),
        InkWell(
            onTap: () => setState(() => showFees = !showFees),
            child: Row(children: [
              Expanded(
                  child: SummaryRow(
                      'Fees', coordinationMoney(quote['fees_total']))),
              Icon(showFees ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  semanticLabel: showFees ? 'Hide fees' : 'Show fees'),
            ])),
        if (showFees) ...[
          SummaryRow(
              'MeSomb collection fees', '${quote['provider_fees']} FCFA'),
          SummaryRow(
              'Sendoh settlement fee', coordinationMoney(quote['sendoh_fee'])),
          if ((quote['payout_cost'] as num) > 0)
            SummaryRow('Payout cost', coordinationMoney(quote['payout_cost'])),
        ],
        const Divider(),
      ] else
        Text('${coordinationMoney(raised['total'])} raised',
            style: SendohTextStyles.headingMedium),
      if ((raised['cash'] as num) > 0)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                'You already hold ${coordinationMoney(raised['cash'])} in cash.',
                style: SendohTextStyles.bodyMedium)),
      if (quote == null)
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: busy ? null : chooseBeneficiary,
                child: Text(receiver['is_you'] == true
                    ? 'You receive this round · Change'
                    : '${receiver['name']} receives this round · Change'))),
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
            child: const Text('Add receiving number'))
      else
        FilledButton(
            onPressed: busy || quote == null || blockers.isNotEmpty
                ? null
                : closeAndSend,
            child: Text(busy ? 'Sending…' : 'Close and send')),
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
              ? 'Delivered to ${walletName(s['method'])}'
              : 'Delivered to ${receiver['name']}',
          '${widget.collectionName} is settled.'
        ),
      'REVIEW' => (
          Icons.info_outline,
          SendohColors.red,
          'Payout needs attention',
          s['review_reason'] == 'PAYOUT_FAILED_FUNDS_RETAINED'
              ? 'MeSomb couldn’t deliver to this number. The money is held safely and nobody is charged again.'
              : 'We’re checking this payout with MeSomb. Nothing will be sent twice.'
        ),
      _ => (
          Icons.schedule,
          SendohColors.teal,
          receiver['is_you'] == true
              ? 'Sending to ${walletName(s['method'])}'
              : 'Sending to ${receiver['name']}',
          '${widget.collectionName} is closed. We’ll notify you when it arrives.'
        ),
    };
    return [
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
      Text('Number ending in $last3',
          textAlign: TextAlign.center, style: SendohTextStyles.bodyMedium),
      const SizedBox(height: 20),
      Text(body,
          textAlign: TextAlign.center, style: SendohTextStyles.bodyMedium),
      const SizedBox(height: 16),
      Text(
          'Reference: ${(s['reference'] as String).substring(0, 8).toUpperCase()}',
          textAlign: TextAlign.center,
          style: SendohTextStyles.caption),
      const SizedBox(height: 28),
      // Deliberately no second Send button: an unresolved payout is only looked up.
      OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to collection')),
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
    final organizer = c['organizer_name'] ?? 'the organizer';
    final fulfilled = p.state == 'FULFILLED';
    return SurfaceCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (fulfilled)
        Row(children: [
          const Icon(Icons.check_circle, color: SendohColors.teal, size: 22),
          const SizedBox(width: 8),
          Expanded(
              child: Text('Your ${coordinationMoney(p.expected)} share is paid',
                  style: SendohTextStyles.titleSmall
                      .copyWith(color: SendohColors.teal))),
        ])
      else
        Text(p.expected == null ? 'Your contribution' : 'Your share',
            style: SendohTextStyles.caption),
      const SizedBox(height: 6),
      Text(coordinationMoney(p.paid),
          style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: SendohColors.teal)),
      if (!fulfilled && p.remaining != null && p.remaining! > 0)
        Text('${coordinationMoney(p.remaining)} remaining',
            style: SendohTextStyles.bodyMedium),
      const SizedBox(height: 8),
      SummaryRow('Mobile Money', coordinationMoney(p.confirmed)),
      if (p.pending > 0)
        SummaryRow('Awaiting confirmation', coordinationMoney(p.pending)),
      if (p.cash > 0) ...[
        SummaryRow('Cash recorded by $organizer', coordinationMoney(p.cash)),
        TextButton(
            onPressed: busy || flagged ? null : flag,
            child: Text(
                flagged ? '$organizer has been told' : 'Flag a cash error')),
      ],
      if (c['status'] == 'SETTLED')
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Settlement delivered to $organizer.',
                style: SendohTextStyles.bodyMedium)),
    ]));
  }
}
