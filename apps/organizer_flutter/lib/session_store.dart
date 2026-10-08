import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionStore {
  static const _storage = FlutterSecureStorage();
  static Future<void> save(String url, String refresh) => _storage.write(
      key: 'sendoh_session', value: jsonEncode({'url': url, 'refresh': refresh}));
  static Future<Map<String, dynamic>?> read() async {
    final raw = await _storage.read(key: 'sendoh_session');
    return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw));
  }
  static Future<bool> locked() async =>
      await _storage.read(key: 'sendoh_device_lock') == 'true';
  static Future<void> setLocked(bool value) =>
      _storage.write(key: 'sendoh_device_lock', value: '$value');
  static Future<void> clear() async {
    await _storage.delete(key: 'sendoh_session');
    await _storage.delete(key: 'sendoh_device_lock');
  }
}
