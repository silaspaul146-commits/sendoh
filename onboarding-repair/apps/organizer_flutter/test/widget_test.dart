import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/main.dart';
void main() {
  testWidgets('Welcome offers onboarding and legacy access', (tester) async {
    await tester.pumpWidget(const SendohApp());
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
    expect(find.text('Payment successful'), findsNothing);
  });
}
