import 'i18n.dart';
import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'design.dart';
import 'coordination.dart' show coordinationMoney, MemberPosition;

String paymentKey() => List.generate(24,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
    .join();

/// Provider-backed contributions using the existing checkout layout.
class ContributionCheckout extends StatefulWidget {
  const ContributionCheckout(
      {super.key,
      required this.api,
      required this.collectionId,
      required this.collection,
      required this.name,
      this.expected,
      this.existing});
  final SendohApi api;
  final String collectionId, collection, name;
  final int? expected;
  final Map<String, dynamic>? existing;
  @override
  State<ContributionCheckout> createState() => _ContributionCheckoutState();
}

class _ContributionCheckoutState extends State<ContributionCheckout> {
  late final amount =
      TextEditingController(text: widget.expected?.toString() ?? '');
  final note = TextEditingController();
  Map<String, dynamic>? payment;
  Map<String, dynamic>? submission;

  /// The backend's review terms. A quote creates nothing and charges nothing.
  Map<String, dynamic>? quote;

  /// Where the payer's own share stands after a verified contribution.
  String? standing;
  String requestKey = paymentKey(), method = 'MTN';
  String? error, storageKey;
  Timer? poll;
  final phone = TextEditingController();
  final storage = const FlutterSecureStorage();
  bool ready = false;
  bool busy = false, confirmed = false;
  int step = 0;

  @override
  void initState() {
    super.initState();
    payment = widget.existing;
    restore();
    if (payment != null) {
      amount.text = '${payment!['amount']}';
      note.text = payment!['note'] as String? ?? '';
      method = payment!['method'] as String;
      step = payment!['status'] == 'PENDING' ? 3 : 4;
    }
  }

  @override
  void dispose() {
    poll?.cancel();
    phone.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Duration pollDelay = const Duration(seconds: 5);

  /// Quiet background checks with backoff: no busy bar, no disabled buttons.
  /// "Refresh payment status" remains the explicit, visible check.
  void schedule() {
    poll?.cancel();
    if (payment?['status'] == 'SUCCEEDED' && standing == null) {
      loadStanding();
    }
    if (mounted && payment?['status'] == 'PENDING') {
      poll = Timer(pollDelay, () async {
        await quietCheck();
        final next = pollDelay.inSeconds * 2;
        pollDelay = Duration(seconds: next > 60 ? 60 : next);
        schedule();
      });
    }
  }

  Future<void> quietCheck() async {
    if (busy || payment == null || !mounted) {
      return;
    }
    try {
      final result = await widget.api.request(
          '/provider-payments/${payment!['id']}/refresh',
          body: <String, dynamic>{});
      if (mounted && !busy) {
        setState(() {
          payment = Map<String, dynamic>.from(result);
          if (payment!['status'] != 'PENDING') {
            step = 4;
          }
        });
        if (payment!['status'] == 'SUCCEEDED') {
          loadStanding();
        }
      }
    } catch (_) {
      // The next check, or the explicit refresh, retries.
    }
  }

  Future<void> restore() async {
    await run(() async {
      final me = await widget.api.request('/me');
      storageKey =
          'sendoh-payment:${widget.api.baseUrl}:${me['id']}:${widget.collectionId}';
      if (payment == null) {
        final saved = await storage.read(key: storageKey!);
        if (saved != null) {
          final draft = jsonDecode(saved) as Map<String, dynamic>;
          requestKey = draft['key'] as String;
          submission = Map<String, dynamic>.from(draft['body']);
          amount.text = '${submission!['amount']}';
          method = submission!['method'] as String;
          phone.text = submission!['payer_phone'] as String;
          step = 2;
          try {
            quote = await fetchQuote();
          } catch (_) {
            // Recovery still works without the review terms.
          }
          if (draft['id'] != null) {
            payment = Map<String, dynamic>.from(
                await widget.api.request('/provider-payments/${draft['id']}'));
            step = payment!['status'] == 'PENDING' ? 3 : 4;
          }
        }
        final history = await widget.api.request(
            '/me/provider-payments?payer_only=true&collection_id=${Uri.encodeQueryComponent(widget.collectionId)}');
        final pending =
            (history['items'] as List).where((p) => p['status'] == 'PENDING');
        if (pending.isNotEmpty && payment == null) {
          payment = Map<String, dynamic>.from(pending.first);
          step = 3;
        }
      }
      if (mounted) {
        setState(() => ready = true);
      }
    });
    schedule();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
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

  Future<Map<String, dynamic>> fetchQuote() async => Map<String, dynamic>.from(
      await widget.api.request('/provider-payments/quote',
          body: submission ??
              {
                'collection_id': widget.collectionId,
                'amount': int.parse(amount.text),
                'method': method,
                'payer_phone': phone.text.trim()
              }));

  Future<void> reviewQuote() => run(() async {
        if (!RegExp(r'^(?:\+237)?6[0-9]{8}$').hasMatch(phone.text.trim())) {
          throw FormatException(t('Enter a valid Mobile Money number.'));
        }
        final q = await fetchQuote();
        if (mounted) {
          setState(() {
            quote = q;
            step = 2;
          });
        }
      });

  /// Read the member's own position from the server after confirmation.
  Future<void> loadStanding() async {
    try {
      final joined = await widget.api.request('/me/joined-collections');
      final item = (joined as List)
          .map((j) => Map<String, dynamic>.from(j))
          .where((j) => j['collection_id'] == widget.collectionId)
          .firstOrNull;
      if (item != null && mounted) {
        setState(() => standing =
            MemberPosition.fromJoined(item).personalLine(coordinationMoney));
      }
    } catch (_) {
      // The collection screen shows it on return.
    }
  }

  void review() {
    final n = int.tryParse(amount.text);
    if (n == null || n <= 0 || n > 1000000000) {
      setState(() => error = t('Enter a positive whole FCFA amount.'));
      return;
    }
    setState(() {
      error = null;
      step = 1;
    });
  }

  Future<void> create() => run(() async {
        if (!ready || storageKey == null) {
          return;
        }
        if (!RegExp(r'^(?:\+237)?6[0-9]{8}$').hasMatch(phone.text.trim())) {
          throw FormatException(t('Enter a valid Mobile Money number.'));
        }
        submission ??= {
          'collection_id': widget.collectionId,
          'amount': int.parse(amount.text),
          'method': method,
          'payer_phone': phone.text.trim()
        };
        await storage.write(
            key: storageKey!,
            value: jsonEncode({'key': requestKey, 'body': submission}));
        final result = await widget.api
            .request('/provider-payments', body: submission, key: requestKey);
        await storage.write(
            key: storageKey!,
            value: jsonEncode(
                {'key': requestKey, 'body': submission, 'id': result['id']}));
        if (mounted) {
          setState(() {
            payment = Map<String, dynamic>.from(result);
            step = payment!['status'] == 'PENDING' ? 3 : 4;
          });
        }
      });

  Future<void> reload({bool receipt = false}) => run(() async {
        final result = await widget.api.request(
            '/provider-payments/${payment!['id']}/refresh',
            body: <String, dynamic>{});
        if (mounted) {
          setState(() {
            payment = Map<String, dynamic>.from(result);
            if (payment!['status'] != 'PENDING') {
              poll?.cancel();
            }
            step = payment!['status'] == 'PENDING'
                ? 3
                : receipt && payment!['status'] == 'SUCCEEDED'
                    ? 5
                    : 4;
          });
          if (payment!['status'] == 'SUCCEEDED' && standing == null) {
            loadStanding();
          }
        }
      });

  Future<void> restart() => run(() async {
        if (storageKey != null) {
          await storage.delete(key: storageKey!);
        }
        if (!mounted) {
          return;
        }
        setState(() {
          requestKey = paymentKey();
          payment = null;
          submission = null;
          poll?.cancel();
          confirmed = false;
          error = null;
          step = 0;
        });
      });

  @override
  Widget build(BuildContext context) {
    final success = payment?['status'] == 'SUCCEEDED';
    return Scaffold(
      appBar: AppBar(
          title: Text([
        t('Contribute'),
        t('Confirm contribution'),
        t('Choose payment method'),
        t('Contribution status'),
        t('Payment result'),
        t('Contribution record')
      ][step])),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        if (step < 4) ...[
          Text(t('Step {value} of 4', {'value': step + 1}),
              style:
                  const TextStyle(fontSize: 12, color: SendohColors.secondary)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
              value: (step + 1) / 4,
              color: SendohColors.teal,
              backgroundColor: SendohColors.tealSoft),
          const SizedBox(height: 16),
        ],
        Text(t('Sandbox · no real money moves'),
            style: TextStyle(fontSize: 12, color: SendohColors.secondary)),
        const SizedBox(height: 20),
        Text(payment?['collection_name'] ?? widget.collection,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(t('Contributing as {payer_name}',
            {'payer_name': payment?['payer_name'] ?? widget.name})),
        const SizedBox(height: 24),
        if (busy) const LinearProgressIndicator(),
        if (!ready && !busy)
          TextButton(onPressed: restore, child: Text(t('Reconnect'))),
        if (error != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(error!,
                  style: const TextStyle(color: SendohColors.red))),
        if (step == 0) ...[
          TextField(
              controller: amount,
              enabled: !busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: t('Amount (FCFA)'))),
          const SizedBox(height: 12),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <int>{
                500,
                1000,
                2000,
                if (widget.expected != null) widget.expected!
              }
                  .where((v) => v > 0)
                  .map((value) => ActionChip(
                      label: Text(coordinationMoney(value)),
                      onPressed: busy
                          ? null
                          : () => setState(() => amount.text = '$value')))
                  .toList()),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: busy || !ready ? null : review,
              child: Text(t('Continue'))),
        ],
        if (step == 1) ...[
          SummaryRow(t('Your contribution'),
              coordinationMoney(int.tryParse(amount.text))),
          const SizedBox(height: 12),
          ...['MTN', 'ORANGE'].map((value) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                  onPressed: busy || submission != null
                      ? null
                      : () => setState(() => method = value),
                  icon: Icon(method == value
                      ? Icons.check_circle
                      : Icons.circle_outlined),
                  label: Text(value == 'MTN'
                      ? t('MTN Mobile Money')
                      : t('Orange Money'))))),
          TextField(
              controller: phone,
              enabled: !busy && submission == null,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: t('Mobile Money number'))),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: busy || !ready ? null : reviewQuote,
              child: Text(t('Review contribution'))),
        ],
        if (step == 2) ...[
          if (quote != null) ...[
            Text(coordinationMoney(quote!['total']),
                style: SendohTextStyles.displayLarge),
            const SizedBox(height: 8),
            SummaryRow(t('Credited to'),
                '${quote!['credited_to']['name']} · ${quote!['credited_to']['collection']}'),
            SummaryRow(t('Organizer'), '${quote!['credited_to']['organizer']}'),
            SummaryRow(t('Pay with'),
                '${quote!['method'] == 'MTN' ? 'MTN MoMo' : 'Orange Money'} ${quote!['payer_masked']}'),
            SummaryRow(
                t('Contribution'), coordinationMoney(quote!['contribution'])),
            SummaryRow(t('Fees'), coordinationMoney(quote!['payer_fees'])),
            SummaryRow(
                t('Total to approve'), coordinationMoney(quote!['total']),
                bold: true),
            if (quote!['fees_from'] == 'COLLECTION_PROCEEDS')
              Text(
                  t('MeSomb’s processing fee is taken from the collection, not added to your total.'),
                  style: SendohTextStyles.caption),
          ] else
            Text(t('Getting your payment details…')),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: busy || !ready || (quote == null && submission == null)
                  ? null
                  : () async {
                      await create();
                      schedule();
                    },
              child: Text(busy
                  ? t('Saving payment…')
                  : submission != null
                      ? t('Recover contribution')
                      : t('Approve {amount}',
                          {'amount': coordinationMoney(quote?['total'])}))),
        ],
        if (step == 3) ...[
          // The backend decides between approval and confirmation; never "failed" on a timeout.
          Semantics(
              liveRegion: true,
              child: Text(
                  payment!['phase'] == 'AWAITING_APPROVAL'
                      ? t('Approve on your phone')
                      : t('Confirming your payment'),
                  style: SendohTextStyles.headingMedium)),
          const SizedBox(height: 8),
          SummaryRow(t('Amount'), coordinationMoney(payment!['amount'])),
          SummaryRow(
              t('Using'),
              '${payment!['method'] == 'MTN' ? 'MTN MoMo' : 'Orange Money'} ${payment!['payer_masked'] ?? ''}'
                  .trim()),
          Text(payment!['phase'] == 'AWAITING_APPROVAL'
              ? t('Check your phone for the Mobile Money prompt and approve it there.')
              : t('We’re checking with Mobile Money. Please don’t pay again. You can leave and come back; this payment will be here.')),
          const SizedBox(height: 24),
          TextButton(
              onPressed: busy ? null : reload,
              child: Text(t('Refresh payment status'))),
        ],
        if (step == 4) ...[
          Icon(success ? Icons.check_circle : Icons.info_outline,
              color: SendohColors.teal, size: 64),
          Text(
              success
                  ? t('Contribution confirmed')
                  : t('Contribution {status}',
                      {'status': payment!['status'].toString().toLowerCase()}),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 16),
          if (success && standing != null)
            Text(standing!,
                textAlign: TextAlign.center,
                style: SendohTextStyles.titleSmall
                    .copyWith(color: SendohColors.teal)),
          Text(success
              ? t('Your contribution counts toward {collection_name}.', {
                  'collection_name':
                      payment?['collection_name'] ?? widget.collection
                })
              : t('This attempt has not added to the collection total. You can try again.')),
          FilledButton(
              onPressed: busy
                  ? null
                  : success
                      ? () => reload(receipt: true)
                      : restart,
              child:
                  Text(success ? t('View record') : t('Start a new attempt'))),
        ],
        if (step == 5) ...[
          Text(t('Sandbox contribution record'),
              style: TextStyle(fontWeight: FontWeight.bold)),
          SummaryRow(t('Reference'), payment!['reference']),
          SummaryRow(t('Amount'), coordinationMoney(payment!['amount'])),
          SummaryRow(
              t('Method'),
              payment!['method'] == 'MTN'
                  ? t('MTN Mobile Money')
                  : t('Orange Money')),
          SummaryRow(
              t('Recorded'),
              DateTime.fromMillisecondsSinceEpoch(((payment!['updated_at'] ??
                          payment!['completed_at']) as int) *
                      1000)
                  .toLocal()
                  .toString()),
          if ((payment!['note'] as String? ?? '').isNotEmpty)
            SummaryRow(t('Note'), payment!['note']),
          Text(t('Sandbox record · Not proof of live payment.')),
        ],
        if (step >= 4 && success)
          TextButton(
              onPressed: busy ? null : restart,
              child: Text(t('Make another contribution'))),
        if (step >= 3)
          OutlinedButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: Text(t('View collection'))),
        if (step > 0 && step < 3 && submission == null)
          TextButton(
              onPressed: busy ? null : () => setState(() => step--),
              child: Text(t('Back'))),
      ]),
    );
  }
}

class ContributionHistory extends StatefulWidget {
  const ContributionHistory(
      {super.key,
      required this.api,
      required this.collectionId,
      this.organizer = false});
  final SendohApi api;
  final String collectionId;
  final bool organizer;
  @override
  State<ContributionHistory> createState() => _ContributionHistoryState();
}

class _ContributionHistoryState extends State<ContributionHistory> {
  List<dynamic> rows = [];
  String? error, cursor;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false}) async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // Server-filtered to this collection. Organizers see contributions to it;
      // members see only their own.
      final query = StringBuffer(
          '/me/provider-payments?collection_id=${Uri.encodeQueryComponent(widget.collectionId)}');
      if (!widget.organizer) {
        query.write('&payer_only=true');
      }
      if (more && cursor != null) {
        query.write('&before=${Uri.encodeQueryComponent(cursor!)}');
      }
      final data = await widget.api.request(query.toString());
      final items = data['items'] as List;
      if (mounted) {
        setState(() {
          rows = more ? [...rows, ...items] : List<dynamic>.from(items);
          cursor = data['next_cursor'];
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = t('Couldn’t load contributions. Try again.'));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> open(Map<String, dynamic> p) async {
    if (widget.organizer) {
      await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                  title: Text(contributionTitle(p)),
                  content: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        SummaryRow(
                            t('Status'), contributionStatusLabel(p['status'])),
                        SummaryRow(t('Method'), methodLabel(p['method'])),
                        SummaryRow(t('Reference'), p['reference']),
                        const SizedBox(height: 8),
                        Text(t('Sandbox record · no real money moved.'),
                            style: TextStyle(
                                fontSize: 12, color: SendohColors.secondary)),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(t('Close')))
                  ]));
    } else {
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ContributionCheckout(
              api: widget.api,
              collectionId: widget.collectionId,
              collection: p['collection_name'] ?? t('Collection'),
              name: p['payer_name'] ?? t('your verified profile'),
              existing: p)));
    }
    if (mounted) {
      await load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(t('Contributions')), actions: [
          IconButton(
              tooltip: t('Refresh'),
              onPressed: busy ? null : () => load(),
              icon: const Icon(Icons.refresh))
        ]),
        body: RefreshIndicator(
            onRefresh: () => load(),
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(22),
                children: [
                  Text(t('Sandbox · no real money moves'),
                      style: TextStyle(
                          fontSize: 12, color: SendohColors.secondary)),
                  const SizedBox(height: 8),
                  if (busy) const LinearProgressIndicator(),
                  if (error != null) ...[
                    Text(error!),
                    TextButton(
                        onPressed: busy ? null : () => load(),
                        child: Text(t('Retry')))
                  ],
                  if (!busy && error == null && rows.isEmpty)
                    Text(t('No contributions yet.')),
                  ...rows.map((raw) {
                    final p = Map<String, dynamic>.from(raw);
                    return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(contributionTitle(p)),
                        subtitle: Text(
                            '${contributionStatusLabel(p['status'])} · ${methodLabel(p['method'])}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => open(p));
                  }),
                  if (cursor != null)
                    OutlinedButton(
                        onPressed: busy ? null : () => load(more: true),
                        child: Text(t('Load older contributions'))),
                ])),
      );
}

String contributionTitle(Map<String, dynamic> p) =>
    '${p['payer_name'] ?? t('Contribution')} · ${coordinationMoney(p['amount'])}';

String contributionStatusLabel(Object? status) => switch (status) {
      'PENDING' => t('Awaiting confirmation'),
      'SUCCEEDED' => t('Confirmed'),
      'FAILED' => t('Unsuccessful'),
      'REFUNDED' => t('Refunded'),
      _ => t('Unknown'),
    };

String methodLabel(Object? method) =>
    method == 'MTN' ? t('MTN Mobile Money') : t('Orange Money');
