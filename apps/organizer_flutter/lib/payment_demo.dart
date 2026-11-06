import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'design.dart';
import 'coordination.dart' show coordinationMoney;

String paymentKey() => List.generate(24,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
    .join();

/// Provider-backed contributions using the existing checkout layout.
class PaymentDemo extends StatefulWidget {
  const PaymentDemo(
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
  State<PaymentDemo> createState() => _PaymentDemoState();
}

class _PaymentDemoState extends State<PaymentDemo> {
  late final amount =
      TextEditingController(text: widget.expected?.toString() ?? '');
  final note = TextEditingController();
  Map<String, dynamic>? payment;
  Map<String, dynamic>? submission;
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

  bool get legacy => payment != null && payment!['provider'] != 'MESOMB';

  void schedule() {
    poll?.cancel();
    if (mounted && payment?['status'] == 'PENDING' && !legacy) {
      poll = Timer(const Duration(seconds: 5), () async {
        await reload();
        schedule();
      });
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
          if (draft['id'] != null) {
            payment = Map<String, dynamic>.from(
                await widget.api.request('/provider-payments/${draft['id']}'));
            step = payment!['status'] == 'PENDING' ? 3 : 4;
          }
        }
        final history = await widget.api.request('/me/provider-payments');
        final pending = (history['items'] as List).where((p) =>
            p['collection_id'] == widget.collectionId &&
            p['payer_id'] == me['id'] &&
            p['status'] == 'PENDING');
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

  void review() {
    final n = int.tryParse(amount.text);
    if (n == null || n <= 0 || n > 1000000000) {
      setState(() => error = 'Enter a positive whole FCFA amount.');
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
          throw const FormatException('Enter a valid Mobile Money number.');
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
            legacy
                ? '/test-payments/${payment!['id']}'
                : '/provider-payments/${payment!['id']}/refresh',
            body: legacy ? null : <String, dynamic>{});
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
        'Contribute',
        'Confirm contribution',
        'Choose payment method',
        'Contribution status',
        'Payment result',
        'Contribution record'
      ][step])),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        if (step < 4) ...[
          Text('Step ${step + 1} of 4',
              style:
                  const TextStyle(fontSize: 12, color: SendohColors.secondary)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
              value: (step + 1) / 4,
              color: SendohColors.teal,
              backgroundColor: SendohColors.tealSoft),
          const SizedBox(height: 16),
        ],
        const Text('Test environment',
            style: TextStyle(fontSize: 12, color: SendohColors.secondary)),
        const SizedBox(height: 20),
        Text(payment?['collection_name'] ?? widget.collection,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Contributing as ${payment?['payer_name'] ?? widget.name}'),
        const SizedBox(height: 24),
        if (busy) const LinearProgressIndicator(),
        if (!ready && !busy)
          TextButton(onPressed: restore, child: const Text('Reconnect')),
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
              decoration: const InputDecoration(labelText: 'Amount (FCFA)')),
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
              child: const Text('Continue')),
        ],
        if (step == 1) ...[
          SummaryRow('Your contribution', '${amount.text} FCFA'),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: confirmed,
              onChanged: (v) => setState(() => confirmed = v ?? false),
              title: const Text('I confirm these details.')),
          FilledButton(
              onPressed: confirmed ? () => setState(() => step = 2) : null,
              child: const Text('Continue to payment method')),
        ],
        if (step == 2) ...[
          ...['MTN', 'ORANGE'].map((value) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                  onPressed: busy || submission != null
                      ? null
                      : () => setState(() => method = value),
                  icon: Icon(method == value
                      ? Icons.check_circle
                      : Icons.circle_outlined),
                  label: Text(
                      value == 'MTN' ? 'MTN Mobile Money' : 'Orange Money')))),
          TextField(
              controller: phone,
              enabled: !busy && submission == null,
              keyboardType: TextInputType.phone,
              decoration:
                  const InputDecoration(labelText: 'Mobile Money number')),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: busy || !ready
                  ? null
                  : () async {
                      await create();
                      schedule();
                    },
              child: Text(busy
                  ? 'Saving payment…'
                  : submission != null
                      ? 'Recover contribution'
                      : 'Continue to pay')),
        ],
        if (step == 3) ...[
          SummaryRow('Amount', coordinationMoney(payment!['amount'])),
          SummaryRow(
              'Using',
              payment!['method'] == 'MTN'
                  ? 'MTN Mobile Money'
                  : 'Orange Money'),
          const Text(
              'Confirming your contribution. You can return to the collection while we check the result.'),
          const SizedBox(height: 24),
          TextButton(
              onPressed: busy ? null : reload,
              child: const Text('Refresh payment status')),
        ],
        if (step == 4) ...[
          Icon(success ? Icons.check_circle : Icons.info_outline,
              color: SendohColors.teal, size: 64),
          Text(
              success
                  ? 'Contribution confirmed'
                  : 'Contribution ${payment!['status'].toString().toLowerCase()}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 16),
          Text(success
              ? 'Your contribution has been recorded. Return to the collection to see the updated progress.'
              : 'This attempt has not added to the collection total.'),
          FilledButton(
              onPressed: busy
                  ? null
                  : success
                      ? () => reload(receipt: true)
                      : restart,
              child: Text(success ? 'View record' : 'Start a new attempt')),
        ],
        if (step == 5) ...[
          const Text('Test environment · Contribution record',
              style: TextStyle(fontWeight: FontWeight.bold)),
          SummaryRow('Reference', payment!['reference']),
          SummaryRow('Amount', coordinationMoney(payment!['amount'])),
          SummaryRow(
              'Method',
              payment!['method'] == 'MTN'
                  ? 'MTN Mobile Money'
                  : 'Orange Money'),
          SummaryRow(
              'Recorded',
              DateTime.fromMillisecondsSinceEpoch(((payment!['updated_at'] ??
                          payment!['completed_at']) as int) *
                      1000)
                  .toLocal()
                  .toString()),
          if ((payment!['note'] as String? ?? '').isNotEmpty)
            SummaryRow('Note', payment!['note']),
          const Text('Sandbox record · Not proof of live payment.'),
        ],
        if (step >= 4 && success)
          TextButton(
              onPressed: busy ? null : restart,
              child: const Text('Make another contribution')),
        if (step >= 3)
          OutlinedButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('View collection')),
        if (step > 0 && step < 3 && submission == null)
          TextButton(
              onPressed: busy ? null : () => setState(() => step--),
              child: const Text('Back')),
      ]),
    );
  }
}

class TestPaymentHistory extends StatefulWidget {
  const TestPaymentHistory(
      {super.key,
      required this.api,
      required this.collectionId,
      this.organizer = false});
  final SendohApi api;
  final String collectionId;
  final bool organizer;
  @override
  State<TestPaymentHistory> createState() => _TestPaymentHistoryState();
}

class _TestPaymentHistoryState extends State<TestPaymentHistory> {
  List<dynamic> rows = [];
  String? error, cursor;
  bool busy = false, legacy = false;
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
      final path = widget.organizer
          ? '/collections/${widget.collectionId}/test-payments?'
          : '/me/test-payments?collection_id=${widget.collectionId}&';
      final data = await widget.api.request(legacy
          ? '$path${more && cursor != null ? 'before=${Uri.encodeQueryComponent(cursor!)}' : ''}'
          : '/me/provider-payments');
      final items = (data['items'] as List)
          .where((p) => legacy || p['collection_id'] == widget.collectionId)
          .toList();
      if (mounted) {
        setState(() {
          rows = more ? [...rows, ...items] : List<dynamic>.from(items);
          cursor = data['next_cursor'];
        });
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

  Future<void> open(Map<String, dynamic> p) async {
    if (widget.organizer) {
      await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Contribution record'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        '${p['payer_name'] ?? 'Contribution'} • ${coordinationMoney(p['amount'])}'),
                    Text('${p['status']} • ${p['method']}'),
                    SelectableText(p['reference']),
                    Text(p['note'] ?? ''),
                    const Text('Test environment · Not proof of live payment.'),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'))
                  ]));
    } else {
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PaymentDemo(
              api: widget.api,
              collectionId: widget.collectionId,
              collection: p['collection_name'] ?? 'Collection',
              name: p['payer_name'] ?? 'your verified profile',
              existing: p)));
    }
    if (mounted) {
      await load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Contribution history'), actions: [
          IconButton(
              onPressed: busy ? null : () => load(),
              icon: const Icon(Icons.refresh))
        ]),
        body: RefreshIndicator(
            onRefresh: () => load(),
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(22),
                children: [
                  const Text('Test environment'),
                  SwitchListTile(
                      title: const Text('Previous simulator records'),
                      value: legacy,
                      onChanged: busy
                          ? null
                          : (value) {
                              setState(() {
                                legacy = value;
                                rows = [];
                                cursor = null;
                              });
                              load();
                            }),
                  if (busy) const LinearProgressIndicator(),
                  if (error != null) ...[
                    Text(error!),
                    TextButton(
                        onPressed: busy ? null : () => load(),
                        child: const Text('Retry'))
                  ],
                  if (!busy && error == null && rows.isEmpty)
                    const Text('No contributions yet.'),
                  ...rows.map((raw) {
                    final p = Map<String, dynamic>.from(raw);
                    return ListTile(
                        title: Text(
                            '${p['payer_name'] ?? 'Contribution'} • ${coordinationMoney(p['amount'])}'),
                        subtitle: Text('${p['status']} • ${p['method']}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => open(p));
                  }),
                  if (cursor != null)
                    OutlinedButton(
                        onPressed: busy ? null : () => load(more: true),
                        child: const Text('Load older payments')),
                ])),
      );
}
