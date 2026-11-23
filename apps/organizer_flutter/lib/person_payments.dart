import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'design.dart';

String paymentStatus(dynamic value) =>
    const {
      'READY': 'Awaiting confirmation',
      'COLLECTING': 'Confirming payment',
      'FUNDED': 'Preparing delivery',
      'DELIVERING': 'Delivering payment',
      'SUCCEEDED': 'Confirmed',
      'FAILED': 'Not completed',
      'REVIEW': 'Under review',
      'PENDING': 'Awaiting confirmation',
      'NOT_STARTED': 'Not started',
      'REFUNDED': 'Reversed',
      'CANCELLED': 'Cancelled',
      'EXPIRED': 'Expired',
    }[value] ??
    'Checking status';

String personMoney(dynamic value) {
  final s = '${value ?? 0}';
  return '${s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} FCFA';
}

Widget paymentRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: LayoutBuilder(builder: (context, size) {
      final large = MediaQuery.textScalerOf(context).scale(14) > 20 ||
          size.maxWidth < 300;
      final text =
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600));
      return large
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(label), const SizedBox(height: 4), text])
          : Row(children: [
              Expanded(child: Text(label)),
              const SizedBox(width: 16),
              Flexible(child: text)
            ]);
    }));

Widget paymentPage(String title, List<Widget> children) => Scaffold(
    appBar: AppBar(title: const Text('Sendoh')),
    body: SafeArea(
        child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                    key: ValueKey(title),
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(title, style: SendohTextStyles.headingMedium),
                      const SizedBox(height: 10),
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                              width: 36,
                              height: 3,
                              color: SendohColors.orange)),
                      const SizedBox(height: 28),
                      ...children
                    ])))));

/// A consistent surface shared by review, status and receipt details.
Widget paymentSurface(List<Widget> children) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: SendohColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SendohColors.border)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );

class ReceivingDetails extends StatefulWidget {
  const ReceivingDetails({super.key, required this.api});
  final SendohApi api;
  @override
  State<ReceivingDetails> createState() => _ReceivingDetailsState();
}

class _ReceivingDetailsState extends State<ReceivingDetails> {
  Map<String, dynamic>? data;
  String method = 'MTN';
  String? error;
  bool busy = false, consent = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = Map<String, dynamic>.from(
          await widget.api.request('/me/receiving-destination'));
      if (!mounted) {
        return;
      }
      setState(() {
        data = result;
        method = result['destination']?['method'] ?? 'MTN';
        consent = false;
      });
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

  Future<void> save() async {
    if (busy || !consent || data == null) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.request('/me/receiving-destination', body: {
        'method': method,
        'expected_version': data!['version'],
        'consent': 'RECEIVE_ON_MY_AUTHENTICATED_PHONE'
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
  Widget build(BuildContext context) => paymentPage('Receiving details', [
        if (busy) const LinearProgressIndicator(color: SendohColors.orange),
        Text(
            data?['account_masked_phone'] ??
                data?['destination']?['masked_phone'] ??
                'Your Sendoh account number',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        const Text('Receive on the number linked to your account.'),
        const SizedBox(height: 24),
        Wrap(
            spacing: 12,
            children: ['MTN', 'ORANGE']
                .map((m) => ChoiceChip(
                    label: Text(m == 'MTN' ? 'MTN MoMo' : 'Orange Money'),
                    selected: method == m,
                    onSelected: busy
                        ? null
                        : (_) => setState(() {
                              method = m;
                              consent = false;
                            })))
                .toList()),
        const SizedBox(height: 20),
        CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Receive payments on my account number'),
            value: consent,
            onChanged:
                busy ? null : (v) => setState(() => consent = v ?? false)),
        if (error != null)
          Text(error!, style: const TextStyle(color: SendohColors.error)),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: busy || !consent || data == null ? null : save,
            child: const Text('Save details')),
        TextButton(
            onPressed: busy ? null : load, child: const Text('Reload details')),
      ]);
}

/// A single unresolved checkout per account prevents an uncertain submission
/// from being silently replaced by another payment after a restart.
class PersonCheckout extends StatefulWidget {
  const PersonCheckout(
      {super.key,
      required this.api,
      this.target,
      this.orderId,
      this.method = 'MTN',
      this.nearby = false});
  final SendohApi api;
  final Map<String, dynamic>? target;
  final String? orderId;
  final String method;

  /// Opened from Near2Pay: title names the person and offers "Wrong person?".
  final bool nearby;
  @override
  State<PersonCheckout> createState() => _PersonCheckoutState();
}

class _PersonCheckoutState extends State<PersonCheckout>
    with WidgetsBindingObserver {
  static const storage = FlutterSecureStorage();
  static bool submitting = false;
  Map<String, dynamic>? quote, order, pending;
  String? slot, error;
  late String method;
  bool busy = false,
      checking = false,
      initialized = false,
      outcomeUnknown = false;
  Timer? timer;
  bool get terminal => ['SUCCEEDED', 'FAILED', 'CANCELLED', 'EXPIRED']
      .contains(order?['status']);
  @override
  void initState() {
    super.initState();
    method = widget.method;
    WidgetsBinding.instance.addObserver(this);
    initialize();
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (order != null &&
          !terminal &&
          !busy &&
          !checking &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        refresh();
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        order != null &&
        !busy &&
        !checking) {
      refresh();
    }
  }

  Future<void> persist() async {
    if (slot != null && pending != null) {
      await storage.write(key: slot!, value: jsonEncode(pending));
    }
  }

  Future<void> clearOwnPending() async {
    if (slot == null || order == null) {
      return;
    }
    final raw = await storage.read(key: slot!);
    if (raw != null && jsonDecode(raw)['order_id'] == order!['id']) {
      await storage.delete(key: slot!);
      pending = null;
    }
  }

  Future<void> initialize() async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final me = await widget.api.request('/me');
      slot = 'sendoh-person-payment:${widget.api.baseUrl}:${me['id']}';
      final raw = await storage.read(key: slot!);
      pending = raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw));
      if (widget.orderId != null) {
        order = Map<String, dynamic>.from(await widget.api
            .request('/person-payments/orders/${widget.orderId}'));
      } else if (pending != null) {
        // Resolve an uncertain order creation with the SAME quote and key.
        // This creates/resumes an order only; it never dispatches money.
        final id = pending!['order_id'];
        order = Map<String, dynamic>.from(id != null
            ? await widget.api.request('/person-payments/orders/$id')
            : await widget.api.request('/person-payments/orders',
                key: pending!['key'],
                body: {
                    'quote_id': pending!['quote_id'],
                    'consent': 'ACCEPT_QUOTED_TOTAL'
                  }));
        pending!['order_id'] = order!['id'];
        await persist();
      } else {
        await fetchQuote();
      }
      if (order != null) {
        quote = Map<String, dynamic>.from(order!['quote']);
        if (terminal) {
          await clearOwnPending();
        }
      }
      initialized = true;
      outcomeUnknown = false;
    } on ApiException catch (e) {
      const rejected = [
        'Quote expired. Review a new quote.',
        'Payment terms changed. Review a new quote.',
        'Your phone identity changed. Review a new quote.',
        'Receiving details changed. Review a new quote.'
      ];
      // The order endpoint checks/replays existing orders under its user lock
      // before these definitive pre-creation rejections.
      if (e.status == 409 &&
          rejected.contains(e.message) &&
          pending?['order_id'] == null &&
          slot != null) {
        await storage.delete(key: slot!);
        pending = null;
        quote = null;
        initialized = true;
      }
      error = e.message;
    } catch (e) {
      error = '$e';
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> fetchQuote() async {
    if (widget.target == null) {
      return;
    }
    quote = Map<String, dynamic>.from(await widget.api.request(
        '/person-payments/quotes',
        body: {...widget.target!, 'payer_method': method}));
  }

  Future<void> newQuote() async {
    if (busy || pending != null || order != null) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
      quote = null;
    });
    try {
      await fetchQuote();
    } catch (e) {
      error = '$e';
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> confirm() async {
    if (busy || submitting || outcomeUnknown || quote == null || !initialized) {
      return;
    }
    submitting = true;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (order == null) {
        final existing = await storage.read(key: slot!);
        if (existing != null) {
          throw StateError('Resume the existing payment first.');
        }
        // Persist before any network mutation. Storage failure prevents charge.
        pending = {
          'quote_id': quote!['id'],
          'key': List.generate(
              24,
              (_) => Random.secure()
                  .nextInt(256)
                  .toRadixString(16)
                  .padLeft(2, '0')).join()
        };
        await persist();
        order = Map<String, dynamic>.from(await widget.api
            .request('/person-payments/orders', key: pending!['key'], body: {
          'quote_id': quote!['id'],
          'consent': 'ACCEPT_QUOTED_TOTAL'
        }));
        pending!['order_id'] = order!['id'];
        await persist();
      }
      if (order!['status'] != 'READY' ||
          order!['execution_available'] != true) {
        error = 'This payment cannot be started. Check its current status.';
        return;
      }
      order = Map<String, dynamic>.from(await widget.api.request(
          '/person-payments/orders/${order!['id']}/execute',
          body: {}));
      if (terminal) {
        await clearOwnPending();
      }
    } catch (_) {
      outcomeUnknown = true;
      error =
          'We could not confirm the latest status. Check this payment before starting another.';
    } finally {
      submitting = false;
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> refresh() async {
    if (busy || checking) {
      return;
    }
    if (order == null) {
      await initialize();
      return;
    }
    checking = true;
    try {
      final result = Map<String, dynamic>.from(
          await widget.api.request('/person-payments/orders/${order!['id']}'));
      order = result;
      quote = Map<String, dynamic>.from(result['quote']);
      error = null;
      outcomeUnknown = false;
      if (terminal) {
        await clearOwnPending();
      }
    } catch (_) {
      error =
          'Couldn’t update this payment. Its last known status is shown below.';
    } finally {
      checking = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> cancelPrepared() async {
    if (busy || order?['status'] != 'READY') {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      order = Map<String, dynamic>.from(await widget.api
          .request('/person-payments/orders/${order!['id']}/cancel', body: {}));
      await clearOwnPending();
    } catch (e) {
      error = '$e';
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = quote;
    final a = q == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(q['amounts']);
    final status = order?['status'];
    final delivered =
        order?['receipt_available'] == true && status == 'SUCCEEDED';
    final ready = order == null || status == 'READY';
    final expired = q != null &&
        (q['expires_at'] as int) <=
            DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final title = delivered
        ? 'Payment delivered'
        : status == 'REVIEW'
            ? 'Payment needs review'
            : status == 'FAILED'
                ? 'Payment not completed'
                : status == 'CANCELLED'
                    ? 'Payment cancelled'
                    : status == 'EXPIRED'
                        ? 'Quote expired'
                        : ready
                            ? (widget.nearby && q != null
                                ? 'Pay ${q['recipient']['name']}'
                                : 'Review payment')
                            : 'Payment in progress';
    return paymentPage(title, [
      if (busy) const LinearProgressIndicator(color: SendohColors.orange),
      if (q != null) ...[
        Row(children: [
          const CircleAvatar(
              radius: 25,
              backgroundColor: SendohColors.tealSoft,
              child: Icon(Icons.person_outline, color: SendohColors.teal)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(q['recipient']['name'],
                    style: SendohTextStyles.titleSmall),
                Text(q['recipient']['identity'],
                    style: SendohTextStyles.caption),
              ])),
        ]),
        const SizedBox(height: 28),
        Semantics(
            liveRegion: true,
            child: Text(personMoney(a['recipient_amount']),
                style: SendohTextStyles.displayLarge)),
        const SizedBox(height: 4),
        Text(
            delivered
                ? 'Delivered to ${q['recipient']['name']}'
                : terminal
                    ? 'To ${q['recipient']['name']}'
                    : '${q['recipient']['name']} receives',
            style: SendohTextStyles.bodyMedium),
        const SizedBox(height: 28),
        if (ready) ...[
          paymentSurface([
            paymentRow(
                'Fees',
                personMoney((a['collection_fee'] as num) +
                    (a['delivery_fee'] as num) +
                    (a['sendoh_fee'] as num))),
            const Divider(height: 16),
            paymentRow('Total', personMoney(a['total_debit'])),
          ]),
          ExpansionTile(
              key: const ValueKey('fee-breakdown'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Fee breakdown'),
              children: [
                paymentRow(
                    'Processing fee',
                    personMoney((a['collection_fee'] as num) +
                        (a['delivery_fee'] as num))),
                paymentRow('Sendoh fee', personMoney(a['sendoh_fee'])),
              ]),
          const SizedBox(height: 16),
          const Text('Pay with', style: SendohTextStyles.titleSmall),
          const SizedBox(height: 12),
          if (order == null && pending == null)
            ...['MTN', 'ORANGE'].map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Semantics(
                      selected: method == m,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                            side: BorderSide(
                                color: method == m
                                    ? SendohColors.teal
                                    : SendohColors.border),
                            backgroundColor: SendohColors.surface),
                        onPressed: busy
                            ? null
                            : () {
                                setState(() => method = m);
                                newQuote();
                              },
                        child: Row(children: [
                          Icon(
                              method == m
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: method == m
                                  ? SendohColors.teal
                                  : SendohColors.secondary),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(
                                  m == 'MTN' ? 'MTN MoMo' : 'Orange Money',
                                  style: SendohTextStyles.titleSmall)),
                        ]),
                      )),
                ))
          else
            paymentRow('Method',
                q['payer_method'] == 'MTN' ? 'MTN MoMo' : 'Orange Money'),
        ],
        if (!ready && !terminal)
          Text(
              status == 'REVIEW'
                  ? 'We’re checking this payment. Do not pay again.'
                  : 'You can leave and return to check this payment.',
              style: SendohTextStyles.bodyMedium),
        if (order != null && !ready)
          ExpansionTile(
              key: const ValueKey('payment-details'),
              tilePadding: EdgeInsets.zero,
              title: Text(delivered ? 'View receipt' : 'Payment details'),
              children: [
                paymentRow('Payment collection',
                    paymentStatus(order!['collection_status'])),
                paymentRow('Recipient delivery',
                    paymentStatus(order!['delivery_status'])),
                paymentRow(
                    'Processing fee',
                    personMoney((a['collection_fee'] as num) +
                        (a['delivery_fee'] as num))),
                paymentRow('Sendoh fee', personMoney(a['sendoh_fee'])),
                paymentRow('Total', personMoney(a['total_debit'])),
                paymentRow('Method',
                    q['payer_method'] == 'MTN' ? 'MTN MoMo' : 'Orange Money'),
                const Align(
                    alignment: Alignment.centerLeft, child: Text('Reference')),
                Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText('${order!['id']}')),
              ]),
      ],
      if (error != null) ...[
        const SizedBox(height: 16),
        Semantics(
            liveRegion: true,
            child:
                Text(error!, style: const TextStyle(color: SendohColors.error)))
      ],
      const SizedBox(height: 28),
      if (ready &&
          q != null &&
          initialized &&
          pending == null &&
          order == null) ...[
        if (expired) const Text('Refresh the quote before confirming.'),
        FilledButton(
            onPressed: busy || expired || q['execution_available'] != true
                ? null
                : confirm,
            child: Text('Pay ${personMoney(a['total_debit'])}')),
        if (q['execution_available'] != true)
          const Text(
              'Payment is currently unavailable. No payment has been started.'),
        if (expired)
          TextButton(
              onPressed: busy ? null : newQuote,
              child: const Text('Refresh quote')),
      ] else if (status == 'READY') ...[
        FilledButton(
            onPressed:
                busy || outcomeUnknown || order!['execution_available'] != true
                    ? null
                    : confirm,
            child: Text('Pay ${personMoney(a['total_debit'])}')),
        TextButton(
            onPressed: busy ? null : cancelPrepared,
            child: const Text('Cancel this payment')),
      ],
      if (quote == null &&
          initialized &&
          pending == null &&
          widget.target != null)
        FilledButton(
            onPressed: busy ? null : newQuote,
            child: const Text('Review new quote')),
      if ((order != null && !terminal) || error != null)
        OutlinedButton(
            onPressed: busy ? null : refresh,
            child: const Text('Check status')),
      if (widget.nearby && ready && order == null)
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Wrong person? Scan again'))
      else
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(delivered ? 'Done' : 'Back')),
    ]);
  }
}

class PersonPaymentHistory extends StatefulWidget {
  const PersonPaymentHistory({super.key, required this.api});
  final SendohApi api;
  @override
  State<PersonPaymentHistory> createState() => _PersonPaymentHistoryState();
}

class _PersonPaymentHistoryState extends State<PersonPaymentHistory> {
  List<dynamic>? items;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await widget.api.request('/person-payments/orders');
      if (mounted) {
        setState(() => items = List<dynamic>.from(r['items']));
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
  Widget build(BuildContext context) => paymentPage('Person payments', [
        if (busy) const LinearProgressIndicator(color: SendohColors.orange),
        if (items?.isEmpty == true)
          const Text('Your person payments will appear here.'),
        for (final item in items ?? [])
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item['quote']['recipient']['name']),
              subtitle: Text(
                  '${personMoney(item['quote']['amounts']['recipient_amount'])} · ${paymentStatus(item['status'])}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => PersonCheckout(
                            api: widget.api, orderId: item['id'])));
                if (mounted) {
                  load();
                }
              }),
        if (error != null) Text(error!),
        TextButton(onPressed: busy ? null : load, child: const Text('Refresh')),
      ]);
}
