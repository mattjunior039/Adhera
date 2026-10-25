import 'package:flutter/material.dart';

Future<void> showPrescriptionImagePreview(
  BuildContext context,
  ImageProvider image, {
  String? title,
}) => showDialog<void>(
  context: context,
  barrierColor: Colors.black87,
  builder: (context) => Dialog(
    backgroundColor: Colors.black,
    insetPadding: const EdgeInsets.all(16),
    child: Stack(
      fit: StackFit.expand,
      children: [
        InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: Image(image: image, fit: BoxFit.contain),
          ),
        ),
        if (title != null)
          Positioned(
            top: 16,
            left: 16,
            child: Text(title, style: const TextStyle(color: Colors.white)),
          ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            tooltip: 'Close preview',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ),
      ],
    ),
  ),
);

class FlattenedLabelPreview extends StatelessWidget {
  const FlattenedLabelPreview({
    super.key,
    required this.image,
    this.height = 160,
  });

  final ImageProvider image;
  final double height;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => showPrescriptionImagePreview(context, image),
    child: Container(
      width: double.infinity,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(image: image, fit: BoxFit.contain),
          for (final (alignment, label) in [
            (Alignment.topLeft, 'Flattened OCR crop'),
            (Alignment.bottomRight, 'Tap to enlarge'),
          ])
            Align(
              alignment: alignment,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
