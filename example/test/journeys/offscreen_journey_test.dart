// Offscreen journey — every capture() op through the real UI, on every
// device shape: pixel ratios, staging, both ready recipes, theme
// inheritance, and every typed error.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mural_example_test_support/mural_example_test_support.dart';

void main() {
  testJourneyAcrossDevices('offscreen: pixel ratios and staging', (
    tester,
    device,
  ) async {
    final app = AppRobot(tester);
    final tab = CaptureRobot(tester);
    await app.launch();

    await tab.runOp('Transcript @1x');
    await tab.awaitStatus('✓ Transcript @1x');
    await tab.expectShot();
    final ltr = await tab.shotBytes();

    await tab.runOp('Transcript @3x');
    await tab.awaitStatus('✓ Transcript @3x');

    await tab.runOp('Narrow constraints');
    await tab.awaitStatus('✓ Narrow constraints');

    await tab.runOp('Transparent background');
    await tab.awaitStatus('✓ Transparent background');

    await tab.runOp('Right-to-left');
    await tab.awaitStatus('✓ Right-to-left');
    final rtl = await tab.shotBytes();

    // The RTL capture must be a real mirror of the LTR one. Bubble
    // ALIGNMENT can't discriminate here: the test environment's
    // every-glyph-is-a-square font makes bubbles span the full width on
    // both sides. The bubble's directional TAIL corner (sharp on the
    // speaker's side, round opposite) survives that — and flips with
    // directionality. Status text can't see any of this; only pixels can.
    expect(
      _bubbleTailIsLeft(ltr),
      isTrue,
      reason: "LTR: the incoming bubble's sharp tail corner sits left",
    );
    expect(
      _bubbleTailIsLeft(rtl),
      isFalse,
      reason:
          "RTL: the incoming bubble's sharp tail corner must flip to "
          'the right — a directionality-blind transcript renders '
          'identically to LTR',
    );
  });

  testJourneyAcrossDevices('offscreen: theme inheritance follows a toggle', (
    tester,
    device,
  ) async {
    final app = AppRobot(tester);
    final tab = CaptureRobot(tester);
    await app.launch();

    await tab.runOp('Themed card');
    await tab.awaitStatus('✓ Themed card');

    await tab.toggleTheme();
    await tab.runOp('Themed card');
    await tab.awaitStatus('✓ Themed card');
  });

  testJourneyAcrossDevices('offscreen: readiness is a signal, not a timer', (
    tester,
    device,
  ) async {
    final app = AppRobot(tester);
    final tab = CaptureRobot(tester);
    await app.launch();

    await tab.runOp('Image via precache');
    // The exact output size first: 96px image + 8px padding all round =
    // 112 logical, at the op's explicit pixelRatio 2 → 224×224.
    await tab.awaitStatus('✓ Image via precache → 224×224');
    // The photo must FILL its 96px slot inside 8px padding: about half
    // the capture area is the photo's orange, and the dead center is the
    // photo's white circle. A photo parked small in its slot (the
    // BoxFit.scaleDown default) or a blank placeholder fails here.
    final decoded = img.decodePng(await tab.shotBytes())!;
    var orange = 0;
    for (final pixel in decoded) {
      if (pixel.r.toInt() > 180 &&
          pixel.g.toInt() > 40 &&
          pixel.g.toInt() < 160 &&
          pixel.b.toInt() < 100) {
        orange++;
      }
    }
    final coverage = orange / (decoded.width * decoded.height);
    expect(
      coverage,
      inExclusiveRange(0.35, 0.65),
      reason:
          'the decoded photo must fill its slot '
          '(orange coverage was \${(coverage * 100).toStringAsFixed(1)}%)',
    );
    final center = decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
    expect(
      (center.r.toInt() > 245, center.g.toInt() > 245, center.b.toInt() > 245),
      (true, true, true),
      reason: 'the photo center must be the white circle',
    );

    await tab.runOp('Delayed data');
    await tab.awaitStatus('✓ Delayed data');
  });

  testJourneyAcrossDevices('offscreen: every failure is typed', (
    tester,
    device,
  ) async {
    final app = AppRobot(tester);
    final tab = CaptureRobot(tester);
    await app.launch();

    await tab.runOp('Empty widget');
    await tab.awaitStatus('MuralLayoutError');

    await tab.runOp('Unbounded widget');
    // Debug builds surface the framework's layout assert as a
    // MuralBuildError; release builds surface MuralLayoutError.
    await tab.awaitStatus('Error: Mural');

    await tab.runOp('Throwing build');
    await tab.awaitStatus('MuralBuildError');
  });
}

/// Whether the top transcript bubble's sharp "tail" corner is on the
/// LEFT. The bubble has a 2px tail corner on its speaker's side and a
/// 12px round corner opposite, so at a small inset from each top corner
/// exactly one side is ink. Scale-independent: the bubble's 6-logical
/// margin gives the capture's pixel ratio.
bool _bubbleTailIsLeft(Uint8List png) {
  final decoded = img.decodePng(png)!;
  bool isInk(img.Pixel p) =>
      p.r.toInt() < 240 || p.g.toInt() < 240 || p.b.toInt() < 240;

  // First inked row = the bubble's top edge, at 6 logical (its margin).
  var firstY = -1;
  for (var y = 0; y < decoded.height && firstY < 0; y++) {
    for (var x = 0; x < decoded.width; x++) {
      if (isInk(decoded.getPixel(x, y))) {
        firstY = y;
        break;
      }
    }
  }
  expect(firstY, greaterThan(0), reason: 'no bubble found in the capture');
  final r = firstY / 6.0;

  // Bubble x-extent measured below both corner radii.
  final deepY = (firstY + (14 * r).round()).clamp(0, decoded.height - 1);
  var left = -1;
  var right = -1;
  for (var x = 0; x < decoded.width; x++) {
    if (isInk(decoded.getPixel(x, deepY))) {
      left = left < 0 ? x : left;
      right = x;
    }
  }

  // At inset 2r from a top corner: a sharp 2r corner is ink, a round
  // 12r corner is still background (12r - inset·√2 leaves ~2r of clear
  // margin against antialiasing).
  final inset = (2 * r).round();
  final cy = firstY + inset;
  final tailLeft = isInk(decoded.getPixel(left + inset, cy));
  final tailRight = isInk(decoded.getPixel(right - inset, cy));
  expect(
    tailLeft != tailRight,
    isTrue,
    reason:
        'exactly one top corner must be the sharp tail '
        '(left=$tailLeft, right=$tailRight)',
  );
  return tailLeft;
}
