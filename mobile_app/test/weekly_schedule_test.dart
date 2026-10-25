import 'package:adhera/models/medication.dart';
import 'package:adhera/models/schedule.dart';
import 'package:adhera/widgets/weekly_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats morning and evening schedule times', () {
    expect(scheduleTimeLabel('08:00:00'), '8:00 AM');
    expect(scheduleTimeLabel('18:00:00'), '6:00 PM');
    expect(scheduleTimeLabel('00:30:00'), '12:30 AM');
    expect(scheduleTimeLabel('12:00:00'), '12:00 PM');
  });

  testWidgets('scheduler shows exact quantity and opens instructions on tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WeeklySchedule(
              medications: [
                Medication(
                  id: 1,
                  userId: 9,
                  name: 'Potassium',
                  dosage: 'Demo - strength unspecified',
                  instructions: 'Demo only. Follow the product label and pharmacist directions.',
                ),
              ],
              schedules: [
                Schedule(
                  id: 1,
                  userId: 9,
                  medicationId: 1,
                  dayOfWeek: 'Saturday',
                  timeOfDay: '18:00:00',
                  notes: 'DEMO ONLY: 3 pill(s); not dosing advice.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Potassium'), findsNothing);
    await tester.tap(find.text('Saturday'));
    await tester.pumpAndSettle();
    expect(find.textContaining('6:00 PM'), findsOneWidget);
    expect(find.textContaining('3 pill(s)'), findsOneWidget);
    await tester.tap(find.text('Potassium'));
    await tester.pumpAndSettle();
    expect(find.text('Instructions'), findsOneWidget);
    expect(find.textContaining('Follow the product label'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Instructions'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
