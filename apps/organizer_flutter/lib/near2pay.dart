/// Near2Pay: two people together pay or contribute without exchanging numbers.
///
/// A code only identifies who is being paid (a person) or what is being paid
/// into (a collection). Money only moves through the existing checkouts, after
/// the payer has seen who, how much and the fees, and approved.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'api.dart';
import 'contribution_checkout.dart' show ContributionCheckout;
import 'coordination.dart' show coordinationMoney;
import 'design.dart';
import 'person_payments.dart' show PersonCheckout, ReceivingDetails;

const nearQrPrefix = 'sendoh:near:';

String initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .take(2)
    .map((w) => w.characters.first.toUpperCase())
    .join();

/// A one-field dialog that owns its controller, so closing it never touches a
/// disposed controller while the route animates out.
class TextPrompt extends StatefulWidget {
  const TextPrompt(
      {super.key,
      required this.title,
      required this.action,
      this.initial = '',
      this.keyboardType,
      this.capitalization = TextCapitalization.none,
      this.style,
      this.decoration = const InputDecoration()});
  final String title, action, initial;
  final TextInputType? keyboardType;
  final TextCapitalization capitalization;
  final TextStyle? style;
  final InputDecoration decoration;
  @override
  State<TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<TextPrompt> {
  late final field = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
            controller: field,
            autofocus: true,
            keyboardType: widget.keyboardType,
            textCapitalization: widget.capitalization,
            style: widget.style,
            decoration: widget.decoration),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, field.text.trim()),
              child: Text(widget.action)),
        ],
      );
}

class _Who extends StatelessWidget {
  const _Who({required this.name, required this.subtitle});
  final String name, subtitle;
  @override
  Widget build(BuildContext context) => Row(children: [
        CircleAvatar(
            radius: 26,
            backgroundColor: SendohColors.tealSoft,
            child: Text(initials(name),
                style: const TextStyle(
                    color: SendohColors.teal, fontWeight: FontWeight.w700))),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: SendohTextStyles.titleSmall),
          Text(subtitle, style: SendohTextStyles.caption),
        ])),
      ]);
}

/// Aïcha: "Get paid nearby". A personal code, or a code for her open collection.
class NearReceiveScreen extends StatefulWidget {
  const NearReceiveScreen(
      {super.key, required this.api, this.collectionId, this.collectionName});
  final SendohApi api;
  final String? collectionId, collectionName;
  @override
  State<NearReceiveScreen> createState() => _NearReceiveScreenState();
}

class _NearReceiveScreenState extends State<NearReceiveScreen> {
  Map<String, dynamic>? me, code, received;
  int? amount, since;
  int secondsLeft = 0;
  bool? receivingReady;
  String? error;
  Timer? tick, poll;

  bool get forCollection => widget.collectionId != null;

  @override
  void initState() {
    super.initState();
    start();
  }

  @override
  void dispose() {
    tick?.cancel();
    poll?.cancel();
    super.dispose();
  }

  Future<void> start() async {
    try {
      me = Map<String, dynamic>.from(await widget.api.request('/me'));
      if (!forCollection) {
        final r = await widget.api.request('/me/receiving-destination');
        final d = r['destination'];
        receivingReady = d is Map && d['identity_current'] == true;
      }
      if (forCollection || receivingReady == true) {
        await newCode();
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    }
  }

  Future<void> newCode() async {
    try {
      final c = Map<String, dynamic>.from(
          await widget.api.request('/near/codes', body: {
        if (amount != null) 'amount': amount,
        if (forCollection) 'collection_id': widget.collectionId,
      }));
      if (!mounted) {
        return;
      }
      setState(() {
        code = c;
        error = null;
        since ??= (c['created_at'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch ~/ 1000;
      });
      tick?.cancel();
      tick = Timer.periodic(const Duration(seconds: 1), (_) {
        final left = (code!['expires_at'] as num).toInt() -
            DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (!mounted) {
          return;
        }
        if (left <= 0 && received == null) {
          tick?.cancel();
          newCode(); // Codes refresh on their own while the screen is open.
        } else {
          setState(() => secondsLeft = left < 0 ? 0 : left);
        }
      });
      poll ??=
          Timer.periodic(const Duration(seconds: 5), (_) => checkReceived());
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    }
  }

  /// "Received" only after verified delivery (person) or confirmed contribution.
  Future<void> checkReceived() async {
    if (received != null || since == null) {
      return;
    }
    try {
      final data = await widget.api.request('/me/notifications');
      final items = (data is Map ? data['items'] : data) as List;
      for (final raw in items) {
        final n = Map<String, dynamic>.from(raw);
        if (((n['created_at'] as num?) ?? 0) < since!) {
          continue;
        }
        final match = forCollection
            ? n['kind'] == 'CONTRIBUTION_CONFIRMED' &&
                n['collection_id'] == widget.collectionId
            : n['kind'] == 'PERSON_RECEIVED' && n['order_id'] != null;
        if (!match) {
          continue;
        }
        Map<String, dynamic>? order;
        if (!forCollection) {
          order = Map<String, dynamic>.from(await widget.api
              .request('/person-payments/orders/${n['order_id']}'));
        }
        if (mounted) {
          tick?.cancel();
          poll?.cancel();
          setState(() => received = {'note': n, 'order': order});
        }
        return;
      }
    } catch (_) {
      // Quiet: the next check retries.
    }
  }

  Future<void> editAmount() async {
    final value = await showDialog<String>(
        context: context,
        builder: (_) => TextPrompt(
            title: 'Requested amount',
            action: 'Save',
            initial: amount?.toString() ?? '',
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                suffixText: 'FCFA',
                helperText: 'Leave empty to let them enter it')));
    if (value == null) {
      return;
    }
    final parsed = int.tryParse(value.replaceAll(',', ''));
    if (value.isNotEmpty && (parsed == null || parsed <= 0)) {
      setState(() => error = 'Enter a whole FCFA amount.');
      return;
    }
    amount = value.isEmpty ? null : parsed;
    await newCode(); // The amount is part of the code.
  }

  Future<void> setUpReceiving() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ReceivingDetails(api: widget.api)));
    await start();
  }

  @override
  Widget build(BuildContext context) {
    final r = received;
    return Scaffold(
        appBar: AppBar(title: Text(r == null ? 'Get paid nearby' : 'Sendoh')),
        body: ListView(padding: const EdgeInsets.all(22), children: [
          if (r != null)
            ..._received(r)
          else ...[
            if (me != null)
              Center(
                  child: Column(children: [
                Text(
                    forCollection
                        ? 'Contribute to ${widget.collectionName}'
                        : '${me!['display_name']}',
                    textAlign: TextAlign.center,
                    style: SendohTextStyles.headingMedium),
                Text(
                    forCollection
                        ? 'Organized by ${me!['display_name']}'
                        : '@${me!['username']}',
                    style: SendohTextStyles.caption),
              ])),
            const SizedBox(height: 16),
            if (receivingReady == false)
              SurfaceCard(
                  color: SendohColors.amberSoft,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Choose where you receive money first',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        TextButton(
                            onPressed: setUpReceiving,
                            child: const Text('Set receiving details')),
                      ])),
            if (code != null) ...[
              Center(
                  child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16)),
                      child: Semantics(
                          label: 'QR code to pay you',
                          child: QrImageView(
                              data: code!['qr'] as String,
                              size: 220,
                              eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.square,
                                  color: SendohColors.ink),
                              dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.square,
                                  color: SendohColors.ink))))),
              const SizedBox(height: 12),
              Center(
                  child: SelectableText(code!['short_code'] as String,
                      style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3,
                          color: SendohColors.teal))),
              Center(
                  child: Text(
                      'Code refreshes in ${secondsLeft ~/ 60}:${(secondsLeft % 60).toString().padLeft(2, '0')}',
                      style: SendohTextStyles.caption)),
              const SizedBox(height: 16),
              const Divider(),
              Row(children: [
                const Expanded(
                    child: Text('Requested amount',
                        style: SendohTextStyles.bodyMedium)),
                Text(
                    amount == null
                        ? 'They enter it'
                        : coordinationMoney(amount),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                IconButton(
                    tooltip: 'Edit requested amount',
                    onPressed: editAmount,
                    icon: const Icon(Icons.edit_outlined,
                        color: SendohColors.teal)),
              ]),
              const SizedBox(height: 8),
              const Text(
                  'Scanning only shows them who you are. They see the fees and approve the payment on their phone.',
                  style: SendohTextStyles.caption),
            ],
          ],
          if (error != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!,
                    style: const TextStyle(color: SendohColors.red))),
        ]));
  }

  List<Widget> _received(Map<String, dynamic> r) {
    final order = r['order'] as Map<String, dynamic>?;
    final note = Map<String, dynamic>.from(r['note'] as Map);
    final amounts = order == null
        ? null
        : Map<String, dynamic>.from(order['quote']['amounts'] as Map);
    return [
      const SizedBox(height: 24),
      const Center(
          child: CircleAvatar(
              radius: 44,
              backgroundColor: SendohColors.tealSoft,
              child: Icon(Icons.check, size: 48, color: SendohColors.teal))),
      const SizedBox(height: 16),
      Text(forCollection ? 'Contribution received' : 'Payment received',
          textAlign: TextAlign.center, style: SendohTextStyles.headingMedium),
      const SizedBox(height: 8),
      if (amounts != null) ...[
        Text(coordinationMoney(amounts['recipient_amount']),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: SendohColors.ink)),
        Text('From ${order!['payer']?['name'] ?? 'Sendoh user'}',
            textAlign: TextAlign.center, style: SendohTextStyles.bodyMedium),
        const SizedBox(height: 16),
        const Divider(),
        SummaryRow(
            'Received on',
            order['quote']['receiving_method'] == 'ORANGE'
                ? 'Orange Money'
                : 'MTN MoMo'),
        SummaryRow(
            'Reference', (order['id'] as String).substring(0, 8).toUpperCase()),
        const SizedBox(height: 20),
        OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    PersonCheckout(api: widget.api, orderId: order['id']))),
            child: const Text('View receipt')),
      ] else
        Text(note['title'] as String? ?? '',
            textAlign: TextAlign.center, style: SendohTextStyles.bodyMedium),
      const SizedBox(height: 8),
      const Text('Sandbox · no real money moves',
          textAlign: TextAlign.center, style: SendohTextStyles.caption),
    ];
  }
}

/// Daniel: scan or type a code, then see exactly what he is paying into.
class NearScanScreen extends StatefulWidget {
  const NearScanScreen({super.key, required this.api, this.scanner = true});
  final SendohApi api;

  /// False in tests and on devices without a camera: code entry only.
  final bool scanner;
  @override
  State<NearScanScreen> createState() => _NearScanScreenState();
}

class _NearScanScreenState extends State<NearScanScreen> {
  MobileScannerController? camera;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.scanner) {
      camera = MobileScannerController(
          detectionSpeed: DetectionSpeed.noDuplicates,
          formats: const [BarcodeFormat.qrCode]);
    }
  }

  @override
  void dispose() {
    camera?.dispose();
    super.dispose();
  }

  String message(Object e) {
    if (e is ApiException) {
      return switch (e.status) {
        404 =>
          'This code has expired or is not valid. Ask them to show a new one. Nothing was paid.',
        429 =>
          'Too many codes tried. Wait a few minutes, or find them by username.',
        _ => e.message,
      };
    }
    return 'Couldn’t check the code. Check your connection and try again.';
  }

  Future<void> handle(String raw) async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    await camera?.stop();
    try {
      final r = Map<String, dynamic>.from(
          await widget.api.request('/near/resolve', body: {'code': raw}));
      if (!mounted) {
        return;
      }
      if (r['purpose'] == 'COLLECTION') {
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => NearContributeScreen(api: widget.api, result: r)));
      } else {
        final person = Map<String, dynamic>.from(r['person'] as Map);
        var amount = (r['amount'] as num?)?.toInt();
        amount ??= await Navigator.of(context).push<int>(MaterialPageRoute(
            builder: (_) => NearAmountScreen(person: person)));
        if (amount != null && mounted) {
          // The existing checkout: who, amount, fees and total before approval.
          await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => PersonCheckout(
                  api: widget.api,
                  nearby: true,
                  target: {'recipient_id': person['id'], 'amount': amount})));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = message(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
      await camera?.start();
    }
  }

  Future<void> typeCode() async {
    final value = await showDialog<String>(
        context: context,
        builder: (_) => const TextPrompt(
            title: 'Enter their code',
            action: 'Find person',
            capitalization: TextCapitalization.characters,
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 4),
            decoration: InputDecoration(hintText: 'K7M-4QX')));
    if (value != null && value.isNotEmpty) {
      await handle(value);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: SendohColors.ink,
      appBar: AppBar(
          backgroundColor: SendohColors.ink,
          foregroundColor: Colors.white,
          title: const Text('Pay nearby')),
      body: SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(children: [
                Expanded(
                    child: Center(
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: SizedBox(
                                width: 280,
                                height: 280,
                                child: camera == null
                                    ? const ColoredBox(
                                        color: Color(0xFF1E4545),
                                        child: Center(
                                            child: Icon(Icons.qr_code_scanner,
                                                size: 64, color: Colors.white)))
                                    : MobileScanner(
                                        controller: camera,
                                        errorBuilder: (context, e, child) =>
                                            const ColoredBox(
                                                color: Color(0xFF1E4545),
                                                child: Padding(
                                                    padding: EdgeInsets.all(20),
                                                    child: Center(
                                                        child: Text(
                                                            'Camera access is off. Allow the camera in your phone settings, or enter their code.',
                                                            textAlign: TextAlign
                                                                .center,
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .white))))),
                                        onDetect: (capture) {
                                          final raw = capture.barcodes
                                              .map((b) => b.rawValue)
                                              .whereType<String>()
                                              .where((v) =>
                                                  v.startsWith(nearQrPrefix))
                                              .firstOrNull;
                                          if (raw != null) {
                                            handle(raw);
                                          }
                                        }))))),
                const Text('Scan their Sendoh code',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text(
                    'You’ll see who it is before anything else happens. Scanning never sends money.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFCFE3E0), fontSize: 13)),
                if (busy)
                  const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child:
                          LinearProgressIndicator(color: SendohColors.orange)),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Semantics(
                          liveRegion: true,
                          child: Text(error!,
                              textAlign: TextAlign.center,
                              style:
                                  const TextStyle(color: Color(0xFFFFD7B0))))),
                const SizedBox(height: 20),
                OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                        minimumSize: const Size.fromHeight(50)),
                    onPressed: busy ? null : typeCode,
                    child: const Text('Enter code instead')),
                TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) =>
                                NearReceiveScreen(api: widget.api))),
                    child: const Text('Get paid nearby',
                        style: TextStyle(color: Color(0xFFE6FFFA)))),
              ]))));
}

/// Only when the code carries no amount: the payer enters it, then reviews fees.
class NearAmountScreen extends StatefulWidget {
  const NearAmountScreen({super.key, required this.person});
  final Map<String, dynamic> person;
  @override
  State<NearAmountScreen> createState() => _NearAmountScreenState();
}

class _NearAmountScreenState extends State<NearAmountScreen> {
  final field = TextEditingController();
  String? error;
  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('Pay ${widget.person['name']}')),
      body: ListView(padding: const EdgeInsets.all(22), children: [
        _Who(
            name: widget.person['name'] as String,
            subtitle: widget.person['identity'] as String),
        const SizedBox(height: 24),
        TextField(
            controller: field,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
                labelText: 'Amount', suffixText: 'FCFA', errorText: error)),
        const SizedBox(height: 8),
        const Text('You’ll see fees and approve on the next screen.',
            style: SendohTextStyles.caption),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: () {
              final n = int.tryParse(field.text.trim().replaceAll(',', ''));
              if (n == null || n <= 0 || n > 1000000000) {
                setState(() => error = 'Enter a whole FCFA amount.');
                return;
              }
              Navigator.pop(context, n);
            },
            child: const Text('Review payment')),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Wrong person? Scan again')),
      ]));
}

/// A collection code: always "Contribute to <collection>", never a personal payment.
class NearContributeScreen extends StatefulWidget {
  const NearContributeScreen(
      {super.key, required this.api, required this.result});
  final SendohApi api;
  final Map<String, dynamic> result;
  @override
  State<NearContributeScreen> createState() => _NearContributeScreenState();
}

class _NearContributeScreenState extends State<NearContributeScreen> {
  bool busy = false;
  String? error;
  late String membership = widget.result['membership'] as String;

  Map<String, dynamic> get collection =>
      Map<String, dynamic>.from(widget.result['collection'] as Map);
  Map<String, dynamic> get organizer =>
      Map<String, dynamic>.from(widget.result['organizer'] as Map);

  Future<void> contribute() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (membership != 'ACCEPTED') {
        // Joining is explicit and separate from paying.
        await widget.api.request(
            '/me/guest-collections/${Uri.encodeComponent(collection['token'] as String)}/join',
            body: {});
        membership = 'ACCEPTED';
      }
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ContributionCheckout(
              api: widget.api,
              collectionId: collection['id'] as String,
              collection: collection['name'] as String,
              name: 'your verified profile',
              expected: (widget.result['amount'] as num?)?.toInt() ??
                  (collection['expected_amount'] as num?)?.toInt())));
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
    final amount = (widget.result['amount'] as num?)?.toInt();
    return Scaffold(
        appBar: AppBar(title: Text('Contribute to ${collection['name']}')),
        body: ListView(padding: const EdgeInsets.all(22), children: [
          const Center(child: CollectionSymbol()),
          const SizedBox(height: 16),
          Text('Contribute to ${collection['name']}',
              textAlign: TextAlign.center,
              style: SendohTextStyles.headingMedium),
          Text('Organized by ${organizer['name']}',
              textAlign: TextAlign.center, style: SendohTextStyles.caption),
          const SizedBox(height: 24),
          if (amount != null)
            SummaryRow('Suggested contribution', coordinationMoney(amount)),
          const SizedBox(height: 8),
          Text(
              membership == 'ACCEPTED'
                  ? 'This counts toward your own share in this collection.'
                  : 'You’ll join ${collection['name']} first. Joining doesn’t make a payment.',
              style: SendohTextStyles.bodyMedium),
          if (error != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!,
                    style: const TextStyle(color: SendohColors.red))),
          const SizedBox(height: 24),
          FilledButton(
              onPressed: busy ? null : contribute,
              child: Text(membership == 'ACCEPTED'
                  ? 'Continue to contribute'
                  : 'Join and contribute')),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Wrong collection? Scan again')),
        ]));
  }
}
