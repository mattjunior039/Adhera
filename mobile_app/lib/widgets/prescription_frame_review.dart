import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'prescription_image_preview.dart';
import 'prescription_viewfinder.dart';

class PrescriptionFrameReview extends StatelessWidget {
  const PrescriptionFrameReview({
    super.key,
    required this.image,
    required this.frames,
    required this.selected,
    required this.previewReady,
    required this.onToggle,
    required this.onRetake,
    required this.onPrepare,
    this.preview,
    this.error,
  });
  final File? image;
  final List<File> frames;
  final List<bool> selected;
  final bool previewReady;
  final Uint8List? preview;
  final String? error;
  final ValueChanged<int> onToggle;
  final VoidCallback onRetake;
  final VoidCallback onPrepare;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      AspectRatio(
        aspectRatio: 4 / 3,
        child: PrescriptionViewfinder(image: image),
      ),
      if (preview != null) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Flattened label preview',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.amber.shade900,
                ),
              ),
              const SizedBox(height: 8),
              FlattenedLabelPreview(image: MemoryImage(preview!)),
              const SizedBox(height: 6),
              Text(
                'Review this processed image before sending it to OCR.',
                style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.shade100),
        ),
        child: Text(
          'Semantic fusion keyframes: ${frames.length} captured. Tap frames to inspect and toggle selection.',
          style: TextStyle(
            fontSize: 13,
            color: Colors.green.shade800,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 96,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: frames.length,
          separatorBuilder: (_, separatorIndex) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final file = frames[index];
            final isSelected = selected[index];
            return GestureDetector(
              onTap: () => showPrescriptionImagePreview(
                context,
                FileImage(file),
                title: 'Frame ${index + 1}',
              ),
              onLongPress: () => onToggle(index),
              child: Stack(
                children: [
                  Container(
                    width: 116,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade400,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Opacity(
                        opacity: isSelected ? 1.0 : 0.45,
                        child: Image.file(file, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () => onToggle(index),
                      child: CircleAvatar(
                        radius: 11,
                        backgroundColor: Colors.black.withValues(alpha: 0.55),
                        child: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 16,
                          color: isSelected
                              ? Colors.lightGreenAccent
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Selected for OCR: ${selected.where((value) => value).length}/${frames.length}',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: Colors.grey.shade700),
      ),
      const SizedBox(height: 12),
      // Retake hint
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Review sharpness before running OCR. Long-press or tap the circle icon to deselect blurry or redundant frames.',
          style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: 12),
      if (error != null) ...[
        PrescriptionScanError(error!),
        const SizedBox(height: 12),
      ],
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onRetake,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Retake sweep'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: selected.any((value) => value) ? onPrepare : null,
              icon: const Icon(Icons.document_scanner_rounded),
              label: Text(
                previewReady ? 'Run OCR' : 'Prepare Flattened Preview',
              ),
            ),
          ),
        ],
      ),
    ],
  );
}
