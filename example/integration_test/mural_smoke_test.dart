// Integration smoke — one pass through every door on a REAL target
// (device, desktop, or browser): the UI journey end to end, plus a
// direct capture whose pixels are verified through an independent
// decoder. The journeys prove behavior across device shapes on the host
// VM; this proves the same package works on the actual engine + GPU of
// the target platform.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mural/mural.dart';
import 'package:mural_example/main.dart' as app;
import 'package:mural_example_test_support/mural_example_test_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every door works on this target', (tester) async {
    final robot = AppRobot(tester);
    final tab = CaptureRobot(tester);
    await robot.launch();

    await tab.runOp('Transcript @3x');
    await tab.awaitStatus('✓ Transcript @3x');
    await tab.expectShot();

    await robot.openTab('On screen');
    await tab.runOp('Freeze the moment');
    await tab.awaitStatus('✓ froze the moment');

    await robot.openTab('Stream');
    await tab.runOp('Stream the poster');
    await tab.awaitStatus('✓ streamed');
  });

  testWidgets('a direct capture is pixel-true on this engine', (tester) async {
    await tester.pumpWidget(const app.MuralExampleApp());
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold).first);

    final shot = await app.mural.capture(
      const SizedBox(
        width: 40,
        height: 20,
        child: ColoredBox(color: Color(0xFF3F51B5)),
      ),
      context: context,
      options: const MuralOptions(pixelRatio: 2),
    );

    expect(shot.width, 80);
    expect(shot.height, 40);
    final decoded = img.decodePng(shot.bytes);
    expect(decoded, isNotNull, reason: 'output must be a real PNG');
    final p = decoded!.getPixel(40, 20);
    expect(
      (p.r.toInt(), p.g.toInt(), p.b.toInt()),
      (0x3F, 0x51, 0xB5),
      reason: 'pixels must survive capture + encode on this engine',
    );
  });
}
