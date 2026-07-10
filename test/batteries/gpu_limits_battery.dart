/// Exercises the GPU-ceiling learner: exact fits teach nothing,
/// proportional clamps reveal the ceiling from the longest side, and
/// failures back off geometrically to the spec floor. Pure logic —
/// both runners execute it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mural/src/capture/gpu_limits.dart';

void runGpuLimitsBattery() {
  group('gpu limits', () {
    test('plans at the requested size before anything is learned', () {
      final limits = GpuLimits();
      expect(limits.learnedMax, isNull);
      expect(limits.planningCeiling(20000), 20000);
    });

    test('an exact result teaches nothing', () {
      final limits = GpuLimits();
      final usable = limits.interpret(
        width: 1024,
        height: 768,
        requestedWidth: 1024,
        requestedHeight: 768,
      );
      expect(usable, isTrue);
      expect(limits.learnedMax, isNull);
    });

    test('a proportional clamp reveals the ceiling from the longest side', () {
      final limits = GpuLimits();
      // The engine scales 20000x500 by 16384/20000 → 16384x409. The
      // SHRUNK side must not be mistaken for the ceiling.
      final usable = limits.interpret(
        width: 16384,
        height: 409,
        requestedWidth: 20000,
        requestedHeight: 500,
      );
      expect(usable, isFalse);
      expect(limits.learnedMax, 16384);
    });

    test('the learned ceiling caps later plans', () {
      final limits = GpuLimits()
        ..interpret(
          width: 16384,
          height: 409,
          requestedWidth: 20000,
          requestedHeight: 500,
        );
      expect(limits.planningCeiling(20000), 16384);
      expect(limits.planningCeiling(1000), 16384);
    });

    test('a zero-sized result backs off geometrically', () {
      final limits = GpuLimits();
      final usable = limits.interpret(
        width: 0,
        height: 0,
        requestedWidth: 16384,
        requestedHeight: 16384,
      );
      expect(usable, isFalse);
      expect(limits.learnedMax, 8192);
    });

    test('failures halve toward the spec floor and stop there', () {
      final limits = GpuLimits()..recordFailure(16384);
      expect(limits.learnedMax, 8192);
      limits.recordFailure(8192);
      expect(limits.learnedMax, 4096);
      limits.recordFailure(4096);
      expect(limits.learnedMax, GpuLimits.specFloor);
      limits.recordFailure(GpuLimits.specFloor);
      expect(limits.learnedMax, GpuLimits.specFloor);
    });

    test('the walk from 16384 to the floor fits in maxRetries', () {
      final limits = GpuLimits();
      var attempts = 0;
      while (limits.learnedMax != GpuLimits.specFloor) {
        limits.recordFailure(limits.planningCeiling(16384));
        attempts++;
      }
      expect(attempts, lessThanOrEqualTo(GpuLimits.maxRetries));
    });

    test('a clamp below the spec floor still floors the ceiling', () {
      final limits = GpuLimits()
        ..interpret(
          width: 1000,
          height: 400,
          requestedWidth: 4000,
          requestedHeight: 1600,
        );
      expect(limits.learnedMax, GpuLimits.specFloor);
    });

    test('back-off never raises an already-lower ceiling', () {
      final limits = GpuLimits()..recordFailure(8192);
      expect(limits.learnedMax, 4096);
      // A failure at a larger request must not reset the ceiling upward.
      limits.recordFailure(16384);
      expect(limits.learnedMax, GpuLimits.specFloor);
    });
  });
}
