import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'main.dart' show apiProvider, money;
import 'design.dart';

class CreateCollection extends ConsumerStatefulWidget {
  const CreateCollection({super.key});
  @override
  ConsumerState<CreateCollection> createState() => _CreateCollectionState();
}

class _CreateCollectionState extends ConsumerState<CreateCollection> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      description = TextEditingController(),
      target = TextEditingController(),
      expected = TextEditingController(),
      participant = TextEditingController();
  final List<String> people = [];
  String mode = 'ANY_AMOUNT';
  DateTime? deadline;
  int step = 0;
  bool busy = false, submitted = false;
  String? error;
  String key =
      List.generate(24, (_) => Random.secure().nextInt(16).toRadixString(16))
          .join();
  @override
  void dispose() {
    for (final c in [name, description, target, expected, participant]) {
      c.dispose();
    }
    super.dispose();
  }

  String? amount(String? value, {bool required = false}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Enter an amount' : null;
    }
    final n = int.tryParse(value.trim());
    return n == null || n <= 0 || n > 1000000000000
        ? 'Enter a positive whole FCFA amount'
        : null;
  }

  void changed() {
    if (submitted) {
      key = List.generate(
          24, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
      submitted = false;
    }
  }

  void addPerson() {
    final value = participant.text.trim();
    if (value.isEmpty) return;
    if (people.length >= 200) {
      setState(() => error = 'You can add up to 200 participants.');
      return;
    }
    changed();
    setState(() {
      people.add(value);
      error = null;
      participant.clear();
    });
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
      submitted = true;
    });
    try {
      final data =
          await ref.read(apiProvider).request('/collections', key: key, body: {
        'name': name.text.trim(),
        'description': description.text.trim(),
        'currency': 'XAF',
        'target_amount':
            target.text.trim().isEmpty ? null : int.parse(target.text.trim()),
        'deadline_at': deadline == null
            ? null
            : DateTime.utc(
                    deadline!.year, deadline!.month, deadline!.day, 22, 59)
                .toIso8601String(),
        'mode': mode,
        'expected_amount':
            mode == 'ANY_AMOUNT' ? null : int.parse(expected.text.trim()),
        'participants': people.map((n) => {'name': n}).toList(),
        'publish': true
      });
      if (mounted) Navigator.of(context).pop(Map<String, dynamic>.from(data));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickDeadline() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial =
        deadline != null && !deadline!.isBefore(today) ? deadline! : today;
    final d = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: today,
        lastDate: today.add(const Duration(days: 3650)));
    if (d != null) {
      changed();
      setState(() => deadline = d);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Create collection'),
          leading: IconButton(
              tooltip: 'Back',
              onPressed: busy
                  ? null
                  : () {
                      if (step > 0) {
                        setState(() => step--);
                      } else {
                        Navigator.pop(context);
                      }
                    },
              icon: const Icon(Icons.arrow_back))),
      body: SafeArea(
          child: Form(
              key: form,
              child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: ConstrainedBox(
                          constraints: BoxConstraints(
                              minHeight: (constraints.maxHeight - 24)
                                  .clamp(0.0, double.infinity)
                                  .toDouble()),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('Step ${step + 1} of 3',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: SendohColors.muted)),
                                const SizedBox(height: 28),
                                if (step == 0) ...[
                                  fieldLabel('Collection name'),
                                  TextFormField(
                                      controller: name,
                                      onChanged: (_) => changed(),
                                      maxLength: 120,
                                      decoration: const InputDecoration(
                                          hintText: 'e.g. Department Activity',
                                          counterText: ''),
                                      validator: (v) =>
                                          v == null || v.trim().isEmpty
                                              ? 'Enter a collection name'
                                              : null),
                                  const SizedBox(height: 20),
                                  fieldLabel('Purpose (optional)'),
                                  TextFormField(
                                      controller: description,
                                      onChanged: (_) => changed(),
                                      maxLength: 2000,
                                      maxLines: 2,
                                      decoration: const InputDecoration(
                                          hintText:
                                              'What are you collecting for?',
                                          counterText: '')),
                                  const SizedBox(height: 20),
                                  fieldLabel('Target amount (optional)'),
                                  TextFormField(
                                      controller: target,
                                      onChanged: (_) => changed(),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly
                                      ],
                                      validator: (v) => amount(v),
                                      decoration: const InputDecoration(
                                          hintText: 'No target',
                                          suffixText: 'FCFA')),
                                  const SizedBox(height: 20),
                                  fieldLabel('Deadline (optional)'),
                                  OutlinedButton.icon(
                                      onPressed: pickDeadline,
                                      icon: const Icon(
                                          Icons.calendar_today_outlined,
                                          size: 18),
                                      label: Text(deadline == null
                                          ? 'Choose a date'
                                          : displayDate(DateTime.utc(
                                                  deadline!.year,
                                                  deadline!.month,
                                                  deadline!.day)
                                              .toIso8601String()))),
                                  if (deadline != null)
                                    Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                            onPressed: () {
                                              changed();
                                              setState(() => deadline = null);
                                            },
                                            child:
                                                const Text('Remove deadline'))),
                                  const SizedBox(height: 20),
                                  fieldLabel('Contribution rule'),
                                  DropdownButtonFormField<String>(
                                      // Compatibility with Flutter SDKs that lack initialValue.
                                      // ignore: deprecated_member_use
                                      value: mode,
                                      isExpanded: true,
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'ANY_AMOUNT',
                                            child: Text('Any amount')),
                                        DropdownMenuItem(
                                            value: 'EXPECTED_TOTAL',
                                            child: Text(
                                                'Expected total per person')),
                                        DropdownMenuItem(
                                            value: 'MINIMUM_TOTAL',
                                            child: Text(
                                                'Minimum total per person'))
                                      ],
                                      onChanged: (v) {
                                        changed();
                                        setState(() => mode = v!);
                                      }),
                                  if (mode != 'ANY_AMOUNT') ...[
                                    const SizedBox(height: 20),
                                    fieldLabel('Suggested contribution'),
                                    TextFormField(
                                        controller: expected,
                                        onChanged: (_) => changed(),
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly
                                        ],
                                        validator: (v) =>
                                            amount(v, required: true),
                                        decoration: const InputDecoration(
                                            hintText: '3,000',
                                            suffixText: 'FCFA'))
                                  ],
                                ],
                                if (step == 1) ...[
                                  const Text('Who should contribute?',
                                      style: TextStyle(
                                          fontSize: 23,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 10),
                                  const Text(
                                      'Add participants now, or share the collection link after creating it.',
                                      style: TextStyle(
                                          fontSize: 13,
                                          height: 1.7,
                                          color: SendohColors.secondary)),
                                  const SizedBox(height: 24),
                                  fieldLabel('Participant name'),
                                  TextField(
                                      controller: participant,
                                      maxLength: 120,
                                      textCapitalization:
                                          TextCapitalization.words,
                                      onSubmitted: (_) => addPerson(),
                                      decoration: InputDecoration(
                                          hintText: 'Full name',
                                          suffixIcon: IconButton(
                                              tooltip: 'Add participant',
                                              onPressed: addPerson,
                                              icon: const Icon(Icons.add,
                                                  color: SendohColors.teal)))),
                                  ...people.asMap().entries.map((e) => ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading:
                                          PersonAvatar(e.value, radius: 17),
                                      title: Text(e.value,
                                          style: const TextStyle(fontSize: 14)),
                                      subtitle: Text(
                                          mode == 'ANY_AMOUNT'
                                              ? 'Any amount'
                                              : money(
                                                  int.tryParse(expected.text)),
                                          style: const TextStyle(fontSize: 12)),
                                      trailing: IconButton(
                                          tooltip: 'Remove ${e.value}',
                                          icon:
                                              const Icon(Icons.close, size: 19),
                                          onPressed: () {
                                            changed();
                                            setState(
                                                () => people.removeAt(e.key));
                                          }))),
                                  if (people.isEmpty)
                                    const EmptyState(
                                        title: 'No participants added',
                                        message:
                                            'You can still create a collection and share its link.'),
                                  const SizedBox(height: 16),
                                  Text('${people.length} participants',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: SendohColors.muted)),
                                ],
                                if (step == 2) ...[
                                  SurfaceCard(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                        Row(children: [
                                          const CollectionSymbol(),
                                          const SizedBox(width: 12),
                                          Expanded(
                                              child: Text(name.text.trim(),
                                                  style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600)))
                                        ]),
                                        const Divider(),
                                        SummaryRow(
                                            'Target',
                                            target.text.trim().isEmpty
                                                ? 'No target'
                                                : money(int.parse(
                                                    target.text.trim()))),
                                        SummaryRow(
                                            'Deadline',
                                            deadline == null
                                                ? 'No deadline'
                                                : displayDate(DateTime.utc(
                                                        deadline!.year,
                                                        deadline!.month,
                                                        deadline!.day)
                                                    .toIso8601String())),
                                        SummaryRow(
                                            mode == 'MINIMUM_TOTAL'
                                                ? 'Minimum total per person'
                                                : 'Suggested contribution',
                                            mode == 'ANY_AMOUNT'
                                                ? 'Any amount'
                                                : money(int.parse(
                                                    expected.text.trim()))),
                                        SummaryRow(
                                            'Participants', '${people.length}'),
                                        const SummaryRow('Who can view?',
                                            'Anyone with the link'),
                                        if (description.text
                                            .trim()
                                            .isNotEmpty) ...[
                                          const Divider(),
                                          Text(description.text.trim(),
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  height: 1.6,
                                                  color:
                                                      SendohColors.secondary))
                                        ]
                                      ])),
                                  const SizedBox(height: 22),
                                  const Text('You will be the organizer.',
                                      style: TextStyle(fontSize: 13)),
                                  const SizedBox(height: 10),
                                  const Text(
                                      'Creating a collection is free. Participant names stay private. Payments are not available yet.',
                                      style: TextStyle(
                                          fontSize: 12,
                                          height: 1.7,
                                          color: SendohColors.secondary)),
                                ],
                                if (error != null)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 18),
                                      child: Text(error!,
                                          style: const TextStyle(
                                              color: SendohColors.red))),
                                const SizedBox(height: 36),
                                Row(children: [
                                  if (step > 0) ...[
                                    Expanded(
                                        child: OutlinedButton(
                                            onPressed: busy
                                                ? null
                                                : () => setState(() => step--),
                                            child: const Text('Back'))),
                                    const SizedBox(width: 12)
                                  ],
                                  Expanded(
                                      flex: 2,
                                      child: FilledButton(
                                          style: FilledButton.styleFrom(
                                              backgroundColor: step == 2
                                                  ? SendohColors.orange
                                                  : SendohColors.teal,
                                              foregroundColor: step == 2
                                                  ? SendohColors.ink
                                                  : Colors.white),
                                          onPressed: busy
                                              ? null
                                              : () {
                                                  if (step < 2) {
                                                    if (form.currentState!
                                                        .validate()) {
                                                      if (step == 1 &&
                                                          participant.text
                                                              .trim()
                                                              .isNotEmpty) {
                                                        addPerson();
                                                      }
                                                      setState(() => step++);
                                                    }
                                                  } else {
                                                    save();
                                                  }
                                                },
                                          child: Text(busy
                                              ? 'Creating…'
                                              : step == 2
                                                  ? 'Create collection'
                                                  : 'Continue')))
                                ]),
                              ])))))));
  Widget fieldLabel(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(fontSize: 12, color: SendohColors.secondary)));
}
