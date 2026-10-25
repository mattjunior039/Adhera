import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/schedule.dart';
import '../repositories/medication_repository.dart';
import '../repositories/sample_day_provider.dart';
import '../widgets/weekly_schedule.dart';

class MedicationAlert {
  const MedicationAlert({
    required this.title,
    required this.message,
    required this.severity,
  });
  final String title;
  final String message;
  final String severity;
}

class CaregiverProfile {
  const CaregiverProfile({
    required this.name,
    required this.relation,
    required this.status,
    this.phone,
  });
  final String name;
  final String relation;
  final String status;
  final String? phone;
}

class AlertsNotifier extends Notifier<List<MedicationAlert>> {
  @override
  List<MedicationAlert> build() => const [];

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
  List<CaregiverProfile> build() => const [];

  void inviteCaregiver({
    required String name,
    required String relation,
    required String phone,
  }) {
    state = [
      ...state,
      CaregiverProfile(
        name: name,
        relation: relation,
        status: 'Invited',
        phone: phone,
      ),
    ];
  }
}

final caregiversProvider =
    NotifierProvider<CaregiverProfilesNotifier, List<CaregiverProfile>>(
      () => CaregiverProfilesNotifier(),
    );

// Backend adherence, or session-only completion states for the sample Wednesday.
final todayAdherenceProvider = FutureProvider<Map<int, String>>((ref) async {
  final userId = ref.watch(userIdProvider);
  if (ref.watch(isSampleProfileProvider)) {
    final overrides = ref.watch(sampleDoseStatusesProvider);
    final schedulesFuture = ref.watch(scheduleByUserProvider(userId).future);
    final medicationsFuture = ref.watch(
      medicationsByUserProvider(userId).future,
    );
    final schedules = await schedulesFuture;
    final medications = await medicationsFuture;
    final names = {
      for (final med in medications) med.id: med.name.toLowerCase(),
    };
    return {
      for (final schedule in schedules)
        if (schedule.dayOfWeek == 'Wednesday' &&
            schedule.notes?.startsWith('DEMO ONLY:') == true &&
            int.parse(schedule.timeOfDay.split(':').first) < 12)
          schedule.id: names[schedule.medicationId] == 'ibuprofen'
              ? 'missed'
              : 'taken',
      ...overrides,
    };
  }
  return ref.read(medicationRepositoryProvider).getTodayAdherence(userId);
});

final activeMedicationAlertsProvider = Provider<List<MedicationAlert>>((ref) {
  final userId = ref.watch(userIdProvider);
  final schedules =
      ref.watch(scheduleByUserProvider(userId)).asData?.value ??
      const <Schedule>[];
  final medications = ref
      .watch(medicationsByUserProvider(userId))
      .asData
      ?.value;
  final statuses =
      ref.watch(todayAdherenceProvider).asData?.value ?? const <int, String>{};
  final todayName = const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][ref.watch(displayedWeekdayProvider) - 1];
  return [
    ...ref.watch(alertsProvider),
    for (final schedule in schedules)
      if (schedule.dayOfWeek == todayName && statuses[schedule.id] == 'missed')
        MedicationAlert(
          title:
              '${medications?.where((med) => med.id == schedule.medicationId).firstOrNull?.name ?? 'Medication'} not taken',
          message:
              'The $todayName ${scheduleTimeLabel(schedule.timeOfDay)} dose was missed. Review today\'s schedule.',
          severity: 'High',
        ),
  ];
});

class AlertPhoneNotifier extends Notifier<String> {
  @override
  String build() => '6084485111';
  void update(String value) => state = value.trim();
}

final alertPhoneProvider = NotifierProvider<AlertPhoneNotifier, String>(
  () => AlertPhoneNotifier(),
);
