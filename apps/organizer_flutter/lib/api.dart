import 'dart:async';
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
  SendohApi(String baseUrl, this.token)
      : baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final String baseUrl;
  String token;
  String? refreshToken;
  Future<void>? _refreshing;

  // Optional explicit health check. Normal requests never wait for this.
  Future<void> wake() async {
    final response = await _send(Uri.parse('$baseUrl/health'), {}, null);
    if (response.statusCode != 200) {
      throw ApiException(
          503, 'Sendoh is temporarily unavailable. Please retry.');
    }
  }

  Future<http.Response> _send(
      Uri uri, Map<String, String> headers, Map<String, dynamic>? body) async {
    final client = http.Client();
    try {
      return await (body == null
              ? client.get(uri, headers: headers)
              : client.post(uri, headers: headers, body: jsonEncode(body)))
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw ApiException(
          408,
          'Sendoh did not respond within 60 seconds. Please retry shortly. '
          'If you requested a code, wait 60 seconds before requesting another.');
    } on http.ClientException {
      throw ApiException(503,
          'Cannot connect to Sendoh. Check your internet connection and retry.');
    } finally {
      client.close();
    }
  }

  Future<void> refresh() =>
      _refreshing ??= _rotate().whenComplete(() => _refreshing = null);

  Future<void> _rotate() async {
    if (refreshToken == null) {
      throw ApiException(401, 'Please sign in again.');
    }
    final result = await SendohApi(baseUrl, '')
        .request('/auth/refresh', body: {'refresh_token': refreshToken});
    token = result['access_token'] as String;
    refreshToken = result['refresh_token'] as String;
    await SessionStore.save(baseUrl, refreshToken!);
  }

  Future<dynamic> request(String path,
      {Map<String, dynamic>? body, String? key, bool retry = true}) async {
    final uri = Uri.parse('$baseUrl/api/v1$path');
    final sentToken = token;
    final headers = <String, String>{
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      if (key != null) 'Idempotency-Key': key,
    };
    // Send directly. Never replay a timed-out POST automatically.
    final response = await _send(uri, headers, body);
    if (response.statusCode == 401 && retry && refreshToken != null) {
      if (sentToken == token) {
        await refresh();
      }
      return request(path, body: body, key: key, retry: false);
    }
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      throw ApiException(
          response.statusCode, 'The server is unavailable. Please try again.');
    }
    if (response.statusCode >= 400) {
      String message = 'Please check your input and try again.';
      if (data is Map) {
        final error = data['error'];
        if (error is Map && error['message'] is String) {
          message = error['message'] as String;
        } else if (data['detail'] is String) {
          message = data['detail'] as String;
        }
      }
      throw ApiException(response.statusCode, message);
    }
    return data;
  }

  Future<List<dynamic>> collections() async =>
      List<dynamic>.from(await request('/collections'));
}
