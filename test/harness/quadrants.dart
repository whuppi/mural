import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mural/mural.dart';

/// A 200x100 logical test card: four solid quadrant colors, exact and
/// assertable at any pixel ratio.
Widget quadrants() => const Column(
  children: [
    Row(
      children: [
        SizedBox(
          width: 100,
          height: 50,
          child: ColoredBox(color: Color(0xFFFF0000)),
        ),
        SizedBox(
          width: 100,
          height: 50,
          child: ColoredBox(color: Color(0xFF00FF00)),
        ),
      ],
    ),
    Row(
      children: [
        SizedBox(
          width: 100,
          height: 50,
          child: ColoredBox(color: Color(0xFF0000FF)),
        ),
        SizedBox(
          width: 100,
          height: 50,
          child: ColoredBox(color: Color(0xFFFFFFFF)),
        ),
      ],
    ),
  ],
);

/// Decodes a PNG capture through the independent `package:image`
/// decoder, asserting the dimensions match the capture's claim.
img.Image decodeShot(MuralImage shot) {
  expect(shot.format, MuralFormat.png);
  final decoded = img.decodePng(shot.bytes);
  expect(decoded, isNotNull, reason: 'output must be a valid PNG');
  expect(decoded!.width, shot.width);
  expect(decoded.height, shot.height);
  return decoded;
}

/// Asserts the four quadrant colors of [quadrants] at any scale.
void expectQuadrants(img.Image image, int width, int height) {
  ({int r, int g, int b}) at(double fx, double fy) {
    final p = image.getPixel((width * fx).round(), (height * fy).round());
    return (r: p.r.toInt(), g: p.g.toInt(), b: p.b.toInt());
  }

  expect(at(0.25, 0.25), (r: 255, g: 0, b: 0), reason: 'top-left red');
  expect(at(0.75, 0.25), (r: 0, g: 255, b: 0), reason: 'top-right green');
  expect(at(0.25, 0.75), (r: 0, g: 0, b: 255), reason: 'bottom-left blue');
  expect(at(0.75, 0.75), (
    r: 255,
    g: 255,
    b: 255,
  ), reason: 'bottom-right white');
}
