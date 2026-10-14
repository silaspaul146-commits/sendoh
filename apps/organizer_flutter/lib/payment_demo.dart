import 'dart:math';
import 'package:flutter/material.dart';
import 'api.dart';
import 'design.dart';

String paymentKey() => List.generate(24, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();

/// Persisted test payments. The server owns identity, status and receipts.
class PaymentDemo extends StatefulWidget {
  const PaymentDemo({super.key, required this.api, required this.collectionId,
    required this.collection, required this.name, this.expected, this.existing});
  final SendohApi api;
  final String collectionId, collection, name;
  final int? expected;
  final Map<String, dynamic>? existing;
  @override
  State<PaymentDemo> createState() => _PaymentDemoState();
}

class _PaymentDemoState extends State<PaymentDemo> {
  late final amount = TextEditingController(text: widget.expected?.toString() ?? '');
  final note = TextEditingController();
  Map<String, dynamic>? payment;
  Map<String, dynamic>? submission;
  String requestKey = paymentKey(), method = 'MTN';
  String? error, pendingOutcome;
  bool busy = false, confirmed = false;
  int step = 0;

  @override
  void initState() {
    super.initState();
    payment = widget.existing;
    if (payment != null) {
      amount.text = '${payment!['amount']}';
      note.text = payment!['note'] as String? ?? '';
      method = payment!['method'] as String;
      step = payment!['status'] == 'PENDING' ? 3 : 4;
    }
  }

  @override
  void dispose() { amount.dispose(); note.dispose(); super.dispose(); }

  Future<void> run(Future<void> Function() action) async {
    if (busy) { return; }
    setState(() { busy = true; error = null; });
    try { await action(); }
    catch (e) { if (mounted) { setState(() => error = '$e'); } }
    finally { if (mounted) { setState(() => busy = false); } }
  }

  void review() {
    final n = int.tryParse(amount.text);
    if (n == null || n <= 0 || n > 1000000000000) {
      setState(() => error = 'Enter a positive whole FCFA amount.');
      return;
    }
    setState(() { error = null; step = 1; });
  }

  Future<void> create() => run(() async {
    // Retain the body AND key after a timeout; retry cannot create a duplicate.
    submission ??= {'collection_id': widget.collectionId, 'amount': int.parse(amount.text), 'method': method, 'note': note.text.trim()};
    final result = await widget.api.request('/test-payments', body: submission, key: requestKey);
    if (mounted) { setState(() { payment = Map<String, dynamic>.from(result); step = payment!['status'] == 'PENDING' ? 3 : 4; }); }
  });

  Future<void> finish(String status) => run(() async {
    pendingOutcome ??= status;
    final result = await widget.api.request('/test-payments/${payment!['id']}/simulate', body: {'status': pendingOutcome});
    if (mounted) { setState(() { payment = Map<String, dynamic>.from(result); pendingOutcome = null; step = 4; }); }
  });

  Future<void> reload({bool receipt = false}) => run(() async {
    final result = await widget.api.request('/test-payments/${payment!['id']}');
    if (mounted) { setState(() {
      payment = Map<String, dynamic>.from(result);
      if (payment!['status'] != 'PENDING') { pendingOutcome = null; }
      step = payment!['status'] == 'PENDING' ? 3 : receipt && payment!['status'] == 'SUCCEEDED' ? 5 : 4;
    }); }
  });

  void restart() => setState(() {
    requestKey = paymentKey(); payment = null; submission = null; pendingOutcome = null;
    confirmed = false; error = null; step = 0;
  });

  @override
  Widget build(BuildContext context) {
    final success = payment?['status'] == 'SUCCEEDED';
    return Scaffold(
      appBar: AppBar(title: Text(['Contribute', 'Confirm contribution', 'Choose payment method', 'Test payment', 'Payment result', 'Test receipt'][step])),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const StatusBadge('TEST • No money moves'),
        const SizedBox(height: 20),
        Text(payment?['collection_name'] ?? widget.collection, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8), Text('Contributing as ${payment?['payer_name'] ?? widget.name}'),
        const SizedBox(height: 24),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(error!, style: const TextStyle(color: SendohColors.red))),
        if (step == 0) ...[
          TextField(controller: amount, enabled: !busy, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (FCFA)')),
          const SizedBox(height: 16),
          TextField(controller: note, enabled: !busy, maxLength: 200, decoration: const InputDecoration(labelText: 'Note (optional)')),
          FilledButton(onPressed: busy ? null : review, child: const Text('Continue')),
        ],
        if (step == 1) ...[
          SummaryRow('Your contribution', '${amount.text} FCFA'),
          const SummaryRow('Test provider fee', '0 FCFA'),
          SummaryRow('Test total', '${amount.text} FCFA', bold: true),
          const Text('The full test amount goes toward the test collection total. Live pricing and collection settlement fees will be shown separately when payments launch.'),
          CheckboxListTile(contentPadding: EdgeInsets.zero, value: confirmed, onChanged: (v) => setState(() => confirmed = v ?? false), title: const Text('I confirm these details.')),
          FilledButton(onPressed: confirmed ? () => setState(() => step = 2) : null, child: const Text('Continue to payment method')),
        ],
        if (step == 2) ...[
          ...['MTN', 'ORANGE'].map((value) => Padding(padding: const EdgeInsets.only(bottom: 12), child: OutlinedButton.icon(
            onPressed: busy || submission != null ? null : () => setState(() => method = value), icon: Icon(method == value ? Icons.check_circle : Icons.circle_outlined), label: Text(value == 'MTN' ? 'MTN Mobile Money' : 'Orange Money')))),
          FilledButton(onPressed: busy ? null : create, child: Text(busy ? 'Saving payment…' : submission != null ? 'Retry same payment request' : 'Continue to pay')),
        ],
        if (step == 3) ...[
          SummaryRow('Test amount', money(payment!['amount'])),
          SummaryRow('Using', payment!['method'] == 'MTN' ? 'MTN Mobile Money' : 'Orange Money'),
          const Text('Your payment attempt is saved on Sendoh. Choose a test result; no provider is charged.'),
          const SizedBox(height: 24),
          if (pendingOutcome == null) ...[
            FilledButton(onPressed: busy ? null : () => finish('SUCCEEDED'), child: const Text('Simulate successful payment')),
            OutlinedButton(onPressed: busy ? null : () => finish('FAILED'), child: const Text('Simulate failed payment')),
            TextButton(onPressed: busy ? null : () => finish('CANCELLED'), child: const Text('Cancel test payment')),
          ] else FilledButton(onPressed: busy ? null : () => finish(pendingOutcome!), child: const Text('Retry saving this result')),
          TextButton(onPressed: busy ? null : reload, child: const Text('Refresh payment status')),
        ],
        if (step == 4) ...[
          Icon(success ? Icons.check_circle : Icons.info_outline, color: SendohColors.teal, size: 64),
          Text(success ? 'Test contribution successful' : 'Test payment ${payment!['status'].toString().toLowerCase()}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 16),
          Text(success ? 'Saved to the backend. Test totals and organizer activity have been updated. No money moved.' : 'The result is saved. This attempt did not increase the test total.'),
          FilledButton(onPressed: busy ? null : success ? () => reload(receipt: true) : restart, child: Text(success ? 'View test receipt' : 'Start a new attempt')),
        ],
        if (step == 5) ...[
          const Text('TEST • Not proof of payment', style: TextStyle(fontWeight: FontWeight.bold)),
          SummaryRow('Reference', payment!['reference']),
          SummaryRow('Amount', money(payment!['amount'])),
          SummaryRow('Method', payment!['method'] == 'MTN' ? 'MTN Mobile Money' : 'Orange Money'),
          SummaryRow('Recorded', DateTime.fromMillisecondsSinceEpoch((payment!['completed_at'] as int) * 1000).toLocal().toString()),
          if ((payment!['note'] as String).isNotEmpty) SummaryRow('Note', payment!['note']),
          const Text('Saved test receipt. No real funds were received.'),
        ],
        if (step >= 3) OutlinedButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('View collection')),
        if (step > 0 && step < 3 && submission == null) TextButton(onPressed: busy ? null : () => setState(() => step--), child: const Text('Back')),
      ]),
    );
  }
}

class TestPaymentHistory extends StatefulWidget {
  const TestPaymentHistory({super.key, required this.api, required this.collectionId, this.organizer = false});
  final SendohApi api;
  final String collectionId;
  final bool organizer;
  @override
  State<TestPaymentHistory> createState() => _TestPaymentHistoryState();
}

class _TestPaymentHistoryState extends State<TestPaymentHistory> {
  List<dynamic> rows = [];
  String? error, cursor;
  bool busy = false;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load({bool more = false}) async {
    if (busy) { return; }
    setState(() { busy = true; error = null; });
    try {
      final path = widget.organizer ? '/collections/${widget.collectionId}/test-payments?' : '/me/test-payments?collection_id=${widget.collectionId}&';
      final data = await widget.api.request('$path${more && cursor != null ? 'before=${Uri.encodeQueryComponent(cursor!)}' : ''}');
      if (mounted) { setState(() { rows = more ? [...rows, ...data['items']] : List<dynamic>.from(data['items']); cursor = data['next_cursor']; }); }
    } catch (e) { if (mounted) { setState(() => error = '$e'); } }
    finally { if (mounted) { setState(() => busy = false); } }
  }
  Future<void> open(Map<String, dynamic> p) async {
    if (widget.organizer) {
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: const Text('Test payment record'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${p['payer_name']} • ${money(p['amount'])}'), Text('${p['status']} • ${p['method']}'),
          SelectableText(p['reference']), Text(p['note'] ?? ''),
          const Text('TEST ONLY. No money moved. Not proof of payment.'),
        ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]));
    } else {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PaymentDemo(api: widget.api, collectionId: widget.collectionId,
        collection: p['collection_name'], name: p['payer_name'], existing: p)));
    }
    if (mounted) { await load(); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Test payment history'), actions: [IconButton(onPressed: busy ? null : () => load(), icon: const Icon(Icons.refresh))]),
    body: RefreshIndicator(onRefresh: () => load(), child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(22), children: [
      const Text('Saved backend records • No real money'),
      if (busy) const LinearProgressIndicator(),
      if (error != null) ...[Text(error!), TextButton(onPressed: busy ? null : () => load(), child: const Text('Retry'))],
      if (!busy && error == null && rows.isEmpty) const Text('No test payments yet.'),
      ...rows.map((raw) { final p = Map<String, dynamic>.from(raw); return ListTile(
        title: Text('${p['payer_name']} • ${money(p['amount'])}'), subtitle: Text('${p['status']} • ${p['method']}'),
        trailing: const Icon(Icons.chevron_right), onTap: () => open(p)); }),
      if (cursor != null) OutlinedButton(onPressed: busy ? null : () => load(more: true), child: const Text('Load older payments')),
    ])),
  );
}
