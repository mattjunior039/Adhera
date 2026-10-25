import 'package:adhera/repositories/dose_verification_repository.dart';
import 'package:adhera/screens/dose_verification_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> eventJson() => {
  'id': 1,
  'user_id': 1,
  'medication_id': null,
  'schedule_id': null,
  'recognized_medication': 'ibuprofen',
  'inventory_updated': false,
  'compartment_index': 10,
  'assumed_label': 'WED_PM',
  'expected_label': 'FRI_PM',
  'am_row': null,
  'period_confident': true,
  'orientation_calibrated': false,
  'wrong_slot': true,
  'pre_count': 3,
  'post_count': 2,
  'event_type': 'CANDIDATE_TRANSFER',
  'confidence': 1.0,
  'requires_review': true,
  'frames_sampled': 12,
  'frames_accepted': 10,
  'created_at': '2026-10-16T12:00:00Z',
  'prototype': 'official_blue_pm',
  'destination_label': 'TUE_PM',
  'reason': 'Same-class transfer; not a net removal.',
};

void main() {
  test('parses official evidence without breaking legacy events', () {
    final json = eventJson();
    final result = DoseVerificationEvent.fromJson(json);
    expect(result.prototype, 'official_blue_pm');
    expect(result.destinationLabel, 'TUE_PM');
    expect(result.requiresReview, isTrue);
    expect(result.inventoryUpdated, isFalse);
    json.remove('prototype');
    json.remove('reason');
    json.remove('destination_label');
    final legacy = DoseVerificationEvent.fromJson(json);
    expect(legacy.prototype, isNull);
    expect(legacy.reason, isNull);
    expect(legacy.destinationLabel, isNull);
  });

  testWidgets(
    'official transfer stays review-only and cannot flip orientation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DoseVerificationResultScreen(
              result: DoseVerificationEvent.fromJson(eventJson()),
            ),
          ),
        ),
      );
      expect(find.text('Possible pill transfer, not removal'), findsOneWidget);
      expect(find.text('Transfer destination: TUE_PM'), findsOneWidget);
      expect(find.text('Unknown result'), findsNothing);
      expect(find.text('Sunday is on the right'), findsNothing);
      await tester.scrollUntilVisible(
        find.textContaining('Manual review required'),
        200,
      );
      expect(find.textContaining('does not prove ingestion'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
