import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../state/prescriptions.dart';

class PrescriptionDecisionDialog extends StatefulWidget {
  const PrescriptionDecisionDialog({
    super.key,
    required this.prescription,
    required this.approve,
    required this.onConfirm,
  });

  final PendingPrescription prescription;
  final bool approve;
  final Future<void> Function(String reviewer, String note) onConfirm;

  @override
  State<PrescriptionDecisionDialog> createState() =>
      _PrescriptionDecisionDialogState();
}

class _PrescriptionDecisionDialogState
    extends State<PrescriptionDecisionDialog> {
  final _form = GlobalKey<FormState>();
  final _reviewer = TextEditingController(text: 'Pharmacist / Caregiver');
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reviewer.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onConfirm(_reviewer.text.trim(), _note.text.trim());
      if (mounted) {
        setState(() => _saving = false);
        Navigator.of(context).pop(true);
      }
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is ApiException ? error.message : error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final approve = widget.approve;
    final prescription = widget.prescription;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(approve ? 'Approve prescription' : 'Reject prescription'),
        content: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  approve
                      ? 'You are approving "${prescription.medicationName} ${prescription.dosage}" for this patient. This will add it to their active medication list.'
                      : 'You are rejecting "${prescription.medicationName} ${prescription.dosage}". The patient will be notified with your reason.',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _reviewer,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Your name / role',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value!.trim().isEmpty ? 'Enter your name or role' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  enabled: !_saving,
                  maxLines: approve ? 2 : 3,
                  decoration: InputDecoration(
                    labelText: approve
                        ? 'Note for patient (optional)'
                        : 'Reason for rejection (required)',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => !approve && value!.trim().isEmpty
                      ? 'Enter a reason for rejection'
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: approve
                ? null
                : FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: _saving ? null : _confirm,
            child: Text(approve ? 'Confirm approval' : 'Confirm rejection'),
          ),
        ],
      ),
    );
  }
}
