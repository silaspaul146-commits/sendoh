import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/api.dart';
import 'package:sendoh_organizer/design.dart';
import 'package:sendoh_organizer/notifications.dart';

class InboxApi extends SendohApi {
  InboxApi() : super('https://example.invalid', 'test');
  bool fail = false;
  bool read = false;
  final calls = <String>[];
  @override
  Future<dynamic> request(String path,
      {Map<String, dynamic>? body, String? key, bool retry = true}) async {
    calls.add(path);
    if (fail) {
      throw ApiException(503, 'Connection unavailable.');
    }
    if (path.endsWith('/read')) {
      read = true;
      return {'ok': true};
    }
    if (path == '/me/invitations' || path == '/me/joined-collections') {
      return [];
    }
    return {
      'items': [
        {
          'id': 'notification',
          'kind': 'INVITED',
          'title': 'You have a collection invitation',
          'collection_name': 'Family support',
          'collection_id': 'collection',
          'created_at': 1790000000,
          'read_at': read ? 1790000001 : null,
          'invitation_available': true
        },
      ],
      'unread_count': read ? 0 : 1,
      'next_cursor': null,
      'push_available': false
    };
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('inbox works when push is not configured', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: NotificationsScreen(api: InboxApi(), userId: 'user')));
    await tester.pumpAndSettle();
    expect(find.text('You have a collection invitation'), findsOneWidget);
    expect(find.textContaining('Family support'), findsOneWidget);
    expect(find.text('Enable push alerts'), findsNothing);
    expect(find.textContaining('Your updates will still appear here'),
        findsOneWidget);
  });

  testWidgets('opening an update marks it read then loads current invitations',
      (tester) async {
    final api = InboxApi();
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: NotificationsScreen(api: api, userId: 'user')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('You have a collection invitation'));
    await tester.tap(find.text('You have a collection invitation'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('/me/notifications/notification/read'));
    expect(api.calls, contains('/me/invitations'));
    expect(find.text('No invitations yet'), findsOneWidget);
  });

  testWidgets('failed inbox load shows retry instead of an empty success',
      (tester) async {
    final api = InboxApi()..fail = true;
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: NotificationsScreen(api: api, userId: 'user')));
    await tester.pumpAndSettle();
    expect(find.text('Connection unavailable.'), findsOneWidget);
    expect(find.text('You’re all caught up'), findsNothing);
    api.fail = false;
    await tester.ensureVisible(find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('You have a collection invitation'), findsOneWidget);
  });
}
