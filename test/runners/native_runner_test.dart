/// Runs every platform-blind battery on the VM, where the PNG worker is
/// a real isolate. The SAME batteries run in a real web engine via
/// web_runner_test.dart — one spec, two worlds, a platform-dependent
/// result is a red build, not an unknown.
///
/// VM-bound suites (isolate hand-off semantics) are quarantined in
/// test/platform/native/ and never appear here.
@TestOn('vm')
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
