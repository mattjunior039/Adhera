import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';

class UploadImageResult {
  const UploadImageResult({required this.photoEventId, required this.message});

  final int photoEventId;
  final String message;

  factory UploadImageResult.fromJson(Map<String, dynamic> json) {
    return UploadImageResult(
      photoEventId: json['photo_event_id'] as int,
      message: json['message'] as String,
    );
  }
}

class InferenceResult {
  const InferenceResult({
    required this.id,
    required this.photoEventId,
    required this.baselineEventId,
    required this.compartmentIndex,
    required this.isChanged,
    required this.confidence,
    this.state,
    this.qualityScore,
  });

  final int id;
  final int photoEventId;
  final int baselineEventId;
  final int compartmentIndex;
  final bool isChanged;
  final double confidence;
  // "changed" | "unchanged" | "occluded" | "low_quality"; null for legacy results.
  final String? state;
  final double? qualityScore;

  bool get isOccluded => state == 'occluded' || state == 'low_quality';

  factory InferenceResult.fromJson(Map<String, dynamic> json) {
    return InferenceResult(
      id: json['id'] as int,
      photoEventId: json['photo_event_id'] as int,
      baselineEventId: json['baseline_event_id'] as int,
      compartmentIndex: json['compartment_index'] as int,
      isChanged: json['is_changed'] as bool,
      confidence: (json['confidence'] as num).toDouble(),
      state: json['state'] as String?,
      qualityScore: (json['quality_score'] as num?)?.toDouble(),
    );
  }
}

class ImageUploadRepository {
  ImageUploadRepository(this._apiService);

  final ApiService _apiService;

  Future<Map<String, dynamic>> _postImageData(
    String path,
    FormData data, {
    required String emptyMessage,
    bool extendedTimeout = false,
  }) async {
    try {
      final response = await _apiService.dio.post<Map<String, dynamic>>(
        path,
        data: data,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
          receiveTimeout: extendedTimeout ? const Duration(seconds: 120) : null,
          sendTimeout: extendedTimeout ? const Duration(seconds: 60) : null,
        ),
      );
      return response.data ?? (throw FormatException(emptyMessage));
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<PillIdentificationResult> identifyPill({
    required File imageFile,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.uri.pathSegments.last,
      ),
    });

    return PillIdentificationResult.fromJson(
      await _postImageData(
        '/pills/identify',
        formData,
        emptyMessage: 'Pill identification response was empty',
        extendedTimeout: true,
      ),
    );
  }

  /// Fast health probe used before OCR uploads to fail quickly when backend is unreachable.
  Future<bool> isBackendReachable() async {
    try {
      final response = await _apiService.dio.get<Map<String, dynamic>>(
        '/health',
        options: Options(
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
          sendTimeout: const Duration(seconds: 3),
        ),
      );
      return response.statusCode == 200;
    } on DioException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Pick an image from camera or gallery.
  /// [imageQuality] 1-100; use 100 for OCR/scanning, null for default (~95%).
  /// [maxDimension] cap longest edge in pixels; 4000 gives sharp text for OCR.
  Future<XFile?> pickImage({
    required ImageSource source,
    int? imageQuality,
    double maxDimension = 4000,
  }) async {
    final picker = ImagePicker();
    return picker.pickImage(
      source: source,
      imageQuality: imageQuality,
      maxWidth: maxDimension,
      maxHeight: maxDimension,
      preferredCameraDevice: CameraDevice.rear,
    );
  }

  /// Compress image for network upload (dose verification: 70%).
  Future<File?> compressImageFile(XFile file) async {
    final filePath = file.path;
    final targetPath = '${filePath}_compressed.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      filePath,
      targetPath,
      quality: 70,
      format: CompressFormat.jpeg,
    );

    return result == null ? null : File(result.path);
  }

  /// Compress image for OCR upload (92% — preserves text sharpness).
  Future<File?> compressForOcr(XFile file) async {
    final targetPath = '${file.path}_ocr.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      file.path,
      targetPath,
      quality: 92,
      format: CompressFormat.jpeg,
      keepExif: true,
    );
    return result == null ? null : File(result.path);
  }

  /// Calls the backend OCR endpoint to extract prescription label details.
  /// Sends multiple full keyframes for semantic text fusion.
  Future<PrescriptionScanResult> scanPrescription({
    required int userId,
    required List<File> imageFiles,
    String? deviceOcrText,
    String? deviceOcrProvider,
  }) async {
    if (imageFiles.isEmpty) {
      throw const FormatException(
        'At least one image file is required for scanning',
      );
    }
    final multipartFiles = <MultipartFile>[];
    for (var i = 0; i < imageFiles.length; i += 1) {
      final image = imageFiles[i];
      multipartFiles.add(
        await MultipartFile.fromFile(image.path, filename: 'view_${i + 1}.jpg'),
      );
    }
    final formData = FormData.fromMap({
      'user_id': userId,
      'files': multipartFiles,
      if (deviceOcrText != null && deviceOcrText.trim().isNotEmpty)
        'device_ocr_text': deviceOcrText.trim(),
      if (deviceOcrProvider != null && deviceOcrProvider.trim().isNotEmpty)
        'device_ocr_provider': deviceOcrProvider.trim(),
    });
    return PrescriptionScanResult.fromJson(
      await _postImageData(
        '/prescriptions/scan',
        formData,
        emptyMessage: 'Scan response was empty',
      ),
    );
  }

  Future<PreparedPrescriptionLabelResult> preparePrescriptionLabel({
    required int userId,
    required File imageFile,
  }) async {
    final formData = FormData.fromMap({
      'user_id': userId,
      'file': await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.uri.pathSegments.last,
      ),
    });
    return PreparedPrescriptionLabelResult.fromJson(
      await _postImageData(
        '/prescriptions/prepare',
        formData,
        emptyMessage: 'Label preparation response was empty',
      ),
    );
  }

  Future<PreparedPrescriptionLabelResult> preparePrescriptionLabelMulti({
    required int userId,
    required List<File> imageFiles,
  }) async {
    if (imageFiles.isEmpty) {
      throw const FormatException(
        'At least one image file is required for multi-frame preparation',
      );
    }
    final multipartFiles = <MultipartFile>[];
    for (final image in imageFiles) {
      multipartFiles.add(
        await MultipartFile.fromFile(
          image.path,
          filename: image.uri.pathSegments.last,
        ),
      );
    }
    final formData = FormData.fromMap({
      'user_id': userId,
      'files': multipartFiles,
    });
    return PreparedPrescriptionLabelResult.fromJson(
      await _postImageData(
        '/prescriptions/prepare-multi',
        formData,
        emptyMessage: 'Multi-frame preparation response was empty',
      ),
    );
  }

  Future<UploadImageResult> uploadImage({
    required int userId,
    required File imageFile,
  }) async {
    final formData = FormData.fromMap({
      'user_id': userId,
      'file': await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.uri.pathSegments.last,
      ),
    });

    final response = await _apiService.dio.post<Map<String, dynamic>>(
      '/images/upload',
      data: formData,
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
    );

    if (response.data == null) {
      throw const FormatException('Image upload response was empty');
    }

    return UploadImageResult.fromJson(response.data!);
  }

  Future<List<InferenceResult>> analyzePhoto({
    required int photoEventId,
    required int baselineEventId,
  }) async {
    try {
      final response = await _apiService.dio.post<List<dynamic>>(
        '/analyze/$photoEventId',
        data: {'baseline_event_id': baselineEventId},
      );

      final items = response.data ?? const <dynamic>[];
      return items
          .map(
            (item) => InferenceResult.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } on DioException catch (e) {
      // Surfaces backend quality-gate rejections (e.g. "please recapture") verbatim.
      throw ApiException.fromDioException(e);
    }
  }
}

final imageUploadRepositoryProvider = Provider<ImageUploadRepository>((ref) {
  // Share the single ApiService instance across the app
  final apiService = ref.watch(apiServiceProvider);
  return ImageUploadRepository(apiService);
});

class PreparedPrescriptionLabelResult {
  const PreparedPrescriptionLabelResult({
    required this.labelPreviewBase64,
    this.labelRegion,
  });

  final String labelPreviewBase64;
  final Map<String, dynamic>? labelRegion;

  factory PreparedPrescriptionLabelResult.fromJson(Map<String, dynamic> json) {
    return PreparedPrescriptionLabelResult(
      labelPreviewBase64: json['label_preview_base64'] as String,
      labelRegion: json['label_region'] is Map
          ? Map<String, dynamic>.from(json['label_region'] as Map)
          : null,
    );
  }
}

// ── Prescription label scan result ──────────────────────────────────────────────

class PrescriptionScanResult {
  const PrescriptionScanResult({
    required this.medicationName,
    required this.dosage,
    required this.instructions,
    this.medicationNameRaw,
    this.medicationNameConfidence,
    this.medicationNameMatched,
    this.medicationNameMatchScore,
    this.medicationNameSource,
    this.medicationNameRxcui,
    this.refillsRemaining,
    this.prescribedBy,
    this.pharmacy,
    this.rawText,
    this.requiresHumanReview,
    this.ocrProviderChain,
    this.qualityGate,
    this.normalizedSig,
    this.labelPreviewBase64,
  });

  final String medicationName;
  final String dosage;
  final String instructions;
  final String? medicationNameRaw;
  final String? medicationNameConfidence;
  final bool? medicationNameMatched;
  final double? medicationNameMatchScore;
  final String? medicationNameSource;
  final String? medicationNameRxcui;
  final String? refillsRemaining;
  final String? prescribedBy;
  final String? pharmacy;
  final String? rawText;
  final bool? requiresHumanReview;
  final List<String>? ocrProviderChain;
  final Map<String, dynamic>? qualityGate;
  final Map<String, dynamic>? normalizedSig;
  final String? labelPreviewBase64;

  factory PrescriptionScanResult.fromJson(Map<String, dynamic> json) {
    return PrescriptionScanResult(
      medicationName: (json['medication_name'] ?? json['name'] ?? '') as String,
      dosage: (json['dosage'] ?? '') as String,
      instructions:
          (json['instructions'] ?? json['directions'] ?? '') as String,
      medicationNameRaw: json['medication_name_raw'] as String?,
      medicationNameConfidence: json['medication_name_confidence'] as String?,
      medicationNameMatched: json['medication_name_matched'] as bool?,
      medicationNameMatchScore: (json['medication_name_match_score'] as num?)
          ?.toDouble(),
      medicationNameSource: json['medication_name_source'] as String?,
      medicationNameRxcui: json['medication_name_rxcui'] as String?,
      refillsRemaining: json['refills_remaining']?.toString(),
      prescribedBy: json['prescribed_by'] as String?,
      pharmacy: json['pharmacy'] as String?,
      rawText: json['raw_text'] as String?,
      requiresHumanReview: json['requires_human_review'] as bool?,
      ocrProviderChain: (json['ocr_provider_chain'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      qualityGate: json['quality_gate'] is Map
          ? Map<String, dynamic>.from(json['quality_gate'] as Map)
          : null,
      normalizedSig: json['normalized_sig'] is Map
          ? Map<String, dynamic>.from(json['normalized_sig'] as Map)
          : null,
      labelPreviewBase64: json['label_preview_base64'] as String?,
    );
  }
}

// ── Pill analysis result ────────────────────────────────────────────────────

class PillIdentificationResult {
  const PillIdentificationResult({
    required this.medicationName,
    required this.similarity,
    this.runnerUpSimilarity,
    required this.requiresReview,
  });

  final String medicationName;
  final double similarity;
  final double? runnerUpSimilarity;
  final bool requiresReview;

  factory PillIdentificationResult.fromJson(Map<String, dynamic> json) {
    return PillIdentificationResult(
      medicationName: json['medication_name'] as String,
      similarity: (json['similarity'] as num).toDouble(),
      runnerUpSimilarity: (json['runner_up_similarity'] as num?)?.toDouble(),
      requiresReview: json['requires_review'] as bool,
    );
  }
}
