import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness/robot.dart';

/// Drives a demo tab: runs an op card and awaits its status line.
///
/// A mural capture rasterizes on the engine — real async work that
/// cannot complete under the test binding's fake clock. [awaitStatus]
/// therefore alternates short real-async windows (where the engine
/// makes progress) with fake-clock elapses (where the pipeline's
/// zero-delay timers fire and the UI catches up), bounded by a
/// wall-clock timeout.
class CaptureRobot extends Robot {
  CaptureRobot(super.tester);

  /// The ACTIVE tab's op list. Every tab keys its list 'demo-list';
  /// only the on-stage one is hit-testable.
  Finder get _list => find
      .descendant(
        of: find.byKey(const ValueKey('demo-list')),
        matching: find.byType(Scrollable),
      )
      .hitTestable()
      .first;

  /// Taps the Run button of the op card titled [title].
  Future<void> runOp(String title) async {
    // Re-home to the top first: scrollUntilVisible only searches
    // downward.
    await tester.drag(_list, const Offset(0, 10000));
    await settle();
    final target = find.byKey(ValueKey('run:$title')).hitTestable();
    await tester.scrollUntilVisible(target, 120, scrollable: _list);
    // Settle BEFORE tapping: a tap during leftover fling momentum is
    // awarded to the scrollable as a stop-gesture, not to the button.
    await settle();
    await tester.tap(target);
    await tester.pump();
  }

  /// Taps the status bar's Cancel button (visible while a task runs).
  Future<void> tapCancel() async {
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').hitTestable());
    await tester.pump();
  }

  /// Taps the app-bar theme toggle.
  Future<void> toggleTheme() async {
    await tester.tap(find.byKey(const ValueKey('toggle-theme')));
    await settle();
  }

  /// Waits until the active tab's status line contains [snippet].
  Future<void> awaitStatus(
    String snippet, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    // DateTime is real wall clock even under the fake test clock.
    final deadline = DateTime.now().add(timeout);
    while (true) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      // The elapse matters: the capture pipeline's zero-delay timers
      // live on the FAKE clock, and pump() without a duration renders a
      // frame without advancing it.
      await tester.pump(const Duration(milliseconds: 20));
      if (_statusLines().any((line) => line.contains(snippet))) {
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        fail(
          'status containing "$snippet" never appeared.\n'
          'Status now: ${_statusLines().join(' | ')}',
        );
      }
    }
  }

  /// Asserts a captured result image is on screen (scrolls to it — the
  /// result section sits at the end of the op list, so it may not even
  /// be BUILT until scrolled to; the finder stays unwrapped so
  /// scrollUntilVisible can poll it while empty).
  Future<void> expectShot() async {
    final shots = find.descendant(
      of: find.byKey(const ValueKey('demo-list')),
      matching: find.byType(Image),
    );
    await tester.scrollUntilVisible(shots, 120, scrollable: _list);
    await settle();
    expectVisible(shots.first);
  }

  /// Returns the encoded bytes of the newest on-screen result image, so
  /// journeys can verify the CONTENT of a capture — not just that one
  /// rendered. This is what catches a demo whose pixels don't match its
  /// claim (a non-mirrored RTL capture, a photo lost in its slot).
  Future<Uint8List> shotBytes() async {
    final shots = find.descendant(
      of: find.byKey(const ValueKey('demo-list')),
      matching: find.byType(Image),
    );
    await tester.scrollUntilVisible(shots, 120, scrollable: _list);
    await settle();
    var provider = tester.widgetList<Image>(shots).last.image;
    // Image.memory with a cacheWidth wraps its MemoryImage in a
    // ResizeImage; the resize is display-only — the wrapped provider
    // still holds the untouched encoded bytes.
    if (provider is ResizeImage) {
      provider = provider.imageProvider;
    }
    return (provider as MemoryImage).bytes;
  }

  Iterable<String> _statusLines() => tester
      .widgetList<Text>(find.byKey(const ValueKey('status-text')))
      .map((t) => t.data ?? '');
}
