import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'prescription_viewfinder.dart';

const prescriptionCaptureTitles = ['Front', 'Directions', 'Warnings'];

class PrescriptionCaptureView extends StatelessWidget {
  const PrescriptionCaptureView({
    super.key,
    required this.controller,
    required this.activeSlot,
    required this.capturedSlots,
    required this.onCapture,
    required this.onUpload,
    this.busy = false,
    this.status,
    this.cameraError,
    this.error,
  });
  final CameraController? controller;
  final int activeSlot;
  final List<bool> capturedSlots;
  final VoidCallback onCapture;
  final VoidCallback onUpload;
  final String? status;
  final String? cameraError;
  final String? error;
  final bool busy;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        const SizedBox(height: 12),
        Icon(
          Icons.document_scanner_rounded,
          size: 72,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 14),
        Text(
          'Scan a prescription label',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Hold the bottle label in the live camera view, let the app lock the label, then review the frozen photo before scanning. You can still upload a label image if needed.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 20),
        _buildCameraPreviewCard(context),
        const SizedBox(height: 12),
        _buildGuidedSlotStrip(context),
        const SizedBox(height: 20),
        // Photography tips
        _buildPhotoTips(context),
        const SizedBox(height: 20),
        if (cameraError != null) ...[
          PrescriptionScanError(cameraError!),
          const SizedBox(height: 12),
        ],
        if (error != null) ...[
          PrescriptionScanError(error!),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: (controller?.value.isInitialized == true && !busy)
                    ? onCapture
                    : null,
                icon: const Icon(Icons.camera_alt_rounded),
                label: Text('Capture ${prescriptionCaptureTitles[activeSlot]}'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onUpload,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Upload image'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    ),
  );

  Widget _buildGuidedSlotStrip(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Row(
      children: List<Widget>.generate(prescriptionCaptureTitles.length, (
        index,
      ) {
        final isActive = activeSlot == index;
        final captured = capturedSlots[index];
        final title = prescriptionCaptureTitles[index];
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(
              right: index == prescriptionCaptureTitles.length - 1 ? 0 : 8,
            ),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: captured
                  ? Colors.green.shade100
                  : (isActive ? Colors.blue.shade100 : Colors.white),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: captured
                    ? Colors.green.shade400
                    : (isActive ? Colors.blue.shade400 : Colors.grey.shade300),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  captured ? 'Captured' : (isActive ? 'Active' : 'Pending'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: captured
                        ? Colors.green.shade800
                        : (isActive
                              ? Colors.blue.shade800
                              : Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    ),
  );

  Widget _buildPhotoTips(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Row(
      children: [
        Icon(
          Icons.tips_and_updates_rounded,
          size: 16,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          'Tips for best results',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      ],
    ),
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer
              .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tipRow(
              '||',
              'Center the label between the two vertical guides to reduce bottle-edge distortion',
            ),
            _tipRow(
              '\ud83d\udcf1',
              'Hold the phone 20\u201330 cm from the label',
            ),
            _tipRow(
              '\ud83d\udca1',
              'Ensure the label is brightly and evenly lit',
            ),
            _tipRow(
              '\ud83d\udccf',
              'Lay the bottle flat so the label is straight',
            ),
            _tipRow(
              '\ud83d\udd0d',
              'Wait for the camera to focus before shooting',
            ),
            _tipRow(
              '\ud83d\udeb7',
              'Avoid shadows \u2014 especially from your hand',
            ),
            _tipRow(
              '\u2197\ufe0f',
              'Capture only the label, not the whole bottle',
            ),
          ],
        ),
      ),
    ],
  );

  Widget _tipRow(String emoji, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );

  Widget _buildCameraPreviewCard(BuildContext context) {
    final controller = this.controller;
    if (kIsWeb ||
        cameraError != null ||
        controller == null ||
        !controller.value.isInitialized) {
      final message = kIsWeb
          ? 'Live camera scanning is available on iPhone and Android only.'
          : cameraError ?? 'Starting camera…';
      return Container(
        width: double.infinity,
        height: 320,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!kIsWeb) ...[
                if (cameraError != null) ...[
                  Icon(
                    Icons.no_photography_rounded,
                    size: 56,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Camera unavailable',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ] else
                  const CircularProgressIndicator(),
                const SizedBox(height: 12),
              ],
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      height: 360,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CameraPreview(controller),
          ),
          const PrescriptionGuideOverlay(),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Container(
                key: ValueKey<String>(status ?? 'status'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  status ?? 'Hold the label steady until the camera locks it.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
