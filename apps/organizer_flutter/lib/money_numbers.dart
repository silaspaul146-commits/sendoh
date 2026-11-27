import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'design.dart';
import 'getting_in.dart' show FieldLabel, PhoneField;
import 'i18n.dart';
import 'onboarding.dart' show OtpBoxes;

/// MTN or Orange from a Cameroon mobile prefix; null when unknown.
String? networkOf(String digits) {
  final d = digits.replaceAll(RegExp(r'\D'), '');
  final p = d.length > 9 ? d.substring(d.length - 9) : d;
  if (p.length < 3 || !p.startsWith('6')) return null;
  final three = int.tryParse(p.substring(0, 3)) ?? 0;
  if (p.startsWith('67') ||
      (three >= 650 && three <= 654) ||
      (three >= 680 && three <= 684)) {
    return 'MTN';
  }
  if (p.startsWith('69') ||
      (three >= 655 && three <= 659) ||
      (three >= 685 && three <= 689)) {
    return 'ORANGE';
  }
  return null;
}

String walletLabel(String? method) =>
    method == 'ORANGE' ? 'Orange Money' : 'MTN MoMo';

/// The small MTN / Orange mark used wherever a number appears.
class NetworkBadge extends StatelessWidget {
  const NetworkBadge(this.method, {super.key, this.large = false});
  final String? method;

  /// The bigger mark used when choosing a network.
  final bool large;
  @override
  Widget build(BuildContext context) {
    final orange = method == 'ORANGE';
    return Container(
        width: large ? 64 : null,
        height: large ? 40 : null,
        alignment: large ? Alignment.center : null,
        padding: large
            ? null
            : EdgeInsets.symmetric(horizontal: orange ? 5 : 6, vertical: orange ? 7 : 6),
        decoration: BoxDecoration(
            color: orange ? const Color(0xFF111111) : const Color(0xFFFFCC00),
            borderRadius: BorderRadius.circular(large ? 10 : 8)),
        child: Text(orange ? 'orange' : 'MTN',
            style: TextStyle(
                fontSize: large ? (orange ? 13 : 15) : (orange ? 8 : 10),
                fontWeight: FontWeight.w700,
                color: orange
                    ? const Color(0xFFFF8A1F)
                    : const Color(0xFF1A1A1A))));
  }
}

/// Testing without SMS: staging servers can return the code with the request.
/// Shown only when the server sends one; production never does.
class TestCodeHint extends StatelessWidget {
  const TestCodeHint({super.key, required this.code, required this.onUse});
  final String code;
  final VoidCallback onUse;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
            color: SendohColors.amberSoft,
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(
              child: Text(t('Testing: your code is {code}', {'code': code}),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: SendohColors.amber))),
          TextButton(onPressed: onUse, child: Text(t('Use it'))),
        ]),
      );
}

/// A Mobile Money number row: network, masked number, what it is used for.
class MoneyNumberTile extends StatelessWidget {
  const MoneyNumberTile(
      {super.key, required this.number, this.onTap, this.trailing});
  final Map<String, dynamic> number;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final verified = number['verified'] == true;
    final uses = [
      if (number['pay_default'] == true) t('Pay with this'),
      if (number['receive_default'] == true) t('Receive on this'),
    ];
    final detail = verified
        ? [t('Verified'), ...uses].join(' · ')
        : t('Waiting for its code');
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: NetworkBadge(number['method'] as String?),
      title: Text('${number['masked']}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      subtitle: Text(detail,
          style: TextStyle(
              fontSize: 12,
              color: verified ? SendohColors.secondary : SendohColors.amber)),
      trailing: trailing ?? const Icon(Icons.chevron_right),
    );
  }
}

/// Settings › Mobile Money numbers: the person's numbers, and adding one.
class MoneyNumbersSection extends StatefulWidget {
  const MoneyNumbersSection(
      {super.key, required this.api, this.showTitle = true});
  final SendohApi api;

  /// False on the Mobile money numbers page, which has its own title.
  final bool showTitle;
  @override
  State<MoneyNumbersSection> createState() => _MoneyNumbersSectionState();
}

class _MoneyNumbersSectionState extends State<MoneyNumbersSection> {
  Map<String, dynamic>? data;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final d = await widget.api.request('/me/money-numbers');
      if (mounted) setState(() => data = Map<String, dynamic>.from(d));
    } catch (_) {
      if (mounted) {
        setState(() => error = t('Your Mobile Money numbers couldn’t load.'));
      }
    }
  }

  Future<void> open(Map<String, dynamic>? number) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => number == null || number['verified'] != true
            ? AddNumberScreen(api: widget.api, pending: number)
            : NumberDetailScreen(api: widget.api, number: number)));
    if (changed == true && mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final numbers = (data?['numbers'] as List? ?? const [])
        .map((n) => Map<String, dynamic>.from(n as Map))
        .toList();
    final full = numbers.length >= ((data?['limit'] as num?) ?? 3);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.showTitle)
      Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Text(t('MOBILE MONEY NUMBERS'),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: SendohColors.secondary))),
      SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            if (data == null && error == null)
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator()),
            if (error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
            for (final n in numbers) ...[
              MoneyNumberTile(number: n, onTap: () => open(n)),
              const Divider(height: 1),
            ],
            if (data != null && !full)
              ListTile(
                  leading: const Icon(Icons.add, color: SendohColors.teal),
                  title: Text(t('Add a Mobile Money number'),
                      style: const TextStyle(
                          color: SendohColors.teal,
                          fontWeight: FontWeight.w700)),
                  onTap: () => open(null)),
            if (full)
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                      t('You can keep up to 3 numbers. Remove one to add another.'),
                      style: SendohTextStyles.caption)),
          ])),
    ]);
  }
}

/// Add a number (MTN or Orange, chosen from the number), then verify it by SMS code.
class AddNumberScreen extends StatefulWidget {
  const AddNumberScreen({super.key, required this.api, this.pending});
  final SendohApi api;

  /// An added number still waiting for its code: go straight to the code.
  final Map<String, dynamic>? pending;
  @override
  State<AddNumberScreen> createState() => _AddNumberScreenState();
}

class _AddNumberScreenState extends State<AddNumberScreen> {
  final phone = TextEditingController(), code = TextEditingController();
  String? method, error, testCode, challenge, numberId, masked;
  bool chosenByHand = false, pay = false, receive = true, busy = false;
  int seconds = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    final p = widget.pending;
    if (p != null) {
      numberId = p['id'] as String;
      masked = p['masked'] as String;
      method = p['method'] as String?;
      WidgetsBinding.instance.addPostFrameCallback((_) => resend());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  void detect(String value) {
    setState(() {
      if (!chosenByHand) method = networkOf(value);
    });
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void codeSent(Map challengeData) {
    challenge = challengeData['challenge_id'] as String;
    testCode = challengeData['test_code'] as String?;
    seconds = (challengeData['resend_after'] as num?)?.toInt() ?? 60;
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || seconds <= 1) {
        t.cancel();
        if (mounted) setState(() => seconds = 0);
      } else {
        setState(() => seconds--);
      }
    });
  }

  Future<void> add() => run(() async {
        final digits = phone.text.replaceAll(RegExp(r'\D'), '');
        if (!RegExp(r'^6[0-9]{8}$').hasMatch(digits)) {
          throw Exception(t('Enter a valid Mobile Money number.'));
        }
        if (method == null) {
          throw Exception(
              t('Choose MTN MoMo or Orange Money for this number.'));
        }
        final r = await widget.api.request('/me/money-numbers', body: {
          'phone': digits,
          'method': method,
          'pay_default': pay,
          'receive_default': receive,
        });
        final n = Map<String, dynamic>.from(r['number'] as Map);
        if (!mounted) return;
        if (n['verified'] == true) {
          Navigator.pop(context, true);
          return;
        }
        setState(() {
          numberId = n['id'] as String;
          masked = n['masked'] as String;
          codeSent(Map.from(r['challenge'] as Map));
        });
      });

  Future<void> resend() => run(() async {
        final r = await widget.api
            .request('/me/money-numbers/$numberId/code', body: {});
        if (mounted) setState(() => codeSent(Map.from(r as Map)));
      });

  Future<void> verify() => run(() async {
        if (code.text.length != 6) throw Exception(t('Enter all 6 digits.'));
        await widget.api.request('/me/money-numbers/$numberId/verify',
            body: {'challenge_id': challenge, 'code': code.text});
        if (mounted) Navigator.pop(context, true);
      });

  Widget networkRow(String value) => InkWell(
      onTap: busy
          ? null
          : () => setState(() {
                method = value;
                chosenByHand = true;
              }),
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            NetworkBadge(value, large: true),
            const SizedBox(width: 16),
            Expanded(
                child: Text(walletLabel(value),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700))),
            Icon(
                method == value
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 26,
                color: method == value
                    ? SendohColors.teal
                    : SendohColors.secondary),
          ])));

  Widget use(String label, bool value, ValueChanged<bool> changed) => InkWell(
      onTap: busy ? null : () => changed(!value),
      child: Row(children: [
        Checkbox(value: value, onChanged: busy ? null : (v) => changed(v == true)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 16)),
      ]));

  static const _title = TextStyle(
      fontSize: 32,
      height: 1.1,
      fontWeight: FontWeight.w800,
      color: SendohColors.ink);

  @override
  Widget build(BuildContext context) {
    final verifying = numberId != null;
    final ready = phone.text.length == 9 && method != null;
    return Scaffold(
      appBar: AppBar(centerTitle: false, title: Text(t('Mobile money'))),
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
        if (!verifying) ...[
          Text(t('Add a number'), style: _title),
          const SizedBox(height: 28),
          FieldLabel(t('Phone number')),
          PhoneField(
              controller: phone,
              enabled: !busy,
              autofocus: true,
              onChanged: detect),
          const SizedBox(height: 24),
          FieldLabel(t('Network')),
          SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                networkRow('MTN'),
                const Divider(height: 1, indent: 16, endIndent: 16),
                networkRow('ORANGE'),
              ])),
          const SizedBox(height: 24),
          FieldLabel(t('Use this number to')),
          use(t('Pay'), pay, (v) => setState(() => pay = v)),
          use(t('Receive money'), receive, (v) => setState(() => receive = v)),
          const SizedBox(height: 20),
          Text(t('We’ll text a code to this number.'),
              style: const TextStyle(
                  fontSize: 15, color: SendohColors.secondary)),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: busy || !ready ? null : add,
              child: Text(busy ? t('Please wait…') : t('Send code'))),
        ] else ...[
          Text(t('Enter the code'), style: _title),
          const SizedBox(height: 10),
          Text(
              t('Sent to {wallet} {number}',
                  {'wallet': walletLabel(method), 'number': masked ?? ''}),
              style: const TextStyle(
                  fontSize: 15, color: SendohColors.secondary)),
          const SizedBox(height: 28),
          OtpBoxes(controller: code, enabled: !busy),
          if (testCode != null)
            TestCodeHint(
                code: testCode!,
                onUse: () => setState(() => code.text = testCode!)),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                  onPressed: busy || seconds > 0 ? null : resend,
                  child: Text(seconds > 0
                      ? t('Resend in 0:{seconds}',
                          {'seconds': seconds.toString().padLeft(2, '0')})
                      : t('Resend code')))),
          Text(t('A parent’s number? Ask them for the code.'),
              style: SendohTextStyles.caption),
          const SizedBox(height: 28),
          FilledButton(
              onPressed: busy ? null : verify,
              child: Text(busy ? t('Please wait…') : t('Verify'))),
        ],
        if (error != null)
          Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(error!,
                  style: const TextStyle(color: SendohColors.red))),
      ])),
    );
  }
}

/// One verified number: make it the default to pay with or receive on, or remove it.
class NumberDetailScreen extends StatefulWidget {
  const NumberDetailScreen(
      {super.key, required this.api, required this.number});
  final SendohApi api;
  final Map<String, dynamic> number;
  @override
  State<NumberDetailScreen> createState() => _NumberDetailScreenState();
}

class _NumberDetailScreenState extends State<NumberDetailScreen> {
  late Map<String, dynamic> n = widget.number;
  bool busy = false, changed = false;
  String? error;

  Future<void> set({bool? pay, bool? receive}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await widget.api
          .request('/me/money-numbers/${n['id']}/defaults', body: {
        if (pay != null) 'pay_default': pay,
        if (receive != null) 'receive_default': receive
      });
      final updated = (r['numbers'] as List)
          .map((x) => Map<String, dynamic>.from(x as Map))
          .firstWhere((x) => x['id'] == n['id'], orElse: () => n);
      if (mounted) {
        setState(() {
          n = updated;
          changed = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
              title: Text(t('Remove this number?')),
              content: Text(t(
                  'Past payments keep their records. You can add it again later with a new code.')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(d, false),
                    child: Text(t('Keep'))),
                TextButton(
                    onPressed: () => Navigator.pop(d, true),
                    child: Text(t('Remove'))),
              ],
            ));
    if (ok != true) return;
    try {
      await widget.api.request('/me/money-numbers/${n['id']}/remove', body: {});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, changed);
      },
      child: Scaffold(
          appBar: AppBar(title: Text(walletLabel(n['method'] as String?))),
          body: ListView(padding: const EdgeInsets.all(24), children: [
            Row(children: [
              NetworkBadge(n['method'] as String?),
              const SizedBox(width: 12),
              Expanded(
                  child: Text('${n['masked']}',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800))),
              Text(t('Verified'),
                  style: const TextStyle(
                      color: SendohColors.green, fontWeight: FontWeight.w700)),
            ]),
            if (n['is_sign_in_number'] == true)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(t('Also your sign-in number'),
                      style: SendohTextStyles.caption)),
            const SizedBox(height: 20),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: n['pay_default'] == true,
                onChanged: busy ? null : (v) => set(pay: v),
                title: Text(t('Pay with this number')),
                subtitle: Text(t(
                    'Chosen first when you pay. You can pick another each time.'))),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: n['receive_default'] == true,
                onChanged: busy ? null : (v) => set(receive: v),
                title: Text(t('Receive money on this number')),
                subtitle:
                    Text(t('Payouts and money sent to you arrive here.'))),
            const SizedBox(height: 24),
            TextButton(
                style: TextButton.styleFrom(foregroundColor: SendohColors.red),
                onPressed: busy ? null : remove,
                child: Text(t('Remove this number'))),
            if (error != null)
              Text(error!, style: const TextStyle(color: SendohColors.red)),
          ])));
}

/// Checkout: pick one of your verified numbers instead of typing one.
/// Returns the chosen number's local digits through [onChanged]; "Use another
/// number" reveals a field for a one-off number.
class PayWithPicker extends StatefulWidget {
  const PayWithPicker(
      {super.key,
      required this.api,
      required this.onChanged,
      this.enabled = true,
      this.allowOther = true,
      this.onEmpty});
  final SendohApi api;
  final bool enabled;

  /// False where only verified numbers may pay (person payments).
  final bool allowOther;

  /// No verified numbers: the caller shows its own fallback.
  final VoidCallback? onEmpty;

  /// (number id or null for a typed number, phone digits, method)
  final void Function(String? numberId, String phone, String? method) onChanged;
  @override
  State<PayWithPicker> createState() => _PayWithPickerState();
}

class _PayWithPickerState extends State<PayWithPicker> {
  List<Map<String, dynamic>> numbers = [];
  String? chosen;
  bool loaded = false, typing = false;
  final other = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    other.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await widget.api.request('/me/money-numbers');
      final list = (r['numbers'] as List)
          .map((n) => Map<String, dynamic>.from(n as Map))
          .where((n) => n['verified'] == true)
          .toList();
      if (!mounted) return;
      setState(() {
        numbers = list;
        loaded = true;
        typing = list.isEmpty && widget.allowOther;
        if (list.isEmpty) widget.onEmpty?.call();
        final first = list.firstWhere((n) => n['pay_default'] == true,
            orElse: () => list.isEmpty ? <String, dynamic>{} : list.first);
        if (first.isNotEmpty) pick(first);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loaded = true;
          typing = widget.allowOther;
        });
        widget.onEmpty?.call();
      }
    }
  }

  void pick(Map<String, dynamic> n) {
    chosen = n['id'] as String;
    typing = false;
    widget.onChanged(chosen, '${n['phone']}', n['method'] as String?);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const LinearProgressIndicator();
    if (numbers.isEmpty && !widget.allowOther) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('PAY WITH'),
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: SendohColors.secondary)),
      const SizedBox(height: 8),
      for (final n in numbers)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
                color: SendohColors.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                        color: chosen == n['id'] && !typing
                            ? SendohColors.teal
                            : SendohColors.border,
                        width: chosen == n['id'] && !typing ? 2 : 1)),
                child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap:
                        widget.enabled ? () => setState(() => pick(n)) : null,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        child: Row(children: [
                          Icon(
                              chosen == n['id'] && !typing
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: SendohColors.teal),
                          const SizedBox(width: 10),
                          NetworkBadge(n['method'] as String?),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('${n['masked']}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15)),
                                Text(
                                    n['pay_default'] == true
                                        ? t('Verified · default')
                                        : t('Verified'),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: SendohColors.green,
                                        fontWeight: FontWeight.w700)),
                              ])),
                        ]))))),
      if (!typing && numbers.isNotEmpty && widget.allowOther)
        TextButton(
            onPressed: widget.enabled
                ? () => setState(() {
                      typing = true;
                      chosen = null;
                      widget.onChanged(null, other.text, networkOf(other.text));
                    })
                : null,
            child: Text(t('+ Use another number'))),
      if (typing)
        TextField(
            controller: other,
            enabled: widget.enabled,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            onChanged: (v) => widget.onChanged(null, v, networkOf(v)),
            decoration: InputDecoration(
                labelText: t('Mobile Money number'), prefixText: '+237  ')),
    ]);
  }
}

/// A new sign-in number takes effect only after its SMS code is entered.
class ChangeSignInNumberScreen extends StatefulWidget {
  const ChangeSignInNumberScreen({super.key, required this.api});
  final SendohApi api;
  @override
  State<ChangeSignInNumberScreen> createState() =>
      _ChangeSignInNumberScreenState();
}

class _ChangeSignInNumberScreenState extends State<ChangeSignInNumberScreen> {
  final phone = TextEditingController(), code = TextEditingController();
  String? challenge, testCode, error;
  bool busy = false;

  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> send() => run(() async {
        if (!RegExp(r'^6[0-9]{8}$').hasMatch(phone.text)) {
          throw Exception(t('Enter a valid 9-digit Cameroon phone number.'));
        }
        final r = await widget.api
            .request('/me/sign-in-number/code', body: {'phone': phone.text});
        if (mounted) {
          setState(() {
            challenge = r['challenge_id'] as String;
            testCode = r['test_code'] as String?;
          });
        }
      });

  Future<void> verify() => run(() async {
        if (code.text.length != 6) throw Exception(t('Enter all 6 digits.'));
        await widget.api.request('/me/sign-in-number/verify',
            body: {'challenge_id': challenge, 'code': code.text});
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t(
                'Your sign-in number is changed. Use it next time you sign in.'))));
        Navigator.pop(context, true);
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(t('Change sign-in number'))),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text(
              t('This only changes how you sign in. Your name, @username, collections and Mobile Money numbers stay the same.'),
              style: SendohTextStyles.bodyMedium),
          const SizedBox(height: 20),
          TextField(
              controller: phone,
              enabled: !busy && challenge == null,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              decoration: InputDecoration(
                  labelText: t('New phone number'), prefixText: '+237  ')),
          if (challenge != null) ...[
            const SizedBox(height: 16),
            TextField(
                controller: code,
                enabled: !busy,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: InputDecoration(
                    labelText: t('Code sent to the new number'))),
            if (testCode != null)
              TestCodeHint(
                  code: testCode!,
                  onUse: () => setState(() => code.text = testCode!)),
          ],
          const SizedBox(height: 20),
          FilledButton(
              onPressed: busy ? null : (challenge == null ? send : verify),
              child: Text(busy
                  ? t('Please wait…')
                  : challenge == null
                      ? t('Text a code to the new number')
                      : t('Verify'))),
          if (error != null)
            Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(error!,
                    style: const TextStyle(color: SendohColors.red))),
        ]),
      );
}
