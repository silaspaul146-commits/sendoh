import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'api.dart';
import 'design.dart';

String invitationLabel(dynamic value) => switch (value) {
      'PENDING' => 'Invited',
      'ACCEPTED' => 'Joined',
      'DECLINED' => 'Declined',
      'CANCELLED' => 'Cancelled',
      'EXPIRED' => 'Expired',
      _ => 'Name only · unverified',
    };

String _amount(dynamic value) => value == null
    ? 'Any amount'
    : '${value.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')} FCFA';

class InvitePerson extends StatefulWidget {
  const InvitePerson(
      {super.key,
      required this.api,
      required this.collection,
      this.participant});
  final SendohApi api;
  final Map<String, dynamic> collection;
  final Map<String, dynamic>? participant;
  @override
  State<InvitePerson> createState() => _InvitePersonState();
}

class _InvitePersonState extends State<InvitePerson> {
  final form = GlobalKey<FormState>();
  final identity = TextEditingController();
  late final name =
      TextEditingController(text: widget.participant?['name'] as String? ?? '');
  late final amount = TextEditingController(
      text: (widget.participant?['expected_amount'] ??
                  widget.collection['expected_amount'])
              ?.toString() ??
          '');
  bool phone = false, busy = false;
  String? error, lastBody, requestKey;

  @override
  void dispose() {
    identity.dispose();
    name.dispose();
    amount.dispose();
    super.dispose();
  }

  String normalizedIdentity() {
    final value = identity.text.trim();
    if (!phone) {
      return value.replaceFirst(RegExp(r'^@'), '').toLowerCase();
    }
    final digits = value.replaceAll(RegExp(r'[\s()-]'), '');
    return RegExp(r'^[26][0-9]{8}$').hasMatch(digits) ? '+237$digits' : digits;
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) {
      return;
    }
    final body = <String, dynamic>{
      if (phone)
        'phone': normalizedIdentity()
      else
        'username': normalizedIdentity(),
      if (phone && name.text.trim().isNotEmpty) 'name': name.text.trim(),
      if (widget.participant != null)
        'participant_id': widget.participant!['id'],
      if (widget.collection['mode'] != 'ANY_AMOUNT' &&
          amount.text.trim().isNotEmpty)
        'expected_amount': int.parse(amount.text.trim()),
    };
    // An unchanged retry reuses its key, including after a network timeout.
    final encoded = jsonEncode(body);
    if (lastBody != encoded) {
      final random = Random.secure();
      requestKey = List.generate(
              24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
      lastBody = encoded;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.request(
          '/collections/${widget.collection['id']}/invitations',
          body: body,
          key: requestKey);
      if (mounted) {
        Navigator.of(context).pop(true);
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
        appBar: AppBar(title: const Text('Invite someone')),
        body: Form(
            key: form,
            child: ListView(padding: const EdgeInsets.all(22), children: [
              const SendohBrand(),
              const SizedBox(height: 24),
              Text(widget.collection['name'] as String,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              const Text(
                  'Choose the person by their exact Sendoh username or phone number. They decide whether to join.',
                  style: TextStyle(height: 1.6, color: SendohColors.secondary)),
              if (widget.participant != null) ...[
                const SizedBox(height: 16),
                SurfaceCard(
                    child: Text(
                        'Link the existing entry: ${widget.participant!['name']}')),
              ],
              const SizedBox(height: 20),
              Wrap(spacing: 10, children: [
                ChoiceChip(
                    label: const Text('Username'),
                    selected: !phone,
                    onSelected: busy
                        ? null
                        : (_) => setState(() {
                              phone = false;
                              identity.clear();
                              error = null;
                            })),
                ChoiceChip(
                    label: const Text('Phone number'),
                    selected: phone,
                    onSelected: busy
                        ? null
                        : (_) => setState(() {
                              phone = true;
                              identity.clear();
                              error = null;
                            })),
              ]),
              const SizedBox(height: 16),
              TextFormField(
                  controller: identity,
                  enabled: !busy,
                  autocorrect: false,
                  keyboardType:
                      phone ? TextInputType.phone : TextInputType.text,
                  decoration: InputDecoration(
                      labelText: phone ? 'Phone number' : 'Sendoh username',
                      hintText: phone ? '+237 6XX XXX XXX' : '@username'),
                  validator: (_) => (phone
                              ? RegExp(r'^\+237[26][0-9]{8}$')
                              : RegExp(r'^[a-z][a-z0-9_]{2,23}$'))
                          .hasMatch(normalizedIdentity())
                      ? null
                      : (phone
                          ? 'Enter a valid Cameroon phone number.'
                          : 'Enter a valid Sendoh username.')),
              if (phone) ...[
                const SizedBox(height: 16),
                TextFormField(
                    controller: name,
                    enabled: !busy,
                    maxLength: 120,
                    decoration: const InputDecoration(
                        labelText: 'Name for your records (optional)')),
              ],
              if (widget.collection['mode'] != 'ANY_AMOUNT') ...[
                const SizedBox(height: 16),
                TextFormField(
                    controller: amount,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Expected amount (FCFA)'),
                    validator: (v) => v == null ||
                            v.trim().isEmpty ||
                            (int.tryParse(v.trim()) != null &&
                                int.parse(v.trim()) > 0)
                        ? null
                        : 'Enter a positive whole amount.'),
              ],
              const SizedBox(height: 20),
              const SurfaceCard(
                  color: SendohColors.tealSoft,
                  child: Text(
                      'The invitation appears in their Sendoh app. A new user must verify the invited phone number first. You can let them know on WhatsApp; no SMS or push alert is sent yet.',
                      style: TextStyle(fontSize: 13, height: 1.6))),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(error!,
                        style: const TextStyle(color: SendohColors.red))),
              const SizedBox(height: 24),
              FilledButton(
                  onPressed: busy ? null : submit,
                  child: Text(busy ? 'Inviting…' : 'Send invitation')),
            ])),
      );
}

class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key, required this.api});
  final SendohApi api;
  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  List<dynamic> pending = [], joined = [];
  bool loading = true, showJoined = false;
  String? error;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.request('/me/invitations'),
        widget.api.request('/me/joined-collections'),
      ]);
      if (mounted) {
        setState(() {
          pending = List<dynamic>.from(results[0]);
          joined = List<dynamic>.from(results[1]);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> open(Map<String, dynamic> item) async {
    final result = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => InvitationDetail(api: widget.api, invitation: item)));
    if (!mounted) {
      return;
    }
    if (result == 'ACCEPTED') {
      setState(() => showJoined = true);
    }
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final rows = showJoined ? joined : pending;
    return Scaffold(
      appBar: AppBar(title: const Text('Your invitations'), actions: [
        IconButton(
            tooltip: 'Refresh',
            onPressed: loading ? null : refresh,
            icon: const Icon(Icons.refresh)),
      ]),
      body: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(22),
              children: [
                const Text('Together starts here.',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text(
                    'Review who invited you and choose which collections to join.',
                    style:
                        TextStyle(height: 1.6, color: SendohColors.secondary)),
                const SizedBox(height: 20),
                Wrap(spacing: 10, children: [
                  ChoiceChip(
                      label: Text('Invitations (${pending.length})'),
                      selected: !showJoined,
                      onSelected: (_) => setState(() => showJoined = false)),
                  ChoiceChip(
                      label: Text('Joined (${joined.length})'),
                      selected: showJoined,
                      onSelected: (_) => setState(() => showJoined = true)),
                ]),
                const SizedBox(height: 20),
                if (loading) const LinearProgressIndicator(),
                if (error != null) ...[
                  Text(error!, style: const TextStyle(color: SendohColors.red)),
                  TextButton(
                      onPressed: refresh, child: const Text('Try again')),
                ] else if (!loading && rows.isEmpty)
                  EmptyState(
                      title: showJoined
                          ? 'No joined collections yet'
                          : 'No invitations yet',
                      message: showJoined
                          ? 'Collections you accept will appear here.'
                          : 'Ask the organizer to invite your username or verified phone number. Pull down to refresh.',
                      icon: Icons.mail_outline),
                if (!loading && error == null)
                  ...rows.map((raw) {
                    final item = Map<String, dynamic>.from(raw);
                    final c = Map<String, dynamic>.from(item['collection']);
                    return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: SurfaceCard(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                const CollectionSymbol(),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Text(c['name'] as String,
                                        style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600))),
                              ]),
                              const SizedBox(height: 12),
                              Text('Organized by ${c['organizer_name']}'),
                              SummaryRow('Your expected amount',
                                  _amount(item['expected_amount'])),
                              OutlinedButton(
                                  onPressed: () => open(item),
                                  child: Text(showJoined
                                      ? 'View collection'
                                      : 'Review invitation')),
                            ])));
                  }),
              ])),
    );
  }
}

class InvitationDetail extends StatefulWidget {
  const InvitationDetail(
      {super.key, required this.api, required this.invitation});
  final SendohApi api;
  final Map<String, dynamic> invitation;
  @override
  State<InvitationDetail> createState() => _InvitationDetailState();
}

class _InvitationDetailState extends State<InvitationDetail> {
  bool busy = false;
  String? error;
  Future<void> respond(String decision) async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.request(
          '/me/invitations/${widget.invitation['id']}/respond',
          body: {'decision': decision});
      if (mounted) {
        Navigator.of(context).pop(result['invitation_state'] as String);
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
  Widget build(BuildContext context) {
    final item = widget.invitation;
    final c = Map<String, dynamic>.from(item['collection']);
    final pending = item['invitation_state'] == 'PENDING';
    return Scaffold(
      appBar: AppBar(
          title: Text(pending ? 'Collection invitation' : 'Joined collection')),
      body: ListView(padding: const EdgeInsets.all(22), children: [
        const Center(child: CollectionSymbol()),
        const SizedBox(height: 20),
        Text(c['name'] as String,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Text('Organized by ${c['organizer_name']}',
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        Center(
            child: StatusBadge(invitationLabel(item['invitation_state']),
                pending: pending)),
        const SizedBox(height: 20),
        if ((c['description'] as String? ?? '').isNotEmpty)
          Text(c['description'] as String, style: const TextStyle(height: 1.6)),
        const SizedBox(height: 16),
        SurfaceCard(
            child: Column(children: [
          SummaryRow('Your expected amount', _amount(item['expected_amount'])),
          SummaryRow('Deadline', displayDate(c['deadline_at'])),
          SummaryRow('Collected', _amount(c['collected_amount'])),
        ])),
        const SizedBox(height: 20),
        Text(
            pending
                ? 'Accepting adds your verified Sendoh profile to this collection. It does not make a payment.'
                : 'You have joined this collection. No payment has been made through Sendoh. Payments are not available yet.',
            style: const TextStyle(height: 1.6, color: SendohColors.secondary)),
        if (pending && item['expires_at'] != null) ...[
          const SizedBox(height: 10),
          Text(
              'Invitation expires ${displayDate(DateTime.fromMillisecondsSinceEpoch((item['expires_at'] as int) * 1000, isUtc: true).toIso8601String())}',
              style: const TextStyle(fontSize: 12, color: SendohColors.muted)),
        ],
        if (error != null)
          Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(error!,
                  style: const TextStyle(color: SendohColors.red))),
        const SizedBox(height: 24),
        if (pending) ...[
          FilledButton(
              onPressed: busy ? null : () => respond('accept'),
              child: Text(busy ? 'Updating…' : 'Accept invitation')),
          const SizedBox(height: 12),
          OutlinedButton(
              onPressed: busy ? null : () => respond('decline'),
              child: const Text('Decline')),
        ],
      ]),
    );
  }
}
