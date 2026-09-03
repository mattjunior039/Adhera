import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import 'api_service.dart';
import 'app_config.dart';
import 'image_upload_repository.dart';
import 'image_upload_screen.dart';
import 'medication_repository.dart';
import 'models/medication.dart';
import 'models/schedule.dart';
import 'models/user.dart';

void main() {
  runApp(const ProviderScope(child: PillboxApp()));
}

class PillboxApp extends ConsumerWidget {
  const PillboxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Pillbox',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
      ),
      routerConfig: router,
    );
  }
}

// ── Data models ─────────────────────────────────────────────────────────────────

class MedicationAlert {
  const MedicationAlert({required this.title, required this.message, required this.severity});
  final String title;
  final String message;
  final String severity;
}

class CaregiverProfile {
  const CaregiverProfile({required this.name, required this.relation, required this.status, this.phone});
  final String name;
  final String relation;
  final String status;
  final String? phone;
}

// ── Synthetic / demo data ────────────────────────────────────────────────────────

final syntheticVerificationProvider = Provider<List<PhotoEventRecord>>((ref) => [
  PhotoEventRecord(
    id: 1, userId: 1, eventType: 'Morning dose — Metformin',
    photoPath: 'demo://morning', eventTime: DateTime.now().subtract(const Duration(hours: 3)),
    notes: 'Pill count matched baseline', medicationId: 1,
  ),
  PhotoEventRecord(
    id: 2, userId: 1, eventType: 'Evening dose — Atorvastatin',
    photoPath: 'demo://evening', eventTime: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
    notes: 'Confirmed with baseline', medicationId: 2,
  ),
  PhotoEventRecord(
    id: 3, userId: 1, eventType: 'Morning dose — Levothyroxine',
    photoPath: 'demo://morning2', eventTime: DateTime.now().subtract(const Duration(days: 2, hours: 5)),
    notes: 'Verified — no missing compartments', medicationId: 4,
  ),
  PhotoEventRecord(
    id: 4, userId: 1, eventType: 'Lunch dose — Vitamin D',
    photoPath: 'demo://lunch', eventTime: DateTime.now().subtract(const Duration(days: 3, hours: 1)),
    notes: 'Pill count matched', medicationId: 3,
  ),
]);

class AlertsNotifier extends Notifier<List<MedicationAlert>> {
  @override
  List<MedicationAlert> build() => const [
    MedicationAlert(
      title: 'Missed dose',
      message: 'Metformin 08:00 was not logged today. Please verify intake.',
      severity: 'High',
    ),
    MedicationAlert(
      title: 'Refill reminder',
      message: 'Levothyroxine supply runs out in 4 days. Contact your pharmacy.',
      severity: 'Medium',
    ),
    MedicationAlert(
      title: 'Drug interaction note',
      message: 'Metformin + Atorvastatin: monitor blood glucose. Consult your pharmacist if concerned.',
      severity: 'Low',
    ),
  ];

  void dismiss(int index) {
    final updated = [...state];
    if (index >= 0 && index < updated.length) {
      updated.removeAt(index);
      state = updated;
    }
  }

  void add(MedicationAlert alert) {
    state = [...state, alert];
  }
}

final alertsProvider = NotifierProvider<AlertsNotifier, List<MedicationAlert>>(
  () => AlertsNotifier(),
);

class CaregiverProfilesNotifier extends Notifier<List<CaregiverProfile>> {
  @override
  List<CaregiverProfile> build() => const [
    CaregiverProfile(name: 'Olivia Chen', relation: 'Daughter', status: 'Connected', phone: '+1 (415) 555-0141'),
    CaregiverProfile(name: 'Marcus Bell', relation: 'Care coordinator', status: 'Pending', phone: '+1 (510) 555-2047'),
  ];

  void inviteCaregiver({required String name, required String relation, required String phone}) {
    state = [...state, CaregiverProfile(name: name, relation: relation, status: 'Invited', phone: phone)];
  }
}

final caregiversProvider = NotifierProvider<CaregiverProfilesNotifier, List<CaregiverProfile>>(
  () => CaregiverProfilesNotifier(),
);

class SyntheticMedicationNotifier extends Notifier<List<Medication>> {
  @override
  List<Medication> build() => const [
    Medication(id: 1, userId: 1, name: 'Metformin',      dosage: '500 mg',   instructions: 'Take with food \u2022 After breakfast'),
    Medication(id: 2, userId: 1, name: 'Atorvastatin',   dosage: '20 mg',    instructions: 'At bedtime \u2022 With water'),
    Medication(id: 3, userId: 1, name: 'Vitamin D',      dosage: '1000 IU',  instructions: 'After lunch'),
    Medication(id: 4, userId: 1, name: 'Levothyroxine',  dosage: '50 mcg',   instructions: 'Take on an empty stomach \u2022 Before breakfast \u2022 With water'),
  ];

  void addMedication(Medication med) {
    if (state.any((m) => m.id == med.id)) {
      state = [for (final m in state) m.id == med.id ? med : m];
    } else {
      state = [...state, med];
    }
  }

  void updateMedication(Medication med) {
    state = [for (final m in state) m.id == med.id ? med : m];
  }

  void deleteMedication(int id) {
    state = state.where((m) => m.id != id).toList();
  }
}

final syntheticMedicationProvider = NotifierProvider<SyntheticMedicationNotifier, List<Medication>>(
  () => SyntheticMedicationNotifier(),
);

class SyntheticScheduleNotifier extends Notifier<List<Schedule>> {
  @override
  List<Schedule> build() => [
    // Metformin (id 1) — Mon, Wed, Fri at 08:00
    Schedule(id:  1, userId: 1, medicationId: 1, dayOfWeek: 'Monday',    timeOfDay: '08:00', notes: 'After breakfast'),
    Schedule(id:  2, userId: 1, medicationId: 1, dayOfWeek: 'Wednesday', timeOfDay: '08:00', notes: 'After breakfast'),
    Schedule(id:  3, userId: 1, medicationId: 1, dayOfWeek: 'Friday',    timeOfDay: '08:00', notes: 'After breakfast'),
    // Atorvastatin (id 2) — every day at 21:00
    Schedule(id:  4, userId: 1, medicationId: 2, dayOfWeek: 'Monday',    timeOfDay: '21:00', notes: 'At bedtime'),
    Schedule(id:  5, userId: 1, medicationId: 2, dayOfWeek: 'Tuesday',   timeOfDay: '21:00', notes: 'At bedtime'),
    Schedule(id:  6, userId: 1, medicationId: 2, dayOfWeek: 'Wednesday', timeOfDay: '21:00', notes: 'At bedtime'),
    Schedule(id:  7, userId: 1, medicationId: 2, dayOfWeek: 'Thursday',  timeOfDay: '21:00', notes: 'At bedtime'),
    Schedule(id:  8, userId: 1, medicationId: 2, dayOfWeek: 'Friday',    timeOfDay: '21:00', notes: 'At bedtime'),
    Schedule(id:  9, userId: 1, medicationId: 2, dayOfWeek: 'Saturday',  timeOfDay: '21:00', notes: 'At bedtime'),
    Schedule(id: 10, userId: 1, medicationId: 2, dayOfWeek: 'Sunday',    timeOfDay: '21:00', notes: 'At bedtime'),
    // Vitamin D (id 3) — weekdays at 12:30
    Schedule(id: 11, userId: 1, medicationId: 3, dayOfWeek: 'Monday',    timeOfDay: '12:30', notes: 'After lunch'),
    Schedule(id: 12, userId: 1, medicationId: 3, dayOfWeek: 'Tuesday',   timeOfDay: '12:30', notes: 'After lunch'),
    Schedule(id: 13, userId: 1, medicationId: 3, dayOfWeek: 'Wednesday', timeOfDay: '12:30', notes: 'After lunch'),
    Schedule(id: 14, userId: 1, medicationId: 3, dayOfWeek: 'Thursday',  timeOfDay: '12:30', notes: 'After lunch'),
    Schedule(id: 15, userId: 1, medicationId: 3, dayOfWeek: 'Friday',    timeOfDay: '12:30', notes: 'After lunch'),
    // Levothyroxine (id 4) — every day at 07:00
    Schedule(id: 16, userId: 1, medicationId: 4, dayOfWeek: 'Monday',    timeOfDay: '07:00', notes: 'Before breakfast, empty stomach'),
    Schedule(id: 17, userId: 1, medicationId: 4, dayOfWeek: 'Tuesday',   timeOfDay: '07:00', notes: 'Before breakfast, empty stomach'),
    Schedule(id: 18, userId: 1, medicationId: 4, dayOfWeek: 'Wednesday', timeOfDay: '07:00', notes: 'Before breakfast, empty stomach'),
    Schedule(id: 19, userId: 1, medicationId: 4, dayOfWeek: 'Thursday',  timeOfDay: '07:00', notes: 'Before breakfast, empty stomach'),
    Schedule(id: 20, userId: 1, medicationId: 4, dayOfWeek: 'Friday',    timeOfDay: '07:00', notes: 'Before breakfast, empty stomach'),
    Schedule(id: 21, userId: 1, medicationId: 4, dayOfWeek: 'Saturday',  timeOfDay: '07:00', notes: 'Before breakfast, empty stomach'),
    Schedule(id: 22, userId: 1, medicationId: 4, dayOfWeek: 'Sunday',    timeOfDay: '07:00', notes: 'Before breakfast, empty stomach'),
  ];

  void addSchedule(Schedule s) => state = [...state, s];

  void deleteSchedule(int id) => state = state.where((s) => s.id != id).toList();
}

final syntheticScheduleProvider = NotifierProvider<SyntheticScheduleNotifier, List<Schedule>>(
  () => SyntheticScheduleNotifier(),
);

// Tracks which schedule IDs have been marked taken today (resets next session)
class DoseLogNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => {};

  void markTaken(int scheduleId) => state = {...state, scheduleId};
  void unmark(int scheduleId) => state = state.where((id) => id != scheduleId).toSet();
}

final doseLogProvider = NotifierProvider<DoseLogNotifier, Set<int>>(() => DoseLogNotifier());

// Backend-verified adherence for today: scheduleId → 'taken'|'missed'|'partial'|'unknown'
final todayAdherenceProvider = FutureProvider<Map<int, String>>((ref) async {
  final userId = ref.watch(userIdProvider);
  try {
    return await ref.read(medicationRepositoryProvider).getTodayAdherence(userId);
  } catch (_) {
    return {};
  }
});

class AlertPhoneNotifier extends Notifier<String> {
  @override
  String build() => '+1 (555) 123-4567';
  void update(String value) => state = value.trim();
}

final alertPhoneProvider = NotifierProvider<AlertPhoneNotifier, String>(() => AlertPhoneNotifier());

// ── Prescription verification workflow ───────────────────────────────────────────

enum VerificationStatus { awaitingPatient, awaitingVerifier, approved, rejected }

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
    String? medicationName, String? dosage, String? instructions,
    String? prescribedBy, String? pharmacy, String? refillsRemaining,
    String? imageFilePath, String? patientNote, VerificationStatus? status,
    String? verifiedBy, DateTime? verifiedAt, String? verifierNote,
  }) =>
      PendingPrescription(
        id: id, scannedAt: scannedAt,
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
  List<PendingPrescription> build() => [
    PendingPrescription(
      id: 1, medicationName: 'Amlodipine', dosage: '5 mg',
      instructions: 'Take 1 tablet once daily for high blood pressure',
      scannedAt: DateTime.now().subtract(const Duration(hours: 2)),
      prescribedBy: 'Dr. Lisa Park, MD', pharmacy: 'Health First Pharmacy',
      refillsRemaining: '11',
      status: VerificationStatus.awaitingVerifier,
      patientNote: 'Just picked up this prescription. Please confirm the dosage.',
    ),
    PendingPrescription(
      id: 2, medicationName: 'Sertraline', dosage: '50 mg',
      instructions: 'Take 1 tablet every morning',
      scannedAt: DateTime.now().subtract(const Duration(days: 1)),
      prescribedBy: 'Dr. Michael Chen, MD', pharmacy: 'Walgreens Pharmacy #887',
      refillsRemaining: '2',
      status: VerificationStatus.awaitingVerifier,
      patientNote: 'New prescription — first time taking this medication.',
    ),
  ];

  void add(PendingPrescription p) => state = [...state, p];

  void patientConfirm(int id, {String? note}) {
    state = [
      for (final p in state)
        p.id == id
            ? p.copyWith(status: VerificationStatus.awaitingVerifier, patientNote: note)
            : p,
    ];
  }

  void approve(int id, {required String verifiedBy, String? note}) {
    state = [
      for (final p in state)
        p.id == id
            ? p.copyWith(
                status: VerificationStatus.approved,
                verifiedBy: verifiedBy,
                verifiedAt: DateTime.now(),
                verifierNote: note,
              )
            : p,
    ];
  }

  void reject(int id, {required String verifiedBy, required String reason}) {
    state = [
      for (final p in state)
        p.id == id
            ? p.copyWith(
                status: VerificationStatus.rejected,
                verifiedBy: verifiedBy,
                verifiedAt: DateTime.now(),
                verifierNote: reason,
              )
            : p,
    ];
  }

  void dismiss(int id) => state = state.where((p) => p.id != id).toList();
}

final pendingPrescriptionsProvider =
    NotifierProvider<PendingPrescriptionsNotifier, List<PendingPrescription>>(
  () => PendingPrescriptionsNotifier(),
);

// ── Router ───────────────────────────────────────────────────────────────────────

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(path: '/login',          builder: (context, state) => const LoginSignupScreen()),
      GoRoute(path: '/dashboard',      builder: (context, state) => const HomeDashboardScreen()),
      GoRoute(path: '/add-medication', builder: (context, state) => const AddMedicationScreen()),
      GoRoute(
        path: '/schedule',
        builder: (_, state) => ScheduleSetupScreen(
          preselectedMedicationId: state.extra is int ? state.extra as int : null,
        ),
      ),
      GoRoute(path: '/capture-photo',  builder: (context, state) => const ImageUploadScreen()),
      GoRoute(
        path: '/event-result',
        builder: (_, state) {
          final results = state.extra is List<InferenceResult>
              ? state.extra as List<InferenceResult>
              : const <InferenceResult>[];
          return EventResultScreen(results: results);
        },
      ),
      GoRoute(path: '/history',    builder: (context, state) => const VerificationHistoryScreen()),
      GoRoute(path: '/alerts',     builder: (context, state) => const AlertsListScreen()),
      GoRoute(path: '/caregiver',  builder: (context, state) => const CaregiverScreen()),
      GoRoute(path: '/settings',   builder: (context, state) => const SettingsScreen()),
      GoRoute(path: '/scan-prescription', builder: (context, state) => const PrescriptionScanScreen()),
      GoRoute(path: '/prescription-queue', builder: (context, state) => const PrescriptionQueueScreen()),
      GoRoute(
        path: '/prescription-review/:id',
        builder: (context, state) => PrescriptionReviewScreen(
          prescriptionId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/medication/:medicationId',
        builder: (_, state) => MedicationDetailScreen(
          medicationId: int.tryParse(state.pathParameters['medicationId'] ?? '') ?? 0,
        ),
      ),
    ],
  );
});

// ── Login / sign-up ───────────────────────────────────────────────────────────────

class LoginSignupScreen extends ConsumerStatefulWidget {
  const LoginSignupScreen({super.key});
  @override
  ConsumerState<LoginSignupScreen> createState() => _LoginSignupScreenState();
}

class _LoginSignupScreenState extends ConsumerState<LoginSignupScreen> {
  final _emailController    = TextEditingController(text: 'user@example.com');
  final _nameController     = TextEditingController(text: 'Sample User');
  final _phoneController    = TextEditingController(text: '+1 (555) 123-4567');
  final _passwordController = TextEditingController(text: 'StrongPass123');
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isCreatingAccount = false;

  bool _shouldUseDemoFallback(ApiException error) {
    final msg = error.message.toLowerCase();
    final networkFail = error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.badCertificate ||
        msg.contains('failed host') || msg.contains('connection') ||
        msg.contains('socket') || msg.contains('network') ||
        msg.contains('request failed') || msg.contains('http status error');
    return error.statusCode == null || error.type == null ||
        (error.statusCode != null && error.statusCode! >= 500) || networkFail ||
        (error.statusCode == 400 &&
            !msg.contains('invalid email or password') &&
            !msg.contains('already exists'));
  }

  void _setFallbackUser(String email) {
    final user = User(
      id: AppConfig.defaultUserId,
      email: email,
      fullName: _nameController.text.trim().isEmpty ? 'Sample User' : _nameController.text.trim(),
      phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
    );
    ref.read(currentUserProvider.notifier).setUser(user);
    ref.read(userIdProvider.notifier).setUserId(user.id);
    ref.read(userEmailProvider.notifier).setUserEmail(user.email);
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) { _showError('Enter both email and password'); return; }
    setState(() => _isLoading = true);
    try {
      final user = await ref.read(medicationRepositoryProvider).loginUser(email: email, password: password);
      ref.read(currentUserProvider.notifier).setUser(user);
      ref.read(userIdProvider.notifier).setUserId(user.id);
      ref.read(userEmailProvider.notifier).setUserEmail(user.email);
      if (!mounted) return;
      context.go('/dashboard');
    } on ApiException catch (e) {
      if (_shouldUseDemoFallback(e)) {
        _setFallbackUser(email);
        if (mounted) context.go('/dashboard');
      } else if (mounted) {
        _showError(e.message);
      }
    } catch (_) {
      _setFallbackUser(email);
      if (mounted) context.go('/dashboard');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final user = await ref.read(medicationRepositoryProvider).createUser(
        email: _emailController.text.trim(),
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        password: _passwordController.text.trim(),
      );
      ref.read(currentUserProvider.notifier).setUser(user);
      ref.read(userIdProvider.notifier).setUserId(user.id);
      ref.read(userEmailProvider.notifier).setUserEmail(user.email);
      if (!mounted) return;
      context.go('/dashboard');
    } on ApiException catch (e) {
      if (_shouldUseDemoFallback(e)) {
        _setFallbackUser(_emailController.text.trim());
        if (mounted) context.go('/dashboard');
      } else if (mounted) {
        _showError(e.message);
      }
    } catch (_) {
      _setFallbackUser(_emailController.text.trim());
      if (mounted) context.go('/dashboard');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.medication_rounded, size: 80, color: Color(0xFF2E7D32)),
                  const SizedBox(height: 20),
                  Text(
                    _isCreatingAccount ? 'Create your account' : 'Welcome back',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isCreatingAccount
                        ? 'Set up your medication routine and care plan.'
                        : 'Secure medication tracking for your care plan',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<bool>(
                    selected: {_isCreatingAccount},
                    onSelectionChanged: (s) => setState(() => _isCreatingAccount = s.first),
                    segments: const [
                      ButtonSegment(value: false, label: Text('Sign in')),
                      ButtonSegment(value: true,  label: Text('Create account')),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_isCreatingAccount) ...[
                    TextFormField(
                      controller: _nameController,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                      decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Email is required' : null,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder()),
                  ),
                  if (_isCreatingAccount) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone number', prefixIcon: Icon(Icons.phone_outlined), border: OutlineInputBorder()),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    validator: (v) => (v == null || v.trim().length < 8) ? 'Password must be at least 8 characters' : null,
                    decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : (_isCreatingAccount ? _createAccount : _signIn),
                    icon: Icon(_isCreatingAccount ? Icons.person_add_alt_1_rounded : Icons.login_rounded),
                    label: Text(_isLoading
                        ? (_isCreatingAccount ? 'Creating account...' : 'Signing in...')
                        : (_isCreatingAccount ? 'Create account' : 'Sign in')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Dashboard ─────────────────────────────────────────────────────────────────────

class HomeDashboardScreen extends ConsumerWidget {
  const HomeDashboardScreen({super.key});

  void _showInviteCaregiverDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final relCtrl  = TextEditingController(text: 'Family member');
    final phoneCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite care team member'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl,  decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(controller: relCtrl,   decoration: const InputDecoration(labelText: 'Relationship')),
          const SizedBox(height: 12),
          TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final name  = nameCtrl.text.trim();
              final rel   = relCtrl.text.trim();
              final phone = phoneCtrl.text.trim();
              if (name.isEmpty || rel.isEmpty || phone.isEmpty) return;
              ref.read(caregiversProvider.notifier).inviteCaregiver(name: name, relation: rel, phone: phone);
              Navigator.of(ctx).pop();
            },
            child: const Text('Send invite'),
          ),
        ],
      ),
    ).whenComplete(() { nameCtrl.dispose(); relCtrl.dispose(); phoneCtrl.dispose(); });
  }

  Widget _buildTodaySchedule(
    BuildContext context,
    WidgetRef ref,
    List<Schedule> schedules,
    Map<int, String> medicationNames,
    String todayName,
    Set<int> takenIds,
    Map<int, String> verifiedStatuses,
  ) {
    final todaySchedules = schedules
        .where((s) => s.dayOfWeek.toLowerCase() == todayName.toLowerCase())
        .toList()
      ..sort((a, b) => a.timeOfDay.compareTo(b.timeOfDay));

    if (todaySchedules.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const Icon(Icons.event_available_rounded, size: 40, color: Colors.green),
            const SizedBox(height: 8),
            const Text('No medications scheduled for today.', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => context.push('/add-medication'),
              icon: const Icon(Icons.add),
              label: const Text('Add a medication'),
            ),
          ]),
        ),
      );
    }

    final doneCount = todaySchedules.where((s) => takenIds.contains(s.id)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: LinearProgressIndicator(
              value: doneCount / todaySchedules.length,
              borderRadius: BorderRadius.circular(4),
              minHeight: 8,
            ),
          ),
          const SizedBox(width: 10),
          Text('$doneCount / ${todaySchedules.length}', style: Theme.of(context).textTheme.labelLarge),
        ]),
        const SizedBox(height: 8),
        ...todaySchedules.map((s) {
          final taken    = takenIds.contains(s.id);
          final verified = verifiedStatuses[s.id];
          final medName  = medicationNames[s.medicationId] ?? 'Medication';
          final note     = (s.notes != null && s.notes!.trim().isNotEmpty) ? '  \u2022  ${s.notes}' : '';
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            color: taken ? Colors.green.shade50 : null,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: taken ? Colors.green.shade400 : Theme.of(context).colorScheme.primary,
                child: Icon(taken ? Icons.check_rounded : Icons.medication_rounded, color: Colors.white),
              ),
              title: Text(
                medName,
                style: taken ? TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey.shade600) : null,
              ),
              subtitle: Row(children: [
                Expanded(child: Text('${s.timeOfDay}$note')),
                if (verified == 'taken') ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(10)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.verified_rounded, size: 11, color: Colors.green.shade700),
                      const SizedBox(width: 3),
                      Text('Verified', style: TextStyle(fontSize: 10, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ],
                if (verified == 'missed') ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.warning_rounded, size: 11, color: Colors.red.shade600),
                      const SizedBox(width: 3),
                      Text('Missed', style: TextStyle(fontSize: 10, color: Colors.red.shade600, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ],
              ]),
              trailing: taken
                  ? IconButton(
                      icon: const Icon(Icons.undo_rounded, color: Colors.grey),
                      tooltip: 'Undo',
                      onPressed: () {
                        ref.read(doseLogProvider.notifier).unmark(s.id);
                        // Fire-and-forget to backend
                        ref.read(medicationRepositoryProvider).logDose(
                          userId: ref.read(userIdProvider),
                          scheduleId: s.id,
                          status: 'unknown',
                        ).ignore();
                      },
                    )
                  : IconButton(
                      icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.green),
                      tooltip: 'Mark taken',
                      onPressed: () {
                        ref.read(doseLogProvider.notifier).markTaken(s.id);
                        // Persist to backend; failure is silently ignored (local state is truth)
                        ref.read(medicationRepositoryProvider).logDose(
                          userId: ref.read(userIdProvider),
                          scheduleId: s.id,
                          status: 'taken',
                          confidence: 1.0,
                        ).ignore();
                      },
                    ),
            ),
          );
        }),
      ],
    );
  }

  String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24)   return '${d.inHours} hr ago';
    return '${d.inDays} day(s) ago';
  }

  Widget _caregiverBadge(String status) {
    if (status == 'Connected') return const Icon(Icons.check_circle_rounded, color: Colors.green);
    if (status == 'Pending')   return const Icon(Icons.schedule_rounded, color: Colors.orange);
    return const Icon(Icons.mail_rounded, color: Colors.blue);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts      = ref.watch(alertsProvider);
    final medications = ref.watch(syntheticMedicationProvider);
    final schedules   = ref.watch(syntheticScheduleProvider);
    final photoEvents = ref.watch(syntheticVerificationProvider);
    final caregivers  = ref.watch(caregiversProvider);
    final takenIds    = ref.watch(doseLogProvider);
    final pending     = ref.watch(pendingPrescriptionsProvider);
    final adherence   = ref.watch(todayAdherenceProvider).asData?.value ?? {};
    final todayName   = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'][DateTime.now().weekday - 1];
    final medNames    = {for (final m in medications) m.id: m.name};
    final todaySched  = schedules.where((s) => s.dayOfWeek.toLowerCase() == todayName.toLowerCase()).toList();
    final doneCount   = todaySched.where((s) => takenIds.contains(s.id)).length;
    final awaitingReview = pending.where((p) => p.status == VerificationStatus.awaitingVerifier).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pillbox'),
        actions: [IconButton(onPressed: () => context.push('/settings'), icon: const Icon(Icons.settings_outlined))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Overview metrics
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Today\u2019s overview', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _MetricChip(label: 'Meds',       value: '${medications.length}')),
                  const SizedBox(width: 12),
                  Expanded(child: _MetricChip(label: 'Doses done', value: '$doneCount / ${todaySched.length}')),
                  const SizedBox(width: 12),
                  Expanded(child: _MetricChip(label: 'Alerts',     value: '${alerts.length}')),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          // Quick actions
          Text('Quick actions', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12,
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1.5,
            children: [
              _ActionCard(icon: Icons.add_circle_outline_rounded, label: 'Add medication',   onTap: () => context.push('/add-medication')),
              _ActionCard(icon: Icons.document_scanner_rounded,   label: 'Scan label',       onTap: () => context.push('/scan-prescription')),
              _ActionCard(icon: Icons.calendar_month_rounded,     label: 'Set schedule',     onTap: () => context.push('/schedule')),
              _ActionCard(icon: Icons.camera_alt_outlined,        label: 'Verify dose',      onTap: () => context.push('/capture-photo')),
            ],
          ),
          const SizedBox(height: 18),
          // Medications list
          Text('Medications', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...medications.map((med) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(Icons.medication_rounded, color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
              title: Text(med.name),
              subtitle: Text(
                [if (med.dosage != null) med.dosage!, if (med.instructions != null) med.instructions!].join('  \u2022  '),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'View / edit',
                onPressed: () => context.push('/medication/${med.id}'),
              ),
            ),
          )),
          const SizedBox(height: 18),
          // Today's schedule with dose tracking
          Text('Today\u2019s schedule', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _buildTodaySchedule(context, ref, schedules, medNames, todayName, takenIds, adherence),
          const SizedBox(height: 18),
          // Recent verifications
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Recent verifications', style: Theme.of(context).textTheme.titleLarge),
            TextButton(onPressed: () => context.push('/history'), child: const Text('View all')),
          ]),
          const SizedBox(height: 4),
          ...photoEvents.take(3).map((e) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.photo_camera_outlined)),
              title: Text(e.eventType),
              subtitle: Text(_relativeTime(e.eventTime)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: () => context.push('/history'),
            ),
          )),
          const SizedBox(height: 18),
          // Prescriptions awaiting verifier review
          if (awaitingReview > 0) ...[
            Card(
              color: Colors.orange.shade50,
              child: ListTile(
                leading: const Icon(Icons.pending_actions_rounded, color: Colors.orange),
                title: Text('$awaitingReview prescription${awaitingReview == 1 ? '' : 's'} pending review'),
                subtitle: const Text('A care team member needs to verify these'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () => context.push('/prescription-queue'),
              ),
            ),
            const SizedBox(height: 18),
          ],
          // Active alerts with dismiss
          Text('Active alerts', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (alerts.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.green),
                  const SizedBox(width: 12),
                  Text('No active alerts', style: Theme.of(context).textTheme.bodyMedium),
                ]),
              ),
            ),
          ...alerts.asMap().entries.map((entry) {
            final a = entry.value;
            final color = a.severity == 'High' ? Colors.red : a.severity == 'Medium' ? Colors.orange : Colors.blue;
            final icon  = a.severity == 'High' ? Icons.error_rounded : a.severity == 'Medium' ? Icons.warning_rounded : Icons.info_rounded;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Icon(icon, color: color),
                title: Text(a.title),
                subtitle: Text(a.message),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Dismiss',
                  onPressed: () => ref.read(alertsProvider.notifier).dismiss(entry.key),
                ),
              ),
            );
          }),
          const SizedBox(height: 18),
          // Care team
          Text('Care team', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...caregivers.map((c) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: c.status == 'Connected' ? Colors.green.shade100 : Colors.orange.shade100,
                child: Icon(Icons.person_rounded, color: c.status == 'Connected' ? Colors.green.shade700 : Colors.orange.shade700),
              ),
              title: Text(c.name),
              subtitle: Text('${c.relation}${c.phone != null ? "  \u2022  ${c.phone}" : ""}'),
              trailing: _caregiverBadge(c.status),
            ),
          )),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _showInviteCaregiverDialog(context, ref),
            icon: const Icon(Icons.group_add_rounded),
            label: const Text('Invite care team member'),
          ),
          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/scan-prescription'),
        icon: const Icon(Icons.document_scanner_rounded),
        label: const Text('Scan prescription'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (i) {
          if (i == 1) { context.go('/alerts'); }
          else if (i == 2) { context.go('/caregiver'); }
          else { context.go('/dashboard'); }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined),          selectedIcon: Icon(Icons.home),          label: 'Home'),
          NavigationDestination(icon: Icon(Icons.notifications_outlined),  selectedIcon: Icon(Icons.notifications),  label: 'Alerts'),
          NavigationDestination(icon: Icon(Icons.people_alt_outlined),     selectedIcon: Icon(Icons.people_alt),     label: 'Care'),
        ],
      ),
    );
  }
}

// ── Medication detail / edit ────────────────────────────────────────────────────

class MedicationDetailScreen extends ConsumerStatefulWidget {
  const MedicationDetailScreen({super.key, required this.medicationId});
  final int medicationId;
  @override
  ConsumerState<MedicationDetailScreen> createState() => _MedicationDetailScreenState();
}

class _MedicationDetailScreenState extends ConsumerState<MedicationDetailScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _dosageController;
  late final TextEditingController _customInstructionsController;
  final Set<String> _selectedInstructions = {};

  static const _instructionOptions = [
    'Take with food', 'Take on an empty stomach', 'After breakfast', 'Before breakfast',
    'After lunch', 'Before dinner', 'At bedtime', 'With water', 'As needed',
  ];

  @override
  void initState() {
    super.initState();
    final med = ref.read(syntheticMedicationProvider).firstWhere(
      (m) => m.id == widget.medicationId,
      orElse: () => Medication(id: widget.medicationId, userId: 1, name: 'Medication'),
    );
    _nameController   = TextEditingController(text: med.name);
    _dosageController = TextEditingController(text: med.dosage ?? '');
    if (med.instructions != null) {
      final parts = med.instructions!.split(' \u2022 ');
      for (final p in parts) {
        if (_instructionOptions.contains(p)) _selectedInstructions.add(p);
      }
      final custom = parts.where((p) => !_instructionOptions.contains(p)).join(' \u2022 ');
      _customInstructionsController = TextEditingController(text: custom);
    } else {
      _customInstructionsController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _customInstructionsController.dispose();
    super.dispose();
  }

  String _buildInstructions() {
    final parts = [
      ..._selectedInstructions,
      if (_customInstructionsController.text.trim().isNotEmpty) _customInstructionsController.text.trim(),
    ];
    return parts.join(' \u2022 ');
  }

  Future<void> _save() async {
    final name         = _nameController.text.trim().isEmpty ? 'Medication' : _nameController.text.trim();
    final dosage       = _dosageController.text.trim().isEmpty ? null : _dosageController.text.trim();
    final instructions = _buildInstructions().isEmpty ? null : _buildInstructions();

    Medication updated;
    try {
      updated = await ref.read(medicationRepositoryProvider).updateMedication(
        medicationId: widget.medicationId,
        name: name,
        dosage: dosage,
        instructions: instructions,
      );
    } catch (_) {
      // Backend unavailable — update local state only
      updated = Medication(
        id: widget.medicationId,
        userId: ref.read(userIdProvider),
        name: name,
        dosage: dosage,
        instructions: instructions,
      );
    }
    ref.read(syntheticMedicationProvider.notifier).updateMedication(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Medication updated')));
    if (mounted) Navigator.of(context).pop();
  }

  void _confirmDelete() {
    final medName = _nameController.text;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete medication?'),
        content: Text('Remove "$medName" and all its scheduled doses?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref.read(syntheticMedicationProvider.notifier).deleteMedication(widget.medicationId);
              final scheduleIds = ref
                  .read(syntheticScheduleProvider)
                  .where((s) => s.medicationId == widget.medicationId)
                  .map((s) => s.id)
                  .toList();
              for (final id in scheduleIds) {
                ref.read(syntheticScheduleProvider.notifier).deleteSchedule(id);
              }
              Navigator.of(ctx).pop();
              context.go('/dashboard');
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final schedules = ref.watch(syntheticScheduleProvider)
        .where((s) => s.medicationId == widget.medicationId)
        .toList()
      ..sort((a, b) => a.timeOfDay.compareTo(b.timeOfDay));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medication details'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.red), tooltip: 'Delete', onPressed: _confirmDelete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Medication name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _dosageController,
            decoration: const InputDecoration(labelText: 'Dosage (e.g. 500 mg)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          Text('Instructions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _instructionOptions.map((opt) {
              final sel = _selectedInstructions.contains(opt);
              return ChoiceChip(
                label: Text(opt), selected: sel,
                onSelected: (_) => setState(() => sel ? _selectedInstructions.remove(opt) : _selectedInstructions.add(opt)),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _customInstructionsController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Custom notes', hintText: 'e.g. Take 30 min before eating', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          if (schedules.isNotEmpty) ...[
            Text('Scheduled doses', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...schedules.map((s) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.schedule_rounded),
                title: Text('${s.dayOfWeek}  \u2022  ${s.timeOfDay}'),
                subtitle: s.notes != null ? Text(s.notes!) : null,
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Remove slot',
                  onPressed: () => ref.read(syntheticScheduleProvider.notifier).deleteSchedule(s.id),
                ),
              ),
            )),
            const SizedBox(height: 8),
          ],
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save changes'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.push('/schedule', extra: widget.medicationId),
            icon: const Icon(Icons.add_alarm_rounded),
            label: const Text('Add schedule slot'),
          ),
        ],
      ),
    );
  }
}

// ── Shared small widgets ─────────────────────────────────────────────────────────

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
      ]),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Add medication ────────────────────────────────────────────────────────────────

class AddMedicationScreen extends ConsumerStatefulWidget {
  const AddMedicationScreen({super.key});
  @override
  ConsumerState<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

class _AddMedicationScreenState extends ConsumerState<AddMedicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController    = TextEditingController();
  final _dosageController  = TextEditingController();
  final _customController  = TextEditingController();
  final Set<String> _selectedInstructions = {};
  bool _isSubmitting = false;

  static const _instructionOptions = [
    'Take with food', 'Take on an empty stomach', 'After breakfast', 'Before breakfast',
    'After lunch', 'Before dinner', 'At bedtime', 'With water', 'As needed',
  ];
  static const _weekdays = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];

  String _buildInstructions() {
    final parts = [
      ..._selectedInstructions,
      if (_customController.text.trim().isNotEmpty) _customController.text.trim(),
    ];
    return parts.join(' \u2022 ');
  }

  void _persistAndContinue(Medication med, String? instructions) {
    ref.read(syntheticMedicationProvider.notifier).addMedication(med);
    ref.read(syntheticScheduleProvider.notifier).addSchedule(Schedule(
      id: DateTime.now().millisecondsSinceEpoch,
      userId: ref.read(userIdProvider),
      medicationId: med.id,
      dayOfWeek: _weekdays[DateTime.now().weekday - 1],
      timeOfDay: (instructions != null && instructions.toLowerCase().contains('bedtime')) ? '21:00' : '08:00',
      notes: instructions ?? 'Scheduled from app',
    ));
    if (mounted) context.push('/schedule', extra: med.id);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    final name   = _nameController.text.trim();
    final dosage = _dosageController.text.trim().isEmpty ? null : _dosageController.text.trim();
    final instr  = _buildInstructions().isEmpty ? null : _buildInstructions();
    final local  = Medication(id: DateTime.now().millisecondsSinceEpoch, userId: ref.read(userIdProvider), name: name, dosage: dosage, instructions: instr);

    try {
      final created = await ref.read(medicationRepositoryProvider).createMedication(
        userId: ref.read(userIdProvider), name: name, dosage: dosage, instructions: instr,
      );
      _persistAndContinue(created, instr);
    } on ApiException {
      _persistAndContinue(local, instr);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved locally \u2014 will sync when online.')));
    } catch (_) {
      _persistAndContinue(local, instr);
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
      appBar: AppBar(title: const Text('Add medication')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(children: [
            // Prominent scan shortcut
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              margin: const EdgeInsets.only(bottom: 20),
              child: ListTile(
                leading: Icon(Icons.document_scanner_rounded, color: Theme.of(context).colorScheme.onPrimaryContainer),
                title: const Text('Scan prescription label'),
                subtitle: const Text('Auto-fill from your bottle'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () => context.push('/scan-prescription'),
              ),
            ),
            Text('Or enter details manually', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Medication name is required' : null,
              decoration: const InputDecoration(
                labelText: 'Medication name', hintText: 'e.g. Metformin',
                prefixIcon: Icon(Icons.medication_outlined), border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _dosageController,
              decoration: const InputDecoration(
                labelText: 'Dosage', hintText: 'e.g. 500 mg, 1 tablet',
                prefixIcon: Icon(Icons.scale_rounded), border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Text('Instructions', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Select all that apply', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _instructionOptions.map((opt) {
                final sel = _selectedInstructions.contains(opt);
                return ChoiceChip(
                  label: Text(opt), selected: sel,
                  onSelected: (_) => setState(() => sel ? _selectedInstructions.remove(opt) : _selectedInstructions.add(opt)),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _customController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Custom notes (optional)', hintText: 'e.g. Take 30 min before eating',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: Text(_isSubmitting ? 'Saving...' : 'Save & set schedule'),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Schedule setup ────────────────────────────────────────────────────────────────

class ScheduleSetupScreen extends ConsumerStatefulWidget {
  const ScheduleSetupScreen({super.key, this.preselectedMedicationId});
  final int? preselectedMedicationId;
  @override
  ConsumerState<ScheduleSetupScreen> createState() => _ScheduleSetupScreenState();
}

class _ScheduleSetupScreenState extends ConsumerState<ScheduleSetupScreen> {
  static const _days  = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
  static const _times = ['06:00','07:00','08:00','09:00','12:00','13:00','18:00','20:00','21:00','22:00'];

  final Set<String> _selectedDays = {};
  String? _selectedTime;
  int?    _selectedMedicationId;
  bool    _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedMedicationId = widget.preselectedMedicationId;
    if (_selectedMedicationId != null) {
      _selectedDays.add(_days[DateTime.now().weekday - 1]);
    }
  }

  Future<void> _save() async {
    if (_selectedMedicationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a medication')));
      return;
    }
    if (_selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one day')));
      return;
    }
    if (_selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select an intake time')));
      return;
    }
    setState(() => _isSaving = true);

    final repo   = ref.read(medicationRepositoryProvider);
    final userId = ref.read(userIdProvider);
    final medId  = _selectedMedicationId!;
    final daysToSave = List<String>.from(_selectedDays);

    for (final day in daysToSave) {
      try {
        final created = await repo.createSchedule(userId: userId, medicationId: medId, dayOfWeek: day, timeOfDay: _selectedTime!, notes: 'Scheduled from app');
        ref.read(syntheticScheduleProvider.notifier).addSchedule(created);
      } catch (_) {
        ref.read(syntheticScheduleProvider.notifier).addSchedule(Schedule(
          id: DateTime.now().millisecondsSinceEpoch + day.hashCode.abs(),
          userId: userId, medicationId: medId, dayOfWeek: day, timeOfDay: _selectedTime!, notes: 'Scheduled from app',
        ));
      }
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Schedule saved for ${daysToSave.length} day(s)')),
    );
    context.push('/capture-photo');
  }

  @override
  Widget build(BuildContext context) {
    final medications = ref.watch(syntheticMedicationProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Schedule setup')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(children: [
          Text('Medication', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _selectedMedicationId,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Select a medication'),
            items: medications.map((m) => DropdownMenuItem(
              value: m.id,
              child: Text('${m.name}${m.dosage != null ? "  \u2014  ${m.dosage}" : ""}'),
            )).toList(),
            onChanged: (v) => setState(() => _selectedMedicationId = v),
          ),
          const SizedBox(height: 24),
          Text('Days', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Select all days you take this medication', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _days.map((day) {
              final sel = _selectedDays.contains(day);
              return FilterChip(
                label: Text(day.substring(0, 3)), selected: sel,
                onSelected: _isSaving ? null : (_) => setState(() => sel ? _selectedDays.remove(day) : _selectedDays.add(day)),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Text('Intake time', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12, runSpacing: 12,
            children: _times.map((t) => ChoiceChip(
              label: Text(t), selected: _selectedTime == t,
              onSelected: _isSaving ? null : (_) => setState(() => _selectedTime = t),
            )).toList(),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded),
            label: Text(_isSaving ? 'Saving...' : 'Save schedule'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => context.go('/dashboard'), child: const Text('Skip for now')),
        ]),
      ),
    );
  }
}

// ── Verification result ────────────────────────────────────────────────────────────

class EventResultScreen extends StatelessWidget {
  const EventResultScreen({super.key, this.results = const []});
  final List<InferenceResult> results;

  @override
  Widget build(BuildContext context) {
    final changedCount = results.where((r) => r.isChanged).length;
    final isConfirmed  = changedCount == 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Verification result')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Icon(
                  isConfirmed ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                  size: 56,
                  color: isConfirmed ? Colors.green.shade700 : Colors.orange.shade700,
                ),
                const SizedBox(height: 12),
                Text(isConfirmed ? 'Confirmed' : 'Changes detected', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(isConfirmed
                    ? 'Pill pattern matched the prescribed medication schedule.'
                    : '$changedCount compartment(s) differ from the baseline photo.'),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1,
              ),
              itemCount: results.isEmpty ? 14 : results.length,
              itemBuilder: (_, i) {
                final r = results.isEmpty ? null : results[i];
                final changed = r?.isChanged ?? false;
                return Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: changed ? Colors.red.shade100 : Colors.green.shade100,
                    border: Border.all(color: changed ? Colors.red.shade700 : Colors.green.shade700, width: 1.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    r == null ? '${i + 1}' : '${r.compartmentIndex + 1}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: changed ? Colors.red.shade900 : Colors.green.shade900),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => context.go('/dashboard'),
            icon: const Icon(Icons.home_rounded),
            label: const Text('Return to dashboard'),
          ),
        ]),
      ),
    );
  }
}

// ── Verification history ──────────────────────────────────────────────────────────

class VerificationHistoryScreen extends ConsumerWidget {
  const VerificationHistoryScreen({super.key});

  String _rel(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24)   return '${d.inHours} hr ago';
    return '${d.inDays} day(s) ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(userIdProvider);
    final asyncEvents = ref.watch(photoEventsByUserProvider(userId));
    final synthetic   = ref.watch(syntheticVerificationProvider);

    Widget buildList(List<PhotoEventRecord> events) => ListView(
      children: events.map((e) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: CircleAvatar(backgroundColor: Colors.green.shade100, child: const Icon(Icons.verified_rounded, color: Colors.green)),
          title: Text(e.eventType),
          subtitle: Text(_rel(e.eventTime)),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      )).toList(),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Verification history')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: asyncEvents.when(
          data: (events) => events.isEmpty ? buildList(synthetic) : buildList(events),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => synthetic.isEmpty
              ? const Center(child: Text('No verification history yet.'))
              : buildList(synthetic),
        ),
      ),
    );
  }
}

// ── Alerts ─────────────────────────────────────────────────────────────────────────

class AlertsListScreen extends ConsumerWidget {
  const AlertsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts     = ref.watch(alertsProvider);
    final alertPhone = ref.watch(alertPhoneProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.phone_in_talk_rounded),
              title: const Text('SMS alert number'),
              subtitle: Text(alertPhone),
              trailing: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => context.push('/settings')),
            ),
          ),
          const SizedBox(height: 12),
          if (alerts.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(children: [
                  Icon(Icons.check_circle_rounded, size: 40, color: Colors.green),
                  SizedBox(height: 8),
                  Text('All caught up! No active alerts.', textAlign: TextAlign.center),
                ]),
              ),
            ),
          ...alerts.asMap().entries.map((entry) {
            final a = entry.value;
            final color = a.severity == 'High' ? Colors.red : a.severity == 'Medium' ? Colors.orange : Colors.blue;
            final icon  = a.severity == 'High' ? Icons.error_rounded : a.severity == 'Medium' ? Icons.warning_rounded : Icons.info_rounded;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(icon, color: color),
                title: Text(a.title),
                subtitle: Text('${a.message}\n\nSMS target: $alertPhone'),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Dismiss',
                  onPressed: () => ref.read(alertsProvider.notifier).dismiss(entry.key),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Care team ──────────────────────────────────────────────────────────────────────

class CaregiverScreen extends ConsumerWidget {
  const CaregiverScreen({super.key});

  void _showInviteDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl  = TextEditingController();
    final relCtrl   = TextEditingController(text: 'Family member');
    final phoneCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite care team member'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl,  decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(controller: relCtrl,   decoration: const InputDecoration(labelText: 'Relationship')),
          const SizedBox(height: 12),
          TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final n = nameCtrl.text.trim(); final r = relCtrl.text.trim(); final p = phoneCtrl.text.trim();
              if (n.isEmpty || r.isEmpty || p.isEmpty) return;
              ref.read(caregiversProvider.notifier).inviteCaregiver(name: n, relation: r, phone: p);
              Navigator.of(ctx).pop();
            },
            child: const Text('Send invite'),
          ),
        ],
      ),
    ).whenComplete(() { nameCtrl.dispose(); relCtrl.dispose(); phoneCtrl.dispose(); });
  }

  Widget _statusBadge(String status) {
    final color = status == 'Connected' ? Colors.green : status == 'Pending' ? Colors.orange : Colors.blue;
    return Chip(
      label: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
      backgroundColor: color.withValues(alpha: 0.12),
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caregivers = ref.watch(caregiversProvider);
    final pending    = ref.watch(pendingPrescriptionsProvider);
    final awaitingCount = pending.where((p) => p.status == VerificationStatus.awaitingVerifier).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Care team')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Prescription review queue
          if (awaitingCount > 0) ...[
            Card(
              color: Colors.orange.shade50,
              child: ListTile(
                leading: const Icon(Icons.pending_actions_rounded, color: Colors.orange),
                title: Text('$awaitingCount prescription${awaitingCount == 1 ? '' : 's'} need${awaitingCount == 1 ? 's' : ''} review'),
                subtitle: const Text('Tap to open the verification queue'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () => context.push('/prescription-queue'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          ...caregivers.map((c) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: c.status == 'Connected' ? Colors.green.shade100 : Colors.orange.shade100,
                child: Icon(Icons.person_rounded, color: c.status == 'Connected' ? Colors.green.shade700 : Colors.orange.shade700),
              ),
              title: Text(c.name),
              subtitle: Text('${c.relation}${c.phone != null ? "  \u2022  ${c.phone}" : ""}'),
              trailing: _statusBadge(c.status),
            ),
          )),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _showInviteDialog(context, ref),
            icon: const Icon(Icons.group_add_rounded),
            label: const Text('Invite care team member'),
          ),
        ],
      ),
    );
  }
}

// \u2500\u2500 Prescription label scanner \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

enum _ScanPhase { initial, imageSelected, scanning, patientReview, submitted }

class PrescriptionScanScreen extends ConsumerStatefulWidget {
  const PrescriptionScanScreen({super.key});
  @override
  ConsumerState<PrescriptionScanScreen> createState() => _PrescriptionScanScreenState();
}

class _PrescriptionScanScreenState extends ConsumerState<PrescriptionScanScreen>
    with SingleTickerProviderStateMixin {
  static const int _hueSweepSegments = 6;
  static const double _guideLeftNorm = 0.22;
  static const double _guideRightNorm = 0.78;

  File? _selectedImage;
  File? _preparedCropImage;
  Uint8List? _labelPreviewBytes;
  _ScanPhase _phase = _ScanPhase.initial;
  PrescriptionScanResult? _result;
  String? _error;
  String? _cameraStatus;
  String? _cameraError;
  bool _patientConfirmed = false;
  bool _labelPreparing = false;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _dosageCtrl;
  late final TextEditingController _instructionsCtrl;
  late final TextEditingController _patientNoteCtrl;
  late final TextRecognizer _textRecognizer;

  CameraController? _cameraController;
  bool _cameraInitializing = false;
  bool _cameraFrameBusy = false;
  bool _cameraCapturePending = false;
  bool _sweepCaptureBusy = false;
  bool _autoFinalizingSweep = false;
  final List<File> _sweepFrames = <File>[];
  final List<bool> _seenHueSegments = List<bool>.filled(_hueSweepSegments, false);
  DateTime? _lastCameraAnalysis;

  late final AnimationController _animCtrl;
  late final Animation<double> _scanLine;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _nameCtrl         = TextEditingController();
    _dosageCtrl       = TextEditingController();
    _instructionsCtrl = TextEditingController();
    _patientNoteCtrl  = TextEditingController();
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
    _scanLine = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut));
    _pulse    = Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut));
    _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _nameCtrl.dispose();
    _dosageCtrl.dispose();
    _instructionsCtrl.dispose();
    _patientNoteCtrl.dispose();
    _textRecognizer.close();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    if (kIsWeb || _cameraInitializing || (_cameraController?.value.isInitialized ?? false)) {
      return;
    }
    _cameraInitializing = true;
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _cameraError = 'No camera was found on this device.';
        });
        return;
      }
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      _cameraController = controller;
      if (!mounted) return;
      await controller.startImageStream(_processCameraFrame);
      if (!mounted) return;
      setState(() {
        _cameraError = null;
        _cameraStatus = 'Point the label into the center guide.';
      });
    } on CameraException catch (error) {
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        _cameraController = null;
        _cameraError = error.description ?? 'Camera preview could not be started.';
      });
    } catch (_) {
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        _cameraController = null;
        _cameraError = 'Camera preview could not be started.';
      });
    } finally {
      _cameraInitializing = false;
    }
  }

  Future<void> _stopCameraStream() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Ignore stream shutdown errors when the stream is already paused.
    }
  }

  Future<void> _resumeCameraStream() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      await _initializeCamera();
      return;
    }
    try {
      if (!controller.value.isStreamingImages) {
        await controller.startImageStream(_processCameraFrame);
      }
    } catch (_) {
      // If the stream cannot be restarted, the preview still works and the user can retake later.
    }
  }

  Future<void> _resetToLiveCamera() async {
    await _resumeCameraStream();
    if (!mounted) return;
    setState(() {
      _selectedImage = null;
      _preparedCropImage = null;
      _labelPreviewBytes = null;
      _result = null;
      _error = null;
      _cameraStatus = 'Point the label into the center guide.';
      _sweepCaptureBusy = false;
      _autoFinalizingSweep = false;
      _sweepFrames.clear();
      for (var i = 0; i < _seenHueSegments.length; i += 1) {
        _seenHueSegments[i] = false;
      }
      _phase = _ScanPhase.initial;
      _patientConfirmed = false;
    });
  }

  String _backendUnreachableMessage() {
    return 'Cannot reach backend at ${AppConfig.baseUrl}. Start backend on port 8000. '
        'If you are on a real iPhone, run with --dart-define=API_BASE_URL=http://<YOUR_MAC_LAN_IP>:8000 '
        '(example: http://192.168.1.8:8000) and keep phone and Mac on the same Wi-Fi.';
  }

  int _detectedHueSegmentCount() {
    var count = 0;
    for (final seen in _seenHueSegments) {
      if (seen) {
        count += 1;
      }
    }
    return count;
  }

  void _updateCameraStatus(String message) {
    if (!mounted) return;
    if (_cameraStatus == message) {
      return;
    }
    setState(() {
      _cameraStatus = message;
    });
  }

  Future<void> _processCameraFrame(CameraImage image) async {
    if (_phase != _ScanPhase.initial || _selectedImage != null || _cameraCapturePending || _cameraFrameBusy || _sweepCaptureBusy) {
      return;
    }
    final now = DateTime.now();
    if (_lastCameraAnalysis != null && now.difference(_lastCameraAnalysis!) < const Duration(milliseconds: 900)) {
      return;
    }
    _lastCameraAnalysis = now;
    _cameraFrameBusy = true;
    try {
      if (!_autoFinalizingSweep && !_sweepCaptureBusy) {
        unawaited(_captureSweepReferenceFrame());
      }
    } catch (_) {
      if (mounted) {
        for (var i = 0; i < _seenHueSegments.length; i += 1) {
          _seenHueSegments[i] = false;
        }
        _updateCameraStatus('Hold the label steady and try again.');
      }
    } finally {
      _cameraFrameBusy = false;
    }
  }

  Future<void> _captureLiveFrame() async {
    if (_cameraCapturePending || _autoFinalizingSweep) {
      return;
    }
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || controller.value.isTakingPicture) {
      return;
    }
    _autoFinalizingSweep = true;
    _cameraCapturePending = true;
    try {
      await _stopCameraStream();
      final picture = await controller.takePicture();
      final captured = File(picture.path);
      final frameSet = <File>[..._sweepFrames, captured];
      if (frameSet.length < 2) {
        await _resumeCameraStream();
        if (mounted) {
          _updateCameraStatus('Need more sweep frames. Move around the full label first.');
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _selectedImage = captured;
        _preparedCropImage = null;
        _labelPreviewBytes = null;
        _phase = _ScanPhase.imageSelected;
        _error = null;
        _result = null;
        _patientConfirmed = false;
        for (var i = 0; i < _seenHueSegments.length; i += 1) {
          _seenHueSegments[i] = false;
        }
        _cameraStatus = null;
        _sweepFrames.clear();
      });
      unawaited(_prepareSelectedLabelForOcr(frameCandidates: frameSet));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cameraError = 'Could not capture the label. Please try again.';
        _cameraStatus = 'Capture failed.';
      });
      await _resumeCameraStream();
    } finally {
      _autoFinalizingSweep = false;
      _cameraCapturePending = false;
    }
  }

  Future<void> _captureSweepReferenceFrame() async {
    if (_phase != _ScanPhase.initial || _sweepCaptureBusy || _autoFinalizingSweep) {
      return;
    }
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || controller.value.isTakingPicture) {
      return;
    }
    _sweepCaptureBusy = true;
    var shouldFinalize = false;
    try {
      await _stopCameraStream();
      final shot = await controller.takePicture();
      final frame = File(shot.path);
      if (!mounted || _phase != _ScanPhase.initial) {
        return;
      }
      final bytes = await frame.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        _updateCameraStatus('Could not read camera frame. Keep sweeping.');
        return;
      }
      final oriented = img.bakeOrientation(decoded);
      final analysis = _analyzeYellowGuideRegion(oriented);
      if (analysis.bounds == null) {
        _updateCameraStatus('No yellow label detected between guide lines. Re-center the label.');
        return;
      }

      var discovered = false;
      var unseenLeftWeight = 0.0;
      var unseenRightWeight = 0.0;
      for (var i = 0; i < _hueSweepSegments; i += 1) {
        final coverage = analysis.segmentCoverage[i];
        if (_seenHueSegments[i]) {
          continue;
        }
        if (i < _hueSweepSegments ~/ 2) {
          unseenLeftWeight += coverage;
        } else {
          unseenRightWeight += coverage;
        }
        if (coverage >= 0.10) {
          _seenHueSegments[i] = true;
          discovered = true;
        }
      }

      final seenSegments = _detectedHueSegmentCount();
      final shouldStore = discovered || _sweepFrames.isEmpty || (analysis.yellowHits > 1200 && _sweepFrames.length < 8);
      if (shouldStore) {
        _sweepFrames.add(frame);
      }

      if (seenSegments >= 4 && _sweepFrames.length >= 3) {
        shouldFinalize = true;
        _updateCameraStatus('Yellow label coverage complete. Building flattened scan...');
      } else if (unseenLeftWeight > unseenRightWeight && unseenLeftWeight > 0.0) {
        _updateCameraStatus('Move left for unseen yellow label area. Captured $seenSegments/$_hueSweepSegments segments.');
      } else if (unseenRightWeight > unseenLeftWeight && unseenRightWeight > 0.0) {
        _updateCameraStatus('Move right for unseen yellow label area. Captured $seenSegments/$_hueSweepSegments segments.');
      } else {
        _updateCameraStatus('Sweep slowly across the yellow label between guide lines. Captured $seenSegments/$_hueSweepSegments segments.');
      }
    } catch (_) {
      // Keep scanning even if a reference frame failed.
    } finally {
      _sweepCaptureBusy = false;
      if (shouldFinalize && !_autoFinalizingSweep) {
        unawaited(_captureLiveFrame());
      } else {
        await _resumeCameraStream();
      }
    }
  }

  Future<(String?, String?)> _runDeviceOcrHint(File imageFile) async {
    if (kIsWeb) {
      return (null, null);
    }
    try {
      final input = InputImage.fromFilePath(imageFile.path);
      final recognized = await _textRecognizer.processImage(input);
      final text = recognized.text.trim();
      if (text.isEmpty) {
        return (null, null);
      }
      final provider = defaultTargetPlatform == TargetPlatform.iOS ? 'apple_vision' : 'google_ml_kit';
      return (text, provider);
    } catch (_) {
      return (null, null);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final repo = ref.read(imageUploadRepositoryProvider);
      await _stopCameraStream();
      // Max resolution + no quality loss during capture ensures sharp label text for OCR
      final picked = await repo.pickImage(
        source: source,
        imageQuality: 100,
        maxDimension: 4000,
      );
      if (picked == null) return;
      // Use OCR-optimised compression (92%) rather than the 70% default
      final compressed = await repo.compressForOcr(picked);
      if (compressed == null) { setState(() => _error = 'Could not process image'); return; }
      _sweepFrames.clear();
      setState(() {
        _selectedImage = compressed;
        _preparedCropImage = null;
        _labelPreviewBytes = null;
        _phase = _ScanPhase.imageSelected;
        _error = null;
        _result = null;
        _patientConfirmed = false;
        _cameraStatus = null;
      });
      unawaited(_prepareSelectedLabelForOcr());
    } catch (_) {
      setState(() => _error = 'Could not access camera or gallery');
    }
  }

  Future<void> _prepareSelectedLabelForOcr({List<File>? frameCandidates}) async {
    final sourceImage = _selectedImage;
    if (sourceImage == null || _labelPreparing) {
      return;
    }
    setState(() {
      _labelPreparing = true;
      _error = null;
      _cameraStatus = 'Building flattened scan on-device…';
    });
    try {
      final candidates = frameCandidates == null ? <File>[] : List<File>.from(frameCandidates);
      if (candidates.isEmpty) {
        candidates.add(sourceImage);
      }
      final flattened = await _composeFlattenedScanLocally(candidates);
      if (!mounted || _selectedImage?.path != sourceImage.path) {
        return;
      }
      if (flattened == null) {
        setState(() {
          _error = 'Could not build a flattened scan from the captured frames. Sweep the full label and try again.';
        });
        return;
      }
      final bytes = await flattened.readAsBytes();
      setState(() {
        _preparedCropImage = flattened;
        _labelPreviewBytes = bytes;
        _cameraStatus = 'Flattened scan ready.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not build the flattened scan on-device. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _labelPreparing = false;
        });
      }
    }
  }

  ({double h, double s, double v}) _rgbToHsv(int r, int g, int b) {
    final rf = r / 255.0;
    final gf = g / 255.0;
    final bf = b / 255.0;
    final maxC = [rf, gf, bf].reduce((a, c) => a > c ? a : c);
    final minC = [rf, gf, bf].reduce((a, c) => a < c ? a : c);
    final delta = maxC - minC;

    double h;
    if (delta == 0) {
      h = 0;
    } else if (maxC == rf) {
      h = 60 * (((gf - bf) / delta) % 6);
    } else if (maxC == gf) {
      h = 60 * (((bf - rf) / delta) + 2);
    } else {
      h = 60 * (((rf - gf) / delta) + 4);
    }
    if (h < 0) {
      h += 360;
    }

    final s = maxC == 0 ? 0.0 : delta / maxC;
    final v = maxC;
    return (h: h, s: s, v: v);
  }

  bool _isLikelyLabelPaperColor(int r, int g, int b) {
    final hsv = _rgbToHsv(r, g, b);
    final yellowHue = hsv.h >= 24.0 && hsv.h <= 58.0;
    final notWhite = hsv.s >= 0.20;
    final notBottleOrange = hsv.h >= 24.0 && hsv.s <= 0.82;
    final brightnessOk = hsv.v >= 0.30 && hsv.v <= 0.96;
    final channelMixOk = g >= (r * 0.55).round() && b <= (g * 0.9).round();
    return yellowHue && notWhite && notBottleOrange && brightnessOk && channelMixOk;
  }

  Rect? _detectLabelColorBounds(img.Image source) {
    final maxWidth = source.width > 1200 ? 1200 : source.width;
    final working = source.width > maxWidth
        ? img.copyResize(source, width: maxWidth, interpolation: img.Interpolation.linear)
        : source;
    final scaleX = source.width / working.width;
    final scaleY = source.height / working.height;

    const sampleStep = 2;
    final guideLeft = (_guideLeftNorm * working.width).round().clamp(0, working.width - 1);
    final guideRight = (_guideRightNorm * working.width).round().clamp(1, working.width);
    if (guideRight - guideLeft < 12) {
      return null;
    }
    final rowHits = List<int>.filled(working.height, 0);
    final colHits = List<int>.filled(working.width, 0);
    var hitCount = 0;

    for (var y = 0; y < working.height; y += sampleStep) {
      for (var x = guideLeft; x < guideRight; x += sampleStep) {
        final px = working.getPixel(x, y);
        final r = px.r.toInt();
        final g = px.g.toInt();
        final b = px.b.toInt();
        if (_isLikelyLabelPaperColor(r, g, b)) {
          rowHits[y] += 1;
          colHits[x] += 1;
          hitCount += 1;
        }
      }
    }

    final sampledPixels = ((guideRight - guideLeft) ~/ sampleStep) * (working.height ~/ sampleStep);
    if (sampledPixels <= 0 || hitCount < sampledPixels * 0.006) {
      return null;
    }

    final rowThreshold = (((guideRight - guideLeft) / sampleStep) * 0.03).clamp(4.0, 99999.0).toInt();
    final colThreshold = ((working.height / sampleStep) * 0.03).clamp(6.0, 99999.0).toInt();

    int top = -1;
    int bottom = -1;
    int left = -1;
    int right = -1;

    for (var y = 0; y < rowHits.length; y += 1) {
      if (rowHits[y] >= rowThreshold) {
        top = y;
        break;
      }
    }
    for (var y = rowHits.length - 1; y >= 0; y -= 1) {
      if (rowHits[y] >= rowThreshold) {
        bottom = y;
        break;
      }
    }
    for (var x = 0; x < colHits.length; x += 1) {
      if (colHits[x] >= colThreshold) {
        left = x;
        break;
      }
    }
    for (var x = colHits.length - 1; x >= 0; x -= 1) {
      if (colHits[x] >= colThreshold) {
        right = x;
        break;
      }
    }

    if (top < 0 || bottom <= top || left < 0 || right <= left) {
      return null;
    }

    final width = right - left;
    final height = bottom - top;
    final expandX = (width * 0.10).toInt();
    final expandY = (height * 0.14).toInt();

    final srcLeft = ((left - expandX).clamp(0, working.width - 1) * scaleX).toDouble();
    final srcTop = ((top - expandY).clamp(0, working.height - 1) * scaleY).toDouble();
    final srcRight = ((right + expandX).clamp(1, working.width) * scaleX).toDouble();
    final srcBottom = ((bottom + expandY).clamp(1, working.height) * scaleY).toDouble();

    return Rect.fromLTRB(srcLeft, srcTop, srcRight, srcBottom);
  }

  ({Rect? bounds, List<double> segmentCoverage, int yellowHits}) _analyzeYellowGuideRegion(img.Image source) {
    final maxWidth = source.width > 1200 ? 1200 : source.width;
    final working = source.width > maxWidth
        ? img.copyResize(source, width: maxWidth, interpolation: img.Interpolation.linear)
        : source;

    final leftGuide = (_guideLeftNorm * working.width).round().clamp(0, working.width - 1);
    final rightGuide = (_guideRightNorm * working.width).round().clamp(1, working.width);
    if (rightGuide - leftGuide < 12) {
      return (bounds: null, segmentCoverage: List<double>.filled(_hueSweepSegments, 0.0), yellowHits: 0);
    }

    const sampleStep = 2;
    final corridorWidth = rightGuide - leftGuide;
    final segmentHits = List<int>.filled(_hueSweepSegments, 0);
    final segmentTotals = List<int>.filled(_hueSweepSegments, 0);
    int? top;
    int? bottom;
    int? left;
    int? right;
    var yellowHits = 0;

    for (var y = 0; y < working.height; y += sampleStep) {
      for (var x = leftGuide; x < rightGuide; x += sampleStep) {
        final seg = (((x - leftGuide) / corridorWidth) * _hueSweepSegments).floor().clamp(0, _hueSweepSegments - 1);
        segmentTotals[seg] += 1;
        final px = working.getPixel(x, y);
        if (_isLikelyLabelPaperColor(px.r.toInt(), px.g.toInt(), px.b.toInt())) {
          yellowHits += 1;
          segmentHits[seg] += 1;
          top = top == null ? y : (y < top ? y : top);
          bottom = bottom == null ? y : (y > bottom ? y : bottom);
          left = left == null ? x : (x < left ? x : left);
          right = right == null ? x : (x > right ? x : right);
        }
      }
    }

    final coverage = List<double>.generate(_hueSweepSegments, (i) {
      final total = segmentTotals[i];
      if (total <= 0) {
        return 0.0;
      }
      return segmentHits[i] / total;
    });

    if (yellowHits < 120 || top == null || bottom == null || left == null || right == null) {
      return (bounds: null, segmentCoverage: coverage, yellowHits: yellowHits);
    }

    final expandX = ((right - left) * 0.10).round();
    final expandY = ((bottom - top) * 0.16).round();
    final rect = Rect.fromLTRB(
      (left - expandX).clamp(0, working.width - 1).toDouble(),
      (top - expandY).clamp(0, working.height - 1).toDouble(),
      (right + expandX).clamp(1, working.width).toDouble(),
      (bottom + expandY).clamp(1, working.height).toDouble(),
    );
    return (bounds: rect, segmentCoverage: coverage, yellowHits: yellowHits);
  }

  Future<File?> _composeFlattenedScanLocally(List<File> frames) async {
    final crops = <img.Image>[];
    for (final frame in frames) {
      final bytes = await frame.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        continue;
      }
      final oriented = img.bakeOrientation(decoded);
      final bounds = _detectLabelColorBounds(oriented);
      if (bounds == null || bounds.width < 30 || bounds.height < 20) {
        continue;
      }

      final marginX = bounds.width * 0.12;
      final marginY = bounds.height * 0.16;
      final left = (bounds.left - marginX).clamp(0, (oriented.width - 1).toDouble()).toInt();
      final top = (bounds.top - marginY).clamp(0, (oriented.height - 1).toDouble()).toInt();
      final right = (bounds.right + marginX).clamp(1, oriented.width.toDouble()).toInt();
      final bottom = (bounds.bottom + marginY).clamp(1, oriented.height.toDouble()).toInt();
      final width = right - left;
      final height = bottom - top;
      if (width < 40 || height < 30) {
        continue;
      }
      crops.add(img.copyCrop(oriented, x: left, y: top, width: width, height: height));
    }

    if (crops.isEmpty) {
      return null;
    }

    final targetWidth = crops.map((c) => c.width).reduce((a, b) => a > b ? a : b);
    final targetHeight = crops.map((c) => c.height).reduce((a, b) => a > b ? a : b);
    final resized = crops
        .map((c) => img.copyResize(c, width: targetWidth, height: targetHeight, interpolation: img.Interpolation.linear))
        .toList();

    final composite = img.Image(width: targetWidth, height: targetHeight);
    for (var y = 0; y < targetHeight; y += 1) {
      for (var x = 0; x < targetWidth; x += 1) {
        var r = 255;
        var g = 255;
        var b = 255;
        for (final frame in resized) {
          final pixel = frame.getPixel(x, y);
          final pr = pixel.r.toInt();
          final pg = pixel.g.toInt();
          final pb = pixel.b.toInt();
          if (pr < r) r = pr;
          if (pg < g) g = pg;
          if (pb < b) b = pb;
        }
        composite.setPixelRgba(x, y, r, g, b, 255);
      }
    }

    final encoded = img.encodeJpg(composite, quality: 92);
    return _writeTempJpeg(Uint8List.fromList(encoded), suffix: '_flattened_local');
  }

  Future<void> _scanLabel() async {
    if (_selectedImage == null) return;
    if (_preparedCropImage == null) {
      setState(() {
        _error = 'Please wait for the label crop to finish preparing.';
      });
      return;
    }
    setState(() { _phase = _ScanPhase.scanning; _error = null; });
    final userId = ref.read(userIdProvider);
    final repo = ref.read(imageUploadRepositoryProvider);
    final reachable = await repo.isBackendReachable();
    if (!reachable) {
      if (!mounted) return;
      final friendly =
          _backendUnreachableMessage();
      setState(() {
        _phase = _ScanPhase.imageSelected;
        _error = friendly;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan failed: $friendly')),
      );
      return;
    }

    final preparedCrop = _preparedCropImage!;

    final (deviceOcrText, deviceOcrProvider) = await _runDeviceOcrHint(preparedCrop);
    if (!kIsWeb && (deviceOcrText == null || deviceOcrText.trim().isEmpty)) {
      if (!mounted) return;
      setState(() {
        _phase = _ScanPhase.imageSelected;
        _error = 'No readable label text detected on-device. Retake the photo with sharper focus and better lighting.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No label text detected. Please retake the photo.')),
      );
      return;
    }

    try {
      final result = await repo.scanPrescription(
        userId: userId,
        imageFile: preparedCrop,
        // ML Kit text is used as fallback-only server-side metadata now.
        deviceOcrText: deviceOcrText,
        deviceOcrProvider: deviceOcrProvider,
      );
      _applyResult(result);
    } on ApiException catch (error) {
      if (!mounted) return;
      final messageLower = error.message.toLowerCase();
      final isConnectionFailure =
          error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.unknown ||
          messageLower.contains('connection refused') ||
          messageLower.contains('request connection took longer') ||
          messageLower.contains('socketexception') ||
          messageLower.contains('timed out');
      final friendly = isConnectionFailure
          ? _backendUnreachableMessage()
          : error.message;
      setState(() {
        _phase = _ScanPhase.imageSelected;
        _error = friendly;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan failed: $friendly')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _ScanPhase.imageSelected;
        _error = 'Scan failed. Ensure backend OCR is running and try again.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan failed. Backend OCR may be unavailable.')),
      );
    }
  }

  void _applyResult(PrescriptionScanResult r) {
    setState(() {
      _result = r;
      _labelPreviewBytes = r.labelPreviewBase64 == null || r.labelPreviewBase64!.trim().isEmpty
          ? null
          : base64Decode(r.labelPreviewBase64!);
      _phase = _ScanPhase.patientReview;
      _nameCtrl.text         = r.medicationName;
      _dosageCtrl.text       = r.dosage;
      _instructionsCtrl.text = r.instructions;
      _patientNoteCtrl.clear();
      _patientConfirmed = false;
    });
  }

  Future<File> _writeTempJpeg(Uint8List bytes, {String suffix = ''}) async {
    final directory = await Directory.systemTemp.createTemp('pillbox_scan');
    final file = File('${directory.path}/label_${DateTime.now().millisecondsSinceEpoch}$suffix.jpg');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  void _submitForVerification() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Medication name is required')));
      return;
    }
    final id = DateTime.now().millisecondsSinceEpoch;
    final pending = PendingPrescription(
      id: id,
      medicationName: name,
      dosage: _dosageCtrl.text.trim(),
      instructions: _instructionsCtrl.text.trim().isEmpty ? null : _instructionsCtrl.text.trim(),
      scannedAt: DateTime.now(),
      prescribedBy: _result?.prescribedBy,
      pharmacy: _result?.pharmacy,
      refillsRemaining: _result?.refillsRemaining,
      imageFilePath: _selectedImage?.path,
      patientNote: _patientNoteCtrl.text.trim().isEmpty ? null : _patientNoteCtrl.text.trim(),
      status: VerificationStatus.awaitingVerifier,
    );
    ref.read(pendingPrescriptionsProvider.notifier).add(pending);
    setState(() { _phase = _ScanPhase.submitted; });
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan prescription label'),
        actions: _phase == _ScanPhase.patientReview
            ? [IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: 'Scan again',
                onPressed: _resetToLiveCamera)]
            : null,
      ),
      body: switch (_phase) {
        _ScanPhase.initial       => _buildInitial(),
        _ScanPhase.imageSelected => _buildImageSelected(),
        _ScanPhase.scanning      => _buildScanning(),
        _ScanPhase.patientReview => _buildPatientReview(),
        _ScanPhase.submitted     => _buildSubmitted(),
      },
    );
  }

  Widget _buildInitial() => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(children: [
      const SizedBox(height: 12),
      Icon(Icons.document_scanner_rounded, size: 72, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 14),
      Text('Scan a prescription label',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(
        'Hold the bottle label in the live camera view, let the app lock the label, then review the frozen photo before scanning. You can still upload a label image if needed.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
      ),
      const SizedBox(height: 20),
      _buildCameraPreviewCard(),
      const SizedBox(height: 20),
      // Photography tips
      _buildPhotoTips(),
      const SizedBox(height: 20),
      if (_cameraError != null) ...[_errorBox(_cameraError!), const SizedBox(height: 12)],
      if (_error != null) ...[_errorBox(_error!), const SizedBox(height: 12)],
      Row(children: [
        Expanded(child: FilledButton.icon(
          onPressed: (_cameraController?.value.isInitialized == true &&
                  _sweepFrames.length >= 3 &&
                  _detectedHueSegmentCount() >= 4)
              ? _captureLiveFrame
              : null,
          icon: const Icon(Icons.camera_alt_rounded),
          label: const Text('Finalize sweep'),
        )),
        const SizedBox(width: 12),
        Expanded(child: OutlinedButton.icon(
          onPressed: () => _pickImage(ImageSource.gallery),
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Upload image'),
        )),
      ]),
      const SizedBox(height: 8),
    ]),
  );

  Widget _buildPhotoTips() => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Row(children: [
      Icon(Icons.tips_and_updates_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 6),
      Text('Tips for best results', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
    ]),
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _tipRow('||', 'Center the label between the two vertical guides to reduce bottle-edge distortion'),
          _tipRow('\ud83d\udcf1', 'Hold the phone 20\u201330 cm from the label'),
          _tipRow('\ud83d\udca1', 'Ensure the label is brightly and evenly lit'),
          _tipRow('\ud83d\udccf', 'Lay the bottle flat so the label is straight'),
          _tipRow('\ud83d\udd0d', 'Wait for the camera to focus before shooting'),
          _tipRow('\ud83d\udeb7', 'Avoid shadows \u2014 especially from your hand'),
          _tipRow('\u2197\ufe0f',  'Capture only the label, not the whole bottle'),
        ]),
      ),
    ],
  );

  Widget _tipRow(String emoji, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
    ]),
  );

  Widget _buildImageSelected() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(children: [
      Expanded(
        child: Column(children: [
          Expanded(child: _buildViewfinder(_selectedImage, scanning: false)),
          const SizedBox(height: 12),
          if (_labelPreviewBytes != null)
            _buildFlattenedPreviewCard(height: 140)
          else if (_labelPreparing)
            Container(
              width: double.infinity,
              height: 140,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 12),
                  Text('Preparing flattened crop…', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      // Retake hint
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Make sure all text on the label is clearly visible and in focus.',
          style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: 12),
      if (_error != null) ...[_errorBox(_error!), const SizedBox(height: 12)],
      if (_preparedCropImage == null && !_labelPreparing)
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _prepareSelectedLabelForOcr,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry flattened crop'),
          ),
        ),
      if (_preparedCropImage == null && !_labelPreparing) const SizedBox(height: 12),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        onPressed: _preparedCropImage != null && !_labelPreparing ? _scanLabel : null,
        icon: const Icon(Icons.document_scanner_rounded),
        label: Text(_labelPreparing ? 'Preparing crop…' : 'Scan label'),
      )),
      TextButton(
        onPressed: _resetToLiveCamera,
        child: const Text('Retake with camera'),
      ),
    ]),
  );

  Widget _buildScanning() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(children: [
      Expanded(child: AnimatedBuilder(
        animation: _animCtrl,
        builder: (context, child) => _buildViewfinder(_selectedImage, scanning: true),
      )),
      const SizedBox(height: 28),
      const CircularProgressIndicator(),
      const SizedBox(height: 16),
      Text('Reading prescription label\u2026', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text('Extracting medication details', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
      const SizedBox(height: 40),
    ]),
  );

  Widget _buildPatientReview() {
    final r = _result!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_labelPreviewBytes != null) ...[
          _buildFlattenedPreviewCard(height: 160),
          const SizedBox(height: 12),
        ],
        // Scanned image thumbnail
        if (_selectedImage != null) ...[
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_selectedImage!, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Info banner about the workflow
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_rounded, color: Colors.blue.shade600, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Review and correct any details below. Once you confirm, a pharmacist or connected care team member will verify this before the medication is added to your list.',
              style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
            )),
          ]),
        ),
        const SizedBox(height: 16),
        // Prescription metadata (read-only)
        if (r.prescribedBy != null || r.pharmacy != null || r.refillsRemaining != null)
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('From label', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                if (r.prescribedBy != null)     _metaRow(Icons.medical_services_outlined, 'Prescriber',        r.prescribedBy!),
                if (r.pharmacy != null)         _metaRow(Icons.local_pharmacy_outlined,   'Pharmacy',          r.pharmacy!),
                if (r.refillsRemaining != null) _metaRow(Icons.refresh_rounded,           'Refills remaining', r.refillsRemaining!),
              ]),
            ),
          ),
        if (r.ocrProviderChain != null || r.requiresHumanReview == true)
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Scan quality', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                if (r.ocrProviderChain != null && r.ocrProviderChain!.isNotEmpty)
                  _metaRow(Icons.layers_outlined, 'OCR providers', r.ocrProviderChain!.join(' -> ')),
                if (r.qualityGate != null && r.qualityGate!['reason'] != null)
                  _metaRow(Icons.analytics_outlined, 'QC status', r.qualityGate!['reason'].toString()),
                if (r.medicationNameMatched != null || r.medicationNameSource != null || r.medicationNameRxcui != null)
                  _metaRow(
                    Icons.medication_liquid_outlined,
                    'Name match',
                    [
                      if (r.medicationNameMatched != null) (r.medicationNameMatched! ? 'matched' : 'unmatched'),
                      if (r.medicationNameConfidence != null && r.medicationNameConfidence!.isNotEmpty)
                        'confidence: ${r.medicationNameConfidence}',
                      if (r.medicationNameMatchScore != null) 'score: ${r.medicationNameMatchScore!.toStringAsFixed(2)}',
                    ].join('  •  '),
                  ),
                if (r.medicationNameSource != null && r.medicationNameSource!.isNotEmpty)
                  _metaRow(Icons.hub_outlined, 'Name source', r.medicationNameSource!),
                if (r.medicationNameRxcui != null && r.medicationNameRxcui!.isNotEmpty)
                  _metaRow(Icons.badge_outlined, 'RxCUI', r.medicationNameRxcui!),
                if (r.requiresHumanReview == true)
                  _metaRow(Icons.fact_check_outlined, 'Review', 'Required before auto-fill acceptance'),
              ]),
            ),
          ),
        // Editable fields
        Text('Medication details', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Correct anything that was misread by the scanner', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Medication name', prefixIcon: Icon(Icons.medication_outlined), border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _dosageCtrl,
          decoration: const InputDecoration(labelText: 'Dosage', prefixIcon: Icon(Icons.scale_rounded), border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _instructionsCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Directions / instructions', prefixIcon: Icon(Icons.list_alt_rounded), border: OutlineInputBorder()),
        ),
        const SizedBox(height: 20),
        // Note for reviewer
        Text('Note for reviewer (optional)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        TextField(
          controller: _patientNoteCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'e.g. New medication, first time taking it',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        // Patient acknowledgment
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: _patientConfirmed ? Colors.green.shade300 : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
            color: _patientConfirmed ? Colors.green.shade50 : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: CheckboxListTile(
              value: _patientConfirmed,
              onChanged: (v) => setState(() => _patientConfirmed = v ?? false),
              title: const Text('I confirm these details are accurate to the best of my knowledge'),
              subtitle: const Text('You are responsible for reviewing the extracted information before submission.'),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: Colors.green,
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _patientConfirmed ? _submitForVerification : null,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Submit for verification'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setState(() { _phase = _ScanPhase.imageSelected; _result = null; }),
            icon: const Icon(Icons.document_scanner_rounded),
            label: const Text('Scan again'),
          ),
        ),
      ]),
    );
  }

  Widget _buildFlattenedPreviewCard({required double height}) {
    final bytes = _labelPreviewBytes;
    if (bytes == null) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: () => _openFlattenedPreview(bytes),
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(bytes, fit: BoxFit.contain),
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Flattened OCR crop',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Tap to enlarge',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openFlattenedPreview(Uint8List bytes) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(10),
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: Colors.black,
                    child: InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 5.0,
                      child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: IconButton.filled(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSubmitted() => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
        child: const Icon(Icons.check_circle_rounded, size: 72, color: Colors.green),
      ),
      const SizedBox(height: 24),
      Text('Submitted for verification',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center),
      const SizedBox(height: 12),
      Text(
        'Your prescription has been submitted. A pharmacist or connected care team member will review and verify the details. Once approved, the medication will automatically be added to your list.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
      ),
      const SizedBox(height: 32),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        onPressed: () => context.push('/prescription-queue'),
        icon: const Icon(Icons.pending_actions_rounded),
        label: const Text('View verification queue'),
      )),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: () => context.go('/dashboard'),
        icon: const Icon(Icons.home_rounded),
        label: const Text('Back to dashboard'),
      )),
    ]),
  );

  // ── Viewfinder ────────────────────────────────────────────────────────────────

  Widget _buildViewfinder(File? image, {required bool scanning}) {
    final borderColor = scanning
        ? Color.lerp(Colors.green.shade300, Colors.green.shade600, _pulse.value)!
        : Colors.grey.shade300;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: scanning ? 2.5 : 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: image != null
            ? SizedBox(
                height: 320,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      child: Image.file(image, width: double.infinity, fit: BoxFit.contain),
                    ),
                    _buildCenterGuideOverlay(),
                    if (scanning) _buildScanOverlay(),
                  ],
                ),
              )
            : Container(
                height: 200,
                alignment: Alignment.center,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.document_scanner_outlined, size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 10),
                  Text('No image selected', style: TextStyle(color: Colors.grey.shade500)),
                ]),
              ),
      ),
    );
  }

  Widget _buildCameraPreviewCard() {
    final controller = _cameraController;
    if (kIsWeb) {
      return Container(
        width: double.infinity,
        height: 320,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text('Live camera scanning is available on iPhone and Android only.', style: TextStyle(color: Colors.grey.shade600)),
      );
    }
    if (_cameraError != null) {
      return Container(
        width: double.infinity,
        height: 320,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.no_photography_rounded, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('Camera unavailable', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              _cameraError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ]),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        width: double.infinity,
        height: 320,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text('Starting camera…', style: TextStyle(color: Colors.grey.shade600)),
        ]),
      );
    }
    return SizedBox(
      height: 360,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CameraPreview(controller),
          ),
          _buildCenterGuideOverlay(),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Container(
                key: ValueKey<String>(_cameraStatus ?? 'status'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _cameraStatus ?? 'Hold the label steady until the camera locks it.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanOverlay() => Positioned.fill(
    child: CustomPaint(
      painter: _ScanOverlayPainter(scanProgress: _scanLine.value, opacity: _pulse.value),
    ),
  );

  Widget _buildCenterGuideOverlay() => Positioned.fill(
    child: IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final guideWidth = width * 0.56;
          final left = (width - guideWidth) / 2;
          final right = left + guideWidth;
          return Stack(children: [
            Positioned(
              left: left,
              top: 10,
              bottom: 10,
              child: Container(width: 2, color: Colors.white.withValues(alpha: 0.85)),
            ),
            Positioned(
              left: right,
              top: 10,
              bottom: 10,
              child: Container(width: 2, color: Colors.white.withValues(alpha: 0.85)),
            ),
            Positioned(
              left: left + 4,
              right: width - right + 4,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: Colors.black.withValues(alpha: 0.35),
                child: const Text(
                  'Keep label text in this center zone',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ]);
        },
      ),
    ),
  );

  Widget _errorBox(String msg) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
    child: Text(msg, style: const TextStyle(color: Colors.red, fontSize: 13)),
  );

  Widget _metaRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Icon(icon, size: 15, color: Colors.grey.shade500),
      const SizedBox(width: 8),
      Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
    ]),
  );
}

/// Paints the animated scan-line + corner brackets over the viewfinder.
class _ScanOverlayPainter extends CustomPainter {
  _ScanOverlayPainter({required this.scanProgress, required this.opacity});
  final double scanProgress;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final green      = Colors.green.withValues(alpha: opacity * 0.9);
    final linePaint  = Paint()..color = green..strokeWidth = 2.5..style = PaintingStyle.stroke;
    final cornerPaint = Paint()..color = Colors.green.withValues(alpha: opacity)..strokeWidth = 4..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;

    final y = size.height * scanProgress;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, y),
        Paint()..color = Colors.green.withValues(alpha: 0.06));

    const len = 28.0, margin = 12.0;
    void corner(double cx, double cy, double dx, double dy) {
      canvas.drawLine(Offset(cx, cy), Offset(cx + dx * len, cy), cornerPaint);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy + dy * len), cornerPaint);
    }
    corner(margin, margin, 1, 1);
    corner(size.width - margin, margin, -1, 1);
    corner(margin, size.height - margin, 1, -1);
    corner(size.width - margin, size.height - margin, -1, -1);
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter old) =>
      old.scanProgress != scanProgress || old.opacity != opacity;
}

// \u2500\u2500 Prescription review (verifier) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

class PrescriptionReviewScreen extends ConsumerStatefulWidget {
  const PrescriptionReviewScreen({super.key, required this.prescriptionId});
  final int prescriptionId;
  @override
  ConsumerState<PrescriptionReviewScreen> createState() => _PrescriptionReviewScreenState();
}

class _PrescriptionReviewScreenState extends ConsumerState<PrescriptionReviewScreen> {
  void _showApproveDialog(BuildContext context, PendingPrescription p) {
    final verifierCtrl = TextEditingController(text: 'Pharmacist / Caregiver');
    final noteCtrl     = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve prescription'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'You are approving "${p.medicationName} ${p.dosage}" for this patient. This will add it to their active medication list.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: verifierCtrl,
            decoration: const InputDecoration(labelText: 'Your name / role', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Note for patient (optional)', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final verifier = verifierCtrl.text.trim();
              if (verifier.isEmpty) return;
              ref.read(pendingPrescriptionsProvider.notifier).approve(
                p.id,
                verifiedBy: verifier,
                note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
              );
              // Add the medication to the active list
              final med = Medication(
                id: DateTime.now().millisecondsSinceEpoch,
                userId: ref.read(userIdProvider),
                name: p.medicationName,
                dosage: p.dosage,
                instructions: p.instructions,
              );
              ref.read(syntheticMedicationProvider.notifier).addMedication(med);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${p.medicationName} approved and added to the medication list')),
              );
              context.go('/prescription-queue');
            },
            child: const Text('Confirm approval'),
          ),
        ],
      ),
    ).whenComplete(() { verifierCtrl.dispose(); noteCtrl.dispose(); });
  }

  void _showRejectDialog(BuildContext context, PendingPrescription p) {
    final verifierCtrl = TextEditingController(text: 'Pharmacist / Caregiver');
    final reasonCtrl   = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject prescription'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'You are rejecting "${p.medicationName} ${p.dosage}". The patient will be notified with your reason.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: verifierCtrl,
            decoration: const InputDecoration(labelText: 'Your name / role', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reasonCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Reason for rejection (required)', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              final verifier = verifierCtrl.text.trim();
              final reason   = reasonCtrl.text.trim();
              if (verifier.isEmpty || reason.isEmpty) return;
              ref.read(pendingPrescriptionsProvider.notifier).reject(p.id, verifiedBy: verifier, reason: reason);
              // Notify the patient via the alerts feed
              ref.read(alertsProvider.notifier).add(MedicationAlert(
                title: 'Prescription rejected: ${p.medicationName}',
                message: 'Reason: $reason (reviewed by $verifier).',
                severity: 'High',
              ));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${p.medicationName} rejected. Patient has been notified.')),
              );
              context.go('/prescription-queue');
            },
            child: const Text('Confirm rejection'),
          ),
        ],
      ),
    ).whenComplete(() { verifierCtrl.dispose(); reasonCtrl.dispose(); });
  }

  @override
  Widget build(BuildContext context) {
    final prescriptions = ref.watch(pendingPrescriptionsProvider);
    final p = prescriptions.firstWhere(
      (x) => x.id == widget.prescriptionId,
      orElse: () => PendingPrescription(
        id: 0, medicationName: 'Unknown', dosage: '', scannedAt: DateTime.now(),
      ),
    );

    final statusColor = switch (p.status) {
      VerificationStatus.awaitingVerifier => Colors.orange,
      VerificationStatus.approved         => Colors.green,
      VerificationStatus.rejected         => Colors.red,
      VerificationStatus.awaitingPatient  => Colors.blue,
    };
    final statusLabel = switch (p.status) {
      VerificationStatus.awaitingVerifier => 'Awaiting verification',
      VerificationStatus.approved         => 'Approved',
      VerificationStatus.rejected         => 'Rejected',
      VerificationStatus.awaitingPatient  => 'Awaiting patient confirmation',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review prescription'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              label: Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 12)),
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
            Text('Scanned label image', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(p.imageFilePath!), height: 200, width: double.infinity, fit: BoxFit.cover),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Container(
              height: 80,
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text('No image available', style: TextStyle(color: Colors.grey.shade500))),
            ),
            const SizedBox(height: 16),
          ],
          // Prescription details
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.medication_rounded, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(p.medicationName, style: Theme.of(context).textTheme.titleMedium)),
                ]),
                if (p.dosage.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(p.dosage, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                ],
                if (p.instructions != null) ...[
                  const Divider(height: 20),
                  Text('Directions', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Text(p.instructions!),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 12),
          // Prescription source metadata
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Prescription info', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                if (p.prescribedBy != null)     _row(Icons.medical_services_outlined, 'Prescriber',        p.prescribedBy!),
                if (p.pharmacy != null)         _row(Icons.local_pharmacy_outlined,   'Pharmacy',          p.pharmacy!),
                if (p.refillsRemaining != null) _row(Icons.refresh_rounded,           'Refills remaining', p.refillsRemaining!),
                _row(Icons.schedule_rounded, 'Scanned', _relDate(p.scannedAt)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          // Patient note
          if (p.patientNote != null) ...[
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.person_rounded, size: 16, color: Colors.blue.shade600),
                    const SizedBox(width: 6),
                    Text('Patient note', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue.shade700, fontSize: 13)),
                  ]),
                  const SizedBox(height: 6),
                  Text(p.patientNote!, style: const TextStyle(fontSize: 13)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Verifier result
          if (p.verifiedBy != null) ...[
            Card(
              color: p.status == VerificationStatus.approved ? Colors.green.shade50 : Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(p.status == VerificationStatus.approved ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        size: 16, color: p.status == VerificationStatus.approved ? Colors.green : Colors.red),
                    const SizedBox(width: 6),
                    Text(
                      p.status == VerificationStatus.approved ? 'Approved by ${p.verifiedBy}' : 'Rejected by ${p.verifiedBy}',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                          color: p.status == VerificationStatus.approved ? Colors.green.shade700 : Colors.red.shade700),
                    ),
                  ]),
                  if (p.verifierNote != null) ...[
                    const SizedBox(height: 6),
                    Text(p.verifierNote!, style: const TextStyle(fontSize: 13)),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Action buttons
          if (p.status == VerificationStatus.awaitingVerifier) ...[
            Row(children: [
              Expanded(child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () => _showApproveDialog(context, p),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Approve'),
              )),
              const SizedBox(width: 12),
              Expanded(child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => _showRejectDialog(context, p),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Reject'),
              )),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Icon(icon, size: 15, color: Colors.grey.shade500),
      const SizedBox(width: 8),
      Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
    ]),
  );

  String _relDate(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24)   return '${d.inHours} hr ago';
    return '${d.inDays} day(s) ago';
  }
}

// \u2500\u2500 Prescription verification queue \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

class PrescriptionQueueScreen extends ConsumerWidget {
  const PrescriptionQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prescriptions = ref.watch(pendingPrescriptionsProvider);

    final awaiting  = prescriptions.where((p) => p.status == VerificationStatus.awaitingVerifier).toList();
    final approved  = prescriptions.where((p) => p.status == VerificationStatus.approved).toList();
    final rejected  = prescriptions.where((p) => p.status == VerificationStatus.rejected).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Verification queue')),
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
                child: Column(children: [
                  Icon(Icons.check_circle_outlined, size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text('No prescriptions pending', style: TextStyle(color: Colors.grey.shade600)),
                ]),
              ),
            ),
          if (awaiting.isNotEmpty) ...[
            _sectionHeader(context, 'Awaiting verification (${awaiting.length})', Colors.orange),
            ...awaiting.map((p) => _prescriptionCard(context, ref, p)),
            const SizedBox(height: 12),
          ],
          if (approved.isNotEmpty) ...[
            _sectionHeader(context, 'Approved (${approved.length})', Colors.green),
            ...approved.map((p) => _prescriptionCard(context, ref, p)),
            const SizedBox(height: 12),
          ],
          if (rejected.isNotEmpty) ...[
            _sectionHeader(context, 'Rejected (${rejected.length})', Colors.red),
            ...rejected.map((p) => _prescriptionCard(context, ref, p)),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Container(width: 4, height: 18, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _prescriptionCard(BuildContext context, WidgetRef ref, PendingPrescription p) {
    final statusColor = switch (p.status) {
      VerificationStatus.awaitingVerifier => Colors.orange,
      VerificationStatus.approved         => Colors.green,
      VerificationStatus.rejected         => Colors.red,
      VerificationStatus.awaitingPatient  => Colors.blue,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/prescription-review/${p.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: p.imageFilePath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(File(p.imageFilePath!), fit: BoxFit.cover),
                    )
                  : Icon(Icons.medication_rounded, color: statusColor),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.medicationName, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(p.dosage, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              if (p.prescribedBy != null)
                Text(p.prescribedBy!, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(
                  p.status == VerificationStatus.awaitingVerifier ? 'Review' : p.status.name,
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 11),
                ),
              ),
              const SizedBox(height: 4),
              Text(_relDate(p.scannedAt), style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
            ]),
          ]),
        ),
      ),
    );
  }

  String _relDate(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24)   return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

// ── Settings ───────────────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notifications = true;
  late final TextEditingController _alertPhoneController;

  @override
  void initState() {
    super.initState();
    _alertPhoneController = TextEditingController(text: ref.read(alertPhoneProvider));
  }

  @override
  void dispose() {
    _alertPhoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (currentUser != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      currentUser.fullName.isNotEmpty ? currentUser.fullName[0].toUpperCase() : '?',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(currentUser.fullName, style: Theme.of(context).textTheme.titleMedium),
                    Text(currentUser.email, style: Theme.of(context).textTheme.bodySmall),
                    if (currentUser.phone != null) Text(currentUser.phone!, style: Theme.of(context).textTheme.bodySmall),
                  ])),
                ]),
              ),
            ),
            const SizedBox(height: 16),
          ],
          SwitchListTile(
            value: _notifications,
            title: const Text('Push notifications'),
            subtitle: const Text('Receive dose reminders'),
            onChanged: (v) => setState(() => _notifications = v),
          ),
          const Divider(),
          const SizedBox(height: 8),
          TextField(
            controller: _alertPhoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'SMS alert phone number',
              prefixIcon: Icon(Icons.phone_iphone_rounded),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => ref.read(alertPhoneProvider.notifier).update(v),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              ref.read(alertPhoneProvider.notifier).update(_alertPhoneController.text);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alert phone number saved')));
            },
            icon: const Icon(Icons.check_rounded),
            label: const Text('Save alert number'),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => context.go('/login'),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }
}
