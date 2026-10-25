import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/prescriptions.dart';
import '../widgets/app_navigation.dart';
import '../widgets/time_labels.dart';

class PrescriptionQueueScreen extends ConsumerWidget {
  const PrescriptionQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prescriptions = ref.watch(pendingPrescriptionsProvider);

    final awaiting = prescriptions
        .where((p) => p.status == VerificationStatus.awaitingVerifier)
        .toList();
    final approved = prescriptions
        .where((p) => p.status == VerificationStatus.approved)
        .toList();
    final rejected = prescriptions
        .where((p) => p.status == VerificationStatus.rejected)
        .toList();

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Verification queue'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/scan-prescription'),
        icon: const Icon(Icons.document_scanner_rounded),
        label: const Text('Scan new prescription'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (prescriptions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle_outlined,
                      size: 56,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No prescriptions pending',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
          if (awaiting.isNotEmpty) ...[
            _sectionHeader(
              context,
              'Awaiting verification (${awaiting.length})',
              Colors.orange,
            ),
            ...awaiting.map((p) => _prescriptionCard(context, ref, p)),
            const SizedBox(height: 12),
          ],
          if (approved.isNotEmpty) ...[
            _sectionHeader(
              context,
              'Approved (${approved.length})',
              Colors.green,
            ),
            ...approved.map((p) => _prescriptionCard(context, ref, p)),
            const SizedBox(height: 12),
          ],
          if (rejected.isNotEmpty) ...[
            _sectionHeader(
              context,
              'Rejected (${rejected.length})',
              Colors.red,
            ),
            ...rejected.map((p) => _prescriptionCard(context, ref, p)),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, Color color) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );

  Widget _prescriptionCard(
    BuildContext context,
    WidgetRef ref,
    PendingPrescription p,
  ) {
    final statusColor = switch (p.status) {
      VerificationStatus.awaitingVerifier => Colors.orange,
      VerificationStatus.approved => Colors.green,
      VerificationStatus.rejected => Colors.red,
      VerificationStatus.awaitingPatient => Colors.blue,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/prescription-review/${p.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: p.imageFilePath != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(p.imageFilePath!),
                          fit: BoxFit.cover,
                        ),
                      )
                    : Icon(Icons.medication_rounded, color: statusColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.medicationName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      p.dosage,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    if (p.prescribedBy != null)
                      Text(
                        p.prescribedBy!,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      p.status == VerificationStatus.awaitingVerifier
                          ? 'Review'
                          : p.status.name,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    relativeTime(p.scannedAt, compact: true),
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
