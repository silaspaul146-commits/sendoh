import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/money_requests.dart';
import 'package:sendoh_organizer/person_payments.dart';

Map<String, dynamic> request(String direction, String status,
        {String? phase}) =>
    {
      'direction': direction,
      'status': status,
      'payment_phase': phase,
      'amount': 5000,
      'requester': {'name': 'Alain'},
      'recipient': {'name': 'Marie'},
    };

void main() {
  test('Collected is not delivered, from both sides', () {
    // Marie paid, delivery to Alain still pending.
    expect(
        requestHeadline(request('RECEIVED', 'PROCESSING', phase: 'DELIVERING')),
        'You paid · delivering to Alain');
    expect(requestHeadline(request('SENT', 'PROCESSING', phase: 'DELIVERING')),
        'Marie paid · on its way to you');
    expect(requestHeadline(request('SENT', 'PROCESSING', phase: 'CONFIRMING')),
        'Marie is paying');
    expect(
        requestHeadline(
            request('RECEIVED', 'PROCESSING', phase: 'AWAITING_APPROVAL')),
        'Confirming your payment');
    for (final r in [
      request('SENT', 'PROCESSING', phase: 'DELIVERING'),
      request('SENT', 'PROCESSING', phase: 'CONFIRMING'),
      request('SENT', 'PAYMENT_REVIEW', phase: 'REVIEW_FUNDS_HELD'),
    ]) {
      expect(requestHeadline(r), isNot(contains('received')));
    }
  });

  test('Resolved and declined requests read clearly to each person', () {
    expect(requestHeadline(request('RECEIVED', 'PAID', phase: 'DELIVERED')),
        'Paid · delivered to Alain');
    expect(requestHeadline(request('SENT', 'PAID', phase: 'DELIVERED')),
        'Paid · you received 5,000 FCFA');
    expect(requestHeadline(request('SENT', 'DECLINED')), 'Marie declined');
    expect(requestHeadline(request('RECEIVED', 'DECLINED')),
        'You declined this request');
    expect(requestHeadline(request('RECEIVED', 'PENDING')),
        'Alain is waiting for your payment');
  });

  test('Payment copy only says received after verified delivery', () {
    for (final phase in [
      'AWAITING_APPROVAL',
      'CONFIRMING',
      'DELIVERING',
      'REVIEW_FUNDS_HELD',
      'FAILED'
    ]) {
      final copy = personPaymentCopy(
          phase: phase,
          recipient: true,
          payer: 'Marie',
          payee: 'Alain',
          amount: '5,000 FCFA');
      expect(copy.title, isNot(contains('received')));
    }
    expect(
        personPaymentCopy(
                phase: 'DELIVERED',
                recipient: true,
                payer: 'Marie',
                payee: 'Alain',
                amount: '5,000 FCFA')
            .title,
        'You received 5,000 FCFA');
  });
}
