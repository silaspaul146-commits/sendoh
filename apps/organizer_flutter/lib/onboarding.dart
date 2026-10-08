import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api.dart';
import 'config.dart';
import 'design.dart';
import 'main.dart';
import 'session_store.dart';
import 'package:image_picker/image_picker.dart';
import 'device_lock.dart';

class Onboarding extends StatefulWidget {
  const Onboarding({super.key});
  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  final phone = TextEditingController();
  final code = TextEditingController();
  final name = TextEditingController();
  final username = TextEditingController();
  String? avatar;
  bool restoring = true, hasSavedSession = false;
  final url = TextEditingController(text: SendohConfig.apiBaseUrl);
  int step = 0, seconds = 0;
  bool busy = false;
  String? error, challenge;
  String? delivery;
  SendohApi? signedIn;
  Timer? timer;
  String get phoneNumber => '+237${phone.text.replaceAll(RegExp(r'\s'), '')}';
  String get developmentOtpCommand =>
      '\$env:SENDOH_ENV="development"\n'
      '.\\.venv\\Scripts\\python.exe -m app.dev_otp $challenge';
  SendohApi get publicApi =>
      SendohApi(url.text.trim().replaceAll(RegExp(r'/+$'), ''), '');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => restore());
  }

  Future<void> restore() async {
    try {
      final saved = await SessionStore.read();
      if (saved == null) return;
      hasSavedSession = true;
      // Do not send an old token to a different configured backend.
      if (saved['url'] != SendohConfig.apiBaseUrl) return;
      if (await SessionStore.locked()) {
        final ok = await authenticateDevice('Unlock your Sendoh account');
        if (!ok) return;
      }
      final api = SendohApi(saved['url'] as String, '')
        ..refreshToken = saved['refresh'] as String;
      await api.refresh();
      final user = await api.request('/me');
      if (!mounted) return;
      signedIn = api;
      await continueWithProfile(Map<String, dynamic>.from(user));
    } on ApiException catch (e) {
      if (e.status == 401) {
        await SessionStore.clear();
        hasSavedSession = false;
      }
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not restore your session. Retry or sign in with your phone.');
    } finally {
      if (mounted) setState(() => restoring = false);
    }
  }

  Future<void> continueWithProfile(Map<String, dynamic> user) async {
    if (user['profile_complete'] == true) {
      await enter(signedIn!, user);
    } else {
      setState(() {
        name.text = user['display_name'] as String? ?? '';
        username.text = user['username'] as String? ?? '';
        avatar = user['avatar'] as String?;
        step = 3;
        restoring = false;
      });
    }
  }

  Future<void> pickPhoto() => run(() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.gallery,
        maxWidth: 512, maxHeight: 512, imageQuality: 75);
    if (photo == null) return;
    final bytes = await photo.readAsBytes();
    if (bytes.length > 200000) throw Exception('Choose a smaller photo (under 200 KB).');
    if (mounted) setState(() => avatar = base64Encode(bytes));
  });

  @override
  void dispose() {
    timer?.cancel();
    phone.dispose();
    code.dispose();
    name.dispose();
    username.dispose();
    url.dispose();
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

  Future<void> sendCode() => run(() async {
        if (!RegExp(r'^\+237[26][0-9]{8}$').hasMatch(phoneNumber)) {
          throw Exception('Enter a valid 9-digit Cameroon phone number.');
        }
        final result =
            await publicApi.request('/auth/code', body: {'phone': phoneNumber});
        if (!mounted) return;
        setState(() {
          challenge = result['challenge_id'] as String;
          delivery = result['delivery'] as String?;
          step = 2;
          seconds = result['resend_after'] as int;
          code.clear();
        });
        timer?.cancel();
        timer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted || seconds <= 1) {
            t.cancel();
            if (mounted) setState(() => seconds = 0);
          } else {
            setState(() => seconds--);
          }
        });
      });

  Future<void> enter(SendohApi api, Map<String, dynamic> user) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ProviderScope(
            overrides: [apiProvider.overrideWithValue(api)],
            child: Shell(name: user['display_name'] as String, account: user))));
    if (!mounted) return;
    setState(() {
      step = 0;
      signedIn = null;
      code.clear();
      name.clear();
      username.clear();
      avatar = null;
      hasSavedSession = false;
    });
  }

  Future<void> verify() => run(() async {
        if (code.text.length != 6) throw Exception('Enter all 6 digits.');
        final result = await publicApi.request('/auth/verify', body: {
          'phone': phoneNumber,
          'challenge_id': challenge,
          'code': code.text,
        });
        if (!mounted) return;
        timer?.cancel();
        signedIn =
            SendohApi(publicApi.baseUrl, result['access_token'] as String)
              ..refreshToken = result['refresh_token'] as String;
        await SessionStore.save(signedIn!.baseUrl, signedIn!.refreshToken!);
        if (!mounted) return;
        await continueWithProfile(Map<String, dynamic>.from(result['user']));
      });

  Future<void> saveProfile() => run(() async {
        if (name.text.trim().isEmpty) {
          throw Exception('Please enter your name.');
        }
        final handle = username.text.trim().toLowerCase();
        if (!RegExp(r'^[a-z][a-z0-9_]{2,23}$').hasMatch(handle)) {
          throw Exception('Use 3–24 letters, numbers or underscores, starting with a letter.');
        }
        final result = await signedIn!.request('/me/profile', body: {
          'display_name': name.text.trim(), 'username': handle, 'avatar': avatar,
        });
        if (mounted) await enter(signedIn!, Map<String, dynamic>.from(result));
      });

  Future<void> settings() async {
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Development connection'),
              content: TextField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'API URL')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Done'))
              ],
            ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: step == 0
              ? null
              : Text([
                  '',
                  'Your phone number',
                  'Verification',
                  'Your profile'
                ][step]),
          leading: step > 0
              ? IconButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                            step = step == 3 ? 0 : step - 1;
                            error = null;
                          }),
                  icon: const Icon(Icons.arrow_back))
              : null,
          actions: [
            if (kDebugMode && step < 2)
              IconButton(
                  tooltip: 'Development connection',
                  onPressed: busy ? null : settings,
                  icon: const Icon(Icons.settings_outlined))
          ],
        ),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          minHeight: (constraints.maxHeight - 40)
                              .clamp(0.0, double.infinity)
                              .toDouble()),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (step == 0) ...[
                              if (restoring) const LinearProgressIndicator(),
                              if (error != null) Text(error!),
                              if (hasSavedSession && !restoring)
                                TextButton(onPressed: () {
                                  setState(() => restoring = true);
                                  restore();
                                }, child: const Text('Unlock / retry saved session')),
                              const SizedBox(height: 12),
                              const SendohBrand(vertical: true),
                              const SizedBox(height: 12),
                              const Text('Organize money. Together.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 15,
                                      color: SendohColors.secondary)),
                              const SizedBox(height: 28),
                              Semantics(
                                label: 'Three people celebrating together',
                                image: true,
                                child: SizedBox(
                                    height: 232,
                                    child: Image.asset(
                                        'assets/welcome-community.png',
                                        fit: BoxFit.contain,
                                        excludeFromSemantics: true)),
                              ),
                              const SizedBox(height: 30),
                              FilledButton(
                                  onPressed: busy || restoring
                                      ? null
                                      : () => setState(() => step = 1),
                                  child: const Text('Create account')),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                  onPressed: busy || restoring
                                      ? null
                                      : () => setState(() => step = 1),
                                  child:
                                      const Text('I already have an account')),
                              if (kDebugMode) ...[
                                const SizedBox(height: 24),
                                TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => Navigator.push(
                                            context,
                                            MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    const DevelopmentSession())),
                                    child: const Text(
                                        'Use existing development token')),
                                const Text(
                                    'Local development tools are enabled',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12)),
                              ],
                            ] else ...[
                              Text(
                                  [
                                    '',
                                    'Enter your phone number',
                                    'Verify your number',
                                    'Create your profile'
                                  ][step],
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 16),
                              Text(step == 1
                                  ? 'We’ll use a code to verify your number.'
                                  : step == 2
                                      ? 'Enter the 6-digit verification code for $phoneNumber'
                                      : 'How should we call you?'),
                              const SizedBox(height: 28),
                              if (step == 1)
                                TextField(
                                    controller: phone,
                                    enabled: !busy,
                                    keyboardType: TextInputType.phone,
                                    autofillHints: const [
                                      AutofillHints.telephoneNumberNational
                                    ],
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(9)
                                    ],
                                    decoration: const InputDecoration(
                                        labelText: 'Phone number',
                                        prefixText: '+237  ',
                                        hintText: '670 12 34 56')),
                              if (step == 2) ...[
                                OtpBoxes(controller: code, enabled: !busy),
                                const SizedBox(height: 12),
                                TextButton(
                                    onPressed:
                                        busy || seconds > 0 ? null : sendCode,
                                    child: Text(seconds > 0
                                        ? 'Resend code in 00:${seconds.toString().padLeft(2, '0')}'
                                        : 'Resend code')),
                                if (kDebugMode && delivery == 'local-development')
                                  ExpansionTile(
                                      title:
                                          const Text('Local development code'),
                                      childrenPadding:
                                          const EdgeInsets.fromLTRB(
                                              16, 0, 16, 14),
                                      children: [
                                        const Text(
                                            'From services/backend in PowerShell, run:'),
                                        const SizedBox(height: 10),
                                        SelectableText(developmentOtpCommand),
                                        TextButton(
                                            onPressed: () => Clipboard.setData(
                                                ClipboardData(
                                                    text:
                                                        developmentOtpCommand)),
                                            child: const Text('Copy commands')),
                                      ]),
                              ],
                              if (step == 3) ...[
                                Center(child: CircleAvatar(radius: 42,
                                  backgroundImage: avatar == null ? null : MemoryImage(base64Decode(avatar!)),
                                  child: avatar == null ? const Icon(Icons.person_outline, size: 40) : null)),
                                TextButton(onPressed: busy ? null : pickPhoto,
                                    child: const Text('Add profile photo (optional)')),
                                if (avatar != null)
                                  TextButton(onPressed: busy ? null : () => setState(() => avatar = null),
                                      child: const Text('Remove photo')),
                                TextField(
                                    controller: name,
                                    enabled: !busy,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    autofillHints: const [AutofillHints.name],
                                    maxLength: 120,
                                    decoration: const InputDecoration(
                                        labelText: 'Full name')),
                                const SizedBox(height: 16),
                                TextField(controller: username, enabled: !busy,
                                  autocorrect: false, enableSuggestions: false, maxLength: 24,
                                  decoration: const InputDecoration(labelText: 'Unique username',
                                    prefixText: '@', helperText: 'Friends will use this to find you.')),
                                const Text('Your phone number stays private. Your name and photo help people recognize you.'),
                              ],
                              if (error != null)
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    child: Text(error!,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error))),
                              const SizedBox(height: 48),
                              FilledButton(
                                  onPressed: busy
                                      ? null
                                      : step == 1
                                          ? sendCode
                                          : step == 2
                                              ? verify
                                              : saveProfile,
                                  child: Text(busy
                                      ? 'Please wait…'
                                      : step == 1
                                          ? 'Send code'
                                          : step == 2
                                              ? 'Verify'
                                              : 'Continue')),
                            ],
                          ]),
                    ),
                  )),
        ))),
      );
}

class OtpBoxes extends StatefulWidget {
  const OtpBoxes({super.key, required this.controller, this.enabled = true});

  final TextEditingController controller;
  final bool enabled;

  @override
  State<OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<OtpBoxes> {
  late final List<TextEditingController> digits;
  late final List<FocusNode> nodes;
  bool syncing = false;

  @override
  void initState() {
    super.initState();
    digits = List.generate(6, (_) => TextEditingController());
    nodes = List.generate(6, (_) => FocusNode());
    _load(widget.controller.text);
    widget.controller.addListener(_externalChanged);
  }

  @override
  void didUpdateWidget(covariant OtpBoxes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_externalChanged);
      widget.controller.addListener(_externalChanged);
      _load(widget.controller.text);
    }
  }

  void _externalChanged() {
    if (!syncing) _load(widget.controller.text);
  }

  void _load(String value) {
    final raw = value.replaceAll(RegExp(r'\D'), '');
    final clean = raw.length > 6 ? raw.substring(0, 6) : raw;
    syncing = true;
    for (var i = 0; i < digits.length; i++) {
      final next = i < clean.length ? clean[i] : '';
      if (digits[i].text != next) digits[i].text = next;
    }
    syncing = false;
  }

  void _changed(int index, String value) {
    if (syncing) return;
    final clean = value.replaceAll(RegExp(r'\D'), '');
    if (clean.length > 1) {
      final pasted = clean.length > 6 ? clean.substring(0, 6) : clean;
      syncing = true;
      for (var i = 0; i < digits.length; i++) {
        digits[i].text = i < pasted.length ? pasted[i] : '';
      }
      widget.controller.text = pasted;
      syncing = false;
      nodes[pasted.isEmpty ? 0 : pasted.length - 1].requestFocus();
      return;
    }
    widget.controller.text = digits.map((field) => field.text).join();
    if (clean.isNotEmpty && index < nodes.length - 1) {
      nodes[index + 1].requestFocus();
    }
    if (clean.isEmpty && index > 0) nodes[index - 1].requestFocus();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_externalChanged);
    for (final controller in digits) {
      controller.dispose();
    }
    for (final node in nodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: '6-digit verification code',
        textField: true,
        child: Row(
          children: List.generate(
              6,
              (index) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: index == 5 ? 0 : 8),
                      child: TextField(
                        key: ValueKey('otp-$index'),
                        controller: digits[index],
                        focusNode: nodes[index],
                        enabled: widget.enabled,
                        autofocus: index == 0,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w600),
                        autofillHints: index == 0
                            ? const [AutofillHints.oneTimeCode]
                            : null,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6)
                        ],
                        decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(vertical: 15)),
                        onChanged: (value) => _changed(index, value),
                      ),
                    ),
                  )),
        ),
      );
}
