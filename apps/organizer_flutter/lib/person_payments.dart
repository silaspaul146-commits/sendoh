import 'i18n.dart';
import 'money_numbers.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'design.dart';

String paymentStatus(dynamic value) =>
    {
      'READY': t('Awaiting confirmation'),
      'COLLECTING': t('Confirming payment'),
      'FUNDED': t('Preparing delivery'),
      'DELIVERING': t('Delivering payment'),
      'SUCCEEDED': t('Confirmed'),
      'FAILED': t('Not completed'),
      'REVIEW': t('Under review'),
      'PENDING': t('Awaiting confirmation'),
      'NOT_STARTED': t('Not started'),
      'REFUNDED': t('Reversed'),
      'CANCELLED': t('Cancelled'),
      'EXPIRED': t('Expired'),
    }[value] ??
    t('Checking status');

String walletLabel(dynamic method) =>
    method == 'ORANGE' ? t('Orange Money') : 'MTN MoMo';

/// One line per moment, from the reader's side. Only DELIVERED says "received".
({String title, String body}) personPaymentCopy(
    {required String? phase,
    required bool recipient,
    required String payer,
    required String payee,
    required String amount}) {
  if (recipient) {
    return switch (phase) {
      'DELIVERED' => (
          title: t('You received {amount}', {'amount': amount}),
          body: t('From {payer}.', {'payer': payer})
        ),
      'DELIVERING' => (
          title: t('{payer} paid · on its way to you', {'payer': payer}),
          body: t(
              'It isn’t in your Mobile Money yet. We’ll tell you when it arrives.')
        ),
      'REVIEW_FUNDS_HELD' => (
          title: t('Delivery needs attention'),
          body: t('{payer}’s payment is held safely. Nobody pays again.',
              {'payer': payer})
        ),
      'FAILED' => (
          title: t('{payer}’s payment didn’t go through', {'payer': payer}),
          body: t('Nothing was taken or delivered.')
        ),
      _ => (
          title: t('{payer} is paying', {'payer': payer}),
          body: t('We’ll tell you when it reaches you.')
        ),
    };
  }
  return switch (phase) {
    'AWAITING_APPROVAL' => (
        title: t('Approve on your phone'),
        body: t(
            'Check your Mobile Money phone for the prompt and approve it there.')
      ),
    'CONFIRMING' => (
        title: t('Confirming your payment'),
        body: t('We’re checking with Mobile Money. Please don’t pay again.')
      ),
    'DELIVERING' => (
        title: t('Paid · delivering to {payee}', {'payee': payee}),
        body: t(
            'We collected your payment. Delivery to {payee} is still being confirmed. Please don’t pay again.',
            {'payee': payee})
      ),
    'DELIVERED' => (
        title: t('Delivered to {payee}', {'payee': payee}),
        body:
            t('{payee} received {amount}.', {'payee': payee, 'amount': amount})
      ),
    'REVIEW_FUNDS_HELD' => (
        title: t('Delivery needs attention'),
        body: t(
            'Your payment was collected and is held safely. Please don’t pay again.')
      ),
    'REVIEW' => (
        title: t('We’re checking this payment'),
        body: t('Please don’t pay again.')
      ),
    'FAILED' => (
        title: t('Payment not completed'),
        body: t('Nothing was delivered. You can try again.')
      ),
    'CANCELLED' => (
        title: t('Payment cancelled'),
        body: t('Nothing was charged.')
      ),
    'EXPIRED' => (title: t('Quote expired'), body: t('Review a new quote.')),
    _ => (title: t('Review payment'), body: ''),
  };
}

/// One Activity line for a person payment, from the reader's side.
({String title, String status}) personActivityLine(Map<String, dynamic> item) {
  final quote = Map<String, dynamic>.from(item['quote'] as Map);
  final amount = personMoney(quote['amounts']['recipient_amount']);
  final sent = item['direction'] == 'SENT';
  final other = sent
      ? '${quote['recipient']['name']}'
      : '${item['payer']?['name'] ?? 'Someone'}';
  final title = sent
      ? t('You sent {amount} to {other}', {'amount': amount, 'other': other})
      : t('{other} sent you {amount}', {'other': other, 'amount': amount});
  final status = switch (item['phase']) {
    'DELIVERED' => sent ? t('Delivered') : t('Received'),
    'DELIVERING' => sent ? t('Paid · delivering') : t('On its way to you'),
    'REVIEW_FUNDS_HELD' => t('Needs attention · held safely'),
    'REVIEW' => t('Being checked'),
    'FAILED' => t('Not completed'),
    _ => sent ? t('Confirming your payment') : t('Being paid'),
  };
  return (title: title, status: status);
}

String personMoney(dynamic value) {
  return fcfa(value ?? 0);
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
    appBar: AppBar(title: Text(t('Sendoh'))),
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
                          // Teal for people payments; orange is collection progress.
                          child: Container(
                              width: 36, height: 3, color: SendohColors.teal)),
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

/// Where money reaches you: your verified Mobile Money numbers, one marked
/// "Receive on this". Opened wherever receiving still needs setting up.
class ReceivingDetails extends StatelessWidget {
  const ReceivingDetails({super.key, required this.api});
  final SendohApi api;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(t('Receiving details'))),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text(
              t('Choose the Mobile Money number where money sent to you, and collection payouts, arrive. Verify it once by SMS code.'),
              style: SendohTextStyles.bodyMedium),
          MoneyNumbersSection(api: api),
        ]),
      );
}

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
  String? slot, error, meId;
  late String method;
  // One of the payer's verified numbers; null: their default, else sign-in number.
  String? payerNumberId;
  bool noVerifiedNumbers = false;
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
      meId = me['id'] as String?;
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
      final rejected = [
        t('Quote expired. Review a new quote.'),
        t('Payment terms changed. Review a new quote.'),
        t('Your phone identity changed. Review a new quote.'),
        t('Receiving details changed. Review a new quote.')
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
      error = t(e.message);
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
    quote = Map<String, dynamic>.from(
        await widget.api.request('/person-payments/quotes', body: {
      ...widget.target!,
      'payer_method': method,
      if (payerNumberId != null) 'payer_number_id': payerNumberId
    }));
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
          throw StateError(t('Resume the existing payment first.'));
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
        error = t('This payment cannot be started. Check its current status.');
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
      error = t(
          'We could not confirm the latest status. Check this payment before starting another.');
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
      error = t(
          'Couldn’t update this payment. Its last known status is shown below.');
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
    // The recipient reads the same payment from their side.
    final isRecipient =
        q != null && meId != null && q['recipient']['id'] == meId;
    final payee = q == null ? '' : '${q['recipient']['name']}';
    final payer = '${order?['payer']?['name'] ?? 'They'}';
    final copy = personPaymentCopy(
        phase: order == null ? null : order!['phase'] as String?,
        recipient: isRecipient,
        payer: payer,
        payee: payee,
        amount: personMoney(a['recipient_amount']));
    final title = ready && !isRecipient
        ? (widget.nearby && q != null
            ? t('Pay {payee}', {'payee': payee})
            : t('Review payment'))
        : copy.title;
    return paymentPage(title, [
      if (busy) const LinearProgressIndicator(color: SendohColors.teal),
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
            isRecipient
                ? t('From {payer}', {'payer': payer})
                : delivered
                    ? t('Delivered to {payee}', {'payee': payee})
                    : ready
                        ? t('{payee} receives', {'payee': payee})
                        : t('To {payee}', {'payee': payee}),
            style: SendohTextStyles.bodyMedium),
        if (q['reason'] != null)
          Text(t('For {reason}', {'reason': q['reason']}),
              style: SendohTextStyles.caption),
        const SizedBox(height: 28),
        if (ready && !isRecipient) ...[
          paymentSurface([
            paymentRow(
                t('{payee} receives on', {'payee': payee}),
                '${walletLabel(q['receiving_method'])} ${q['receiving_masked'] ?? ''}'
                    .trim()),
            paymentRow(
                t('Fees'),
                personMoney((a['collection_fee'] as num) +
                    (a['delivery_fee'] as num) +
                    (a['sendoh_fee'] as num))),
            const Divider(height: 16),
            paymentRow(t('Total'), personMoney(a['total_debit'])),
          ]),
          ExpansionTile(
              key: const ValueKey('fee-breakdown'),
              tilePadding: EdgeInsets.zero,
              title: Text(t('Fee breakdown')),
              children: [
                paymentRow(
                    t('Processing fee'),
                    personMoney((a['collection_fee'] as num) +
                        (a['delivery_fee'] as num))),
                paymentRow(t('Sendoh fee'), personMoney(a['sendoh_fee'])),
              ]),
          const SizedBox(height: 16),
          Text(t('Pay with'), style: SendohTextStyles.titleSmall),
          const SizedBox(height: 12),
          if (order == null && pending == null)
            PayWithPicker(
                api: widget.api,
                enabled: !busy,
                allowOther: false,
                onEmpty: () {
                  if (mounted) setState(() => noVerifiedNumbers = true);
                },
                onChanged: (id, _, network) {
                  final changed = payerNumberId != null && payerNumberId != id;
                  payerNumberId = id;
                  if (network != null) method = network;
                  if (changed) newQuote();
                }),
          if (order == null && pending == null && noVerifiedNumbers)
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
                                  m == 'MTN' ? 'MTN MoMo' : t('Orange Money'),
                                  style: SendohTextStyles.titleSmall)),
                        ]),
                      )),
                )),
          if (order != null || pending != null)
            paymentRow(t('Method'),
                q['payer_method'] == 'MTN' ? 'MTN MoMo' : t('Orange Money')),
        ],
        if (!ready || isRecipient)
          Semantics(
              liveRegion: true,
              child: Text(copy.body, style: SendohTextStyles.bodyMedium)),
        if (!ready && !terminal && !isRecipient)
          Text(t('You can leave and come back; this payment will be here.'),
              style: SendohTextStyles.caption),
        if (order != null && !ready)
          ExpansionTile(
              key: const ValueKey('payment-details'),
              tilePadding: EdgeInsets.zero,
              title: Text(delivered ? t('View receipt') : t('Payment details')),
              children: [
                paymentRow(t('From'), payer),
                paymentRow('To', payee),
                if (q['reason'] != null) paymentRow(t('For'), '${q['reason']}'),
                paymentRow(
                    t('Received on'),
                    '${walletLabel(q['receiving_method'])} ${q['receiving_masked'] ?? ''}'
                        .trim()),
                paymentRow(t('Payment collection'),
                    paymentStatus(order!['collection_status'])),
                paymentRow(t('Recipient delivery'),
                    paymentStatus(order!['delivery_status'])),
                paymentRow(
                    t('Processing fee'),
                    personMoney((a['collection_fee'] as num) +
                        (a['delivery_fee'] as num))),
                paymentRow(t('Sendoh fee'), personMoney(a['sendoh_fee'])),
                paymentRow(t('Total'), personMoney(a['total_debit'])),
                paymentRow(
                    t('Method'),
                    q['payer_method'] == 'MTN'
                        ? 'MTN MoMo'
                        : t('Orange Money')),
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text(t('Reference'))),
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
        if (expired) Text(t('Refresh the quote before confirming.')),
        FilledButton(
            onPressed: busy || expired || q['execution_available'] != true
                ? null
                : confirm,
            child: Text(
                t('Pay {amount}', {'amount': personMoney(a['total_debit'])}))),
        if (q['execution_available'] != true)
          Text(t(
              'Payment is currently unavailable. No payment has been started.')),
        if (expired)
          TextButton(
              onPressed: busy ? null : newQuote,
              child: Text(t('Refresh quote'))),
      ] else if (status == 'READY') ...[
        FilledButton(
            onPressed:
                busy || outcomeUnknown || order!['execution_available'] != true
                    ? null
                    : confirm,
            child: Text(
                t('Pay {amount}', {'amount': personMoney(a['total_debit'])}))),
        TextButton(
            onPressed: busy ? null : cancelPrepared,
            child: Text(t('Cancel this payment'))),
      ],
      if (quote == null &&
          initialized &&
          pending == null &&
          widget.target != null)
        FilledButton(
            onPressed: busy ? null : newQuote,
            child: Text(t('Review new quote'))),
      if ((order != null && !terminal) || error != null)
        OutlinedButton(
            onPressed: busy ? null : refresh, child: Text(t('Check status'))),
      if (widget.nearby && ready && order == null)
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Wrong person? Scan again')))
      else
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(delivered ? t('Done') : t('Back'))),
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
  Widget build(BuildContext context) => paymentPage(t('Person payments'), [
        if (busy) const LinearProgressIndicator(color: SendohColors.teal),
        if (items?.isEmpty == true)
          Text(t('Your person payments will appear here.')),
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
        TextButton(onPressed: busy ? null : load, child: Text(t('Refresh'))),
      ]);
}
