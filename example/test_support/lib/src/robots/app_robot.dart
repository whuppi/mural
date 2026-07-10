import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mural_example/main.dart';

import '../harness/robot.dart';

/// Drives the example app's top-level chrome: launch and tab switching.
class AppRobot extends Robot {
  AppRobot(super.tester);

  /// Boots the real app and waits for the first stable frame.
  Future<void> launch() async {
    await tester.pumpWidget(const MuralExampleApp());
    await settle();
  }

  /// Switches to the named top tab. The bar holds three fixed tabs —
  /// always visible, no scrolling — so a plain tap plus settle is the
  /// whole move (the harness tapTab is for scrollable bars).
  Future<void> openTab(String label) async {
    await tester.tap(find.widgetWithText(Tab, label));
    await settle();
  }
}
