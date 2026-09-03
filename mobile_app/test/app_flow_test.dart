import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pillbox/main.dart';

void main() {
  testWidgets('app loads login screen and can navigate to dashboard', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PillboxApp()));

    expect(find.text('Welcome back'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.login_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Quick actions'), findsOneWidget);
  });

  testWidgets('dashboard exposes core actions for medication and photo verification', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PillboxApp()));

    await tester.tap(find.byIcon(Icons.login_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('Add medication'), findsWidgets);
    expect(find.text('Verify dose'), findsOneWidget);
  });

  testWidgets('signup includes phone number and shows seeded dashboard data', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PillboxApp()));

    await tester.tap(find.text('Create account').last);
    await tester.pumpAndSettle();

    expect(find.text('Phone number'), findsOneWidget);

    final createButton = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('Today\u2019s overview'), findsOneWidget);
    // Seeded metric chips confirm synthetic data is loaded
    expect(find.text('Meds'), findsOneWidget);
    expect(find.text('Alerts'), findsWidgets);
  });
}
