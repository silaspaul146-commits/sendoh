import 'dart:convert';
import 'package:http/http.dart' as http;

class SendohApi {
  SendohApi(this.baseUrl, this.token);
  final String baseUrl;
  final String token;
  Future<dynamic> request(String path,
      {Map<String, dynamic>? body, String? key}) async {
    final uri = Uri.parse('$baseUrl/api/v1$path');
    final headers = {
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      if (key != null) 'Idempotency-Key': key
    };
    final response = await (body == null
            ? http.get(uri, headers: headers)
            : http.post(uri, headers: headers, body: jsonEncode(body)))
        .timeout(const Duration(seconds: 20));
    final data = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(data is Map && data['error'] is Map
          ? data['error']['message']
          : 'Please check your input and try again.');
    }
    return data;
  }

  Future<List<dynamic>> collections() async =>
      List<dynamic>.from(await request('/collections'));
}
