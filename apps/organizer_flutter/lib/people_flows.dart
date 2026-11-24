import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design.dart';

enum PeopleIntent { pay, request }

/// Identity must come from an authenticated backend lookup, never raw QR text.
class ResolvedPerson {
  const ResolvedPerson(
      {required this.id,
      required this.name,
      required this.identity,
      this.receivingReady = true});
  final String id, name, identity;

  /// They have set where they receive money; known before any amount or charge.
  final bool receivingReady;
}

String _initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .take(2)
    .map((w) => w.characters.first.toUpperCase())
    .join();

/// The same recipient preview for a handle search and a Near2Pay code.
class RecipientPreview extends StatelessWidget {
  const RecipientPreview(
      {super.key, required this.name, required this.identity});
  final String name, identity;
  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: 'Paying $name, $identity',
        child: Column(children: [
          CircleAvatar(
              radius: 36,
              backgroundColor: SendohColors.tealSoft,
              child: Text(_initials(name),
                  style: const TextStyle(
                      color: SendohColors.teal,
                      fontSize: 24,
                      fontWeight: FontWeight.w700))),
          const SizedBox(height: 12),
          Text(name,
              textAlign: TextAlign.center,
              style: SendohTextStyles.headingMedium),
          Text(identity,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 16, color: SendohColors.secondary)),
          const SizedBox(height: 8),
          const Text('Check this is the person you mean.',
              textAlign: TextAlign.center, style: SendohTextStyles.caption),
        ]),
      );
}

/// Shown instead of a payment button when the recipient cannot receive yet.
class CannotReceiveYet extends StatefulWidget {
  const CannotReceiveYet(
      {super.key, required this.name, required this.onRemind});
  final String name;
  final Future<void> Function() onRemind;
  @override
  State<CannotReceiveYet> createState() => _CannotReceiveYetState();
}

class _CannotReceiveYetState extends State<CannotReceiveYet> {
  bool sent = false, busy = false;
  String? error;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: SendohColors.amberSoft,
              borderRadius: BorderRadius.circular(14)),
          child: Text(
              '${widget.name} hasn’t set where they receive money yet. Nothing has been charged. Once they add it in Sendoh, you can pay.',
              style: SendohTextStyles.bodyMedium),
        ),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: busy || sent
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await widget.onRemind();
                      if (mounted) setState(() => sent = true);
                    } catch (_) {
                      if (mounted) {
                        setState(() => error = 'Couldn’t send. Try again.');
                      }
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: Text(sent
                ? 'We let ${widget.name} know'
                : 'Let ${widget.name} know')),
        if (error != null)
          Text(error!, style: const TextStyle(color: SendohColors.red)),
      ]);
}

class PeopleDraft {
  const PeopleDraft(
      {required this.person,
      required this.intent,
      required this.amount,
      required this.note,
      this.method,
      this.expiry});
  final ResolvedPerson person;
  final PeopleIntent intent;
  final int amount; // Whole FCFA, not floating-point money.
  final String note;
  final String? method;
  final DateTime? expiry;
}

/// Implement against confirmed contracts. The checkout must fetch a quote,
/// review it, persist an idempotent attempt and reconcile its provider outcome.
/// It owns submission, push/activity updates and receipt navigation.
abstract class PeopleFlowGateway {
  Future<ResolvedPerson> resolve(String identity, {required bool fromQr});
  Future<String?> scan(BuildContext context);
  Future<void> openCheckout(BuildContext context, PeopleDraft draft);

  /// Tell someone a person wants to pay them and they need receiving details.
  Future<void> remindReceiving(String personId);
}

class PeopleFlow extends StatefulWidget {
  const PeopleFlow(
      {super.key,
      this.intent = PeopleIntent.pay,
      this.nearby = false,
      this.gateway,
      this.nearbyBuilder});
  final PeopleIntent intent;
  final bool nearby;
  final PeopleFlowGateway? gateway;

  /// The Near2Pay scanner, when connected.
  final Widget Function()? nearbyBuilder;
  @override
  State<PeopleFlow> createState() => _PeopleFlowState();
}

class _PeopleFlowState extends State<PeopleFlow> {
  final identity = TextEditingController();
  final amount = TextEditingController();
  final note = TextEditingController();
  final form = GlobalKey<FormState>();
  late PeopleIntent intent;
  ResolvedPerson? person;
  DateTime? expiry;
  String method = 'MTN MoMo';
  String? error;
  int step = 0;
  bool busy = false;
  bool get request => intent == PeopleIntent.request;

  @override
  void initState() {
    super.initState();
    intent = widget.intent;
  }

  @override
  void dispose() {
    identity.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> resolve() async {
    if (identity.text.trim().isEmpty) {
      setState(() => error = widget.nearby
          ? 'Scan or paste a Sendoh code.'
          : 'Enter their exact Sendoh username.');
      return;
    }
    final gateway = widget.gateway;
    if (gateway == null) {
      setState(() => error =
          'Person lookup is not connected in this build. Your details have not been sent.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result =
          await gateway.resolve(identity.text.trim(), fromQr: widget.nearby);
      if (!mounted) {
        return;
      }
      setState(() {
        person = result;
        step = 1;
      });
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'We couldn’t confirm this person. Check the details and try again.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> scan() async {
    final gateway = widget.gateway;
    if (gateway == null) {
      setState(() => error = 'QR scanning is not connected in this build.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await gateway.scan(context);
      if (!mounted || value == null) {
        return;
      }
      identity.text = value;
      // Require an explicit lookup and identity confirmation after scanning.
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'Camera unavailable. You can paste the Sendoh code instead.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> chooseExpiry() async {
    final now = DateTime.now();
    final date = await showDatePicker(
        context: context,
        initialDate: expiry ?? now.add(const Duration(days: 7)),
        firstDate: DateTime(now.year, now.month, now.day),
        lastDate: now.add(const Duration(days: 365)));
    if (mounted && date != null) {
      setState(() => expiry = date);
    }
  }

  Future<void> checkout() async {
    if (busy || person == null || widget.gateway == null) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.gateway!.openCheckout(
          context,
          PeopleDraft(
              person: person!,
              intent: intent,
              amount: int.parse(amount.text),
              note: note.text.trim(),
              method: request ? null : method,
              expiry: request ? expiry : null));
      // Returning from checkout is NOT proof of success.
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'Couldn’t open the next step. Check Activity before repeating an action.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Widget detail(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(color: SendohColors.secondary))),
        const SizedBox(width: 16),
        Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w600))),
      ]));

  @override
  Widget build(BuildContext context) {
    final title = step == 0
        ? (widget.nearby
            ? 'Meet through Sendoh'
            : request
                ? 'Request money'
                : 'Pay someone')
        : step == 1
            ? 'Confirm the person'
            : step == 2
                ? (request ? 'Your request' : 'Your payment')
                : 'Review details';
    return PopScope(
        canPop: step == 0 && !busy,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && !busy && step > 0) {
            setState(() {
              step--;
              error = null;
            });
          }
        },
        child: Scaffold(
          appBar: AppBar(
              title: Text(title),
              leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: busy
                      ? null
                      : () {
                          if (step > 0) {
                            setState(() {
                              step--;
                              error = null;
                            });
                          } else {
                            Navigator.pop(context);
                          }
                        })),
          body: SafeArea(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: form,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.gateway == null) ...[
                            const Text('Not connected yet',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            const Text(
                                'This journey needs person lookup and payment/request services before it can be used.',
                                style: TextStyle(
                                    color: SendohColors.secondary,
                                    height: 1.5)),
                            const SizedBox(height: 24),
                          ],
                          if (step == 0) ...[
                            Text(
                                widget.nearby
                                    ? 'Scan their QR, confirm who they are, then pay or request.'
                                    : 'Start with a person you know.',
                                style: const TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 24),
                            if (widget.nearby) ...[
                              OutlinedButton.icon(
                                  onPressed: busy ? null : scan,
                                  icon: const Icon(Icons.qr_code_scanner),
                                  label: const Text('Scan Sendoh QR')),
                              const SizedBox(height: 20),
                            ],
                            TextFormField(
                                controller: identity,
                                enabled: !busy,
                                autocorrect: false,
                                decoration: InputDecoration(
                                    labelText: widget.nearby
                                        ? 'Sendoh code or link'
                                        : 'Sendoh @username')),
                            const SizedBox(height: 24),
                            FilledButton(
                                onPressed: busy ? null : resolve,
                                child:
                                    Text(busy ? 'Checking…' : 'Find person')),
                            if (!widget.nearby)
                              TextButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => Navigator.push(
                                          context,
                                          MaterialPageRoute<void>(
                                              builder: (_) =>
                                                  widget.nearbyBuilder
                                                      ?.call() ??
                                                  PeopleFlow(
                                                      intent: intent,
                                                      nearby: true,
                                                      gateway:
                                                          widget.gateway))),
                                  icon: const Icon(Icons.qr_code_scanner),
                                  label: const Text('Use Near2Pay')),
                          ],
                          if (step >= 1 && person != null) ...[
                            RecipientPreview(
                                name: person!.name, identity: person!.identity),
                            const SizedBox(height: 24),
                          ],
                          if (step == 1 && !request && !person!.receivingReady)
                            CannotReceiveYet(
                                name: person!.name,
                                onRemind: () =>
                                    widget.gateway!.remindReceiving(person!.id))
                          else if (step == 1) ...[
                            if (widget.nearby) ...[
                              FilledButton(
                                  onPressed: () => setState(() {
                                        intent = PeopleIntent.pay;
                                        step = 2;
                                      }),
                                  child: const Text('Pay this person')),
                              OutlinedButton(
                                  onPressed: () => setState(() {
                                        intent = PeopleIntent.request;
                                        step = 2;
                                      }),
                                  child:
                                      const Text('Request from this person')),
                            ] else
                              FilledButton(
                                  onPressed: () => setState(() => step = 2),
                                  child: const Text('Continue')),
                            TextButton(
                                onPressed: () => setState(() {
                                      person = null;
                                      step = 0;
                                    }),
                                child: const Text('Choose someone else')),
                          ],
                          if (step == 2) ...[
                            TextFormField(
                                controller: amount,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(9)
                                ],
                                decoration: const InputDecoration(
                                    labelText: 'Amount (FCFA)'),
                                validator: (v) =>
                                    (int.tryParse(v ?? '') ?? 0) <= 0
                                        ? 'Enter an amount greater than zero.'
                                        : null),
                            const SizedBox(height: 20),
                            if (request)
                              TextFormField(
                                  controller: note,
                                  maxLength: 140,
                                  decoration: InputDecoration(
                                      labelText: request
                                          ? 'Reason'
                                          : 'Note (optional)'),
                                  validator: (v) =>
                                      request && (v ?? '').trim().isEmpty
                                          ? 'Add a reason for this request.'
                                          : null),
                            if (request) ...[
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Expiry (optional)'),
                                  subtitle: Text(expiry == null
                                      ? 'No expiry'
                                      : '${expiry!.day}/${expiry!.month}/${expiry!.year}'),
                                  trailing:
                                      const Icon(Icons.calendar_today_outlined),
                                  onTap: chooseExpiry),
                              if (expiry != null)
                                TextButton(
                                    onPressed: () =>
                                        setState(() => expiry = null),
                                    child: const Text('Remove expiry')),
                            ] else ...[
                              const Text('Payment method'),
                              SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment<String>(
                                    value: 'MTN MoMo',
                                    label: Text('MTN MoMo'),
                                  ),
                                  ButtonSegment<String>(
                                    value: 'Orange Money',
                                    label: Text('Orange Money'),
                                  ),
                                ],
                                selected: {method},
                                onSelectionChanged: (selection) {
                                  setState(() => method = selection.single);
                                },
                              ),
                            ],
                            const SizedBox(height: 24),
                            FilledButton(
                                onPressed: busy
                                    ? null
                                    : () {
                                        if (form.currentState!.validate()) {
                                          if (request) {
                                            setState(() => step = 3);
                                          } else {
                                            checkout();
                                          }
                                        }
                                      },
                                child: const Text('Review details')),
                          ],
                          if (step == 3) ...[
                            detail(
                                request ? 'Request amount' : 'Payment amount',
                                '${amount.text} FCFA'),
                            if (note.text.trim().isNotEmpty)
                              detail(request ? 'Reason' : 'Note',
                                  note.text.trim()),
                            if (!request) detail('Method', method),
                            if (request)
                              detail(
                                  'Expiry',
                                  expiry == null
                                      ? 'No expiry'
                                      : '${expiry!.day}/${expiry!.month}/${expiry!.year}'),
                            const Divider(),
                            Text(request
                                ? 'Review the delivery details in the next step before sending.'
                                : 'The next step shows the live quote and total before you authorise payment.'),
                            const SizedBox(height: 24),
                            FilledButton(
                                onPressed: busy ? null : checkout,
                                child: Text(busy
                                    ? 'Opening…'
                                    : request
                                        ? 'Continue to send review'
                                        : 'Continue to payment quote')),
                            TextButton(
                                onPressed: busy
                                    ? null
                                    : () => setState(() => step = 2),
                                child: const Text('Edit details')),
                          ],
                          if (error != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 20),
                                child: Semantics(
                                    liveRegion: true,
                                    child: Text(error!,
                                        style: const TextStyle(
                                            color: SendohColors.red)))),
                        ]),
                  ))),
        ));
  }
}
