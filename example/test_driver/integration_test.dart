// Web leg driver — `flutter drive` runs the integration smoke in a real
// Chrome via chromedriver (see Makefile test-example-web).
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
