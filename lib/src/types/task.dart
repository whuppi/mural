import 'dart:async';

import 'package:mural/src/types/errors.dart';
import 'package:mural/src/types/progress.dart';

/// A running capture: awaitable like a [Future], observable via
/// [progress], and cancellable.
///
/// ```dart
/// final task = mural.capture(bigWidget, context: context);
/// task.progress.listen((p) => setState(() => _fraction = p.fraction));
/// cancelButton.onPressed = task.cancel;
/// final shot = await task; // throws MuralCancelled if cancelled
/// ```
class MuralTask<T> implements Future<T> {
  MuralTask._(this._progress);

  /// Creates a task and hands the engine its completion + progress hooks.
  ///
  /// Not for package consumers — captures create their own tasks.
  factory MuralTask.internal() = MuralTask<T>._internal;

  MuralTask._internal() : this._(StreamController<MuralProgress>.broadcast());

  final Completer<T> _completer = Completer<T>();
  final StreamController<MuralProgress> _progress;
  bool _cancelled = false;

  /// Progress reports, from `layout` through `encode`.
  ///
  /// The stream closes when the task completes, fails, or is cancelled.
  Stream<MuralProgress> get progress => _progress.stream;

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Requests cooperative cancellation.
  ///
  /// The capture stops at the next band boundary; the awaited future then
  /// completes with [MuralCancelled]. Calling [cancel] after completion
  /// has no effect.
  void cancel() => _cancelled = true;

  // ── Engine-side hooks ──────────────────────────────────────────────

  /// Reports progress to listeners. Engine-side only.
  void report(MuralProgress event) {
    if (!_progress.isClosed) {
      _progress.add(event);
    }
  }

  /// Completes the task successfully. Engine-side only.
  void complete(T value) {
    if (!_completer.isCompleted) {
      _completer.complete(value);
    }
    _close();
  }

  /// Completes the task with an error. Engine-side only.
  void fail(Object error, StackTrace stackTrace) {
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace);
    }
    _close();
  }

  void _close() {
    if (!_progress.isClosed) {
      unawaited(_progress.close());
    }
  }

  // ── Future<T> delegation ───────────────────────────────────────────

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) => _completer.future.then(onValue, onError: onError);

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) =>
      _completer.future.catchError(onError, test: test);

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) =>
      _completer.future.whenComplete(action);

  @override
  Stream<T> asStream() => _completer.future.asStream();

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) =>
      _completer.future.timeout(timeLimit, onTimeout: onTimeout);
}
