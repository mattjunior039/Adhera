import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../repositories/medication_repository.dart';
import '../repositories/sample_day_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_navigation.dart';
import '../widgets/weekly_schedule.dart';

class ScheduleSetupScreen extends ConsumerStatefulWidget {
  const ScheduleSetupScreen({super.key, this.preselectedMedicationId});
  final int? preselectedMedicationId;
  @override
  ConsumerState<ScheduleSetupScreen> createState() =>
      _ScheduleSetupScreenState();
}

class _ScheduleSetupScreenState extends ConsumerState<ScheduleSetupScreen> {
  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _times = [
    '06:00',
    '07:00',
    '08:00',
    '09:00',
    '12:00',
    '13:00',
    '18:00',
    '20:00',
    '21:00',
    '22:00',
  ];

  final Set<String> _selectedDays = {};
  String? _selectedTime;
  int? _selectedMedicationId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedMedicationId = widget.preselectedMedicationId;
    if (_selectedMedicationId != null) {
      _selectedDays.add(_days[ref.read(displayedWeekdayProvider) - 1]);
    }
  }

  Future<void> _save() async {
    if (_selectedMedicationId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a medication')));
      return;
    }
    if (_selectedDays.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select at least one day')));
      return;
    }
    if (_selectedTime == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select an intake time')));
      return;
    }
    setState(() => _isSaving = true);

    final repo = ref.read(medicationRepositoryProvider);
    final userId = ref.read(userIdProvider);
    final medId = _selectedMedicationId!;
    final daysToSave = List<String>.from(_selectedDays);

    try {
      for (final day in daysToSave) {
        await repo.createSchedule(
          userId: userId,
          medicationId: medId,
          dayOfWeek: day,
          timeOfDay: _selectedTime!,
          notes: 'Scheduled from app',
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    } catch (error) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save schedule: $error')),
        );
      }
      return;
    }

    if (!mounted) return;
    ref.invalidate(scheduleByUserProvider(userId));
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Schedule saved for ${daysToSave.length} day(s)')),
    );
    context.push('/capture-photo');
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(userIdProvider);
    final medicationsState = ref.watch(medicationsByUserProvider(userId));
    if (medicationsState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (medicationsState.hasError) {
      return Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('Schedule setup'),
        ),
        body: Center(
          child: Text('Could not load medications: ${medicationsState.error}'),
        ),
      );
    }
    final medications = medicationsState.requireValue;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Schedule setup'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            ref
                .watch(scheduleByUserProvider(userId))
                .when(
                  data: (schedules) => WeeklySchedule(
                    schedules: schedules,
                    medications: medications,
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text('Could not load schedule: $error'),
                ),
            const Divider(height: 32),
            Text('Add schedule', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text('Medication', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _selectedMedicationId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Select a medication',
              ),
              items: medications
                  .map(
                    (m) => DropdownMenuItem(
                      value: m.id,
                      child: Text(
                        '${m.name}${m.dosage != null ? "  \u2014  ${m.dosage}" : ""}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selectedMedicationId = v),
            ),
            const SizedBox(height: 24),
            Text('Days', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Select all days you take this medication',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _days.map((day) {
                final sel = _selectedDays.contains(day);
                return FilterChip(
                  label: Text(day.substring(0, 3)),
                  selected: sel,
                  onSelected: _isSaving
                      ? null
                      : (_) => setState(
                          () => sel
                              ? _selectedDays.remove(day)
                              : _selectedDays.add(day),
                        ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text('Intake time', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _times
                  .map(
                    (t) => ChoiceChip(
                      label: Text(t),
                      selected: _selectedTime == t,
                      onSelected: _isSaving
                          ? null
                          : (_) => setState(() => _selectedTime = t),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_isSaving ? 'Saving...' : 'Save schedule'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.go('/dashboard'),
              child: const Text('Skip for now'),
            ),
          ],
        ),
      ),
    );
  }
}
