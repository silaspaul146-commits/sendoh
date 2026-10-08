import 'dart:convert';
import 'package:http/http.dart' as http;
import 'session_store.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

class SendohApi {
  SendohApi(this.baseUrl, this.token);
  final String baseUrl;
  String token;
  String? refreshToken;
  Future<void>? _refreshing;
  Future<void> refresh() => _refreshing ??= _rotate().whenComplete(() => _refreshing = null);
  Future<void> _rotate() async {
    if (refreshToken == null) throw ApiException(401, 'Please sign in again.');
    final result = await SendohApi(baseUrl, '').request('/auth/refresh',
        body: {'refresh_token': refreshToken});
    token = result['access_token'] as String;
    refreshToken = result['refresh_token'] as String;
    await SessionStore.save(baseUrl, refreshToken!);
  }
  Future<dynamic> request(String path,
      {Map<String, dynamic>? body, String? key, bool retry = true}) async {
    final uri = Uri.parse('$baseUrl/api/v1$path');
    final sentToken = token;
    final headers = {
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      if (key != null) 'Idempotency-Key': key
    };
    final response = await (body == null
            ? http.get(uri, headers: headers)
            : http.post(uri, headers: headers, body: jsonEncode(body)))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 401 && retry && refreshToken != null) {
      if (sentToken == token) await refresh();
      return request(path, body: body, key: key, retry: false);
    }
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      throw ApiException(response.statusCode, 'The server is unavailable. Please try again.');
    }
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, data is Map && data['error'] is Map
          ? data['error']['message']
          : 'Please check your input and try again.');
    }
    return data;
  }

  Future<List<dynamic>> collections() async =>
      List<dynamic>.from(await request('/collections'));
}
