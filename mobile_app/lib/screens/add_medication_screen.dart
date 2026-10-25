import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/medication.dart';
import '../repositories/medication_repository.dart';
import '../services/api_service.dart';
import '../widgets/app_navigation.dart';

class AddMedicationScreen extends ConsumerStatefulWidget {
  const AddMedicationScreen({super.key});
  @override
  ConsumerState<AddMedicationScreen> createState() =>
      _AddMedicationScreenState();
}

class _AddMedicationScreenState extends ConsumerState<AddMedicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _customController = TextEditingController();
  final Set<String> _selectedInstructions = {};
  bool _isSubmitting = false;

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    final name = _nameController.text.trim();
    final dosage = _dosageController.text.trim().isEmpty
        ? null
        : _dosageController.text.trim();
    final instr = buildMedicationInstructions(
      _selectedInstructions,
      _customController.text,
    );
    try {
      final created = await ref
          .read(medicationRepositoryProvider)
          .createMedication(
            userId: ref.read(userIdProvider),
            name: name,
            dosage: dosage,
            instructions: instr,
          );
      ref.invalidate(medicationsByUserProvider(ref.read(userIdProvider)));
      if (mounted) context.push('/schedule', extra: created.id);
    } on ApiException catch (error) {
      if (mounted) _showError(error.message);
    } catch (error) {
      if (mounted) _showError('Could not save medication: $error');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Add medication'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Prominent scan shortcut
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                margin: const EdgeInsets.only(bottom: 20),
                child: ListTile(
                  leading: Icon(
                    Icons.document_scanner_rounded,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  title: const Text('Scan prescription label'),
                  subtitle: const Text('Auto-fill from your bottle'),
                  trailing: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                  ),
                  onTap: () => context.push('/scan-prescription'),
                ),
              ),
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                margin: const EdgeInsets.only(bottom: 20),
                child: ListTile(
                  leading: Icon(
                    Icons.camera_rounded,
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
                  title: const Text('Analyze Pill'),
                  subtitle: const Text('Extract pill signatures using AI'),
                  trailing: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                  ),
                  onTap: () => context.push('/analyze-pill'),
                ),
              ),
              Text(
                'Or enter details manually',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Medication name is required'
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Medication name',
                  hintText: 'e.g. Acetaminophen',
                  prefixIcon: Icon(Icons.medication_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _dosageController,
                decoration: const InputDecoration(
                  labelText: 'Dosage',
                  hintText: 'e.g. 500 mg, 1 tablet',
                  prefixIcon: Icon(Icons.scale_rounded),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Instructions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Select all that apply',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 10),
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
              const SizedBox(height: 16),
              TextField(
                controller: _customController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Custom notes (optional)',
                  hintText: 'e.g. Take 30 min before eating',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _isSubmitting ? 'Saving...' : 'Save & set schedule',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
