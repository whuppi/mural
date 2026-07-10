import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:mural/src/types/errors.dart';
import 'package:mural/src/types/stage.dart';
import 'package:mural/src/capture/scene_boundary.dart';

/// An isolated render tree that lays out and paints one widget offscreen.
///
/// The tree owns its [PipelineOwner] and roots its own [BuildScope] on
/// the binding's [BuildOwner] (GlobalKeys resolve against that owner's
/// registry — a private owner breaks material widgets like [ListTile]).
/// It is never registered for frames, hit testing, or semantics, and its
/// dirty elements never enter the app's build passes.
///
/// The hosted widget gets a faithful ambient context:
///
/// * every [InheritedTheme] above `context`, via [InheritedTheme.captureAll]
/// * a [MediaQuery] copied from `context` with `devicePixelRatio` set to
///   the capture ratio, so asset images resolve at capture resolution —
///   and so [Scrollable] and friends take their MediaQuery path instead
///   of `View.of` (which has no answer in an isolated tree)
/// * [Directionality] and [Localizations] copied from `context`
///
/// Widgets with hard `View.of` dependencies (notably [EditableText])
/// cannot render in an isolated tree; capture those on-screen via
/// `Mural.captureBoundary` instead.
final class RenderHost {
  RenderHost._(
    this.boundary,
    this._renderView,
    this._pipelineOwner,
    this._buildOwner,
    this._rootElement,
  );

  /// The painted boundary regions are captured from.
  final MuralSceneBoundary boundary;

  final RenderView _renderView;
  final PipelineOwner _pipelineOwner;
  final BuildOwner _buildOwner;
  final RenderObjectToWidgetElement<RenderBox> _rootElement;
  bool _disposed = false;

  /// Builds, lays out, and paints [widget] in a fresh isolated tree.
  ///
  /// Throws [MuralBuildError] if the widget throws during build, and
  /// [MuralLayoutError] if it resolves to an empty or non-finite size.
  static Future<RenderHost> mount(
    Widget widget, {
    required BuildContext context,
    required double pixelRatio,
    required MuralStage stage,
  }) async {
    final contextualWidget = InheritedTheme.captureAll(
      context,
      MediaQuery(
        data: MediaQuery.of(context).copyWith(devicePixelRatio: pixelRatio),
        child: Localizations(
          locale: Localizations.maybeLocaleOf(context) ?? const Locale('en'),
          delegates: const [
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          child: Directionality(
            textDirection: Directionality.of(context),
            child: stage.background != null
                ? ColoredBox(color: stage.background!, child: widget)
                : widget,
          ),
        ),
      ),
    );

    final boundary = MuralSceneBoundary();
    // Loose constraints make the RenderView size itself by its child —
    // RenderView.performLayout treats any non-tight constraints as
    // child-sized. The widget's own layout must resolve finite.
    final constraints = stage.constraints;
    final renderView = RenderView(
      view: View.of(context),
      configuration: ViewConfiguration(
        logicalConstraints: constraints,
        physicalConstraints: constraints * pixelRatio,
        devicePixelRatio: pixelRatio,
      ),
      child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
    );

    final pipelineOwner = PipelineOwner();
    // The BINDING's BuildOwner, not a private one: GlobalKey.currentContext
    // resolves against the binding owner's registry, and material widgets
    // (Ink, ListTile) use internal GlobalKeys during build. Isolation is
    // preserved anyway — this root gets its own BuildScope, so its dirty
    // elements never enter the app's build passes.
    final buildOwner = WidgetsBinding.instance.buildOwner!;

    pipelineOwner.rootNode = renderView;
    renderView.prepareInitialFrame();

    final rootElement = _guardBuild(
      () => RenderObjectToWidgetAdapter<RenderBox>(
        container: boundary,
        child: contextualWidget,
      ).attachToRenderTree(buildOwner),
    );

    final host = RenderHost._(
      boundary,
      renderView,
      pipelineOwner,
      buildOwner,
      rootElement,
    );

    try {
      host._flushFrame();
      await host._settle(stage);
      host._checkSize();
    } catch (_) {
      host.dispose();
      rethrow;
    }
    return host;
  }

  /// Runs [action] with widget-level errors rerouted to the caller.
  ///
  /// [BuildOwner.buildScope] reports widget exceptions through
  /// [FlutterError.onError] and substitutes [ErrorWidget] — which would
  /// make a failed capture silently produce a red-box image. The handler
  /// is swapped only around the synchronous build; no other code can
  /// observe the swap.
  static T _guardBuild<T>(T Function() action) {
    final previous = FlutterError.onError;
    FlutterErrorDetails? failure;
    FlutterError.onError = (details) => failure ??= details;
    try {
      final result = action();
      if (failure != null) {
        throw MuralBuildError(
          'The captured widget threw during build. See `cause` for the '
          'original error.',
          cause: failure!.exception,
          stackTrace: failure!.stack,
        );
      }
      return result;
    } finally {
      FlutterError.onError = previous;
    }
  }

  void _flushFrame() {
    _guardBuild(() {
      _buildOwner.buildScope(_rootElement);
      _pipelineOwner
        ..flushLayout()
        ..flushCompositingBits()
        ..flushPaint();
    });
  }

  /// Waits for the caller's readiness signal, then rebuilds. The signal
  /// receives a context inside the offscreen tree so `precacheImage`
  /// resolves assets at the capture's pixel ratio. Deterministic — the
  /// package never guesses with timers.
  Future<void> _settle(MuralStage stage) async {
    if (stage.ready == null) {
      return;
    }
    await stage.ready!(_rootElement);
    // Let completed futures deliver to their listeners (image streams,
    // FutureBuilder) so the rebuilds they schedule are dirty before the
    // frame flush.
    await Future<void>.delayed(Duration.zero);
    _flushFrame();
  }

  void _checkSize() {
    final size = boundary.size;
    if (size.isEmpty) {
      throw const MuralLayoutError(
        'The widget laid out to an empty size. Give it content, or pass '
        'constraints that force a size via MuralStage.constraints.',
      );
    }
    if (!size.isFinite) {
      throw const MuralLayoutError(
        'The widget laid out to a non-finite size. Bound the growing axis '
        'via MuralStage.constraints (for example '
        'BoxConstraints(maxWidth: 400) for tall content).',
      );
    }
  }

  /// Rebuilds and repaints the hosted tree; call between capture passes
  /// if the content may have changed.
  void pump() => _flushFrame();

  /// Unmounts the widget and releases every render/element/focus
  /// resource this host created. Idempotent.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    // Detach the widget subtree: attaching a null child to the same
    // element unmounts the previous child tree cleanly.
    RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
    ).attachToRenderTree(_buildOwner, _rootElement);
    _buildOwner.finalizeTree();
    _pipelineOwner.rootNode = null;
    _renderView.dispose();
  }
}
