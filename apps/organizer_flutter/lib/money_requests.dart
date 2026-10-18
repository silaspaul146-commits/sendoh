import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'design.dart';
import 'people_flows.dart';

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
        id: p['id'], name: p['name'], identity: p['identity']);
  }

  @override
  Future<String?> scan(BuildContext context) async {
    await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('QR scanning is not connected yet'),
                content: const Text(
                    'Use the person’s Sendoh username to pay or request.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Done'))
                ]));
    return null;
  }

  @override
  Future<void> openCheckout(BuildContext context, PeopleDraft draft) async {
    if (draft.intent == PeopleIntent.pay) {
      await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('Payments are not available yet'),
                  content: const Text(
                      'No payment has been submitted. Live quotes and provider authorisation are still being connected.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('Done'))
                  ]));
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
  String get storageKey => 'sendoh-request-pending-${widget.userId}';
  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    try {
      final saved = await storage.read(key: storageKey);
      if (!mounted) return;
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
      error = 'Couldn’t restore the request. Please try again.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> send() async {
    if (busy || envelope == null) return;
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
      if (mounted) setState(() => result = Map<String, dynamic>.from(data));
      await storage.delete(key: storageKey);
    } catch (e) {
      if (e is ApiException && [403, 404, 422, 429].contains(e.status)) {
        await storage.delete(key: storageKey);
        if (mounted) {
          setState(() => error =
              'Request was not sent. Go back to correct the details or try later. $e');
        }
        return;
      }
      if (mounted) {
        setState(() => error = result == null
            ? 'The result could not be confirmed. Retry this saved request; do not create another. $e'
            : 'Request saved. Local cleanup needs a retry; reopening will check the same request.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(result == null ? 'Review and send' : 'Request saved')),
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
        if (busy) const LinearProgressIndicator(),
        if (envelope != null && result == null) ...[
          Text('Request from ${envelope!['name'] ?? 'this person'}',
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          Text('${envelope!['body']['amount']} FCFA',
              style:
                  const TextStyle(fontSize: 30, fontWeight: FontWeight.w600)),
          Text(envelope!['body']['reason']),
          Text(envelope!['body']['expires_at'] == null
              ? 'No expiry'
              : 'Expires: ${DateTime.fromMillisecondsSinceEpoch((envelope!['body']['expires_at'] as int) * 1000).toLocal()}'),
          const SizedBox(height: 24),
          const Text(
              'Sending a request does not charge anyone. If an earlier submission was interrupted, this continues that same request.'),
          const SizedBox(height: 24),
          FilledButton(
              onPressed: busy ? null : send,
              child: const Text('Send or check request')),
        ],
        if (!busy && envelope == null)
          const Text('No saved request to resume.'),
        if (result != null) ...[
          const Icon(Icons.check_circle_outline, size: 40),
          const SizedBox(height: 16),
          Text('Status: ${result!['status']}'),
          const Text('The request is saved on Sendoh. No money has moved.'),
          TextButton(
              onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => MoneyRequestDetail(
                          api: widget.api, id: result!['id']))),
              child: const Text('View request')),
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
      appBar: AppBar(title: const Text('Money requests'), actions: [
        IconButton(
            tooltip: 'Refresh',
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
              if (mounted) setState(load);
            },
            child: const Text('Resume an interrupted request')),
        FutureBuilder<dynamic>(
            future: data,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text(
                    'Requests could not load. Use Refresh to try again.');
              }
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final rows = snapshot.data['items'] as List;
              if (rows.isEmpty) return const Text('No money requests yet.');
              return Column(children: [
                const Text('Latest 100 requests · sent and received'),
                ...rows.map((r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        '${r['amount']} FCFA · ${r['direction'] == 'SENT' ? r['recipient']['name'] : r['requester']['name']}'),
                    subtitle: Text(
                        '${r['reason']} · ${r['direction']} · ${r['status']}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => MoneyRequestDetail(
                                  api: widget.api, id: r['id'])));
                      if (mounted) setState(load);
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
      if (mounted) setState(() => data = Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> respond() async {
    final action = data!['direction'] == 'SENT' ? 'CANCEL' : 'DECLINE';
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(action == 'CANCEL'
                    ? 'Cancel request?'
                    : 'Decline request?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Keep request')),
                  TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Confirm'))
                ]));
    if (!mounted || yes != true) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await widget.api.request('/money-requests/${widget.id}/respond',
          body: {'action': action});
      if (mounted) setState(() => data = Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Money request'), actions: [
        IconButton(
            tooltip: 'Refresh',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh))
      ]),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        if (busy) const LinearProgressIndicator(),
        if (data != null) ...[
          Text(
              data!['direction'] == 'RECEIVED'
                  ? '${data!['requester']['name']} requested'
                  : 'Requested from ${data!['recipient']['name']}',
              style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 20),
          Text('${data!['amount']} FCFA',
              style:
                  const TextStyle(fontSize: 32, fontWeight: FontWeight.w600)),
          Text(data!['reason']),
          const SizedBox(height: 20),
          Text('Status: ${data!['status']}'),
          if (data!['expires_at'] != null)
            Text(
                'Expires: ${DateTime.fromMillisecondsSinceEpoch((data!['expires_at'] as int) * 1000).toLocal()}'),
          const SizedBox(height: 24),
          if (data!['status'] == 'PENDING') ...[
            if (data!['direction'] == 'RECEIVED')
              const Text(
                  'Payment is not available yet. This request has not charged you.'),
            OutlinedButton(
                onPressed: busy ? null : respond,
                child: Text(data!['direction'] == 'SENT'
                    ? 'Cancel request'
                    : 'Decline request')),
          ],
        ],
        if (error != null)
          Text(error!, style: const TextStyle(color: SendohColors.red)),
      ]));
}
