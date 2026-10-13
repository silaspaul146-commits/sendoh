import 'package:flutter/material.dart';
import 'design.dart';

/// Local simulation only: no provider call, database write or real receipt.
class PaymentDemo extends StatefulWidget {
  const PaymentDemo({super.key, required this.collection, required this.name, this.expected});
  final String collection, name;
  final int? expected;
  @override
  State<PaymentDemo> createState() => _PaymentDemoState();
}
class _PaymentDemoState extends State<PaymentDemo> {
  late final amount = TextEditingController(text: widget.expected?.toString() ?? '');
  final note = TextEditingController();
  int step = 0;
  String method = 'MTN Mobile Money', outcome = '', reference = '';
  bool confirmed = false;
  String? error;
  @override
  void dispose() { amount.dispose(); note.dispose(); super.dispose(); }
  void next() {
    final n = int.tryParse(amount.text);
    if (n == null || n <= 0 || n > 1000000000000) {
      setState(() => error = 'Enter a positive whole FCFA amount.'); return;
    }
    setState(() { error = null; step++; });
  }
  void finish(String result) => setState(() { outcome = result; reference = 'DEMO-${DateTime.now().millisecondsSinceEpoch}'; step = 4; });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(['Contribute', 'Confirm contribution', 'Choose payment method', 'Payment demo', 'Demo result', 'Demo receipt'][step])),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      const StatusBadge('DEMO • No money moves'),
      const SizedBox(height: 20),
      Text(widget.collection, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8), Text('Contributing as ${widget.name}'),
      const SizedBox(height: 24),
      if (step == 0) ...[
        TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (FCFA)')),
        const SizedBox(height: 16),
        TextField(controller: note, maxLength: 200, decoration: const InputDecoration(labelText: 'Note (optional)')),
        if (error != null) Text(error!, style: const TextStyle(color: SendohColors.red)),
        FilledButton(onPressed: next, child: const Text('Continue')),
      ],
      if (step == 1) ...[
        SummaryRow('Your contribution', '${amount.text} FCFA'),
        const SummaryRow('Demo provider cost', '0 FCFA'),
        SummaryRow('Demo total', '${amount.text} FCFA', bold: true),
        const Text('Demo fees are zero. Live pricing will be shown before a real payment. Collection settlement fees are separate.'),
        CheckboxListTile(contentPadding: EdgeInsets.zero, value: confirmed, onChanged: (v) => setState(() => confirmed = v ?? false), title: const Text('I confirm these details.')),
        FilledButton(onPressed: confirmed ? next : null, child: const Text('Continue to payment method')),
      ],
      if (step == 2) ...[
        ...['MTN Mobile Money', 'Orange Money'].map((value) => Padding(padding: const EdgeInsets.only(bottom: 12), child: OutlinedButton.icon(
          onPressed: () => setState(() => method = value), icon: Icon(method == value ? Icons.check_circle : Icons.circle_outlined), label: Text(value)))),
        FilledButton(onPressed: next, child: const Text('Continue')),
      ],
      if (step == 3) ...[
        SummaryRow('Demo amount', '${amount.text} FCFA'), SummaryRow('Using', method),
        const Text('No provider request will be sent. Choose an outcome to test the flow.'),
        const SizedBox(height: 24),
        FilledButton(onPressed: () => finish('success'), child: const Text('Simulate successful payment')),
        OutlinedButton(onPressed: () => finish('failed'), child: const Text('Simulate failed payment')),
        TextButton(onPressed: () => finish('cancelled'), child: const Text('Cancel')),
      ],
      if (step == 4) ...[
        Icon(outcome == 'success' ? Icons.check_circle : Icons.info_outline, color: SendohColors.teal, size: 64),
        Text(outcome == 'success' ? 'Demo contribution successful' : 'Demo payment $outcome', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 16), const Text('No money was charged. Your collection total has not changed.'),
        FilledButton(onPressed: () => setState(() => step = outcome == 'success' ? 5 : 3), child: Text(outcome == 'success' ? 'View demo receipt' : 'Try again')),
      ],
      if (step == 5) ...[
        const Text('DEMO • Not proof of payment', style: TextStyle(fontWeight: FontWeight.bold)),
        SummaryRow('Demo reference', reference), SummaryRow('Amount', '${amount.text} FCFA'), SummaryRow('Method', method),
        if (note.text.trim().isNotEmpty) SummaryRow('Note', note.text.trim()),
        const Text('This simulation is not recorded as a contribution.'),
      ],
      if (step >= 4) OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('View collection')),
      if (step > 0 && step < 4) TextButton(onPressed: () => setState(() => step--), child: const Text('Back')),
    ]));
}
