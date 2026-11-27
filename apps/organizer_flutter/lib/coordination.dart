import 'i18n.dart';
import 'package:flutter/material.dart';
import 'design.dart';
import 'payment_state.dart';

export 'payment_state.dart';

String coordinationMoney(dynamic value) =>
    value == null ? t('No target') : fcfa(value);

// Totals come from the payment-state contract; legacy simulator money is never shown.
bool showingProviderTest(Map<String, dynamic> data) {
  final totals = CollectionTotals.fromCollection(data);
  return totals.sandbox && totals.confirmed > 0;
}

int displayedCollectionAmount(Map<String, dynamic> data) =>
    CollectionTotals.fromCollection(data).confirmed;

/// The same progress language for organizers and invited members.
class CollectionProgress extends StatelessWidget {
  const CollectionProgress(
      {super.key, required this.data, this.dark = false, this.compact = false});
  final Map<String, dynamic> data;
  final bool dark, compact;
  @override
  Widget build(BuildContext context) {
    final totals = CollectionTotals.fromCollection(data);
    final actual = totals.confirmed;
    final target = (data['target_amount'] as num?)?.toInt();
    final color = dark ? Colors.white : SendohColors.teal;
    final muted = dark ? const Color(0xFFD1E4E0) : SendohColors.secondary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
          showingProviderTest(data) ? t('Collected · Sandbox') : t('Collected'),
          style: TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 6),
      Text(coordinationMoney(actual),
          style: TextStyle(
              color: color, fontSize: 28, fontWeight: FontWeight.w700)),
      if (target != null && target > 0) ...[
        const SizedBox(height: 5),
        Text('of ${coordinationMoney(target)}',
            style: TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 14),
        ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
                value: (actual / target).clamp(0.0, 1.0).toDouble(),
                minHeight: 7,
                color: SendohColors.orange,
                backgroundColor:
                    dark ? const Color(0xFF316260) : SendohColors.tealSoft)),
        const SizedBox(height: 8),
        if (!compact)
          Text(
              actual >= target
                  ? t('Target reached')
                  : t('{amount} to go',
                      {'amount': coordinationMoney(target - actual)}),
              style: TextStyle(color: muted, fontSize: 12)),
      ],
      // Awaiting money is named, but the orange line stays at confirmed money.
      if (totals.pending > 0 && !compact) ...[
        const SizedBox(height: 10),
        Text(
            t('{amount} awaiting confirmation',
                {'amount': coordinationMoney(totals.pending)}),
            style: TextStyle(color: muted, fontSize: 12)),
      ],
    ]);
  }
}

class PeoplePreview extends StatelessWidget {
  const PeoplePreview({super.key, required this.people, this.dark = false});
  final List<dynamic> people;
  final bool dark;
  @override
  Widget build(BuildContext context) => Wrap(
          spacing: 5,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...people.take(5).map(
                (p) => MemberAvatar(Map<String, dynamic>.from(p), radius: 15)),
            if (people.length > 5)
              CircleAvatar(
                  radius: 15,
                  backgroundColor: SendohColors.tealSoft,
                  child: Text('+${people.length - 5}',
                      style: const TextStyle(
                          fontSize: 10, color: SendohColors.teal))),
            Text(
                people.length == 1
                    ? t('1 person')
                    : t('{count} people', {'count': people.length}),
                style: TextStyle(
                    fontSize: 12,
                    color: dark ? Colors.white : SendohColors.secondary)),
          ]);
}

class JoinedCollectionCard extends StatelessWidget {
  const JoinedCollectionCard(
      {super.key, required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = Map<String, dynamic>.from(item['collection']);
    return Semantics(
        button: true,
        label: t('Open joined collection {name}', {'name': c['name']}),
        child: Material(
          color: SendohColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: SendohColors.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
              onTap: onTap,
              child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          CollectionSymbol(),
                          Spacer(),
                          StatusBadge('JOINED')
                        ]),
                        const SizedBox(height: 14),
                        Text(c['name'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text('By ${c['organizer_name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: SendohColors.secondary)),
                        const SizedBox(height: 18),
                        Text(
                            item['expected_amount'] == null
                                ? t('Contribute any amount')
                                : t('Your expected contribution'),
                            style: const TextStyle(
                                fontSize: 12, color: SendohColors.secondary)),
                        if (item['expected_amount'] != null)
                          Text(coordinationMoney(item['expected_amount']),
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: SendohColors.teal)),
                        const SizedBox(height: 10),
                        Text(displayDate(c['deadline_at']),
                            style: const TextStyle(
                                fontSize: 12, color: SendohColors.secondary)),
                        const SizedBox(height: 18),
                        Row(children: [
                          Expanded(
                              child: Text(t('Open collection'),
                                  style: TextStyle(
                                      color: SendohColors.teal,
                                      fontWeight: FontWeight.w600))),
                          Icon(Icons.arrow_forward,
                              color: SendohColors.teal, size: 18)
                        ]),
                      ]))),
        ));
  }
}

class CoordinationAction extends StatelessWidget {
  const CoordinationAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: SendohColors.canvas,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 4,
              ),
              child: Column(
                children: [
                  Icon(
                    icon,
                    color:
                        onTap == null ? SendohColors.muted : SendohColors.teal,
                    size: 22,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: SendohColors.teal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Money a member has started paying that the provider has not yet confirmed.
int memberPendingAmount(Map<String, dynamic> member) =>
    MemberPosition.fromMember(member).pending;

/// Organizer row text: confirmed money first, awaiting money beside it, never summed.
String memberContributionLine(
        Map<String, dynamic> member, String Function(Object?) money) =>
    MemberPosition.fromMember(member).rosterLine(money);

/// Invitation acceptance and contribution settlement are separate states.
String collectionMemberPaymentStatus(Map<String, dynamic> member) =>
    MemberPosition.fromMember(member).badge;
