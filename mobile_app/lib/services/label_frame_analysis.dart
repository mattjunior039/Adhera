import 'dart:io';
import 'dart:ui';

import 'package:image/image.dart' as img;

const labelSweepSegments = 6;
const labelGuideLeft = 0.22;
const labelGuideRight = 0.78;

List<File> selectSemanticFusionKeyframes(List<File> frames) {
  if (frames.length <= 4) {
    return List<File>.from(frames);
  }
  final targetCount = frames.length >= 6 ? 4 : 3;
  final picked = <File>[];
  for (var i = 0; i < targetCount; i += 1) {
    final index = ((i * (frames.length - 1)) / (targetCount - 1)).round();
    picked.add(frames[index]);
  }
  return picked;
}

int _lumaAt(img.Image source, int x, int y) {
  final px = source.getPixel(x, y);
  final r = px.r.toInt();
  final g = px.g.toInt();
  final b = px.b.toInt();
  return (r * 299 + g * 587 + b * 114) ~/ 1000;
}

({
  Rect? bounds,
  List<double> segmentEdgeDensity,
  int edgeHitCount,
  List<double> centerProfile,
})
analyzeGuideEdgeRegion(img.Image source) {
  final maxWidth = source.width > 1200 ? 1200 : source.width;
  final working = source.width > maxWidth
      ? img.copyResize(
          source,
          width: maxWidth,
          interpolation: img.Interpolation.linear,
        )
      : source;

  final leftGuide = (labelGuideLeft * working.width).round().clamp(
    0,
    working.width - 1,
  );
  final rightGuide = (labelGuideRight * working.width).round().clamp(
    1,
    working.width,
  );
  if (rightGuide - leftGuide < 12) {
    return (
      bounds: null,
      segmentEdgeDensity: List<double>.filled(labelSweepSegments, 0.0),
      edgeHitCount: 0,
      centerProfile: const <double>[],
    );
  }

  const sampleStep = 2;
  final corridorWidth = rightGuide - leftGuide;
  final segmentHits = List<int>.filled(labelSweepSegments, 0);
  final segmentTotals = List<int>.filled(labelSweepSegments, 0);
  final centerProfile = List<double>.filled(corridorWidth, 0.0);
  final centerY = working.height ~/ 2;
  final centerBand = (working.height * 0.25).round();
  int? top;
  int? bottom;
  int? left;
  int? right;
  var edgeHitCount = 0;

  for (var y = sampleStep; y < working.height; y += sampleStep) {
    for (var x = leftGuide + sampleStep; x < rightGuide; x += sampleStep) {
      final seg = (((x - leftGuide) / corridorWidth) * labelSweepSegments)
          .floor()
          .clamp(0, labelSweepSegments - 1);
      segmentTotals[seg] += 1;
      final center = _lumaAt(working, x, y);
      final leftPx = _lumaAt(working, x - sampleStep, y);
      final upPx = _lumaAt(working, x, y - sampleStep);
      final edgeStrength = (center - leftPx).abs() + (center - upPx).abs();
      if ((y - centerY).abs() <= centerBand) {
        centerProfile[(x - leftGuide).clamp(0, centerProfile.length - 1)] +=
            edgeStrength.toDouble();
      }
      if (edgeStrength >= 30) {
        edgeHitCount += 1;
        segmentHits[seg] += 1;
        top = top == null ? y : (y < top ? y : top);
        bottom = bottom == null ? y : (y > bottom ? y : bottom);
        left = left == null ? x : (x < left ? x : left);
        right = right == null ? x : (x > right ? x : right);
      }
    }
  }

  final density = List<double>.generate(labelSweepSegments, (i) {
    final total = segmentTotals[i];
    if (total <= 0) {
      return 0.0;
    }
    return segmentHits[i] / total;
  });

  if (edgeHitCount < 220 ||
      top == null ||
      bottom == null ||
      left == null ||
      right == null) {
    return (
      bounds: null,
      segmentEdgeDensity: density,
      edgeHitCount: edgeHitCount,
      centerProfile: centerProfile,
    );
  }

  final expandX = ((right - left) * 0.10).round();
  final expandY = ((bottom - top) * 0.16).round();
  final rect = Rect.fromLTRB(
    (left - expandX).clamp(0, working.width - 1).toDouble(),
    (top - expandY).clamp(0, working.height - 1).toDouble(),
    (right + expandX).clamp(1, working.width).toDouble(),
    (bottom + expandY).clamp(1, working.height).toDouble(),
  );
  return (
    bounds: rect,
    segmentEdgeDensity: density,
    edgeHitCount: edgeHitCount,
    centerProfile: centerProfile,
  );
}

int estimateHorizontalShift(List<double> a, List<double> b, {int maxLag = 72}) {
  if (a.isEmpty || b.isEmpty) {
    return 0;
  }
  final n = a.length < b.length ? a.length : b.length;
  if (n < 24) {
    return 0;
  }

  var bestLag = 0;
  var bestScore = double.negativeInfinity;
  final lagLimit = maxLag < (n ~/ 2) ? maxLag : (n ~/ 2);
  for (var lag = -lagLimit; lag <= lagLimit; lag += 1) {
    var score = 0.0;
    for (var i = 0; i < n; i += 1) {
      final j = i + lag;
      if (j < 0 || j >= n) {
        continue;
      }
      score += a[i] * b[j];
    }
    if (score > bestScore) {
      bestScore = score;
      bestLag = lag;
    }
  }
  return bestLag;
}
