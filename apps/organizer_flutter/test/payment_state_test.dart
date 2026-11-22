import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/payment_state.dart';

String fmt(Object? n) => '$n FCFA';

void main() {
  test('contract position is read as-is', () {
    final p = MemberPosition.fromMember({
      'invitation_state': 'ACCEPTED',
      'sandbox_paid_amount': 999, // ignored when position exists
      'position': {
        'state': 'CONFIRMING',
        'membership': 'ACCEPTED',
        'confirmed_amount': 2000,
        'pending_amount': 1000,
        'expected_amount': 5000,
        'remaining_amount': 3000,
      },
    });
    expect(p.badge, 'Pending');
    expect(p.confirmed, 2000);
    expect(p.rosterLine(fmt),
        '2000 FCFA contributed · 1000 FCFA awaiting confirmation · 5000 FCFA expected');
    expect(p.outstanding, isFalse); // never remind while confirming
  });

  test('totals use confirmed money only for progress', () {
    final t = CollectionTotals.fromCollection({
      'totals': {
        'environment': 'SANDBOX',
        'confirmed_amount': 30000,
        'pending_amount': 1000,
        'target_amount': 50000,
      },
    });
    expect(t.progress, 0.6);
    expect(t.pending, 1000);
    expect(t.remaining, 20000);
  });

  test('older backend falls back to provider totals, never the simulator', () {
    final t = CollectionTotals.fromCollection({
      'collected_amount': 0,
      'sandbox_collected_amount': 1000,
      'test_collected_amount': 50000,
      'target_amount': 10000,
    });
    expect(t.confirmed, 1000);
    expect(t.sandbox, isTrue);
  });

  test('open contribution has no invented target', () {
    final p = MemberPosition.fromJoined({
      'expected_amount': null,
      'contribution_summary': {'sandbox_paid_amount': 1500},
    });
    expect(p.state, 'CONTRIBUTED');
    expect(p.remaining, isNull);
    expect(p.personalLine(fmt), '1500 FCFA contributed');
  });
}
