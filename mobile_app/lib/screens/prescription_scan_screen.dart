import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../app_config.dart';
import '../repositories/image_upload_repository.dart';
import '../repositories/medication_repository.dart';
import '../services/api_service.dart';
import '../services/label_frame_analysis.dart';
import '../state/prescriptions.dart';
import '../widgets/app_navigation.dart';
import '../widgets/prescription_capture_view.dart';
import '../widgets/prescription_frame_review.dart';
import '../widgets/prescription_patient_review.dart';
import '../widgets/prescription_viewfinder.dart';

enum _ScanPhase { initial, imageSelected, scanning, patientReview, submitted }

class PrescriptionScanScreen extends ConsumerStatefulWidget {
  const PrescriptionScanScreen({super.key});
  @override
  ConsumerState<PrescriptionScanScreen> createState() =>
      _PrescriptionScanScreenState();
}

class _PrescriptionScanScreenState
    extends ConsumerState<PrescriptionScanScreen> {
  static const List<String> _guidedSlotPrompts = <String>[
    'Point at the main drug name.',
    'Turn slightly to show directions.',
    'Turn to show refills and warnings.',
  ];

  File? _selectedImage;
  final List<File> _selectedSweepKeyframes = <File>[];
  final List<bool> _selectedSweepFrameFlags = <bool>[];
  final List<File?> _guidedSlotFrames = List<File?>.filled(3, null);
  int _activeGuidedSlot = 0;
  Uint8List? _labelPreviewBytes;
  bool _flattenedPreviewReady = false;
  _ScanPhase _phase = _ScanPhase.initial;
  PrescriptionScanResult? _result;
  String? _error;
  String? _cameraStatus;
  String? _cameraError;

  late final TextRecognizer _textRecognizer;

  CameraController? _cameraController;
  bool _cameraInitializing = false;
  bool _captureBusy = false;
  bool _pickingImage = false;
  bool _hasSweepReference = false;
  List<double>? _lastSweepProfile;
  DateTime? _lastCameraAnalysis;

  @override
  void initState() {
    super.initState();
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    if (!mounted ||
        kIsWeb ||
        _cameraInitializing ||
        (_cameraController?.value.isInitialized ?? false)) {
      return;
    }
    _cameraInitializing = true;
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        throw CameraException(
          'NoCamera',
          'No camera was found on this device.',
        );
      }
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _cameraController = controller;
      _cameraError = null;
      await _resumeCameraStream();
      if (!mounted) return;
      setState(() => _cameraStatus = _guidedSlotPrompts[_activeGuidedSlot]);
    } on Exception catch (error, stack) {
      await controller?.dispose();
      if (!mounted) return;
      _cameraController = null;
      _reportCameraError('Camera preview could not be started', error, stack);
    } finally {
      _cameraInitializing = false;
    }
  }

  void _reportCameraError(String message, Object error, StackTrace stack) {
    debugPrint('$message: $error\n$stack');
    if (!mounted) return;
    setState(
      () => _cameraError = error is CameraException
          ? error.description ?? message
          : message,
    );
  }

  Future<void> _stopCameraStream() async {
    final controller = _cameraController;
    if (controller?.value.isStreamingImages == true) {
      await controller!.stopImageStream();
    }
  }

  Future<void> _resumeCameraStream() async {
    if (!mounted || _phase != _ScanPhase.initial || _pickingImage) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      await _initializeCamera();
      return;
    }
    try {
      if (!controller.value.isStreamingImages) {
        await controller.startImageStream(_processCameraFrame);
      }
    } on Exception catch (error, stack) {
      _reportCameraError('Camera stream could not be resumed', error, stack);
    }
  }

  Future<void> _resetToLiveCamera() async {
    if (!mounted) return;
    setState(() {
      _selectedImage = null;
      _selectedSweepKeyframes.clear();
      _selectedSweepFrameFlags.clear();
      for (var i = 0; i < _guidedSlotFrames.length; i += 1) {
        _guidedSlotFrames[i] = null;
      }
      _activeGuidedSlot = 0;
      _labelPreviewBytes = null;
      _flattenedPreviewReady = false;
      _result = null;
      _error = null;
      _cameraError = null;
      _cameraStatus = _guidedSlotPrompts[_activeGuidedSlot];
      _hasSweepReference = false;
      _lastSweepProfile = null;
      _phase = _ScanPhase.initial;
      _lastCameraAnalysis = null;
    });
    await _resumeCameraStream();
  }

  Future<void> _storeGuidedSlotFrame(File frame) async {
    if (!mounted) {
      return;
    }

    _guidedSlotFrames[_activeGuidedSlot] = frame;
    final nextSlot = _activeGuidedSlot + 1;
    if (nextSlot >= _guidedSlotFrames.length) {
      final frames = _guidedSlotFrames.whereType<File>().toList();
      final keyframes = selectSemanticFusionKeyframes(frames);
      final previewFrame = keyframes[keyframes.length ~/ 2];
      setState(() {
        _selectedImage = previewFrame;
        _selectedSweepKeyframes
          ..clear()
          ..addAll(keyframes);
        _selectedSweepFrameFlags
          ..clear()
          ..addAll(List<bool>.filled(keyframes.length, true));
        _labelPreviewBytes = null;
        _flattenedPreviewReady = false;
        _phase = _ScanPhase.imageSelected;
        _error = null;
        _result = null;
        _cameraStatus = '3 target slots captured. Review frames before OCR.';
        _hasSweepReference = false;
      });
      return;
    }

    setState(() {
      _activeGuidedSlot = nextSlot;
      _cameraStatus = _guidedSlotPrompts[_activeGuidedSlot];
    });
  }

  List<File> _selectedSweepFrames() {
    final selected = <File>[];
    for (var i = 0; i < _selectedSweepKeyframes.length; i += 1) {
      final isSelected = i < _selectedSweepFrameFlags.length
          ? _selectedSweepFrameFlags[i]
          : true;
      if (isSelected) {
        selected.add(_selectedSweepKeyframes[i]);
      }
    }
    return selected;
  }

  void _toggleSweepFrameSelection(int index) {
    if (index < 0 || index >= _selectedSweepFrameFlags.length) {
      return;
    }
    final selectedCount = _selectedSweepFrameFlags.where((v) => v).length;
    if (_selectedSweepFrameFlags[index] && selectedCount <= 1) {
      return;
    }
    setState(() {
      _selectedSweepFrameFlags[index] = !_selectedSweepFrameFlags[index];
      _labelPreviewBytes = null;
      _flattenedPreviewReady = false;
      _error = null;
    });
  }

  String _backendUnreachableMessage() {
    return 'Cannot reach backend at ${AppConfig.baseUrl}. Start backend on port 8000. '
        'If you are on a real iPhone, run with --dart-define=API_BASE_URL=http://<YOUR_MAC_LAN_IP>:8000 '
        '(example: http://192.168.1.8:8000) and keep phone and Mac on the same Wi-Fi.';
  }

  void _updateCameraStatus(String message) {
    if (mounted && _cameraStatus != message) {
      setState(() => _cameraStatus = message);
    }
  }

  void _processCameraFrame(CameraImage image) {
    if (!mounted ||
        _phase != _ScanPhase.initial ||
        _selectedImage != null ||
        _captureBusy ||
        _pickingImage) {
      return;
    }
    final now = DateTime.now();
    if (_lastCameraAnalysis != null &&
        now.difference(_lastCameraAnalysis!) <
            const Duration(milliseconds: 900)) {
      return;
    }
    _lastCameraAnalysis = now;
    unawaited(_captureFrame(automatic: true));
  }

  Future<void> _captureLiveFrame() => _captureFrame();

  Future<void> _captureFrame({bool automatic = false}) async {
    if (!mounted ||
        _phase != _ScanPhase.initial ||
        _captureBusy ||
        _pickingImage) {
      return;
    }
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }
    setState(() {
      _captureBusy = true;
      _cameraError = null;
    });
    try {
      await _stopCameraStream();
      if (!mounted) return;
      final picture = await controller.takePicture();
      if (!mounted || _phase != _ScanPhase.initial) return;
      final frame = File(picture.path);
      if (automatic) {
        await _inspectSweepFrame(frame);
      } else {
        await _storeGuidedSlotFrame(frame);
      }
    } on Exception catch (error, stack) {
      _reportCameraError(
        'Could not capture the label. Please try again.',
        error,
        stack,
      );
    } finally {
      if (mounted) {
        setState(() => _captureBusy = false);
        await _resumeCameraStream();
      }
    }
  }

  Future<void> _inspectSweepFrame(File frame) async {
    final bytes = await frame.readAsBytes();
    if (!mounted || _phase != _ScanPhase.initial) return;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException(
        'Could not read the camera frame. Please try again.',
      );
    }
    final analysis = analyzeGuideEdgeRegion(img.bakeOrientation(decoded));
    if (analysis.bounds == null) {
      _lastSweepProfile = null;
      _updateCameraStatus(
        'No readable label structure detected in the guide area. Re-center and hold steady.',
      );
      return;
    }
    final shift = _lastSweepProfile == null
        ? 0
        : estimateHorizontalShift(_lastSweepProfile!, analysis.centerProfile);
    _lastSweepProfile = analysis.centerProfile;
    final movedEnough = !_hasSweepReference || shift.abs() >= 15;
    _hasSweepReference = true;
    final sharpEnough = analysis.edgeHitCount >= 1700;
    if (sharpEnough && (_activeGuidedSlot == 0 || movedEnough)) {
      await _storeGuidedSlotFrame(frame);
    } else {
      _updateCameraStatus(
        _activeGuidedSlot > 0 && !movedEnough
            ? 'Turn slightly more to fill ${prescriptionCaptureTitles[_activeGuidedSlot]}.'
            : 'Hold steady and focus on ${prescriptionCaptureTitles[_activeGuidedSlot]} text.',
      );
    }
  }

  /// Reads label text on the device from every captured view.
  ///
  /// A curved bottle shows different text in each view, so lines from all
  /// frames are combined (duplicates are removed on the server).
  Future<(String?, String?)> _runDeviceOcr(List<File> imageFiles) async {
    if (kIsWeb) {
      return (null, null);
    }
    final texts = <String>[];
    for (final imageFile in imageFiles) {
      try {
        final input = InputImage.fromFilePath(imageFile.path);
        final recognized = await _textRecognizer.processImage(input);
        final text = recognized.text.trim();
        if (text.isNotEmpty) texts.add(text);
      } on Exception catch (error, stack) {
        debugPrint('On-device text recognition failed: $error\n$stack');
      }
    }
    if (texts.isEmpty) {
      return (null, null);
    }
    final provider = defaultTargetPlatform == TargetPlatform.iOS
        ? 'apple_vision'
        : 'google_ml_kit';
    return (texts.join('\n'), provider);
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_captureBusy || _pickingImage) return;
    setState(() => _pickingImage = true);
    final repo = ref.read(imageUploadRepositoryProvider);
    try {
      await _stopCameraStream();
      if (!mounted) return;
      final picked = await repo.pickImage(
        source: source,
        imageQuality: 100,
        maxDimension: 4000,
      );
      if (!mounted || picked == null) return;
      final compressed = await repo.compressForOcr(picked);
      if (!mounted) return;
      if (compressed == null) {
        throw const FormatException('Could not process image');
      }
      setState(() {
        _selectedImage = compressed;
        _selectedSweepKeyframes
          ..clear()
          ..add(compressed);
        _selectedSweepFrameFlags
          ..clear()
          ..add(true);
        _hasSweepReference = false;
        _labelPreviewBytes = null;
        _flattenedPreviewReady = false;
        _phase = _ScanPhase.imageSelected;
        _error = null;
        _result = null;
        _cameraStatus = null;
      });
    } on Exception catch (error, stack) {
      debugPrint('Could not select prescription image: $error\n$stack');
      if (mounted) {
        setState(() => _error = 'Could not access or process image: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _pickingImage = false);
        await _resumeCameraStream();
      }
    }
  }

  Future<void> _scanLabel() async {
    if (_selectedImage == null) return;
    final selectedFrames = _selectedSweepFrames();
    final minRequired = _selectedSweepKeyframes.length > 1 ? 2 : 1;
    if (selectedFrames.length < minRequired) {
      setState(() {
        _error =
            'Select at least $minRequired clear frame(s) before running OCR.';
      });
      return;
    }

    final repo = ref.read(imageUploadRepositoryProvider);
    final userId = ref.read(userIdProvider);
    if (!_flattenedPreviewReady) {
      setState(() {
        _phase = _ScanPhase.scanning;
        _error = null;
      });
      try {
        final prepared = await repo.preparePrescriptionLabelMulti(
          userId: userId,
          imageFiles: selectedFrames,
        );
        if (!mounted) return;
        final preview = base64Decode(prepared.labelPreviewBase64);
        setState(() {
          _labelPreviewBytes = preview;
          _flattenedPreviewReady = true;
          _phase = _ScanPhase.imageSelected;
          _error = null;
          _cameraStatus =
              'Flattened label preview ready. Review it before OCR.';
        });
      } on ApiException catch (error) {
        if (!mounted) return;
        setState(() {
          _phase = _ScanPhase.imageSelected;
          _error = 'Could not prepare the flattened label: ${error.message}';
        });
      } on Exception catch (error, stack) {
        debugPrint('Could not prepare prescription label: $error\n$stack');
        if (!mounted) return;
        setState(() {
          _phase = _ScanPhase.imageSelected;
          _error = 'Could not prepare the flattened label. Try again.';
        });
      }
      return;
    }

    setState(() {
      _phase = _ScanPhase.scanning;
      _error = null;
    });
    final reachable = await repo.isBackendReachable();
    if (!mounted) return;
    if (!reachable) {
      final friendly = _backendUnreachableMessage();
      setState(() {
        _phase = _ScanPhase.imageSelected;
        _error = friendly;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Scan failed: $friendly')));
      return;
    }

    final (deviceOcrText, deviceOcrProvider) = await _runDeviceOcr(
      selectedFrames,
    );
    if (!mounted) return;
    if (!kIsWeb && (deviceOcrText == null || deviceOcrText.trim().isEmpty)) {
      _updateCameraStatus(
        'Little label text was found. You can enter the details by hand.',
      );
    }

    try {
      final result = await repo.scanPrescription(
        userId: userId,
        imageFiles: selectedFrames,
        deviceOcrText: deviceOcrText,
        deviceOcrProvider: deviceOcrProvider,
      );
      _applyResult(result);
    } on ApiException catch (error) {
      if (!mounted) return;
      final messageLower = error.message.toLowerCase();
      final isConnectionFailure =
          error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.unknown ||
          messageLower.contains('connection refused') ||
          messageLower.contains('request connection took longer') ||
          messageLower.contains('socketexception') ||
          messageLower.contains('timed out');
      final friendly = isConnectionFailure
          ? _backendUnreachableMessage()
          : error.message;
      setState(() {
        _phase = _ScanPhase.imageSelected;
        _error = friendly;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Scan failed: $friendly')));
    } on Exception catch (error, stack) {
      debugPrint('Prescription scan failed: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _phase = _ScanPhase.imageSelected;
        _error = 'Scan failed. Ensure backend OCR is running and try again.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scan failed. Backend OCR may be unavailable.'),
        ),
      );
    }
  }

  void _applyResult(PrescriptionScanResult r) {
    if (!mounted) return;
    final preview = r.labelPreviewBase64;
    final bytes = preview == null || preview.trim().isEmpty
        ? null
        : base64Decode(preview);
    setState(() {
      _result = r;
      _labelPreviewBytes = bytes;
      _flattenedPreviewReady = true;
      _phase = _ScanPhase.patientReview;
    });
  }

  void _submitForVerification(PrescriptionDraft draft) {
    if (_phase != _ScanPhase.patientReview) return;
    final name = draft.name;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medication name is required')),
      );
      return;
    }
    final id = DateTime.now().millisecondsSinceEpoch;
    final pending = PendingPrescription(
      id: id,
      medicationName: name,
      dosage: draft.dosage,
      instructions: draft.instructions.isEmpty ? null : draft.instructions,
      scannedAt: DateTime.now(),
      prescribedBy: _result?.prescribedBy,
      pharmacy: _result?.pharmacy,
      refillsRemaining: _result?.refillsRemaining,
      imageFilePath: _selectedImage?.path,
      patientNote: draft.note.isEmpty ? null : draft.note,
      status: VerificationStatus.awaitingVerifier,
    );
    ref.read(pendingPrescriptionsProvider.notifier).add(pending);
    setState(() {
      _phase = _ScanPhase.submitted;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Scan prescription label'),
        actions: _phase == _ScanPhase.patientReview
            ? [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Scan again',
                  onPressed: _resetToLiveCamera,
                ),
              ]
            : null,
      ),
      body: switch (_phase) {
        _ScanPhase.initial => PrescriptionCaptureView(
          controller: _cameraController,
          activeSlot: _activeGuidedSlot,
          busy: _captureBusy || _pickingImage,
          capturedSlots: _guidedSlotFrames
              .map((frame) => frame != null)
              .toList(),
          status: _cameraStatus,
          cameraError: _cameraError,
          error: _error,
          onCapture: _captureLiveFrame,
          onUpload: () => _pickImage(ImageSource.gallery),
        ),
        _ScanPhase.imageSelected => PrescriptionFrameReview(
          image: _selectedImage,
          frames: _selectedSweepKeyframes,
          selected: _selectedSweepFrameFlags,
          preview: _labelPreviewBytes,
          previewReady: _flattenedPreviewReady,
          error: _error,
          onToggle: _toggleSweepFrameSelection,
          onRetake: _resetToLiveCamera,
          onPrepare: _scanLabel,
        ),
        _ScanPhase.scanning => _buildScanning(),
        _ScanPhase.patientReview => PrescriptionPatientReview(
          result: _result!,
          image: _selectedImage,
          preview: _labelPreviewBytes,
          onSubmit: _submitForVerification,
          onScanAgain: () => setState(() {
            _phase = _ScanPhase.imageSelected;
            _result = null;
          }),
        ),
        _ScanPhase.submitted => _buildSubmitted(),
      },
    );
  }

  Widget _buildScanning() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Expanded(
          child: PrescriptionViewfinder(image: _selectedImage, scanning: true),
        ),
        const SizedBox(height: 28),
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          'Reading prescription label\u2026',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Extracting medication details',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 40),
      ],
    ),
  );

  Widget _buildSubmitted() => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            size: 72,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Submitted for verification',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Your prescription has been submitted. A pharmacist or connected care team member will review and verify the details. Once approved, the medication will automatically be added to your list.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => context.push('/prescription-queue'),
            icon: const Icon(Icons.pending_actions_rounded),
            label: const Text('View verification queue'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.go('/dashboard'),
            icon: const Icon(Icons.home_rounded),
            label: const Text('Back to dashboard'),
          ),
        ),
      ],
    ),
  );

  // ── Viewfinder ────────────────────────────────────────────────────────────────
}
