import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isolates_in_practice/scenarios/audio_merge/audio_page.dart';
import 'package:isolates_in_practice/scenarios/lottie_bundle/lottie_page.dart';
import 'package:isolates_in_practice/scenarios/photo_filter/photo_page.dart';

/// Taps "Background isolate" on a real page and waits for the result.
///
/// These tests guard against a real bug: an `Isolate.run` closure created
/// inside a State captured the widget and failed with "Illegal argument in
/// isolate message". Unit tests of the logic did not catch it.
Future<void> runInBackground(
  WidgetTester tester,
  Widget page,
  String expected,
) async {
  await tester.pumpWidget(MaterialApp(home: page));
  for (
    var i = 0;
    i < 100 &&
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed ==
            null;
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.tap(find.text('Background isolate'));
  for (
    var i = 0;
    i < 200 && find.textContaining(expected).evaluate().isEmpty;
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.textContaining(expected), findsOneWidget);
}

void main() {
  testWidgets('photo page runs in a background isolate', (tester) async {
    await runInBackground(tester, const PhotoPage(), 'Isolate.run: 4000x3000');
  });

  testWidgets('lottie page unpacks in a background isolate', (tester) async {
    await runInBackground(
      tester,
      const LottiePage(),
      'Isolate.run: 150 animations',
    );
  });

  testWidgets('audio page merges in a background isolate', (tester) async {
    // No platform in tests: answer path_provider's getTemporaryDirectory.
    final tmp = Directory.systemTemp.createTempSync('audio_page');
    addTearDown(() => tmp.deleteSync(recursive: true));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
    await runInBackground(tester, const AudioPage(), 'Isolate.run: 118 s');
  });
}
