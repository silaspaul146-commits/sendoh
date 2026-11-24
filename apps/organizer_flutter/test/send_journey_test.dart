import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/api.dart';
import 'package:sendoh_organizer/design.dart';
import 'package:sendoh_organizer/near2pay.dart';
import 'package:sendoh_organizer/people_flows.dart';
import 'package:sendoh_organizer/person_payments.dart';

class Gateway implements PeopleFlowGateway {
  Gateway({this.ready = true});
  final bool ready;
  final reminded = <String>[];
  @override
  Future<ResolvedPerson> resolve(String identity,
          {required bool fromQr}) async =>
      ResolvedPerson(
          id: 'alain-id',
          name: 'Alain',
          identity: '@alain',
          receivingReady: ready);
  @override
  Future<String?> scan(BuildContext context) async => null;
  @override
  Future<void> openCheckout(BuildContext context, PeopleDraft draft) async {}
  @override
  Future<void> remindReceiving(String personId) async => reminded.add(personId);
}

class NearApi extends SendohApi {
  NearApi({this.ready = true, this.amount})
      : super('https://example.invalid', 's');
  final bool ready;
  final int? amount;
  final paths = <String>[];
  @override
  Future<dynamic> request(String path,
      {Map<String, dynamic>? body, String? key, bool retry = true}) async {
    paths.add(path);
    if (path == '/near/resolve') {
      return {
        'purpose': 'PERSON',
        'person': {
          'id': 'alain-id',
          'name': 'Alain',
          'identity': '@alain',
          'receiving_ready': ready
        },
        'amount': amount,
      };
    }
    if (path == '/people/receiving-reminder') {
      return {'sent': true};
    }
    throw StateError('Unexpected $path');
  }
}

Future<void> typeCode(WidgetTester tester) async {
  await tester.tap(find.text('Enter code instead'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'K7M-4QX');
  await tester.tap(find.text('Find person'));
  await tester.pumpAndSettle();
}

Widget app(Widget home, {double scale = 1}) => MaterialApp(
    theme: sendohTheme(),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: home);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('Handle search shows the recipient preview before any amount',
      (tester) async {
    await tester.pumpWidget(app(PeopleFlow(gateway: Gateway())));
    await tester.enterText(find.byType(TextFormField), '@alain');
    await tester.tap(find.text('Find person'));
    await tester.pumpAndSettle();
    expect(find.text('Alain'), findsOneWidget);
    expect(find.text('@alain'), findsOneWidget);
    expect(find.text('Check this is the person you mean.'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Choose someone else'), findsOneWidget);
  });

  testWidgets('No receiving details: nothing to pay, a way to tell them',
      (tester) async {
    final gateway = Gateway(ready: false);
    await tester.pumpWidget(app(PeopleFlow(gateway: gateway)));
    await tester.enterText(find.byType(TextFormField), '@alain');
    await tester.tap(find.text('Find person'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing has been charged'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    await tester.tap(find.text('Let Alain know'));
    await tester.pumpAndSettle();
    expect(gateway.reminded, ['alain-id']);
    expect(find.text('We let Alain know'), findsOneWidget);
  });

  testWidgets('A code reaches the same preview and backing out moves nothing',
      (tester) async {
    final api = NearApi(amount: 2500);
    await tester.pumpWidget(app(NearScanScreen(api: api, scanner: false)));
    expect(find.text('Show my code'), findsOneWidget);
    await typeCode(tester);
    expect(find.text('Alain'), findsOneWidget);
    expect(find.text('@alain'), findsOneWidget);
    expect(find.text('Check this is the person you mean.'), findsOneWidget);
    // The amount Alain put on his code is shown, not silently charged.
    expect(find.widgetWithText(TextField, '2500'), findsOneWidget);
    await tester.tap(find.text('Wrong person? Scan again'));
    await tester.pumpAndSettle();
    expect(find.text('Enter code instead'), findsOneWidget);
    expect(api.paths.where((p) => p.startsWith('/person-payments')), isEmpty);
  });

  testWidgets('A code for someone who cannot receive explains it before paying',
      (tester) async {
    final api = NearApi(ready: false);
    await tester.pumpWidget(app(NearScanScreen(api: api, scanner: false)));
    await typeCode(tester);
    expect(find.textContaining('hasn’t set where they receive money'),
        findsOneWidget);
    expect(find.text('Review payment'), findsNothing);
    await tester.tap(find.text('Let Alain know'));
    await tester.pumpAndSettle();
    expect(api.paths, contains('/people/receiving-reminder'));
  });

  testWidgets('Recipient preview fits a compact phone with large text',
      (tester) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(
        NearAmountScreen(api: NearApi(), person: const {
          'id': 'a',
          'name': 'Alain Mbarga Ndongo',
          'identity': '@alain',
          'receiving_ready': true
        }),
        scale: 1.6));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Reachable by scrolling, fully inside the 320 px screen.
    await tester.scrollUntilVisible(find.text('Review payment'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Review payment'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Review payment')).right,
        lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  test('Activity lines tell each person whether it reached Alain', () {
    Map<String, dynamic> item(String direction, String phase) => {
          'direction': direction,
          'phase': phase,
          'payer': {'name': 'Marie'},
          'quote': {
            'recipient': {'name': 'Alain'},
            'amounts': {'recipient_amount': 2500}
          },
        };
    expect(personActivityLine(item('SENT', 'DELIVERING')),
        (title: 'You sent 2,500 FCFA to Alain', status: 'Paid · delivering'));
    expect(personActivityLine(item('RECEIVED', 'DELIVERING')),
        (title: 'Marie sent you 2,500 FCFA', status: 'On its way to you'));
    expect(
        personActivityLine(item('RECEIVED', 'DELIVERED')).status, 'Received');
    expect(personActivityLine(item('SENT', 'DELIVERED')).status, 'Delivered');
    for (final phase in [
      'AWAITING_APPROVAL',
      'CONFIRMING',
      'DELIVERING',
      'REVIEW_FUNDS_HELD'
    ]) {
      expect(personActivityLine(item('RECEIVED', phase)).status,
          isNot('Received'));
    }
  });
}
