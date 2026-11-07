import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/home.dart';

void main() {
  Map<String, dynamic> item(int paid, {bool pending = false}) => {
        'collection': {'status': 'ACTIVE'},
        'expected_amount': 1000,
        'contribution_summary': {
          'sandbox_paid_amount': paid,
          'sandbox_payment_pending': pending,
          'live_available': false,
        },
      };
  test('Verified provider contribution fulfils personal share', () {
    expect(joinedPersonalStatus(item(1000)), 'Your part done ✓');
  });
  test('Partial contribution shows outstanding share', () {
    expect(joinedPersonalStatus(item(400)), '600 FCFA remaining');
  });
  test('Pending attempt does not claim completion', () {
    expect(joinedPersonalStatus(item(0, pending: true)), 'Payment pending');
  });
}
