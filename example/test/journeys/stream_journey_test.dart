// Stream journey — captureInto() through the real UI: bands through a
// tight budget with live progress, the rawRgba escape hatch, and
// cooperative cancellation from the status bar.

import 'package:mural_example_test_support/mural_example_test_support.dart';

void main() {
  testJourneyAcrossDevices('stream: bands flow through a tight budget', (
    tester,
    device,
  ) async {
    final app = AppRobot(tester);
    final tab = CaptureRobot(tester);
    await app.launch();
    await app.openTab('Stream');

    await tab.runOp('Stream the poster');
    await tab.awaitStatus('✓ streamed');
    await tab.expectShot();

    await tab.runOp('Raw straight RGBA');
    await tab.awaitStatus('✓ rawRgba');
  });

  testJourneyAcrossDevices('stream: Cancel stops a capture mid-flight', (
    tester,
    device,
  ) async {
    final app = AppRobot(tester);
    final tab = CaptureRobot(tester);
    await app.launch();
    await app.openTab('Stream');

    await tab.runOp('Start, then cancel');
    await tab.tapCancel();
    await tab.awaitStatus('✓ cancelled cleanly');
  });
}
