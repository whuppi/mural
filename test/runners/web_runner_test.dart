/// Runs the IDENTICAL batteries as native_runner_test.dart, in a real
/// web engine — where the PNG worker is the inline fallback and captures
/// rasterize through the web renderer.
///
/// Run with `flutter test --platform chrome test/runners/web_runner_test.dart`.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';

import '../batteries/capture_battery.dart';
import '../batteries/encode_battery.dart';
import '../batteries/gpu_limits_battery.dart';
import '../batteries/worker_battery.dart';

void main() {
  runGpuLimitsBattery();
  runEncodeBattery();
  runWorkerBattery();
  runCaptureBattery();
}
