import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../repositories/medication_repository.dart';
import '../services/api_service.dart';
import '../state/adherence.dart';
import '../state/prescriptions.dart';
import '../widgets/app_navigation.dart';
import '../widgets/prescription_decision_dialog.dart';
import '../widgets/time_labels.dart';

class PrescriptionReviewScreen extends ConsumerStatefulWidget {
  const PrescriptionReviewScreen({super.key, required this.prescriptionId});
  final int prescriptionId;
  @override
  ConsumerState<PrescriptionReviewScreen> createState() =>
      _PrescriptionReviewScreenState();
}

class _PrescriptionReviewScreenState
    extends ConsumerState<PrescriptionReviewScreen> {
  Future<void> _reviewPrescription(
    PendingPrescription prescription, {
    required bool approve,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PrescriptionDecisionDialog(
        prescription: prescription,
        approve: approve,
        onConfirm: (reviewer, note) async {
          final notifier = ref.read(pendingPrescriptionsProvider.notifier);
          if (approve) {
            final name = prescription.medicationName.trim();
            if (!{'acetaminophen', 'ibuprofen'}.contains(name.toLowerCase())) {
              throw ApiException(
                'This extraction test supports acetaminophen and ibuprofen only.',
              );
            }
            final userId = ref.read(userIdProvider);
            await ref
                .read(medicationRepositoryProvider)
                .createMedication(
                  userId: userId,
                  name: name,
                  dosage: prescription.dosage,
                  instructions: prescription.instructions,
                );
            if (!mounted) return;
            ref.invalidate(medicationsByUserProvider(userId));
            notifier.approve(
              prescription.id,
              verifiedBy: reviewer,
              note: note.isEmpty ? null : note,
            );
          } else {
            notifier.reject(
              prescription.id,
              verifiedBy: reviewer,
              reason: note,
            );
            ref
                .read(alertsProvider.notifier)
                .add(
                  MedicationAlert(
                    title:
                        'Prescription rejected: ${prescription.medicationName}',
                    message: 'Reason: $note (reviewed by $reviewer).',
                    severity: 'High',
                  ),
                );
          }
        },
      ),
    );
    if (!mounted || confirmed != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          approve
              ? '${prescription.medicationName} approved and added to the medication list'
              : '${prescription.medicationName} rejected. Patient has been notified.',
        ),
      ),
    );
    context.go('/prescription-queue');
  }

  @override
  Widget build(BuildContext context) {
    final prescriptions = ref.watch(pendingPrescriptionsProvider);
    final p = prescriptions
        .where((p) => p.id == widget.prescriptionId)
        .firstOrNull;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('Review prescription'),
        ),
        body: const Center(child: Text('Prescription not found')),
      );
    }

    final statusColor = switch (p.status) {
      VerificationStatus.awaitingVerifier => Colors.orange,
      VerificationStatus.approved => Colors.green,
      VerificationStatus.rejected => Colors.red,
      VerificationStatus.awaitingPatient => Colors.blue,
    };
    final statusLabel = switch (p.status) {
      VerificationStatus.awaitingVerifier => 'Awaiting verification',
      VerificationStatus.approved => 'Approved',
      VerificationStatus.rejected => 'Rejected',
      VerificationStatus.awaitingPatient => 'Awaiting patient confirmation',
    };

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Review prescription'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              label: Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              backgroundColor: statusColor.withValues(alpha: 0.12),
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Scanned image
          if (p.imageFilePath != null) ...[
            Text(
              'Scanned label image',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(p.imageFilePath!),
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  'No image available',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Prescription details
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.medication_rounded, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          p.medicationName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  if (p.dosage.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      p.dosage,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (p.instructions != null) ...[
                    const Divider(height: 20),
                    Text(
                      'Directions',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 4),
                    Text(p.instructions!),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Prescription source metadata
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Prescription info',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  if (p.prescribedBy != null)
                    _row(
                      Icons.medical_services_outlined,
                      'Prescriber',
                      p.prescribedBy!,
                    ),
                  if (p.pharmacy != null)
                    _row(
                      Icons.local_pharmacy_outlined,
                      'Pharmacy',
                      p.pharmacy!,
                    ),
                  if (p.refillsRemaining != null)
                    _row(
                      Icons.refresh_rounded,
                      'Refills remaining',
                      p.refillsRemaining!,
                    ),
                  _row(
                    Icons.schedule_rounded,
                    'Scanned',
                    relativeTime(p.scannedAt),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Patient note
          if (p.patientNote != null) ...[
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.person_rounded,
                          size: 16,
                          color: Colors.blue.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Patient note',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(p.patientNote!, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Verifier result
          if (p.verifiedBy != null) ...[
            Card(
              color: p.status == VerificationStatus.approved
                  ? Colors.green.shade50
                  : Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          p.status == VerificationStatus.approved
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          size: 16,
                          color: p.status == VerificationStatus.approved
                              ? Colors.green
                              : Colors.red,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          p.status == VerificationStatus.approved
                              ? 'Approved by ${p.verifiedBy}'
                              : 'Rejected by ${p.verifiedBy}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: p.status == VerificationStatus.approved
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                    if (p.verifierNote != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        p.verifierNote!,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Action buttons
          if (p.status == VerificationStatus.awaitingVerifier) ...[
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    onPressed: () => _reviewPrescription(p, approve: true),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => _reviewPrescription(p, approve: false),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, size: 15, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}
