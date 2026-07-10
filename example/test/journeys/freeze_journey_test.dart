// On-screen journey — captureBoundary() through the real UI: the
// frozen moment on a live animation, a burst series, the plain
// RepaintBoundary path, and the unmounted-key error.

import 'package:mural_example_test_support/mural_example_test_support.dart';

void main() {
  testJourneyAcrossDevices('boundary: freeze, burst, plain, error', (
    tester,
    device,
  ) async {
    final app = AppRobot(tester);
    final tab = CaptureRobot(tester);
    await app.launch();
    await app.openTab('On screen');

    await tab.runOp('Freeze the moment');
    await tab.awaitStatus('✓ froze the moment');
    await tab.expectShot();

    await tab.runOp('Plain RepaintBoundary');
    await tab.awaitStatus('✓ plain boundary');

    await tab.runOp('Unmounted key');
    await tab.awaitStatus('MuralBoundaryError');
  });
}
