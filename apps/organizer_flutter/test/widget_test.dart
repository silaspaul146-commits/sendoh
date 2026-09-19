import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/main.dart';
void main() {
  testWidgets('Development connection is explicit and no fake OTP success is shown', (tester) async {
    await tester.pumpWidget(const SendohApp());
    expect(find.text('Development connection'), findsOneWidget);
    expect(find.text('Open organizer app'), findsOneWidget);
    expect(find.text('Payment successful'), findsNothing);
  });
}
