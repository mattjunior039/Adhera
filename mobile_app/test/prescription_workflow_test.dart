import 'dart:async';

import 'package:adhera/models/medication.dart';
import 'package:adhera/repositories/medication_repository.dart';
import 'package:adhera/screens/prescription_review_screen.dart';
import 'package:adhera/services/api_service.dart';
import 'package:adhera/state/adherence.dart';
import 'package:adhera/state/prescriptions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _MedicationRepository extends MedicationRepository {
  _MedicationRepository() : super(ApiService());

  int requests = 0;
  final pending = Completer<Medication>();

  @override
  Future<Medication> createMedication({
    required int userId,
    required String name,
    String? dosage,
    String? instructions,
  }) {
    requests++;
    return pending.future;
  }
}

void main() {
  Future<ProviderContainer> showReview(
    WidgetTester tester, {
    _MedicationRepository? repository,
    bool includePrescription = true,
  }) async {
    final container = ProviderContainer(
      overrides: [
        if (repository != null)
          medicationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    if (includePrescription) {
      container
          .read(pendingPrescriptionsProvider.notifier)
          .add(
            PendingPrescription(
              id: 1,
              medicationName: 'Ibuprofen',
              dosage: '200 mg',
              scannedAt: DateTime(2026),
              status: VerificationStatus.awaitingVerifier,
            ),
          );
    }
    final router = GoRouter(
      initialLocation: '/review',
      routes: [
        GoRoute(
          path: '/review',
          builder: (_, _) => const PrescriptionReviewScreen(prescriptionId: 1),
        ),
        GoRoute(
          path: '/prescription-queue',
          builder: (_, _) => const Scaffold(body: Text('Verification queue')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('missing prescription is reported instead of fabricated', (
    tester,
  ) async {
    await showReview(tester, includePrescription: false);
    expect(find.text('Prescription not found'), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);
  });

  testWidgets('approval cannot send duplicate requests while saving', (
    tester,
  ) async {
    final repository = _MedicationRepository();
    final container = await showReview(tester, repository: repository);
    await tester.ensureVisible(find.text('Approve'));
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm approval'));
    await tester.pump();
    await tester.tap(find.text('Confirm approval'));
    await tester.pump();
    expect(repository.requests, 1);
    repository.pending.completeError(ApiException('Save failed'));
    await tester.pumpAndSettle();
    expect(find.text('Save failed'), findsOneWidget);
    expect(
      container.read(pendingPrescriptionsProvider).single.status,
      VerificationStatus.awaitingVerifier,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'successful approval creates one medication and updates verification',
    (tester) async {
      final repository = _MedicationRepository();
      final container = await showReview(tester, repository: repository);
      await tester.ensureVisible(find.text('Approve'));
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm approval'));
      await tester.pump();
      expect(
        container.read(pendingPrescriptionsProvider).single.status,
        VerificationStatus.awaitingVerifier,
      );
      repository.pending.complete(
        const Medication(id: 1, userId: 1, name: 'Ibuprofen'),
      );
      await tester.pumpAndSettle();
      expect(repository.requests, 1);
      final prescription = container.read(pendingPrescriptionsProvider).single;
      expect(prescription.status, VerificationStatus.approved);
      expect(prescription.verifiedBy, 'Pharmacist / Caregiver');
      expect(find.text('Verification queue'), findsOneWidget);
    },
  );

  testWidgets(
    'rejection requires a reason and notifies without creating medication',
    (tester) async {
      final repository = _MedicationRepository();
      final container = await showReview(tester, repository: repository);
      final previousAlerts = container.read(alertsProvider).length;
      await tester.ensureVisible(find.text('Reject'));
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm rejection'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a reason for rejection'), findsOneWidget);
      expect(
        container.read(pendingPrescriptionsProvider).single.status,
        VerificationStatus.awaitingVerifier,
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'Unreadable directions',
      );
      await tester.tap(find.text('Confirm rejection'));
      await tester.pumpAndSettle();
      final prescription = container.read(pendingPrescriptionsProvider).single;
      expect(prescription.status, VerificationStatus.rejected);
      expect(prescription.verifierNote, 'Unreadable directions');
      expect(repository.requests, 0);
      expect(container.read(alertsProvider), hasLength(previousAlerts + 1));
      expect(
        container.read(alertsProvider).last.message,
        contains('Unreadable directions'),
      );
      expect(find.text('Verification queue'), findsOneWidget);
    },
  );
}
