import 'dart:ui' as ui;

import 'package:adhera/app.dart';
import 'package:adhera/state/adherence.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default alert phone number is configurable', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(alertPhoneProvider), '6084485111');
    container.read(alertPhoneProvider.notifier).update('6081234567');
    expect(container.read(alertPhoneProvider), '6081234567');
  });

  testWidgets('logo background is transparent', (tester) async {
    await tester.runAsync(() async {
      final data = await rootBundle.load('assets/adhera_logo.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final pixels = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(pixels!.getUint8(3), 0);
      expect(pixels.getUint8((60 * frame.image.width + 175) * 4 + 3), 255);
      frame.image.dispose();
      codec.dispose();
    });
  });

  testWidgets('app does not enter a local demo session without credentials', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: AdheraApp()));
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'Adhera',
    );
    expect(
      find.image(const AssetImage('assets/adhera_logo.png')),
      findsOneWidget,
    );

    expect(find.text('Welcome back'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Quick actions'), findsNothing);
    expect(find.text('Enter your account email'), findsOneWidget);
  });
}
