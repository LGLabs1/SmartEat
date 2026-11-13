import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/widgets/download_apps_card.dart';

void main() {
  testWidgets('renders download options and wires callbacks', (tester) async {
    var androidTaps = 0;
    var windowsTaps = 0;
    var iosTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadAppsCard(
            isWebOverride: true,
            onDownloadAndroid: () => androidTaps++,
            onDownloadWindows: () => windowsTaps++,
            onInstallIos: () => iosTaps++,
          ),
        ),
      ),
    );

    expect(find.text('Download Android APK'), findsOneWidget);
    expect(find.text('Download for Windows'), findsOneWidget);
    expect(find.text('Install on iPhone/iPad'), findsOneWidget);

    await tester.tap(find.text('Download Android APK'));
    await tester.tap(find.text('Download for Windows'));
    await tester.tap(find.text('Install on iPhone/iPad'));

    expect(androidTaps, 1);
    expect(windowsTaps, 1);
    expect(iosTaps, 1);
  });

  testWidgets('shows iOS install instructions by default', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DownloadAppsCard(isWebOverride: true),
        ),
      ),
    );

    await tester.tap(find.text('Install on iPhone/iPad'));
    await tester.pumpAndSettle();

    expect(find.text('1. Open Smart Eat in Safari.'), findsOneWidget);
    expect(find.text('3. Choose "Add to Home Screen", then tap Add.'),
        findsOneWidget);
  });

  testWidgets('hides the build already running on this device',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DownloadAppsCard(
            isWebOverride: false,
            platformOverride: TargetPlatform.windows,
          ),
        ),
      ),
    );

    expect(find.text('Download Android APK'), findsOneWidget);
    expect(find.text('Download for Windows'), findsNothing);
    expect(find.text('Install on iPhone/iPad'), findsOneWidget);
  });
}
