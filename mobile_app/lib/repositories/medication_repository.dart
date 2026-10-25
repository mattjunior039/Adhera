import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_config.dart';
import '../models/medication.dart';
import '../models/schedule.dart';
import '../models/user.dart';
import '../services/api_service.dart';

export '../services/api_service.dart' show apiServiceProvider;

class MedicationRepository {
  MedicationRepository(this._apiService);

  final ApiService _apiService;

  Future<User> createUser({
    required String email,
    required String fullName,
    String? phone,
    required String password,
  }) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      '/users',
      data: UserCreate(email: email, fullName: fullName, phone: phone).toJson()
        ..addAll({'password': password}),
    );

    if (response.data == null) {
      throw const FormatException('User creation response was empty');
    }

    return User.fromJson(response.data!);
  }

  Future<User> loginUser({
    required String email,
    required String password,
  }) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password},
    );

    if (response.data == null) {
      throw const FormatException('Login response was empty');
    }

    final data = response.data!;
    final userMap = data['user'] ?? data;
    if (userMap is! Map<String, dynamic>) {
      throw const FormatException(
        'Login response did not include a user object',
      );
    }

    if (userMap.containsKey('user_id') && !userMap.containsKey('id')) {
      return User(
        id: userMap['user_id'] as int,
        email: userMap['email'] as String,
        fullName: userMap['full_name'] as String,
        phone: userMap['phone'] as String?,
      );
    }

    return User.fromJson(userMap);
  }

  Future<Medication> createMedication({
    required int userId,
    required String name,
    String? dosage,
    String? instructions,
  }) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      '/medications',
      data: {
        'user_id': userId,
        'name': name,
        'dosage': dosage,
        'instructions': instructions,
      },
    );

    if (response.data == null) {
      throw const FormatException('Medication creation response was empty');
    }

    return Medication.fromJson(response.data!);
  }

  Future<List<Medication>> getMedicationsForUser(int userId) async {
    final response = await _apiService.get<List<dynamic>>(
      '/medications/$userId',
    );
    final items = response.data ?? const <dynamic>[];
    return items
        .map((item) => Medication.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Medication> updateMedication({
    required int medicationId,
    required String name,
    String? dosage,
    String? instructions,
  }) async {
    final response = await _apiService.put<Map<String, dynamic>>(
      '/medications/$medicationId',
      data: {'name': name, 'dosage': dosage, 'instructions': instructions},
    );
    if (response.data == null) {
      throw const FormatException('Update response was empty');
    }
    return Medication.fromJson(response.data!);
  }

  /// Log a manual dose outcome (taken/missed/unknown) against a schedule slot.
  Future<void> logDose({
    required int userId,
    required int scheduleId,
    required String status,
    double confidence = 1.0,
    String? notes,
  }) async {
    await _apiService.post<Map<String, dynamic>>(
      '/adherence/log',
      data: {
        'user_id': userId,
        'schedule_id': scheduleId,
        'status': status,
        'confidence': confidence,
        'notes': notes,
      },
    );
  }

  /// Returns a map of scheduleId → status for today's logged outcomes.
  /// Returns empty map if the backend is unreachable.
  Future<Map<int, String>> getTodayAdherence(int userId) async {
    final response = await _apiService.get<List<dynamic>>(
      '/adherence/today/$userId',
    );
    final items = response.data ?? const <dynamic>[];
    final result = <int, String>{};
    for (final item in items) {
      if (item is Map<String, dynamic>) {
        final sid = item['schedule_id'] as int?;
        final st = item['status'] as String?;
        if (sid != null && st != null) result[sid] = st;
      }
    }
    return result;
  }

  Future<Schedule> createSchedule({
    required int userId,
    required int medicationId,
    required String dayOfWeek,
    required String timeOfDay,
    String? notes,
  }) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      '/schedules',
      data: {
        'user_id': userId,
        'medication_id': medicationId,
        'day_of_week': dayOfWeek,
        'time_of_day': timeOfDay,
        'notes': notes,
      },
    );

    if (response.data == null) {
      throw const FormatException('Schedule creation response was empty');
    }

    return Schedule.fromJson(response.data!);
  }

  Future<List<Schedule>> getScheduleForUser(int userId) async {
    final response = await _apiService.get<List<dynamic>>('/schedule/$userId');
    final items = response.data ?? const <dynamic>[];
    return items
        .map((item) => Schedule.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}

final medicationRepositoryProvider = Provider<MedicationRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return MedicationRepository(apiService);
});

final medicationsByUserProvider = FutureProvider.family<List<Medication>, int>((
  ref,
  userId,
) async {
  final repo = ref.watch(medicationRepositoryProvider);
  return repo.getMedicationsForUser(userId);
});

final scheduleByUserProvider = FutureProvider.family<List<Schedule>, int>((
  ref,
  userId,
) async {
  final repo = ref.watch(medicationRepositoryProvider);
  return repo.getScheduleForUser(userId);
});

class CurrentUserNotifier extends Notifier<User?> {
  @override
  User? build() => null;

  void setUser(User user) => state = user;

  void clear() => state = null;
}

final currentUserProvider = NotifierProvider<CurrentUserNotifier, User?>(
  () => CurrentUserNotifier(),
);

class UserIdNotifier extends Notifier<int> {
  @override
  int build() => AppConfig.defaultUserId;

  void setUserId(int userId) => state = userId;
}

class UserEmailNotifier extends Notifier<String> {
  @override
  String build() => AppConfig.defaultUserEmail;

  void setUserEmail(String email) => state = email;
}

final userIdProvider = NotifierProvider<UserIdNotifier, int>(
  () => UserIdNotifier(),
);
final userEmailProvider = NotifierProvider<UserEmailNotifier, String>(
  () => UserEmailNotifier(),
);
