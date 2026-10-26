import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';
import 'medication_repository.dart'
    show medicationsByUserProvider, scheduleByUserProvider;

class AdheraInventorySlot {
  const AdheraInventorySlot({
    required this.id,
    required this.userId,
    required this.dayOfWeek,
    required this.period,
    required this.medicationId,
    required this.medicationName,
    required this.pillCount,
  });

  final int id;
  final int userId;
  final String dayOfWeek;
  final String period;
  final int medicationId;
  final String medicationName;
  final int pillCount;

  factory AdheraInventorySlot.fromJson(Map<String, dynamic> json) {
    return AdheraInventorySlot(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      dayOfWeek: json['day_of_week'] as String,
      period: json['period'] as String,
      medicationId: json['medication_id'] as int,
      medicationName: json['medication_name'] as String,
      pillCount: json['pill_count'] as int,
    );
  }
}

class AdheraInventoryRepository {
  AdheraInventoryRepository(this._apiService);

  final ApiService _apiService;

  Future<List<AdheraInventorySlot>> getInventory(int userId) async {
    final response = await _apiService.get<List<dynamic>>(
      '/adhera/$userId/inventory',
    );
    return (response.data ?? const <dynamic>[])
        .map(
          (item) => AdheraInventorySlot.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<List<AdheraInventorySlot>> initializeTestInventory(int userId) async {
    try {
      final response = await _apiService.dio.post<List<dynamic>>(
        '/adhera/$userId/initialize-test-inventory',
      );
      return (response.data ?? const <dynamic>[])
          .map(
            (item) => AdheraInventorySlot.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}

final adheraInventoryRepositoryProvider = Provider<AdheraInventoryRepository>((
  ref,
) {
  return AdheraInventoryRepository(ref.watch(apiServiceProvider));
});

final adheraInventoryProvider =
    FutureProvider.family<List<AdheraInventorySlot>, int>((ref, userId) async {
      final repository = ref.watch(adheraInventoryRepositoryProvider);
      final slots = await repository.getInventory(userId);
      if (slots.length == 14) return slots;
      final initialized = await repository.initializeTestInventory(userId);
      ref.invalidate(medicationsByUserProvider(userId));
      ref.invalidate(scheduleByUserProvider(userId));
      return initialized;
    });
