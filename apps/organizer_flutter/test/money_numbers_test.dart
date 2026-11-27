import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/api.dart';
import 'package:sendoh_organizer/design.dart';
import 'package:sendoh_organizer/getting_in.dart';
import 'package:sendoh_organizer/money_numbers.dart';

class NumbersApi extends SendohApi {
  NumbersApi() : super('https://example.invalid', 's');
  final calls = <String, Map<String, dynamic>?>{};
  List<Map<String, dynamic>> numbers = [
    {
      'id': 'n1',
      'method': 'MTN',
      'phone': '671234589',
      'masked': '671 •• •• 89',
      'verified': true,
      'pay_default': true,
      'receive_default': true,
      'is_sign_in_number': true
    },
    {
      'id': 'n2',
      'method': 'ORANGE',
      'phone': '699876512',
      'masked': '699 •• •• 12',
      'verified': true,
      'pay_default': false,
      'receive_default': false,
      'is_sign_in_number': false
    },
  ];
  @override
  Future<dynamic> request(String path,
      {Map<String, dynamic>? body, String? key, bool retry = true}) async {
    calls[path] = body;
    if (path == '/me/money-numbers' && body != null) {
      return {
        'numbers': numbers,
        'number': {
          'id': 'n3',
          'method': 'ORANGE',
          'masked': '655 •• •• 00',
          'verified': false
        },
        'challenge': {
          'challenge_id': 'c1',
          'resend_after': 60,
          'test_code': '482913'
        },
      };
    }
    if (path.endsWith('/verify')) return {'numbers': numbers};
    return {
      'numbers': numbers,
      'limit': 3,
      'sign_in_masked': '+237 671 •• •• 89',
      'sign_in_network': 'MTN'
    };
  }
}

Widget app(Widget home) => MaterialApp(theme: sendohTheme(), home: home);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('the network follows the number', () {
    expect(networkOf('671234589'), 'MTN');
    expect(networkOf('699876512'), 'ORANGE');
    expect(networkOf('655000000'), 'ORANGE');
    expect(networkOf('652000000'), 'MTN');
    expect(networkOf('620000000'), isNull);
  });

  testWidgets('add a number, then verify it with the code we texted',
      (tester) async {
    final api = NumbersApi();
    bool? result;
    await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () async => result = await Navigator.of(context)
                    .push<bool>(MaterialPageRoute(
                        builder: (_) => AddNumberScreen(api: api))),
                child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '655000000');
    await tester.pump();
    expect(
        find.text(
            'This is an Orange Money number, so Orange Money is selected for you.'),
        findsOneWidget);
    await tester.tap(find.text('Text a code to this number'));
    await tester.pumpAndSettle();
    expect(api.calls['/me/money-numbers'], {
      'phone': '655000000',
      'method': 'ORANGE',
      'pay_default': false,
      'receive_default': true
    });
    // Testing without SMS: the staging code is offered on screen.
    expect(find.text('Testing: your code is 482913'), findsOneWidget);
    await tester.tap(find.text('Use it'));
    await tester.pump();
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(api.calls['/me/money-numbers/n3/verify'],
        {'challenge_id': 'c1', 'code': '482913'});
    expect(result, isTrue);
  });

  testWidgets('settings list numbers with what each is used for',
      (tester) async {
    await tester.pumpWidget(app(Scaffold(
        body: SingleChildScrollView(
            child: MoneyNumbersSection(api: NumbersApi())))));
    await tester.pumpAndSettle();
    expect(find.text('671 •• •• 89'), findsOneWidget);
    expect(find.text('Verified · Pay with this · Receive on this'),
        findsOneWidget);
    expect(find.text('Add a Mobile Money number'), findsOneWidget);
  });

  testWidgets('paying picks the default verified number, not a typed one',
      (tester) async {
    final picked = <String?>[];
    await tester.pumpWidget(app(Scaffold(
        body: PayWithPicker(
            api: NumbersApi(),
            onChanged: (id, phone, method) =>
                picked.add('$id $phone $method')))));
    await tester.pumpAndSettle();
    expect(picked.first, 'n1 671234589 MTN');
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('699 •• •• 12'));
    await tester.pump();
    expect(picked.last, 'n2 699876512 ORANGE');
  });

  testWidgets('step 4 offers the sign-in number as already verified',
      (tester) async {
    var done = false;
    await tester.pumpWidget(app(Scaffold(
        body: SingleChildScrollView(
            child: WalletStep(
                signInMasked: '671 •• •• 89',
                network: 'MTN',
                useSignIn: true,
                onToggle: (_) {},
                added: const [],
                onAdd: () {},
                onDone: () => done = true,
                onSkip: () {})))));
    expect(find.text('MTN MoMo · 671 •• •• 89'), findsOneWidget);
    expect(find.text('Step 4 of 4'), findsOneWidget);
    await tester.ensureVisible(find.text('Done'));
    await tester.tap(find.text('Done'));
    expect(done, isTrue);
  });
}
