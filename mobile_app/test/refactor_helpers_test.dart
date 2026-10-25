import 'dart:io';

import 'package:adhera/models/medication.dart';
import 'package:adhera/services/label_frame_analysis.dart';
import 'package:adhera/state/prescriptions.dart';
import 'package:adhera/widgets/time_labels.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('instruction builder preserves order, separator and empty values', () {
    expect(buildMedicationInstructions({}, '  '), isNull);
    expect(buildMedicationInstructions({}, '  Custom note  '), 'Custom note');
    expect(
      buildMedicationInstructions({
        'With water',
        'At bedtime',
      }, '  Custom note '),
      'With water \u2022 At bedtime \u2022 Custom note',
    );
  });

  test('relative time keeps both existing label styles at boundaries', () {
    final now = DateTime(2026, 10, 17, 12);
    for (final (duration, long, short) in [
      (const Duration(minutes: 59), '59 min ago', '59m ago'),
      (const Duration(hours: 1), '1 hr ago', '1h ago'),
      (const Duration(hours: 23), '23 hr ago', '23h ago'),
      (const Duration(days: 1), '1 day(s) ago', '1d ago'),
    ]) {
      expect(relativeTime(now.subtract(duration), now: now), long);
      expect(
        relativeTime(now.subtract(duration), compact: true, now: now),
        short,
      );
    }
  });

  test(
    'keyframe selection preserves endpoints and returns a separate list',
    () {
      final frames = List.generate(8, (index) => File('frame-$index.jpg'));
      expect(selectSemanticFusionKeyframes(frames), [
        frames[0],
        frames[2],
        frames[5],
        frames[7],
      ]);
      expect(selectSemanticFusionKeyframes(frames.take(5).toList()), [
        frames[0],
        frames[2],
        frames[4],
      ]);
      final small = frames.take(3).toList();
      expect(selectSemanticFusionKeyframes(small), small);
      expect(identical(selectSemanticFusionKeyframes(small), small), isFalse);
      expect(selectSemanticFusionKeyframes([]), isEmpty);
    },
  );

  test('horizontal shift keeps insufficient-profile and lag behavior', () {
    expect(estimateHorizontalShift([], [1]), 0);
    expect(estimateHorizontalShift([1, 2], [2, 1]), 0);
    final first = List<double>.filled(100, 0)..[35] = 1;
    final shifted = List<double>.filled(100, 0)..[47] = 1;
    expect(estimateHorizontalShift(first, shifted), 12);
    expect(estimateHorizontalShift(shifted, first), -12);
    expect(estimateHorizontalShift(first, first), 0);
  });

  test('blank and narrow frames cannot claim readable label bounds', () {
    for (final width in [10, 100]) {
      final analysis = analyzeGuideEdgeRegion(
        img.Image(width: width, height: 100),
      );
      expect(analysis.bounds, isNull);
      expect(analysis.edgeHitCount, 0);
      expect(
        analysis.segmentEdgeDensity,
        List<double>.filled(labelSweepSegments, 0),
      );
    }
  });

  test('prescription transitions preserve details and unrelated entries', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(pendingPrescriptionsProvider.notifier);
    for (final id in [1, 2]) {
      notifier.add(
        PendingPrescription(
          id: id,
          medicationName: 'Medication $id',
          dosage: '500 mg',
          scannedAt: DateTime(2026),
          instructions: 'With water',
        ),
      );
    }
    final second = container.read(pendingPrescriptionsProvider)[1];
    notifier.patientConfirm(1, note: 'Checked');
    notifier.approve(1, verifiedBy: 'Reviewer', note: 'Approved');
    var first = container.read(pendingPrescriptionsProvider).first;
    expect(first.status, VerificationStatus.approved);
    expect(first.patientNote, 'Checked');
    expect(first.instructions, 'With water');
    expect(first.verifiedAt, isNotNull);
    notifier.reject(1, verifiedBy: 'Reviewer', reason: 'Needs another scan');
    first = container.read(pendingPrescriptionsProvider).first;
    expect(first.status, VerificationStatus.rejected);
    expect(first.verifierNote, 'Needs another scan');
    expect(
      identical(container.read(pendingPrescriptionsProvider)[1], second),
      isTrue,
    );
  });
}
