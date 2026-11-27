import 'i18n.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'design.dart';
import 'people_flows.dart';
import 'person_payments.dart';

/// The request's state from the reader's side. "Received" only after delivery.
String requestHeadline(Map<String, dynamic> r) {
  final mine = r['direction'] == 'RECEIVED'; // I was asked to pay
  final requester = '${r['requester']['name']}';
  final payer = '${r['recipient']['name']}';
  final amount = personMoney(r['amount']);
  switch (r['status']) {
    case 'PAID':
      return mine
          ? t('Paid · delivered to {requester}', {'requester': requester})
          : t('Paid · you received {amount}', {'amount': amount});
    case 'PAYMENT_REVIEW':
      return t('Payment needs attention · nobody pays again');
    case 'DECLINED':
      return mine
          ? t('You declined this request')
          : t('{payer} declined', {'payer': payer});
    case 'CANCELLED':
      return mine
          ? t('{requester} cancelled this request', {'requester': requester})
          : t('You cancelled this request');
    case 'EXPIRED':
      return t('This request expired');
    case 'PROCESSING':
      return r['payment_phase'] == 'DELIVERING'
          ? (mine
              ? t('You paid · delivering to {requester}',
                  {'requester': requester})
              : t('{payer} paid · on its way to you', {'payer': payer}))
          : (mine
              ? t('Confirming your payment')
              : t('{payer} is paying', {'payer': payer}));
  }
  return mine
      ? t('{requester} is waiting for your payment', {'requester': requester})
      : t('Waiting for {payer}', {'payer': payer});
}

String requestStatus(dynamic value) =>
    {
      'PENDING': t('Awaiting payment'),
      'PROCESSING': t('Payment in progress'),
      'PAYMENT_REVIEW': t('Payment under review'),
      'PAID': t('Paid'),
      'DECLINED': t('Declined'),
      'CANCELLED': t('Cancelled'),
      'EXPIRED': t('Expired'),
    }[value] ??
    t('Checking status');

class ApiPeopleGateway implements PeopleFlowGateway {
  ApiPeopleGateway(this.api, this.userId);
  final SendohApi api;
  final String userId;
  @override
  Future<ResolvedPerson> resolve(String identity,
      {required bool fromQr}) async {
    final p = await api.request('/people/resolve',
        body: {'identity': identity, 'from_qr': fromQr});
    return ResolvedPerson(
        id: p['id'],
        name: p['name'],
        identity: p['identity'],
        receivingReady: p['receiving_ready'] != false);
  }

  @override
  Future<void> remindReceiving(String personId) => api
      .request('/people/receiving-reminder', body: {'recipient_id': personId});

  @override
  Future<String?> scan(BuildContext context) async {
    await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(t('QR scanning is not connected yet')),
                content: Text(
                    t('Use the person’s Sendoh username to pay or request.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c), child: Text(t('Done')))
                ]));
    return null;
  }

  @override
  Future<void> openCheckout(BuildContext context, PeopleDraft draft) async {
    if (draft.intent == PeopleIntent.pay) {
      await Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => PersonCheckout(
                  api: api,
                  target: {
                    'recipient_id': draft.person.id,
                    'amount': draft.amount
                  },
                  method: draft.method == 'Orange Money' ? 'ORANGE' : 'MTN')));
      return;
    }
    final body = <String, dynamic>{
      'recipient_id': draft.person.id,
      'amount': draft.amount,
      'reason': draft.note,
      'expires_at': draft.expiry == null
          ? null
          : DateTime(draft.expiry!.year, draft.expiry!.month, draft.expiry!.day,
                      23, 59, 59)
                  .millisecondsSinceEpoch ~/
              1000
    };
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => RequestSend(
                api: api,
                userId: userId,
                body: body,
                personName: draft.person.name)));
  }
}

class RequestSend extends StatefulWidget {
  const RequestSend(
      {super.key,
      required this.api,
      required this.userId,
      this.body,
      this.personName});
  final SendohApi api;
  final String userId;
  final Map<String, dynamic>? body;
  final String? personName;
  @override
  State<RequestSend> createState() => _RequestSendState();
}

class _RequestSendState extends State<RequestSend> {
  static const storage = FlutterSecureStorage();
  Map<String, dynamic>? envelope, result;
  String? error;
  bool busy = true;

  /// The requester must say where they receive money, or the payer hits a dead end.
  bool? receivingReady;
  String get storageKey => 'sendoh-request-pending-${widget.userId}';

  Future<void> checkReceiving() async {
    try {
      final r = await widget.api.request('/me/receiving-destination');
      final d = r['destination'];
      if (mounted) {
        setState(
            () => receivingReady = d is Map && d['identity_current'] == true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => receivingReady = false);
      }
    }
  }

  Future<void> setUpReceiving() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ReceivingDetails(api: widget.api)));
    await checkReceiving();
  }

  @override
  void initState() {
    super.initState();
    restore();
    checkReceiving();
  }

  Future<void> restore() async {
    try {
      final saved = await storage.read(key: storageKey);
      if (!mounted) {
        return;
      }
      if (saved != null) {
        envelope = Map<String, dynamic>.from(jsonDecode(saved));
      } else if (widget.body != null) {
        final random = Random.secure();
        envelope = {
          'key': List.generate(24,
                  (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
              .join(),
          'body': widget.body,
          'name': widget.personName
        };
      }
    } catch (_) {
      error = t('Couldn’t restore the request. Please try again.');
    }
    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> send() async {
    if (busy || envelope == null) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // Persist both payload and key BEFORE submitting. A retry sends exactly these.
      await storage.write(key: storageKey, value: jsonEncode(envelope));
      final data = await widget.api.request('/money-requests',
          body: Map<String, dynamic>.from(envelope!['body']),
          key: envelope!['key']);
      if (mounted) {
        setState(() => result = Map<String, dynamic>.from(data));
      }
      await storage.delete(key: storageKey);
    } catch (e) {
      if (e is ApiException && [403, 404, 422, 429].contains(e.status)) {
        await storage.delete(key: storageKey);
        if (mounted) {
          setState(() => error = t(
              'Request was not sent. Go back to correct the details or try later. {e}',
              {'e': e}));
        }
        return;
      }
      if (mounted) {
        setState(() => error = result == null
            ? t('The result could not be confirmed. Retry this saved request; do not create another. {e}',
                {'e': e})
            : t('Request saved. Local cleanup needs a retry; reopening will check the same request.'));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title:
              Text(result == null ? t('Review and send') : t('Request saved'))),
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
        if (busy) const LinearProgressIndicator(),
        if (envelope != null && result == null) ...[
          Text(
              t('Request from {name}',
                  {'name': envelope!['name'] ?? t('this person')}),
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          Text('${envelope!['body']['amount']} FCFA',
              style:
                  const TextStyle(fontSize: 30, fontWeight: FontWeight.w600)),
          Text(envelope!['body']['reason']),
          Text(envelope!['body']['expires_at'] == null
              ? t('No expiry')
              : t('Expires: {body}', {
                  'body': DateTime.fromMillisecondsSinceEpoch(
                          (envelope!['body']['expires_at'] as int) * 1000)
                      .toLocal()
                })),
          const SizedBox(height: 24),
          Text(t(
              'Sending a request does not charge anyone. If an earlier submission was interrupted, this continues that same request.')),
          const SizedBox(height: 24),
          if (receivingReady == false) ...[
            SurfaceCard(
                color: SendohColors.amberSoft,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('Choose where you receive money first'),
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(t(
                          'Then the person you ask can pay you straight away.')),
                      TextButton(
                          onPressed: setUpReceiving,
                          child: Text(t('Set receiving details'))),
                    ])),
            const SizedBox(height: 16),
          ],
          FilledButton(
              onPressed: busy || receivingReady != true ? null : send,
              child: Text(t('Send or check request'))),
        ],
        if (!busy && envelope == null) Text(t('No saved request to resume.')),
        if (result != null) ...[
          const Icon(Icons.check_circle_outline, size: 40),
          const SizedBox(height: 16),
          Text(requestStatus(result!['status'])),
          Text(t('Your request has been sent. Track the response here.')),
          TextButton(
              onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => MoneyRequestDetail(
                          api: widget.api, id: result!['id']))),
              child: Text(t('View request'))),
        ],
        if (error != null)
          Text(error!, style: const TextStyle(color: SendohColors.red)),
      ])));
}

class MoneyRequestInbox extends StatefulWidget {
  const MoneyRequestInbox({super.key, required this.api, required this.userId});
  final SendohApi api;
  final String userId;
  @override
  State<MoneyRequestInbox> createState() => _MoneyRequestInboxState();
}

class _MoneyRequestInboxState extends State<MoneyRequestInbox> {
  late Future<dynamic> data;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    data = widget.api.request('/money-requests');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(t('Money requests')), actions: [
        IconButton(
            tooltip: t('Refresh'),
            onPressed: () => setState(load),
            icon: const Icon(Icons.refresh))
      ]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextButton(
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) =>
                          RequestSend(api: widget.api, userId: widget.userId)));
              if (mounted) {
                setState(load);
              }
            },
            child: Text(t('Resume an interrupted request'))),
        FutureBuilder<dynamic>(
            future: data,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                    t('Requests could not load. Use Refresh to try again.'));
              }
              if (!snapshot.hasData) {
                return const LinearProgressIndicator();
              }
              final rows = snapshot.data['items'] as List;
              if (rows.isEmpty) {
                return Text(t('No money requests yet.'));
              }
              return Column(children: [
                Text(t('Latest 100 requests · sent and received')),
                ...rows.map((r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        '${r['amount']} FCFA · ${r['direction'] == 'SENT' ? r['recipient']['name'] : r['requester']['name']}'),
                    subtitle: Text(
                        '${r['reason']} · ${requestHeadline(Map<String, dynamic>.from(r))}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => MoneyRequestDetail(
                                  api: widget.api, id: r['id'])));
                      if (mounted) {
                        setState(load);
                      }
                    })),
              ]);
            }),
      ]));
}

class MoneyRequestDetail extends StatefulWidget {
  const MoneyRequestDetail({super.key, required this.api, required this.id});
  final SendohApi api;
  final String id;
  @override
  State<MoneyRequestDetail> createState() => _MoneyRequestDetailState();
}

class _MoneyRequestDetailState extends State<MoneyRequestDetail> {
  Map<String, dynamic>? data;
  String? error;
  bool busy = false;
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
      final r = await widget.api.request('/money-requests/${widget.id}');
      if (mounted) {
        setState(() => data = Map<String, dynamic>.from(r));
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

  Future<void> respond() async {
    final action = data!['direction'] == 'SENT' ? 'CANCEL' : 'DECLINE';
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(action == 'CANCEL'
                    ? t('Cancel request?')
                    : t('Decline request?')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text(t('Keep request'))),
                  TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(t('Confirm')))
                ]));
    if (!mounted || yes != true) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await widget.api.request('/money-requests/${widget.id}/respond',
          body: {'action': action});
      if (mounted) {
        setState(() => data = Map<String, dynamic>.from(r));
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
      appBar: AppBar(title: Text(t('Money request')), actions: [
        IconButton(
            tooltip: t('Refresh'),
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh))
      ]),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        if (busy) const LinearProgressIndicator(),
        if (data != null) ...[
          Row(children: [
            PersonAvatar(
                data!['direction'] == 'RECEIVED'
                    ? '${data!['requester']['name']}'
                    : '${data!['recipient']['name']}',
                radius: 22),
            const SizedBox(width: 12),
            Expanded(
                child: Text(
                    data!['direction'] == 'RECEIVED'
                        ? t('{name} asked you for',
                            {'name': data!['requester']['name']})
                        : t('You asked {name} for',
                            {'name': data!['recipient']['name']}),
                    style: SendohTextStyles.titleSmall)),
          ]),
          const SizedBox(height: 16),
          Text(personMoney(data!['amount']),
              style: SendohTextStyles.displayLarge),
          Text(t('For {reason}', {'reason': data!['reason']}),
              style: SendohTextStyles.bodyMedium),
          const SizedBox(height: 20),
          Semantics(
              liveRegion: true,
              child: StatusBadge(requestHeadline(data!),
                  pending: data!['status'] != 'PAID')),
          if (data!['payment_order_id'] != null)
            TextButton(
                onPressed: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => PersonCheckout(
                              api: widget.api,
                              orderId: data!['payment_order_id'])));
                  if (mounted) {
                    load();
                  }
                },
                child: Text(data!['status'] == 'PAID'
                    ? t('View receipt')
                    : t('View payment'))),
          if (data!['expires_at'] != null)
            Text(t('Expires: {expires_at}', {
              'expires_at': DateTime.fromMillisecondsSinceEpoch(
                      (data!['expires_at'] as int) * 1000)
                  .toLocal()
            })),
          const SizedBox(height: 24),
          if (data!['status'] == 'PENDING') ...[
            if (data!['direction'] == 'RECEIVED')
              FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                  builder: (_) => PersonCheckout(
                                      api: widget.api,
                                      target: {'request_id': widget.id})));
                          if (mounted) {
                            load();
                          }
                        },
                  child: Text(t('Review payment'))),
            OutlinedButton(
                onPressed: busy ? null : respond,
                child: Text(data!['direction'] == 'SENT'
                    ? t('Cancel request')
                    : t('Decline request'))),
          ],
        ],
        if (error != null)
          Text(error!, style: const TextStyle(color: SendohColors.red)),
      ]));
}
