import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.type});

  final String message;
  final int? statusCode;
  final DioExceptionType? type;

  factory ApiException.fromDioException(DioException exception) {
    final status = exception.response?.statusCode;
    final data = exception.response?.data;
    String message = 'Request failed';

    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) {
        message = detail;
      } else if (detail is List) {
        message = detail.map((e) => e.toString()).join(', ');
      }
    } else if (exception.message != null && exception.message!.isNotEmpty) {
      message = exception.message!;
    }

    return ApiException(message, statusCode: status, type: exception.type);
  }

  @override
  String toString() =>
      'ApiException(statusCode: $statusCode, message: $message, type: $type)';
}

class ApiService {
  ApiService()
    : dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.baseUrl,
          // Increased connect timeout for larger payloads/video uploads
          connectTimeout: const Duration(seconds: 120),
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 120),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );

  final Dio dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      return await dio.get<T>(path, queryParameters: queryParameters);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Response<T>> post<T>(String path, {dynamic data}) async {
    try {
      return await dio.post<T>(path, data: data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Response<T>> put<T>(String path, {dynamic data}) async {
    try {
      return await dio.put<T>(path, data: data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

/// Parses a backend timestamp as UTC and converts it to local time.
///
/// The API stores UTC, but SQLite returns values without an offset; Dart would
/// otherwise interpret those as local time.
DateTime parseServerDateTime(String value) {
  final hasOffset = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(value);
  return DateTime.parse(hasOffset ? value : '${value}Z').toLocal();
}
