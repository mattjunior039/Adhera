import 'package:flutter/material.dart';

import '../models/medication.dart';
import '../models/schedule.dart';

String scheduleTimeLabel(String time) {
  final parts = time.split(':');
  final hour = int.tryParse(parts.first);
  if (hour == null || parts.length < 2) return time;
  return '${hour % 12 == 0 ? 12 : hour % 12}:${parts[1]} ${hour < 12 ? 'AM' : 'PM'}';
}

Future<void> showMedicationInstructions(
  BuildContext context,
  Schedule schedule,
  Medication? medication,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(medication?.name ?? 'Medication instructions'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${schedule.dayOfWeek} at ${scheduleTimeLabel(schedule.timeOfDay)}',
            ),
            if (schedule.notes?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(schedule.notes!),
            ],
            if (medication?.dosage?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(medication!.dosage!),
            ],
            const SizedBox(height: 16),
            const Text(
              'Instructions',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              medication?.instructions?.trim().isNotEmpty == true
                  ? medication!.instructions!
                  : 'No medication-specific instructions have been provided. Follow your prescription or product label and confirm directions with your pharmacist.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class WeeklySchedule extends StatefulWidget {
  const WeeklySchedule({
    super.key,
    required this.schedules,
    required this.medications,
  });

  final List<Schedule> schedules;
  final List<Medication> medications;

  @override
  State<WeeklySchedule> createState() => _WeeklyScheduleState();
}

class _WeeklyScheduleState extends State<WeeklySchedule> {
  final Set<String> _expandedDays = {};

  @override
  Widget build(BuildContext context) {
    final schedules = widget.schedules;
    final medications = widget.medications;
    final byId = {for (final med in medications) med.id: med};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Weekly schedule', style: Theme.of(context).textTheme.titleLarge),
        const Text('Tap a medication for its instructions.'),
        if (schedules.any((s) => s.notes?.startsWith('DEMO ONLY:') == true))
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Demo quantities only - not a prescription or dosing advice.',
            ),
          ),
        if (schedules.isEmpty) const Text('No scheduled medications yet.'),
        for (final day in const [
          'Sunday',
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
        ])
          if (schedules.any((s) => s.dayOfWeek == day))
            ExpansionTile(
              title: Text(day),
              onExpansionChanged: (expanded) => setState(() {
                if (expanded) {
                  _expandedDays.add(day);
                } else {
                  _expandedDays.remove(day);
                }
              }),
              children: [
                if (_expandedDays.contains(day))
                  for (final period in const ['AM', 'PM'])
                    ...(() {
                      final entries =
                          schedules.where((s) {
                            final hour = int.tryParse(
                              s.timeOfDay.split(':').first,
                            );
                            return s.dayOfWeek == day &&
                                hour != null &&
                                (period == 'AM' ? hour < 12 : hour >= 12);
                          }).toList()..sort(
                            (a, b) => a.timeOfDay.compareTo(b.timeOfDay),
                          );
                      return [
                        if (entries.isNotEmpty)
                          ListTile(
                            dense: true,
                            title: Text(
                              period,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        for (final entry in entries)
                          ListTile(
                            leading: const Icon(Icons.medication_outlined),
                            title: Text(
                              byId[entry.medicationId]?.name ?? 'Medication',
                            ),
                            subtitle: Text(
                              [
                                scheduleTimeLabel(entry.timeOfDay),
                                if (entry.notes?.isNotEmpty == true)
                                  entry.notes!,
                              ].join(' - '),
                            ),
                            trailing: const Icon(Icons.info_outline),
                            onTap: () => showMedicationInstructions(
                              context,
                              entry,
                              byId[entry.medicationId],
                            ),
                          ),
                      ];
                    })(),
              ],
            ),
      ],
    );
  }
}
