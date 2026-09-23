import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/main.dart';

void main() {
  testWidgets('welcome mirrors the approved Sendoh onboarding', (tester) async {
    await tester.pumpWidget(const SendohApp());
    expect(find.text('SENDOH'), findsOneWidget);
    expect(find.text('Organize money. Together.'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
    expect(find.text('Payment successful'), findsNothing);
  });

  testWidgets('phone step does not imply payment availability', (tester) async {
    await tester.pumpWidget(const SendohApp());
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your phone number'), findsOneWidget);
    expect(find.text('+237  '), findsOneWidget);
    expect(find.textContaining('payment', findRichText: true), findsNothing);
  });
}
