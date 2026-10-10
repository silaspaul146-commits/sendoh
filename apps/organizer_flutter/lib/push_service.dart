import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';

/// Push is optional. Firebase client identifiers are build configuration, never
/// the service-account private key used by Render.
class PushService {
  static const enabled = bool.fromEnvironment('PUSH_ENABLED');
  static const _store = FlutterSecureStorage();
  static final updates = ValueNotifier<int>(0);
  static bool ready = false, pendingOpen = false;
  static SendohApi? _api;
  static bool _optedIn = false;
  static int _generation = 0;
  static StreamSubscription<String>? _refresh;
  static Future<void>? _starting;
  static Future<NotificationSettings>? _permissionRequest;

  static bool get supported => !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> initialize() => _starting ??= _initialize();
  static Future<void> _initialize() async {
    if (!enabled || !supported) {
      return;
    }
    const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
    const sender = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final appId = ios ? const String.fromEnvironment('FIREBASE_IOS_APP_ID') :
        const String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
    final apiKey = ios ? const String.fromEnvironment('FIREBASE_IOS_API_KEY') :
        const String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
    if ([project, sender, appId, apiKey].any((v) => v.isEmpty)) {
      return;
    }
    try {
      await Firebase.initializeApp(options: FirebaseOptions(apiKey: apiKey,
          appId: appId, messagingSenderId: sender, projectId: project,
          iosBundleId: ios ? const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID') : null));
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
      FirebaseMessaging.onMessage.listen((_) => updates.value++);
      FirebaseMessaging.onMessageOpenedApp.listen((_) {
        pendingOpen = true;
        updates.value++;
      });
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      pendingOpen = initial != null;
      ready = true;
    } catch (_) {
      // Inbox and login must remain available if Firebase cannot initialize.
      ready = false;
    }
  }

  static Future<bool> attach(SendohApi api, String user) async {
    final generation = ++_generation;
    await _refresh?.cancel();
    _refresh = null;
    _api = api;
    _optedIn = false;
    await initialize();
    if (!ready || generation != _generation) {
      return false;
    }
    final value = await _store.read(key: 'sendoh_push_$user');
    if (generation != _generation) {
      return false;
    }
    // Existing explicit opt-outs remain respected. New accounts default on.
    _optedIn = value != 'false';
    if (!_optedIn) {
      return false;
    }
    var permission = await FirebaseMessaging.instance.getNotificationSettings();
    final alreadyAsked = await _store.read(key: 'sendoh_push_permission_asked');
    if (generation != _generation) {
      return false;
    }
    if (_permissionRequest != null) {
      permission = await _permissionRequest!;
    } else if (alreadyAsked != 'true' &&
        permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      // Android 13 reports denied for both unasked and denied. Remember our
      // first request so returning users are never repeatedly prompted.
      await _store.write(key: 'sendoh_push_permission_asked', value: 'true');
      if (generation != _generation) {
        return false;
      }
      _permissionRequest = FirebaseMessaging.instance.requestPermission(
          alert: true, badge: true, sound: true);
      try {
        permission = await _permissionRequest!;
      } finally {
        _permissionRequest = null;
      }
    }
    if (generation != _generation) {
      return false;
    }
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      try {
        await api.request('/me/push-devices/disable', body: {});
      } catch (_) { /* Device expiry remains the fallback. */ }
      return false;
    }
    final registered = await _register(generation);
    if (generation == _generation) {
      _refresh = FirebaseMessaging.instance.onTokenRefresh.listen((_) async {
        try {
          await _register(generation);
        } catch (_) { /* Retry on next app resume. */ }
      }, onError: (_) {});
    }
    return registered;
  }

  static Future<bool> _register(int generation) async {
    if (!ready || !_optedIn || _api == null || generation != _generation) {
      return false;
    }
    final api = _api!;
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        await FirebaseMessaging.instance.getAPNSToken() == null) {
      throw StateError('Apple push registration is not ready. Please try again shortly.');
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (generation != _generation) {
      return false;
    }
    if (token == null) {
      throw StateError('Push token is not ready. Check connectivity and try again.');
    }
    await api.request('/me/push-devices/register', body: {
      'token': token,
      'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    });
    return generation == _generation;
  }

  static Future<String> enable(SendohApi api, String user) async {
    await initialize();
    if (!ready) {
      return 'Push alerts are not configured in this build. Your inbox still works.';
    }
    await _store.write(key: 'sendoh_push_permission_asked', value: 'true');
    final permission = await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true);
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      return 'Notifications are not allowed. You can enable them in your phone settings.';
    }
    await _store.write(key: 'sendoh_push_$user', value: 'true');
    // A network failure is not an opt-out. Retry registration on resume.
    if (!await attach(api, user)) {
      throw StateError('Push registration was interrupted. Please try again.');
    }
    return 'Push alerts enabled for this device.';
  }

  static Future<void> disable(SendohApi api, String user) async {
    // Require server confirmation before reporting push as disabled.
    await api.request('/me/push-devices/disable', body: {});
    await _store.write(key: 'sendoh_push_$user', value: 'false');
    await detach(deleteToken: true);
  }

  static Future<void> detach({bool deleteToken = false}) async {
    _generation++;
    _api = null;
    _optedIn = false;
    pendingOpen = false;
    await _refresh?.cancel();
    _refresh = null;
    if (ready && deleteToken) {
      try {
        await FirebaseMessaging.instance.setAutoInitEnabled(false);
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) { /* Server logout revokes this session's push devices. */ }
    }
  }

  static Future<bool> optedIn(String user) async =>
      await _store.read(key: 'sendoh_push_$user') != 'false';
}
