import 'package:flutter_riverpod/flutter_riverpod.dart';

enum VerificationStatus {
  awaitingPatient,
  awaitingVerifier,
  approved,
  rejected,
}

class PendingPrescription {
  PendingPrescription({
    required this.id,
    required this.medicationName,
    required this.dosage,
    required this.scannedAt,
    this.instructions,
    this.prescribedBy,
    this.pharmacy,
    this.refillsRemaining,
    this.imageFilePath,
    this.patientNote,
    this.status = VerificationStatus.awaitingPatient,
    this.verifiedBy,
    this.verifiedAt,
    this.verifierNote,
  });

  final int id;
  final String medicationName;
  final String dosage;
  final DateTime scannedAt;
  final String? instructions;
  final String? prescribedBy;
  final String? pharmacy;
  final String? refillsRemaining;
  final String? imageFilePath;
  final String? patientNote;
  final VerificationStatus status;
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final String? verifierNote;

  PendingPrescription copyWith({
    String? medicationName,
    String? dosage,
    String? instructions,
    String? prescribedBy,
    String? pharmacy,
    String? refillsRemaining,
    String? imageFilePath,
    String? patientNote,
    VerificationStatus? status,
    String? verifiedBy,
    DateTime? verifiedAt,
    String? verifierNote,
  }) => PendingPrescription(
    id: id,
    scannedAt: scannedAt,
    medicationName: medicationName ?? this.medicationName,
    dosage: dosage ?? this.dosage,
    instructions: instructions ?? this.instructions,
    prescribedBy: prescribedBy ?? this.prescribedBy,
    pharmacy: pharmacy ?? this.pharmacy,
    refillsRemaining: refillsRemaining ?? this.refillsRemaining,
    imageFilePath: imageFilePath ?? this.imageFilePath,
    patientNote: patientNote ?? this.patientNote,
    status: status ?? this.status,
    verifiedBy: verifiedBy ?? this.verifiedBy,
    verifiedAt: verifiedAt ?? this.verifiedAt,
    verifierNote: verifierNote ?? this.verifierNote,
  );
}

class PendingPrescriptionsNotifier extends Notifier<List<PendingPrescription>> {
  @override
  List<PendingPrescription> build() => const [];

  void add(PendingPrescription p) => state = [...state, p];

  void _update(
    int id,
    PendingPrescription Function(PendingPrescription) update,
  ) {
    state = [for (final p in state) p.id == id ? update(p) : p];
  }

  void patientConfirm(int id, {String? note}) => _update(
    id,
    (p) => p.copyWith(
      status: VerificationStatus.awaitingVerifier,
      patientNote: note,
    ),
  );

  void approve(int id, {required String verifiedBy, String? note}) => _update(
    id,
    (p) => p.copyWith(
      status: VerificationStatus.approved,
      verifiedBy: verifiedBy,
      verifiedAt: DateTime.now(),
      verifierNote: note,
    ),
  );

  void reject(int id, {required String verifiedBy, required String reason}) =>
      _update(
        id,
        (p) => p.copyWith(
          status: VerificationStatus.rejected,
          verifiedBy: verifiedBy,
          verifiedAt: DateTime.now(),
          verifierNote: reason,
        ),
      );

  void dismiss(int id) => state = state.where((p) => p.id != id).toList();
}

final pendingPrescriptionsProvider =
    NotifierProvider<PendingPrescriptionsNotifier, List<PendingPrescription>>(
      () => PendingPrescriptionsNotifier(),
    );
