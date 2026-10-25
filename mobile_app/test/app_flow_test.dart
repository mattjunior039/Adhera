import 'dart:async';

import 'package:adhera/app.dart';
import 'package:adhera/app_router.dart';
import 'package:adhera/models/medication.dart';
import 'package:adhera/models/schedule.dart';
import 'package:adhera/models/user.dart';
import 'package:adhera/repositories/dose_verification_repository.dart';
import 'package:adhera/repositories/medication_repository.dart';
import 'package:adhera/repositories/pillbox_inventory_repository.dart';
import 'package:adhera/repositories/sample_day_provider.dart';
import 'package:adhera/screens/home_dashboard_screen.dart';
import 'package:adhera/state/adherence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sampleUser = User(
    id: 1,
    email: 'adherasample@gmail.com',
    fullName: 'Adhera Test',
  );
  const demoMeds = [
    Medication(id: 1, userId: 1, name: 'Ibuprofen'),
    Medication(id: 2, userId: 1, name: 'Acetaminophen'),
    Medication(id: 3, userId: 1, name: 'Iron'),
    Medication(id: 4, userId: 1, name: 'Potassium'),
  ];
  final demoSchedules = [
    for (var id = 1; id <= 8; id++)
      Schedule(
        id: id,
        userId: 1,
        medicationId: (id - 1) % 4 + 1,
        dayOfWeek: 'Wednesday',
        timeOfDay: id <= 4 ? '08:00:00' : '18:00:00',
        notes: 'DEMO ONLY: 1 pill(s); not dosing advice.',
      ),
    const Schedule(
      id: 9,
      userId: 1,
      medicationId: 1,
      dayOfWeek: 'Friday',
      timeOfDay: '08:00:00',
      notes: 'DEMO ONLY:',
    ),
  ];

  ProviderContainer sampleContainer() {
    final container = ProviderContainer(
      overrides: [
        medicationsByUserProvider(1).overrideWith((ref) async => demoMeds),
        scheduleByUserProvider(1).overrideWith((ref) async => demoSchedules),
        pillboxInventoryProvider(1)
            .overrideWith((ref) async => <PillboxInventorySlot>[]),
        doseVerificationEventsProvider(1)
            .overrideWith((ref) async => <DoseVerificationEvent>[]),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentUserProvider.notifier).setUser(sampleUser);
    return container;
  }

  test('sample Wednesday states are scoped and do not mark PM or other days complete', () async {
    final container = sampleContainer();
    expect(container.read(displayedWeekdayProvider), DateTime.wednesday);
    expect(await container.read(todayAdherenceProvider.future), {
      1: 'missed',
      2: 'taken',
      3: 'taken',
      4: 'taken',
    });
    expect(
      container.read(activeMedicationAlertsProvider).single.title,
      'Ibuprofen not taken',
    );
    container.read(sampleDoseStatusesProvider.notifier).update(1, 'taken');
    await container.read(todayAdherenceProvider.future);
    expect(container.read(activeMedicationAlertsProvider), isEmpty);
    container.read(currentUserProvider.notifier).clear();
    expect(container.read(isSampleProfileProvider), isFalse);
    expect(container.read(displayedWeekdayProvider), DateTime.now().weekday);
    expect(container.read(sampleDoseStatusesProvider), isEmpty);
  });

  testWidgets('alerts shows missed Wednesday ibuprofen and can return home', (
    tester,
  ) async {
    final container = sampleContainer();
    final router = container.read(appRouterProvider);
    router.go('/dashboard');
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AdheraApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alerts').last);
    await tester.pumpAndSettle();
    expect(find.text('Ibuprofen not taken'), findsOneWidget);
    expect(find.textContaining('Wednesday 8:00 AM'), findsOneWidget);
    expect(find.text('6084485111'), findsOneWidget);
    expect(find.text('All caught up! No active alerts.'), findsNothing);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Today\u2019s schedule'), findsOneWidget);
    router.go('/caregiver');
    await tester.pumpAndSettle();
    expect(find.text('Care team'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Today\u2019s schedule'), findsOneWidget);
    router.go('/caregiver');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alerts').last);
    await tester.pumpAndSettle();
    expect(find.text('Ibuprofen not taken'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    router.push('/settings');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Today\u2019s schedule'), findsOneWidget);
    router.go('/settings');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Today\u2019s schedule'), findsOneWidget);
    router.go('/alerts');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Today\u2019s schedule'), findsOneWidget);
  });

  testWidgets(
    'sample dashboard shows Wednesday completion and missed ibuprofen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = sampleContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomeDashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final dashboardList = tester.widget<ListView>(
        find.byType(ListView).first,
      );
      final children =
          dashboardList.childrenDelegate as SliverChildListDelegate;
      expect((children.children.first as Text).data, 'Today\u2019s schedule');
      for (var id = 5; id <= 8; id++) {
        final card = find.byKey(ValueKey('dose-$id'));
        expect(card, findsOneWidget);
        expect(
          find.descendant(
            of: card,
            matching: find.text(demoMeds[(id - 1) % 4].name),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('Today\u2019s overview'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byKey(const ValueKey('dose-1')), findsNothing);
      expect(find.text('Complete'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Completed (3)'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Completed (3)'));
      await tester.pumpAndSettle();
      expect(find.text('Complete'), findsNWidgets(3));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dose-1')),
          matching: find.text('Missed'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Completed (3)'));
      await tester.pumpAndSettle();
      expect(find.text('Complete'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dose-5')),
          matching: find.text('Complete'),
        ),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('dose-9')), findsNothing);
      await tester.tap(find.text('Completed (3)'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('dose-1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('dose-1')),
          matching: find.byTooltip('Mark taken'),
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(todayAdherenceProvider).requireValue[1], 'taken');
      expect(container.read(activeMedicationAlertsProvider), isEmpty);
      await tester.scrollUntilVisible(
        find.text('Completed (4)'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('dose-1')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('dose-1')),
          matching: find.byTooltip('Undo'),
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(todayAdherenceProvider).requireValue[1], 'unknown');
    },
  );

  testWidgets(
    'dashboard is usable while inventory and history are still pending',
    (tester) async {
      final inventory = Completer<List<PillboxInventorySlot>>();
      final events = Completer<List<DoseVerificationEvent>>();
      var adherenceStarted = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            medicationsByUserProvider(1).overrideWith(
              (ref) async => const [
                Medication(id: 1, userId: 1, name: 'Acetaminophen'),
              ],
            ),
            scheduleByUserProvider(1)
                .overrideWith((ref) async => const <Schedule>[]),
            pillboxInventoryProvider(1).overrideWith((ref) => inventory.future),
            doseVerificationEventsProvider(1)
                .overrideWith((ref) => events.future),
            todayAdherenceProvider.overrideWith((ref) async {
              adherenceStarted = true;
              return <int, String>{};
            }),
          ],
          child: const MaterialApp(home: HomeDashboardScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(adherenceStarted, isTrue);
      expect(find.text('Quick actions'), findsOneWidget);
      expect(find.text('Verify with video'), findsNothing);
      expect(find.text('Verify dose'), findsNothing);
      expect(find.text('Set schedule'), findsOneWidget);
      expect(inventory.isCompleted, isFalse);
      expect(events.isCompleted, isFalse);
      inventory.completeError(Exception('Inventory unavailable'));
      events.completeError(Exception('History unavailable'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('Quick actions'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Could not load pillbox inventory'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Could not load pillbox inventory'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'original dashboard renders backend medication and compartment data',
    (tester) async {
      const medications = [
        Medication(id: 1, userId: 1, name: 'Acetaminophen', dosage: '500 mg'),
        Medication(id: 2, userId: 1, name: 'Ibuprofen', dosage: '200 mg'),
      ];
      const days = [
        'Sunday',
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
      ];
      var slotId = 1;
      final slots = [
        for (final day in days)
          for (final period in const ['AM', 'PM'])
            PillboxInventorySlot(
              id: slotId++,
              userId: 1,
              dayOfWeek: day,
              period: period,
              medicationId: period == 'AM' ? 1 : 2,
              medicationName: period == 'AM' ? 'Acetaminophen' : 'Ibuprofen',
              pillCount: period == 'AM' ? 2 : 1,
            ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            medicationsByUserProvider(1)
                .overrideWith((ref) async => medications),
            scheduleByUserProvider(1)
                .overrideWith((ref) async => const <Schedule>[]),
            pillboxInventoryProvider(1).overrideWith((ref) async => slots),
            doseVerificationEventsProvider(1)
                .overrideWith((ref) async => const <DoseVerificationEvent>[]),
            todayAdherenceProvider.overrideWith((ref) async => <int, String>{}),
          ],
          child: const MaterialApp(home: HomeDashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Quick actions'), findsOneWidget);
      expect(find.text('Verify with video'), findsNothing);
      expect(find.text('Verify dose'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Weekly pillbox contents'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.scrollUntilVisible(
        find.textContaining('Acetaminophen').first,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Weekly pillbox contents'), findsOneWidget);
      expect(find.textContaining('Acetaminophen'), findsWidgets);
      expect(find.textContaining('Ibuprofen'), findsWidgets);
      expect(find.textContaining('pill(s) in compartment'), findsWidgets);
    },
  );
}
