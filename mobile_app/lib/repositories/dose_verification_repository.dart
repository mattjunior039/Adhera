import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';

class DoseVerificationEvent {
  const DoseVerificationEvent({
    required this.id,
    required this.userId,
    this.medicationId,
    this.scheduleId,
    this.recognizedMedication,
    this.inventoryUpdated = false,
    this.prototype,
    this.reason,
    this.destinationLabel,
    this.compartmentIndex,
    this.assumedLabel,
    this.expectedLabel,
    this.amRow,
    required this.periodConfident,
    required this.orientationCalibrated,
    required this.wrongSlot,
    this.preCount,
    this.postCount,
    required this.eventType,
    required this.confidence,
    required this.requiresReview,
    required this.framesSampled,
    required this.framesAccepted,
    required this.createdAt,
  });

  final int id;
  final int userId;
  final int? medicationId;
  final int? scheduleId;
  final String? recognizedMedication;
  final bool inventoryUpdated;
  final String? prototype;
  final String? reason;
  final String? destinationLabel;
  final int? compartmentIndex;
  // Grid-position guess only (e.g. "SUN_AM"); unverified against printed labels.
  final String? assumedLabel;
  // Derived from the linked schedule, if any — what slot the user said they'd verify.
  final String? expectedLabel;
  final int? amRow;
  // False when the AM/PM color read was ambiguous; calibration/wrong-slot are skipped.
  final bool periodConfident;
  final bool orientationCalibrated;
  final bool wrongSlot;
  final int? preCount;
  final int? postCount;
  final String eventType;
  final double confidence;
  final bool requiresReview;
  final int framesSampled;
  final int framesAccepted;
  final DateTime createdAt;

  factory DoseVerificationEvent.fromJson(Map<String, dynamic> json) {
    return DoseVerificationEvent(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      medicationId: json['medication_id'] as int?,
      scheduleId: json['schedule_id'] as int?,
      recognizedMedication: json['recognized_medication'] as String?,
      inventoryUpdated: json['inventory_updated'] as bool? ?? false,
      prototype: json['prototype'] as String?,
      reason: json['reason'] as String?,
      destinationLabel: json['destination_label'] as String?,
      compartmentIndex: json['compartment_index'] as int?,
      assumedLabel: json['assumed_label'] as String?,
      expectedLabel: json['expected_label'] as String?,
      amRow: json['am_row'] as int?,
      periodConfident: json['period_confident'] as bool,
      orientationCalibrated: json['orientation_calibrated'] as bool,
      wrongSlot: json['wrong_slot'] as bool,
      preCount: json['pre_count'] as int?,
      postCount: json['post_count'] as int?,
      eventType: json['event_type'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      requiresReview: json['requires_review'] as bool,
      framesSampled: json['frames_sampled'] as int,
      framesAccepted: json['frames_accepted'] as int,
      createdAt: parseServerDateTime(json['created_at'] as String),
    );
  }
}

class AdheraOrientationProfile {
  const AdheraOrientationProfile({
    required this.userId,
    required this.columnOrder,
  });

  final int userId;
  // "forward" (canonical column 0 = SUN) | "reversed" (canonical column 0 = SAT)
  final String columnOrder;

  factory AdheraOrientationProfile.fromJson(Map<String, dynamic> json) {
    return AdheraOrientationProfile(
      userId: json['user_id'] as int,
      columnOrder: json['column_order'] as String,
    );
  }
}

class DoseVerificationRepository {
  DoseVerificationRepository(this._apiService);

  final ApiService _apiService;

  /// Record a short open -> remove pill -> close clip. Uses the rear camera; no
  /// duration/quality guidance beyond what the OS camera UI already provides.
  Future<XFile?> recordVerificationVideo() async {
    final picker = ImagePicker();
    return picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(seconds: 20),
    );
  }

  Future<XFile?> pickVerificationVideoFromGallery() async {
    final picker = ImagePicker();
    return picker.pickVideo(source: ImageSource.gallery);
  }

  Future<DoseVerificationEvent> analyzeVideo({
    required int userId,
    required File videoFile,
    required int compartmentId,
    int? medicationId,
    int? scheduleId,
    List<double>? phaseWindows,
  }) async {
    final fields = <String, dynamic>{'user_id': userId};
    if (medicationId != null) fields['medication_id'] = medicationId;
    if (scheduleId != null) fields['schedule_id'] = scheduleId;
    fields['compartment_id'] = compartmentId;
    if (phaseWindows != null) {
      if (phaseWindows.length != 4 ||
          phaseWindows.any((value) => !value.isFinite) ||
          !(0 <= phaseWindows[0] &&
              phaseWindows[0] < phaseWindows[1] &&
              phaseWindows[1] < phaseWindows[2] &&
              phaseWindows[2] < phaseWindows[3] &&
              phaseWindows[3] <= 120)) {
        throw const FormatException('Invalid before/after time intervals');
      }
      const names = ['before_start', 'before_end', 'after_start', 'after_end'];
      for (var index = 0; index < names.length; index++) {
        fields[names[index]] = phaseWindows[index];
      }
    }
    fields['file'] = await MultipartFile.fromFile(
      videoFile.path,
      filename: videoFile.uri.pathSegments.last,
    );
    final formData = FormData.fromMap(fields);

    try {
      final response = await _apiService.dio.post<Map<String, dynamic>>(
        '/dose-verification/analyze-video',
        data: formData,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
          // Model inference needs more time than a photo upload.
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 60),
        ),
      );
      if (response.data == null) {
        throw const FormatException('Dose verification response was empty');
      }
      return DoseVerificationEvent.fromJson(response.data!);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<DoseVerificationEvent>> getEventsForUser(int userId) async {
    final response = await _apiService.get<List<dynamic>>(
      '/dose-verification/$userId',
    );
    final items = response.data ?? const <dynamic>[];
    return items
        .map(
          (item) => DoseVerificationEvent.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<AdheraOrientationProfile?> getOrientationProfile(int userId) async {
    final response = await _apiService.get<Map<String, dynamic>>(
      '/adhera-orientation/$userId',
    );
    final data = response.data;
    return data == null ? null : AdheraOrientationProfile.fromJson(data);
  }

  /// Manually set/correct which direction the Adhera columns run for this user
  /// (e.g. after a WRONG_SLOT false alarm caused by bad auto-calibration).
  Future<AdheraOrientationProfile> setOrientationProfile({
    required int userId,
    required String columnOrder,
  }) async {
    try {
      final response = await _apiService.dio.put<Map<String, dynamic>>(
        '/adhera-orientation/$userId',
        data: {'column_order': columnOrder},
      );
      if (response.data == null) {
        throw const FormatException('Orientation update response was empty');
      }
      return AdheraOrientationProfile.fromJson(response.data!);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}

final doseVerificationRepositoryProvider = Provider<DoseVerificationRepository>(
  (ref) {
    final apiService = ref.watch(apiServiceProvider);
    return DoseVerificationRepository(apiService);
  },
);

final doseVerificationEventsProvider =
    FutureProvider.family<List<DoseVerificationEvent>, int>((ref, userId) {
      return ref
          .watch(doseVerificationRepositoryProvider)
          .getEventsForUser(userId);
    });
