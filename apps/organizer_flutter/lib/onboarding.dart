import 'i18n.dart';
import 'getting_in.dart';
import 'money_numbers.dart';
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
  bool restoring = true, hasSavedSession = false, deviceUnlocked = false;
  bool verificationRequired = false;
  final url = TextEditingController(text: SendohConfig.apiBaseUrl);
  int step = 0, seconds = 0;
  bool busy = false;
  String? error, challenge;
  String? delivery, testCode;
  // Step 3: the person confirms they are 12 or older.
  bool oldEnough = false;
  // Step 4: how they pay and get paid.
  Map<String, dynamic>? pendingUser;
  String? signInMasked, signInNetwork;
  bool useSignInNumber = true;
  List<Map<String, dynamic>> addedNumbers = [];
  SendohApi? signedIn;
  Timer? timer;
  String get phoneNumber => '+237${phone.text.replaceAll(RegExp(r'\s'), '')}';
  String get developmentOtpCommand => '\$env:SENDOH_ENV="development"\n'
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
      if (mounted) setState(() => hasSavedSession = true);
      // Do not send an old token to a different configured backend.
      if (saved['url'] != SendohConfig.apiBaseUrl) {
        throw ApiException(
          409,
          t('This saved account belongs to another server. Sign out before switching servers.'),
        );
      }
      if (!deviceUnlocked && await SessionStore.locked()) {
        final ok = await authenticateDevice(t('Unlock your Sendoh account'));
        if (!ok) return;
        deviceUnlocked = true;
      }
      final api = SendohApi(saved['url'] as String, '')
        ..refreshToken = saved['refresh'] as String;
      await api.refresh();
      final user = await api.request('/me');
      if (!mounted) return;
      signedIn = api;
      await continueWithProfile(Map<String, dynamic>.from(user));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          verificationRequired = e.status == 401;
          error = verificationRequired
              ? t('Your session has expired. Verify your phone number to securely reopen your account.')
              : t(e.message);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = t(
              'Cannot reach Sendoh yet. Your account is saved. Check your connection and retry.'),
        );
      }
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
        final photo = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 512,
          maxHeight: 512,
          imageQuality: 75,
        );
        if (photo == null) return;
        final bytes = await photo.readAsBytes();
        if (bytes.length > 200000) {
          throw Exception(t('Choose a smaller photo (under 200 KB).'));
        }
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
          throw Exception(t('Enter a valid 9-digit Cameroon phone number.'));
        }
        final result = await publicApi.request(
          '/auth/code',
          body: {'phone': phoneNumber},
        );
        if (!mounted) return;
        setState(() {
          challenge = result['challenge_id'] as String;
          delivery = result['delivery'] as String?;
          testCode = result['test_code'] as String?;
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProviderScope(
          overrides: [apiProvider.overrideWithValue(api)],
          child: PopScope(
            canPop: false,
            child: Shell(name: user['display_name'] as String, account: user),
          ),
        ),
      ),
    );
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
        if (code.text.length != 6) throw Exception(t('Enter all 6 digits.'));
        final result = await publicApi.request(
          '/auth/verify',
          body: {
            'phone': phoneNumber,
            'challenge_id': challenge,
            'code': code.text,
          },
        );
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
          throw Exception(t('Please enter your name.'));
        }
        if (!oldEnough) {
          throw Exception(t('Sendoh is for people aged 12 and over.'));
        }
        final handle = username.text.trim().toLowerCase();
        if (!RegExp(r'^[a-z][a-z0-9_]{2,23}$').hasMatch(handle)) {
          throw Exception(
            t('Use 3–24 letters, numbers or underscores, starting with a letter.'),
          );
        }
        final result = await signedIn!.request(
          '/me/profile',
          body: {
            'display_name': name.text.trim(),
            'username': handle,
            'avatar': avatar,
          },
        );
        if (!mounted) return;
        pendingUser = Map<String, dynamic>.from(result);
        await openWalletStep();
      });

  /// Step 4 after a new profile: offer the sign-in number as a Mobile Money number.
  Future<void> openWalletStep() async {
    try {
      final numbers = await signedIn!.request('/me/money-numbers');
      final masked = numbers['sign_in_masked'] as String?;
      setState(() {
        signInMasked = masked?.replaceFirst('+237 ', '');
        signInNetwork = numbers['sign_in_network'] as String?;
        addedNumbers = numbersBesidesSignIn(numbers);
        step = 4;
      });
    } catch (_) {
      // Numbers can be added later in Settings; never block getting in.
      await enter(signedIn!, pendingUser!);
    }
  }

  List<Map<String, dynamic>> numbersBesidesSignIn(dynamic numbers) =>
      (numbers['numbers'] as List? ?? const [])
          .map((n) => Map<String, dynamic>.from(n as Map))
          .where((n) => n['is_sign_in_number'] != true)
          .toList();

  Future<void> addAnotherNumber() async {
    final added = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => AddNumberScreen(api: signedIn!)));
    if (added == true && mounted) {
      final numbers = await signedIn!.request('/me/money-numbers');
      if (mounted) setState(() => addedNumbers = numbersBesidesSignIn(numbers));
    }
  }

  Future<void> finishWallet({required bool skip}) => run(() async {
        if (!skip && useSignInNumber && signInNetwork != null) {
          await signedIn!.request('/me/money-numbers', body: {
            'sign_in_number': true,
            'pay_default': true,
            'receive_default':
                addedNumbers.every((n) => n['receive_default'] != true)
          });
        }
        if (mounted) await enter(signedIn!, pendingUser!);
      });

  Widget errorText() => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );

  Future<void> settings() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('Development connection')),
        content: TextField(
          controller: url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'API URL'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('Done')),
          ),
        ],
      ),
    );
  }

  bool get usernameValid => RegExp(r'^[a-z][a-z0-9_]{2,23}$')
      .hasMatch(username.text.trim().toLowerCase());

  bool get profileReady =>
      name.text.trim().isNotEmpty && usernameValid && oldEnough;

  /// +237 6XX XX XX XX, for reading back the number a code went to.
  String get prettyPhone {
    final d = phone.text.replaceAll(RegExp(r'\D'), '');
    if (d.length != 9) return phoneNumber;
    return '+237 ${d.substring(0, 3)} ${d.substring(3, 5)} '
        '${d.substring(5, 7)} ${d.substring(7)}';
  }

  void back() => setState(() {
        step = step == 3 ? 0 : step - 1;
        testCode = null;
        error = null;
      });

  Widget welcomeBack() => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SendohBrand(vertical: true),
                  const SizedBox(height: 24),
                  Text(
                    t('Welcome back'),
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    restoring
                        ? t('Opening your account…')
                        : (error ?? t('Unlock to continue where you left off.')),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (restoring)
                    const CircularProgressIndicator()
                  else
                    FilledButton(
                      onPressed: () {
                        if (verificationRequired) {
                          setState(() {
                            step = 1;
                            error = null;
                            verificationRequired = false;
                          });
                          return;
                        }
                        setState(() {
                          restoring = true;
                          error = null;
                        });
                        restore();
                      },
                      child: Text(
                        verificationRequired
                            ? t('Verify my phone number')
                            : t('Continue to my account'),
                      ),
                    ),
                  if (!restoring)
                    TextButton(
                      onPressed: () async {
                        await SessionStore.clear();
                        if (mounted) {
                          setState(() {
                            hasSavedSession = false;
                            deviceUnlocked = false;
                            error = null;
                          });
                        }
                      },
                      child: Text(t('Use another account')),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget? developmentTools() => !kDebugMode
      ? null
      : Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Wrap(alignment: WrapAlignment.center, children: [
            TextButton(
              onPressed: busy
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const DevelopmentSession(),
                        ),
                      ),
              child: Text(t('Use existing development token')),
            ),
            TextButton(
              onPressed: busy ? null : settings,
              child: Text(t('Development connection')),
            ),
          ]),
        );

  Widget phoneStep() => StepFrame(
        title: t('Your phone number'),
        lead: t('We’ll text you a code to sign in.'),
        footer: const TermsNote(),
        action: FilledButton(
          onPressed: busy || phone.text.length != 9 ? null : sendCode,
          child: Text(busy ? t('Please wait…') : t('Send code')),
        ),
        children: [
          FieldLabel(t('Phone number')),
          PhoneField(
            controller: phone,
            enabled: !busy,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          if (error != null) errorText(),
        ],
      );

  Widget codeStep() => StepFrame(
        title: t('Enter the code'),
        lead: t('Sent to {phoneNumber}', {'phoneNumber': prettyPhone}),
        action: FilledButton(
          onPressed: busy ? null : verify,
          child: Text(busy ? t('Please wait…') : t('Verify')),
        ),
        children: [
          OtpBoxes(controller: code, enabled: !busy),
          if (testCode != null)
            TestCodeHint(
              code: testCode!,
              onUse: () => setState(() => code.text = testCode!),
            ),
          const SizedBox(height: 12),
          Row(children: [
            TextButton(
              onPressed: busy || seconds > 0 ? null : sendCode,
              child: Text(
                seconds > 0
                    ? t('Resend in 0:{seconds}',
                        {'seconds': seconds.toString().padLeft(2, '0')})
                    : t('Resend code'),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                        step = 1;
                        testCode = null;
                        error = null;
                      }),
              child: Text(t('Change number')),
            ),
          ]),
          if (delivery == 'staging-push')
            Text(t('Check your other signed-in device for the code.'),
                style: SendohTextStyles.caption),
          if (kDebugMode && delivery == 'local-development')
            ExpansionTile(
              title: Text(t('Local development code')),
              children: [
                SelectableText(developmentOtpCommand),
                TextButton(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: developmentOtpCommand),
                  ),
                  child: Text(t('Copy commands')),
                ),
              ],
            ),
          if (error != null) errorText(),
        ],
      );

  Widget profileStep() => StepFrame(
        title: t('Your profile'),
        action: FilledButton(
          onPressed: busy || !profileReady ? null : saveProfile,
          child: Text(busy ? t('Please wait…') : t('Continue')),
        ),
        children: [
          Row(children: [
            Semantics(
              button: true,
              label: t('Add photo'),
              child: GestureDetector(
                onTap: busy ? null : pickPhoto,
                child: Stack(children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: SendohColors.tealSoft,
                    backgroundImage: avatar == null
                        ? null
                        : MemoryImage(base64Decode(avatar!)),
                    child: avatar == null
                        ? const Icon(Icons.person_outline,
                            size: 38, color: SendohColors.ink)
                        : null,
                  ),
                  const Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: SendohColors.teal,
                      child: Icon(Icons.photo_camera_outlined,
                          size: 15, color: Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: busy
                  ? null
                  : avatar == null
                      ? pickPhoto
                      : () => setState(() => avatar = null),
              child: Text(avatar == null ? t('Add photo') : t('Remove photo'),
                  style: const TextStyle(
                      fontSize: 16,
                      decoration: TextDecoration.underline,
                      decorationColor: SendohColors.teal)),
            ),
            if (avatar == null)
              Text(t('Optional'),
                  style: const TextStyle(color: SendohColors.secondary)),
          ]),
          const SizedBox(height: 28),
          FieldLabel(t('Name')),
          TextField(
            controller: name,
            enabled: !busy,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            inputFormatters: [LengthLimitingTextInputFormatter(120)],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          FieldLabel(t('Username')),
          TextField(
            controller: username,
            enabled: !busy,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [LengthLimitingTextInputFormatter(24)],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixText: '@',
              errorText: username.text.isNotEmpty && !usernameValid
                  ? t('3 to 24 letters, numbers or _, starting with a letter')
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: busy ? null : () => setState(() => oldEnough = !oldEnough),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Checkbox(
                value: oldEnough,
                onChanged:
                    busy ? null : (v) => setState(() => oldEnough = v == true),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    t('I’m at least 12 and, if under 18, have a parent or guardian’s permission.'),
                    style: const TextStyle(fontSize: 15, height: 1.4),
                  ),
                ),
              ),
            ]),
          ),
          if (error != null) errorText(),
        ],
      );

  Widget currentStep() => switch (step) {
        1 => phoneStep(),
        2 => codeStep(),
        3 => profileStep(),
        _ => WalletStep(
            busy: busy,
            signInMasked: signInMasked,
            network: signInNetwork,
            useSignIn: useSignInNumber,
            onToggle: (v) => setState(() => useSignInNumber = v),
            added: addedNumbers,
            onAdd: addAnotherNumber,
            onDone: () => finishWallet(skip: false),
            onSkip: () => finishWallet(skip: true),
          ),
      };

  @override
  Widget build(BuildContext context) {
    if ((restoring || hasSavedSession) && step == 0) return welcomeBack();
    if (step == 0) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: WelcomeStep(
                busy: busy,
                onStart: () => setState(() => step = 1),
                onSignIn: () => setState(() => step = 1),
                notice: error == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(error!, textAlign: TextAlign.center),
                      ),
                extra: developmentTools(),
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(children: [
              StepHeader(
                step: step,
                onBack: step < 4 && !busy ? back : null,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  children: [currentStep()],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
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
        label: t('6-digit verification code'),
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
                  autofillHints:
                      index == 0 ? const [AutofillHints.oneTimeCode] : null,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(vertical: 15),
                  ),
                  onChanged: (value) => _changed(index, value),
                ),
              ),
            ),
          ),
        ),
      );
}
