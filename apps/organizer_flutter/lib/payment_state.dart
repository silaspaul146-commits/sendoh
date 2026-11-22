/// The single client reading of the backend payment-state contract
/// (`position` for one member, `totals` for one collection).
///
/// Screens must use these types instead of reading payment fields directly.
/// Confirmed money and money awaiting confirmation are never added together,
/// and joining a collection is never treated as paying.
library;

int _int(Object? v) => (v as num?)?.toInt() ?? 0;
int? _intOrNull(Object? v) => (v as num?)?.toInt();

class MemberPosition {
  const MemberPosition({
    required this.state,
    required this.membership,
    required this.confirmed,
    required this.pending,
    required this.expected,
    required this.remaining,
    this.environment = 'SANDBOX',
  });

  /// INVITED, NOT_JOINED, DECLINED, CANCELLED, EXPIRED, NOT_STARTED,
  /// CONFIRMING, PARTIAL, FULFILLED, CONTRIBUTED.
  final String state;
  final String membership;
  final int confirmed, pending;
  final int? expected, remaining;
  final String environment;

  bool get joined => membership == 'ACCEPTED';
  bool get confirming => state == 'CONFIRMING';
  bool get paidUp => state == 'FULFILLED' || state == 'CONTRIBUTED';

  /// Joined, nothing awaiting confirmation, and money still expected.
  bool get outstanding =>
      joined && !confirming && (state == 'NOT_STARTED' || state == 'PARTIAL');

  factory MemberPosition.fromJson(Map<String, dynamic> p) => MemberPosition(
        state: p['state'] as String,
        membership: p['membership'] as String? ?? 'ACCEPTED',
        confirmed: _int(p['confirmed_amount']),
        pending: _int(p['pending_amount']),
        expected: _intOrNull(p['expected_amount']),
        remaining: _intOrNull(p['remaining_amount']),
        environment: p['environment'] as String? ?? 'SANDBOX',
      );

  /// An organizer roster row. Falls back to older sandbox fields if the
  /// backend predates the contract.
  factory MemberPosition.fromMember(Map<String, dynamic> m) {
    final p = m['position'];
    if (p is Map) {
      return MemberPosition.fromJson(Map<String, dynamic>.from(p));
    }
    return _legacy(
        membership: m['invitation_state'] as String? ?? 'NOT_JOINED',
        confirmed: _int(m['sandbox_paid_amount']),
        pending: _int(m['sandbox_pending_amount']),
        pendingFlag: m['sandbox_payment_pending'] == true,
        expected: _intOrNull(m['expected_amount']));
  }

  /// A joined-collection item (`contribution_summary` + `expected_amount`).
  factory MemberPosition.fromJoined(Map<String, dynamic> item) {
    final summary = Map<String, dynamic>.from(
        (item['contribution_summary'] as Map?) ?? const {});
    final p = summary['position'];
    if (p is Map) {
      return MemberPosition.fromJson(Map<String, dynamic>.from(p));
    }
    return _legacy(
        membership: 'ACCEPTED',
        confirmed: _int(summary['sandbox_paid_amount']),
        pending: _int(summary['sandbox_pending_amount']),
        pendingFlag: summary['sandbox_payment_pending'] == true,
        expected: _intOrNull(item['expected_amount']));
  }

  static MemberPosition _legacy(
      {required String membership,
      required int confirmed,
      required int pending,
      required bool pendingFlag,
      required int? expected}) {
    final remaining = expected != null && expected > 0
        ? (expected - confirmed).clamp(0, expected)
        : null;
    final String state;
    if (membership != 'ACCEPTED' && confirmed == 0 && !pendingFlag) {
      state = switch (membership) {
        'PENDING' => 'INVITED',
        'DECLINED' => 'DECLINED',
        'CANCELLED' => 'CANCELLED',
        'EXPIRED' => 'EXPIRED',
        _ => 'NOT_JOINED',
      };
    } else if (pendingFlag || pending > 0) {
      state = 'CONFIRMING';
    } else if (confirmed == 0) {
      state = 'NOT_STARTED';
    } else if (remaining == null) {
      state = 'CONTRIBUTED';
    } else {
      state = remaining > 0 ? 'PARTIAL' : 'FULFILLED';
    }
    return MemberPosition(
        state: state,
        membership: membership,
        confirmed: confirmed,
        pending: pending,
        expected: expected,
        remaining: remaining);
  }

  /// Short organizer badge; also the roster filter value.
  String get badge => switch (state) {
        'INVITED' => 'Invited',
        'DECLINED' => 'Declined',
        'CANCELLED' => 'Cancelled',
        'EXPIRED' => 'Expired',
        'NOT_JOINED' => 'Not joined',
        'CONFIRMING' => 'Pending',
        'NOT_STARTED' => 'Unpaid',
        'PARTIAL' => 'Partial',
        _ => 'Paid',
      };

  /// Organizer row: confirmed first, awaiting beside it, never summed.
  String rosterLine(String Function(Object?) money) {
    final parts = <String>['${money(confirmed)} contributed'];
    if (pending > 0) {
      parts.add('${money(pending)} awaiting confirmation');
    }
    if (expected != null) {
      parts.add('${money(expected)} expected');
    }
    return parts.join(' · ');
  }

  /// The member's own one-line position.
  String personalLine(String Function(Object?) money) => switch (state) {
        'CONFIRMING' => 'Payment pending',
        'FULFILLED' => 'Your part paid',
        'PARTIAL' => '${money(remaining)} remaining',
        'CONTRIBUTED' => '${money(confirmed)} contributed',
        _ => expected != null && expected! > 0
            ? '${money(expected)} expected'
            : 'Any amount welcome',
      };
}

class CollectionTotals {
  const CollectionTotals(
      {required this.confirmed,
      required this.pending,
      required this.target,
      required this.known,
      this.environment = 'SANDBOX'});

  final int confirmed, pending;
  final int? target;

  /// False when the payload carries no total at all (e.g. a minimal preview).
  final bool known;
  final String environment;

  bool get sandbox => environment == 'SANDBOX';
  bool get targetReached =>
      target != null && target! > 0 && confirmed >= target!;
  int? get remaining => target != null && target! > 0
      ? (target! - confirmed).clamp(0, target!)
      : null;

  /// Progress uses confirmed money only.
  double get progress => target != null && target! > 0
      ? (confirmed / target!).clamp(0.0, 1.0).toDouble()
      : 0;

  factory CollectionTotals.fromCollection(Map<String, dynamic> c) {
    final t = c['totals'];
    if (t is Map) {
      return CollectionTotals(
          confirmed: _int(t['confirmed_amount']),
          pending: _int(t['pending_amount']),
          target: _intOrNull(t['target_amount']),
          known: true,
          environment: t['environment'] as String? ?? 'SANDBOX');
    }
    // Older backend: live total if any, otherwise provider sandbox. Never the simulator.
    final live = _int(c['collected_amount']);
    final sandbox = _int(c['sandbox_collected_amount']);
    return CollectionTotals(
        confirmed: live > 0 ? live : sandbox,
        pending: 0,
        target: _intOrNull(c['target_amount']),
        known: c.containsKey('collected_amount') ||
            c.containsKey('sandbox_collected_amount'),
        environment: live > 0 ? 'LIVE' : 'SANDBOX');
  }
}
