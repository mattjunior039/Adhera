import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'repositories/dose_verification_repository.dart';
import 'repositories/image_upload_repository.dart';
import 'screens/add_medication_screen.dart';
import 'screens/alerts_list_screen.dart';
import 'screens/analyze_pill_screen.dart';
import 'screens/caregiver_screen.dart';
import 'screens/dose_verification_screen.dart';
import 'screens/event_result_screen.dart';
import 'screens/home_dashboard_screen.dart';
import 'screens/image_upload_screen.dart';
import 'screens/login_signup_screen.dart';
import 'screens/medication_detail_screen.dart';
import 'screens/prescription_queue_screen.dart';
import 'screens/prescription_review_screen.dart';
import 'screens/prescription_scan_screen.dart';
import 'screens/schedule_setup_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/verification_history_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginSignupScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const HomeDashboardScreen(),
      ),
      GoRoute(
        path: '/add-medication',
        builder: (context, state) => const AddMedicationScreen(),
      ),
      GoRoute(
        path: '/analyze-pill',
        builder: (context, state) => const AnalyzePillScreen(),
      ),
      GoRoute(
        path: '/schedule',
        builder: (_, state) => ScheduleSetupScreen(
          preselectedMedicationId: state.extra is int
              ? state.extra as int
              : null,
        ),
      ),
      GoRoute(
        path: '/capture-photo',
        builder: (context, state) => const ImageUploadScreen(),
      ),
      GoRoute(
        path: '/verify-video-dose',
        builder: (context, state) => const DoseVerificationVideoScreen(),
      ),
      GoRoute(
        path: '/dose-verification-result',
        builder: (context, state) {
          final result = state.extra as DoseVerificationEvent;
          return DoseVerificationResultScreen(result: result);
        },
      ),
      GoRoute(
        path: '/event-result',
        builder: (_, state) {
          final results = state.extra is List<InferenceResult>
              ? state.extra as List<InferenceResult>
              : const <InferenceResult>[];
          return EventResultScreen(results: results);
        },
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const VerificationHistoryScreen(),
      ),
      GoRoute(
        path: '/alerts',
        builder: (context, state) => const AlertsListScreen(),
      ),
      GoRoute(
        path: '/caregiver',
        builder: (context, state) => const CaregiverScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/scan-prescription',
        builder: (context, state) => const PrescriptionScanScreen(),
      ),
      GoRoute(
        path: '/prescription-queue',
        builder: (context, state) => const PrescriptionQueueScreen(),
      ),
      GoRoute(
        path: '/prescription-review/:id',
        builder: (context, state) => PrescriptionReviewScreen(
          prescriptionId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/medication/:medicationId',
        builder: (_, state) => MedicationDetailScreen(
          medicationId:
              int.tryParse(state.pathParameters['medicationId'] ?? '') ?? 0,
        ),
      ),
    ],
  );
});
