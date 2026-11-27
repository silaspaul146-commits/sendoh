import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'i18n_fr.dart';

/// The two languages Sendoh speaks. The person chooses in Profile; the
/// phone's language is only the first guess.
enum AppLanguage { en, fr }

const _storageKey = 'sendoh_language';

/// Current language. Screens read it through [t]; the app rebuilds when it changes.
final appLanguage = ValueNotifier<AppLanguage>(AppLanguage.en);

/// Restores the saved choice, else follows the phone if it is set to French.
Future<void> loadLanguage({FlutterSecureStorage? storage}) async {
  String? saved;
  try {
    saved =
        await (storage ?? const FlutterSecureStorage()).read(key: _storageKey);
  } catch (_) {
    // A storage failure must never block opening the app.
  }
  appLanguage.value = switch (saved) {
    'fr' => AppLanguage.fr,
    'en' => AppLanguage.en,
    _ => PlatformDispatcher.instance.locale.languageCode == 'fr'
        ? AppLanguage.fr
        : AppLanguage.en,
  };
}

Future<void> chooseLanguage(AppLanguage language,
    {FlutterSecureStorage? storage}) async {
  appLanguage.value = language;
  try {
    await (storage ?? const FlutterSecureStorage())
        .write(key: _storageKey, value: language.name);
  } catch (_) {
    // The choice still applies for this session.
  }
}

/// Translate English source text. `{name}` placeholders are filled from [args].
/// Missing French falls back to English, never to a blank.
String t(String english, [Map<String, Object?> args = const {}]) {
  var out = appLanguage.value == AppLanguage.fr
      ? (frenchStrings[english] ?? english)
      : english;
  args.forEach((name, value) => out = out.replaceAll('{$name}', '$value'));
  return out;
}

/// 5,000 FCFA in English; 5 000 FCFA in French.
String formatFcfa(num value) {
  final digits = value.round().abs().toString();
  // French groups thousands with a narrow no-break space (U+202F).
  final separator =
      appLanguage.value == AppLanguage.fr ? String.fromCharCode(0x202F) : ',';
  final grouped = digits.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}$separator');
  return '${value < 0 ? '−' : ''}$grouped FCFA';
}

/// Any amount the app shows (int, double or a decimal string from the API).
String fcfa(dynamic value) {
  final n = value is num ? value : num.tryParse('$value');
  return n == null ? '$value FCFA' : formatFcfa(n);
}

Map<String, String>? _english;

/// The English source of a shown string (itself if it is already English).
/// Lets a status colour follow meaning, not wording.
String englishOf(String shown) {
  _english ??= {for (final e in frenchStrings.entries) e.value: e.key};
  return _english![shown] ?? shown;
}

/// Rebuilds every widget under [context] in place, keeping navigation and
/// state, so a language change reaches every open screen at once.
void rebuildAll(BuildContext context) {
  void rebuild(Element element) {
    element.markNeedsBuild();
    element.visitChildren(rebuild);
  }

  (context as Element).visitChildren(rebuild);
}
