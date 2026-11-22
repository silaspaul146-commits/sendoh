import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/coordination.dart';

String fmt(Object? n) => '$n FCFA';

void main() {
  Map<String, dynamic> member(int paid, int pending, {int? expected}) => {
        'invitation_state': 'ACCEPTED',
        'sandbox_paid_amount': paid,
        'sandbox_pending_amount': pending,
        'sandbox_payment_pending': pending > 0,
        'sandbox_payment_status': paid == 0
            ? 'Unpaid'
            : (expected != null && paid < expected ? 'Partial' : 'Paid'),
        'expected_amount': expected,
      };

  test('confirmed and awaiting money are shown separately, never summed', () {
    expect(memberContributionLine(member(2000, 1000, expected: 5000), fmt),
        '2000 FCFA contributed · 1000 FCFA awaiting confirmation · 5000 FCFA expected');
    expect(memberPendingAmount(member(2000, 1000)), 1000);
  });

  test('no awaiting line without a pending attempt', () {
    expect(
        memberContributionLine(member(1000, 0), fmt), '1000 FCFA contributed');
  });

  test('a pending attempt is shown as Pending, not Paid', () {
    expect(collectionMemberPaymentStatus(member(0, 1000, expected: 1000)),
        'Pending');
  });

  test('joining is not paying', () {
    expect(
        collectionMemberPaymentStatus(
            {'invitation_state': 'PENDING', 'sandbox_paid_amount': 0}),
        'Invited');
  });
}
