import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';

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
  String toString() => 'ApiException(statusCode: $statusCode, message: $message, type: $type)';
}

class ApiService {
  ApiService() : dio = Dio(BaseOptions(
          baseUrl: AppConfig.baseUrl,
          // Keep connect timeout short for unreachable hosts, but allow OCR responses longer.
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 75),
          sendTimeout: const Duration(seconds: 30),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        )) {
    dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => debugPrint(obj.toString()),
    ));
  }

  final Dio dio;

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters}) async {
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

void debugPrint(Object? object) {
  // no-op placeholder to avoid depending on Flutter-only debugPrint in tests
  // The actual logger is provided by Dio's LogInterceptor when used in Flutter runtime.
}

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());
