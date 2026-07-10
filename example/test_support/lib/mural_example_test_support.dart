/// The example's UI-test kit: the app-agnostic harness (robot base,
/// device matrix, hang-proof pump strategies) plus mural-specific
/// robots. Journeys and the integration smoke both import only this.
library;

export 'src/harness/device_matrix.dart';
export 'src/harness/device_profiles.dart';
export 'src/harness/pump_strategies.dart';
export 'src/harness/robot.dart';
export 'src/robots/app_robot.dart';
export 'src/robots/capture_robot.dart';
