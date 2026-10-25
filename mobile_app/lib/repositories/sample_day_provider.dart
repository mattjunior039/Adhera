import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'medication_repository.dart';

final isSampleProfileProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  return user != null &&
      user.id == ref.watch(userIdProvider) &&
      user.email.toLowerCase() == 'adherasample@gmail.com' &&
      user.fullName == 'Adhera Test';
});

final displayedWeekdayProvider = Provider<int>((ref) {
  return ref.watch(isSampleProfileProvider)
      ? DateTime.wednesday
      : DateTime.now().weekday;
});

class SampleDoseStatuses extends Notifier<Map<int, String>> {
  @override
  Map<int, String> build() {
    ref.watch(currentUserProvider);
    return {};
  }

  void update(int scheduleId, String status) {
    state = {...state, scheduleId: status};
  }
}

final sampleDoseStatusesProvider =
    NotifierProvider<SampleDoseStatuses, Map<int, String>>(
      SampleDoseStatuses.new,
    );
