import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/medication.dart';
import '../models/schedule.dart';
import '../repositories/medication_repository.dart';
import '../services/api_service.dart';
import '../widgets/app_navigation.dart';

class MedicationDetailScreen extends ConsumerStatefulWidget {
  const MedicationDetailScreen({super.key, required this.medicationId});
  final int medicationId;
  @override
  ConsumerState<MedicationDetailScreen> createState() =>
      _MedicationDetailScreenState();
}

class _MedicationDetailScreenState
    extends ConsumerState<MedicationDetailScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _dosageController;
  late final TextEditingController _customInstructionsController;
  final Set<String> _selectedInstructions = {};
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _dosageController = TextEditingController();
    _customInstructionsController = TextEditingController();
    _loadMedication();
  }

  Future<void> _loadMedication() async {
    try {
      final userId = ref.read(userIdProvider);
      final medications = await ref
          .read(medicationRepositoryProvider)
          .getMedicationsForUser(userId);
      final medication = medications.firstWhere(
        (item) => item.id == widget.medicationId,
      );
      _nameController.text = medication.name;
      _dosageController.text = medication.dosage ?? '';
      final instructions = medication.instructions;
      if (instructions != null) {
        final parts = instructions.split('  ');
        for (final part in parts) {
          if (medicationInstructionOptions.contains(part)) {
            _selectedInstructions.add(part);
          }
        }
        _customInstructionsController.text = parts
            .where((part) => !medicationInstructionOptions.contains(part))
            .join('  ');
      }
    } on Exception catch (error) {
      _loadError = error is ApiException ? error.message : error.toString();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _customInstructionsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim().isEmpty
        ? 'Medication'
        : _nameController.text.trim();
    final dosage = _dosageController.text.trim().isEmpty
        ? null
        : _dosageController.text.trim();
    final instructions = buildMedicationInstructions(
      _selectedInstructions,
      _customInstructionsController.text,
    );

    try {
      await ref
          .read(medicationRepositoryProvider)
          .updateMedication(
            medicationId: widget.medicationId,
            name: name,
            dosage: dosage,
            instructions: instructions,
          );
      ref.invalidate(medicationsByUserProvider(ref.read(userIdProvider)));
    } on Exception catch (error) {
      if (!mounted) return;
      final message = error is ApiException ? error.message : error.toString();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Medication updated')));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final schedulesState = ref.watch(
      scheduleByUserProvider(ref.watch(userIdProvider)),
    );
    final schedules =
        (schedulesState.asData?.value ?? const <Schedule>[])
            .where((schedule) => schedule.medicationId == widget.medicationId)
            .toList()
          ..sort((a, b) => a.timeOfDay.compareTo(b.timeOfDay));

    if (_isLoading || schedulesState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null || schedulesState.hasError) {
      return Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('Medication details'),
        ),
        body: Center(child: Text(_loadError ?? 'Could not load schedule data')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Medication details'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Medication name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _dosageController,
            decoration: const InputDecoration(
              labelText: 'Dosage (e.g. 500 mg)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Text('Instructions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: medicationInstructionOptions.map((opt) {
              final sel = _selectedInstructions.contains(opt);
              return ChoiceChip(
                label: Text(opt),
                selected: sel,
                onSelected: (_) => setState(
                  () => sel
                      ? _selectedInstructions.remove(opt)
                      : _selectedInstructions.add(opt),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _customInstructionsController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Custom notes',
              hintText: 'e.g. Take 30 min before eating',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          if (schedules.isNotEmpty) ...[
            Text(
              'Scheduled doses',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...schedules.map(
              (s) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.schedule_rounded),
                  title: Text('${s.dayOfWeek}  \u2022  ${s.timeOfDay}'),
                  subtitle: s.notes != null ? Text(s.notes!) : null,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save changes'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () =>
                context.push('/schedule', extra: widget.medicationId),
            icon: const Icon(Icons.add_alarm_rounded),
            label: const Text('Add schedule slot'),
          ),
        ],
      ),
    );
  }
}
