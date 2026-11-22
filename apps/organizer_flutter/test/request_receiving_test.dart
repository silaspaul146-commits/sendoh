import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/api.dart';
import 'package:sendoh_organizer/money_requests.dart';

class ReceivingApi extends SendohApi {
  ReceivingApi(this.destination) : super('https://example.invalid', 'session');
  final Map<String, dynamic>? destination;
  @override
  Future<dynamic> request(String path,
      {Map<String, dynamic>? body, String? key, bool retry = true}) async {
    if (path == '/me/receiving-destination') {
      return {
        'version': destination == null ? 0 : 1,
        'destination': destination
      };
    }
    throw StateError('Unexpected $path');
  }
}

Future<void> open(WidgetTester tester, SendohApi api) async {
  await tester.pumpWidget(MaterialApp(
      home: RequestSend(
          api: api,
          userId: 'u1',
          personName: 'Marie',
          body: const {
        'recipient_id': 'r1',
        'amount': 1000,
        'reason': 'Lunch',
        'expires_at': null
      })));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('A request cannot be sent before the requester can receive',
      (tester) async {
    await open(tester, ReceivingApi(null));
    expect(find.text('Choose where you receive money first'), findsOneWidget);
    final send = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Send or check request'));
    expect(send.onPressed, isNull);
  });

  testWidgets('A requester with receiving details can send', (tester) async {
    await open(
        tester, ReceivingApi({'method': 'MTN', 'identity_current': true}));
    expect(find.text('Choose where you receive money first'), findsNothing);
    final send = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Send or check request'));
    expect(send.onPressed, isNotNull);
  });
}
