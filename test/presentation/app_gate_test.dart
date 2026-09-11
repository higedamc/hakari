import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/domain/entities/app_settings.dart';
import 'package:hakari/presentation/app.dart';
import 'package:hakari/presentation/screens/onboarding_screen.dart';
import 'package:hakari/presentation/screens/root_shell.dart';

import 'screen_fakes.dart';

/// The root gate still sends first launches to onboarding and everyone else
/// into the tab shell.
void main() {
  Widget app(AppSettings settings) =>
      scopedForScreens(const HakariApp(), settings: settings);

  testWidgets('first launch without a signer shows onboarding', (tester) async {
    await tester.pumpWidget(app(const AppSettings()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(RootShell), findsNothing);
    // Welcome splash auto-advances; let it settle before teardown.
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed onboarding lands in the tab shell', (tester) async {
    await tester.pumpWidget(app(const AppSettings(onboardingComplete: true)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(RootShell), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pre-existing signer skips onboarding', (tester) async {
    await tester.pumpWidget(
      app(const AppSettings(signerMode: SignerMode.localKey)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(RootShell), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });
}
