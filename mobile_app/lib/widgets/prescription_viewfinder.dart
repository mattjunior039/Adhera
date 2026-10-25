import 'dart:io';

import 'package:flutter/material.dart';

class PrescriptionViewfinder extends StatefulWidget {
  const PrescriptionViewfinder({super.key, this.image, this.scanning = false});
  final File? image;
  final bool scanning;
  @override
  State<PrescriptionViewfinder> createState() => _PrescriptionViewfinderState();
}

class _PrescriptionViewfinderState extends State<PrescriptionViewfinder>
    with SingleTickerProviderStateMixin {
  late final _animCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  late final _scanLine = CurvedAnimation(
    parent: _animCtrl,
    curve: Curves.easeInOut,
  );
  late final _pulse = Tween<double>(begin: 0.4, end: 1).animate(_scanLine);
  @override
  void initState() {
    super.initState();
    if (widget.scanning) _animCtrl.repeat();
  }

  @override
  void didUpdateWidget(PrescriptionViewfinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scanning != widget.scanning) {
      if (widget.scanning) {
        _animCtrl.repeat();
      } else {
        _animCtrl.stop();
      }
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final scanning = widget.scanning;
    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, _) {
        final borderColor = scanning
            ? Color.lerp(
                Colors.green.shade300,
                Colors.green.shade600,
                _pulse.value,
              )!
            : Colors.grey.shade300;
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: scanning ? 2.5 : 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: image != null
                ? SizedBox(
                    height: 320,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          color: Colors.black,
                          alignment: Alignment.center,
                          child: Image.file(
                            image,
                            width: double.infinity,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const PrescriptionGuideOverlay(),
                        if (scanning)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _ScanOverlayPainter(
                                scanProgress: _scanLine.value,
                                opacity: _pulse.value,
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : Container(
                    height: 200,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.document_scanner_outlined,
                          size: 56,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No image selected',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class PrescriptionGuideOverlay extends StatelessWidget {
  const PrescriptionGuideOverlay({super.key});
  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final guideWidth = width * 0.56;
          final left = (width - guideWidth) / 2;
          final right = left + guideWidth;
          return Stack(
            children: [
              Positioned(
                left: left,
                top: 10,
                bottom: 10,
                child: Container(
                  width: 2,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              Positioned(
                left: right,
                top: 10,
                bottom: 10,
                child: Container(
                  width: 2,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              Positioned(
                left: left + 4,
                right: width - right + 4,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  color: Colors.black.withValues(alpha: 0.35),
                  child: const Text(
                    'Keep label text in this center zone',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class PrescriptionScanError extends StatelessWidget {
  const PrescriptionScanError(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      message,
      style: const TextStyle(color: Colors.red, fontSize: 13),
    ),
  );
}

/// Paints the animated scan-line + corner brackets over the viewfinder.
class _ScanOverlayPainter extends CustomPainter {
  _ScanOverlayPainter({required this.scanProgress, required this.opacity});
  final double scanProgress;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final green = Colors.green.withValues(alpha: opacity * 0.9);
    final linePaint = Paint()
      ..color = green
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final cornerPaint = Paint()
      ..color = Colors.green.withValues(alpha: opacity)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final y = size.height * scanProgress;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, y),
      Paint()..color = Colors.green.withValues(alpha: 0.06),
    );

    const len = 28.0, margin = 12.0;
    void corner(double cx, double cy, double dx, double dy) {
      canvas.drawLine(Offset(cx, cy), Offset(cx + dx * len, cy), cornerPaint);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy + dy * len), cornerPaint);
    }

    corner(margin, margin, 1, 1);
    corner(size.width - margin, margin, -1, 1);
    corner(margin, size.height - margin, 1, -1);
    corner(size.width - margin, size.height - margin, -1, -1);
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter old) =>
      old.scanProgress != scanProgress || old.opacity != opacity;
}
