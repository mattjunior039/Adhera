import 'dart:io';

import 'package:adhera/repositories/image_upload_repository.dart';
import 'package:adhera/services/api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ApiService api;
  late ImageUploadRepository repository;
  late File image;

  setUp(() async {
    api = ApiService();
    repository = ImageUploadRepository(api);
    final directory = await Directory.systemTemp.createTemp(
      'adhera-upload-test-',
    );
    image = await File('${directory.path}/label.jpg').writeAsBytes([1, 2, 3]);
    addTearDown(() async {
      api.dio.close(force: true);
      await directory.delete(recursive: true);
    });
  });

  test(
    'scan preserves multipart views, OCR hints and inherited timeouts',
    () async {
      api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.path, '/prescriptions/scan');
            expect(options.receiveTimeout, api.dio.options.receiveTimeout);
            expect(options.sendTimeout, api.dio.options.sendTimeout);
            final form = options.data as FormData;
            expect(Map.fromEntries(form.fields), {
              'user_id': '7',
              'device_ocr_text': 'Label text',
              'device_ocr_provider': 'apple_vision',
            });
            expect(form.files.map((entry) => entry.value.filename), [
              'view_1.jpg',
              'view_2.jpg',
            ]);
            handler.resolve(
              Response(
                requestOptions: options,
                data: <String, dynamic>{'medication_name': 'Ibuprofen'},
              ),
            );
          },
        ),
      );
      final result = await repository.scanPrescription(
        userId: 7,
        imageFiles: [image, image],
        deviceOcrText: ' Label text ',
        deviceOcrProvider: ' apple_vision ',
      );
      expect(result.medicationName, 'Ibuprofen');
    },
  );

  test(
    'identification preserves extended timeouts and review-only result',
    () async {
      api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.path, '/pills/identify');
            expect(options.receiveTimeout, const Duration(seconds: 120));
            expect(options.sendTimeout, const Duration(seconds: 60));
            handler.resolve(
              Response(
                requestOptions: options,
                data: <String, dynamic>{
                  'medication_name': 'Ibuprofen',
                  'similarity': 0.9,
                  'requires_review': true,
                },
              ),
            );
          },
        ),
      );
      expect(
        (await repository.identifyPill(imageFile: image)).requiresReview,
        isTrue,
      );
    },
  );

  test('empty preparation response remains an explicit format error', () async {
    api.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(requestOptions: options),
          );
        },
      ),
    );
    await expectLater(
      repository.preparePrescriptionLabel(userId: 1, imageFile: image),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Label preparation response was empty',
        ),
      ),
    );
  });

  test('preparation preserves backend error details', () async {
    api.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(
                requestOptions: options,
                statusCode: 503,
                data: <String, dynamic>{'detail': 'OCR unavailable'},
              ),
            ),
          );
        },
      ),
    );
    await expectLater(
      repository.preparePrescriptionLabelMulti(userId: 1, imageFiles: [image]),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having((error) => error.message, 'message', 'OCR unavailable'),
      ),
    );
  });
}
