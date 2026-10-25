import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adhera/repositories/image_upload_repository.dart';
import 'package:adhera/screens/prescription_scan_screen.dart';
import 'package:adhera/services/api_service.dart';
import 'package:adhera/state/prescriptions.dart';
import 'package:adhera/widgets/prescription_frame_review.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class _Camera extends CameraPlatform {
  Completer<void>? initializing;
  int starts = 0;
  int stops = 0;
  int disposed = 0;
  int captures = 0;
  Future<XFile>? picture;
  CameraException? captureError;
  late File image;
  late final frames = StreamController<CameraImageData>.broadcast(
    onListen: () => starts++,
    onCancel: () => stops++,
  );

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'test',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 0,
    ),
  ];

  @override
  Future<int> createCamera(
    CameraDescription description,
    ResolutionPreset? preset, {
    bool enableAudio = false,
  }) async => 1;

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    await initializing?.future;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          640,
          480,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      Stream.multi((controller) {});

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) => frames.stream;

  @override
  Future<XFile> takePicture(int cameraId) async {
    captures++;
    if (captureError != null) throw captureError!;
    if (picture != null) return picture!;
    return XFile(image.path);
  }

  @override
  Widget buildPreview(int cameraId) => const SizedBox();

  @override
  Future<void> dispose(int cameraId) async => disposed++;
}

class _Images extends ImageUploadRepository {
  _Images() : super(ApiService());
  XFile? picked;
  File? compressed;
  Future<File?>? compression;
  late String preview;
  int scans = 0;
  int compressions = 0;
  final scan = Completer<PrescriptionScanResult>();

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    int? imageQuality,
    double maxDimension = 4000,
  }) async => picked;

  @override
  Future<File?> compressForOcr(XFile file) {
    compressions++;
    return compression ?? Future.value(compressed);
  }

  @override
  Future<PreparedPrescriptionLabelResult> preparePrescriptionLabelMulti({
    required int userId,
    required List<File> imageFiles,
  }) async => PreparedPrescriptionLabelResult(labelPreviewBase64: preview);

  @override
  Future<bool> isBackendReachable() async => true;

  @override
  Future<PrescriptionScanResult> scanPrescription({
    required int userId,
    required List<File> imageFiles,
    String? deviceOcrText,
    String? deviceOcrProvider,
  }) {
    scans++;
    return scan.future;
  }
}

void main() {
  late _Camera camera;
  late _Images images;

  setUp(() async {
    final previousCamera = CameraPlatform.instance;
    camera = _Camera();
    CameraPlatform.instance = camera;
    images = _Images();
    final directory = await Directory.systemTemp.createTemp(
      'adhera-scan-test-',
    );
    final bytes = img.encodePng(img.Image(width: 60, height: 40));
    camera.image = await File('${directory.path}/label.png')
        .writeAsBytes(bytes);
    images.compressed = camera.image;
    images.preview = base64Encode(bytes);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('google_mlkit_text_recognizer'),
          (call) async => call.method == 'vision#startTextRecognizer'
              ? {'text': 'Label text', 'blocks': []}
              : null,
        );
    addTearDown(() async {
      CameraPlatform.instance = previousCamera;
      await camera.frames.close();
      await directory.delete(recursive: true);
    });
  });

  Future<void> showScanner(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageUploadRepositoryProvider.overrideWithValue(images)],
        child: const MaterialApp(home: PrescriptionScanScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAction(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pumpAndSettle();
  }

  testWidgets('gallery cancellation resumes camera streaming', (tester) async {
    await showScanner(tester);
    expect(camera.starts, 1);
    await tapAction(tester, 'Upload image');
    expect(camera.stops, 1);
    expect(camera.starts, 2);
    expect(find.text('Capture Front'), findsOneWidget);
  });

  testWidgets('gallery compression failure is visible and resumes streaming', (
    tester,
  ) async {
    images.picked = XFile(camera.image.path);
    images.compressed = null;
    await showScanner(tester);
    await tapAction(tester, 'Upload image');
    expect(find.textContaining('Could not process image'), findsOneWidget);
    expect(camera.starts, 2);
  });

  testWidgets(
    'late camera initialization releases the camera after navigation away',
    (tester) async {
      camera.initializing = Completer<void>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [imageUploadRepositoryProvider.overrideWithValue(images)],
          child: const MaterialApp(home: PrescriptionScanScreen()),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      camera.initializing!.complete();
      await tester.pumpAndSettle();
      expect(camera.disposed, 1);
      expect(camera.starts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late gallery compression does not update a disposed screen', (
    tester,
  ) async {
    final compression = Completer<File?>();
    images.picked = XFile(camera.image.path);
    images.compression = compression.future;
    await showScanner(tester);
    await tapAction(tester, 'Upload image');
    expect(images.compressions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    compression.complete(camera.image);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(camera.disposed, 1);
  });

  testWidgets('capture requests cannot overlap', (tester) async {
    final picture = Completer<XFile>();
    camera.picture = picture.future;
    await showScanner(tester);
    await tester.tap(find.text('Capture Front'));
    await tester.tap(find.text('Capture Front'));
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pumpAndSettle();
    expect(camera.captures, 1);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Upload image'),
          )
          .onPressed,
      isNull,
    );
    picture.complete(XFile(camera.image.path));
    await tester.pumpAndSettle();
    expect(find.text('Capture Directions'), findsOneWidget);
  });

  testWidgets(
    'three captures advance through slots and stop streaming for review',
    (tester) async {
      await showScanner(tester);
      for (final slot in ['Front', 'Directions', 'Warnings']) {
        await tapAction(tester, 'Capture $slot');
      }
      expect(find.text('Prepare Flattened Preview'), findsOneWidget);
      expect(find.text('Selected for OCR: 3/3'), findsOneWidget);
      expect(camera.starts, 3);
      expect(camera.stops, 3);
      await tapAction(tester, 'Retake sweep');
      expect(find.text('Capture Front'), findsOneWidget);
      expect(camera.starts, 4);
    },
  );

  testWidgets(
    'capture failure remains visible rather than silently continuing',
    (tester) async {
      camera.captureError = CameraException(
        'CaptureFailed',
        'Camera capture failed',
      );
      await showScanner(tester);
      await tapAction(tester, 'Capture Front');
      expect(find.text('Camera capture failed'), findsWidgets);
      expect(camera.starts, 2);
    },
  );

  testWidgets('late OCR response does not update a disposed screen', (
    tester,
  ) async {
    images.picked = XFile(camera.image.path);
    await showScanner(tester);
    await tapAction(tester, 'Upload image');
    await tapAction(tester, 'Prepare Flattened Preview');
    await tester.tap(find.text('Run OCR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(images.scans, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    images.scan.complete(
      const PrescriptionScanResult(
        medicationName: 'Ibuprofen',
        dosage: '200 mg',
        instructions: 'With water',
      ),
    );
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('patient must confirm edited OCR details before submission', (
    tester,
  ) async {
    images.picked = XFile(camera.image.path);
    await showScanner(tester);
    await tapAction(tester, 'Upload image');
    await tapAction(tester, 'Prepare Flattened Preview');
    await tester.tap(find.text('Run OCR'));
    await tester.pump();
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump(const Duration(milliseconds: 16));
    expect(images.scans, 1);
    images.scan.complete(
      const PrescriptionScanResult(
        medicationName: 'Ibuprofen',
        dosage: '200 mg',
        instructions: 'With water',
      ),
    );
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PrescriptionScanScreen)),
    );
    final submit = find.widgetWithText(FilledButton, 'Submit for verification');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(container.read(pendingPrescriptionsProvider), isEmpty);
    await tester.enterText(find.byType(TextField).first, 'Acetaminophen');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final prescription = container.read(pendingPrescriptionsProvider).single;
    expect(prescription.medicationName, 'Acetaminophen');
    expect(prescription.dosage, '200 mg');
    expect(prescription.status, VerificationStatus.awaitingVerifier);
    expect(find.text('Submitted for verification'), findsOneWidget);
  });

  testWidgets(
    'frame review fits a short phone screen and keeps OCR accessible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrescriptionFrameReview(
              image: camera.image,
              frames: [camera.image],
              selected: const [true],
              preview: base64Decode(images.preview),
              previewReady: true,
              onToggle: (_) {},
              onRetake: () {},
              onPrepare: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Run OCR'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Run OCR').hitTestable(), findsOneWidget);
    },
  );
}
