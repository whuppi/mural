// mural example — every capability, one file.
//
// ONE file on purpose — pub.dev renders example/lib/main.dart as the
// package's Example tab. Splitting it hides everything past main.dart
// from that page. Do not modularize.
//
// Three tabs, one per capture door:
//   Offscreen  — capture(): pixel ratios, constraints, backgrounds and
//                transparency, theme + directionality inheritance, the
//                ready recipes (precacheImage + a delayed data signal),
//                and every typed error
//   On screen  — captureBoundary(): the frozen moment on a live
//                animation, a burst series, a plain RepaintBoundary,
//                and the unmounted-key error
//   Stream     — captureInto(): live MuralProgress, chunk accounting,
//                a tight memory budget, rawRgba, a 10,000-row capture
//                far beyond the GPU texture limit, and cancellation
//
// Every op reports into the tab's status bar (ValueKey 'status-text');
// Run buttons carry ValueKey 'run:<title>'. The journeys drive this UI
// through those keys — keep both stable, they are the test contract.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mural/mural.dart';

void main() => runApp(const MuralExampleApp());

/// One shared capturer: it remembers the device's learned GPU ceiling,
/// so later captures plan without rediscovery.
final Mural mural = Mural();

class MuralExampleApp extends StatefulWidget {
  const MuralExampleApp({super.key});

  @override
  State<MuralExampleApp> createState() => _MuralExampleAppState();
}

class _MuralExampleAppState extends State<MuralExampleApp> {
  ThemeMode _mode = ThemeMode.light;

  void _toggleTheme() => setState(
    () => _mode = _mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mural example',
      themeMode: _mode,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.indigo,
      ),
      home: HomePage(onToggleTheme: _toggleTheme),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onToggleTheme});

  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('mural'),
          actions: [
            // Flip the theme, then re-run "Themed card" on the Offscreen
            // tab: the capture follows the app's CURRENT theme, because
            // capture() inherits the caller context's InheritedThemes.
            IconButton(
              key: const ValueKey('toggle-theme'),
              icon: const Icon(Icons.brightness_6),
              onPressed: onToggleTheme,
              tooltip: 'Toggle theme',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Offscreen'),
              Tab(text: 'On screen'),
              Tab(text: 'Stream'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_OffscreenTab(), _BoundaryTab(), _StreamTab()],
        ),
      ),
    );
  }
}

// ─── Shared op runner — status bar + cancel wiring, used by every tab ─

mixin _CaptureRunner<T extends StatefulWidget> on State<T> {
  String? status;
  bool running = false;
  MuralTask<Object?>? _inFlight;

  /// Runs one op: status transitions, typed-error handling, and the
  /// status bar's Cancel button while the task is in flight.
  Future<void> runOp(
    String label,
    MuralTask<Object?> Function() start, {
    String Function(Object? result)? describe,
  }) async {
    setState(() {
      running = true;
      status = '$label…';
    });
    final task = start();
    _inFlight = task;
    try {
      final result = await task;
      setState(() => status = describe?.call(result) ?? '✓ $label');
    } on MuralCancelled {
      setState(() => status = '✓ cancelled cleanly (MuralCancelled)');
    } on MuralError catch (e) {
      setState(() => status = 'Error: $e');
    } finally {
      _inFlight = null;
      setState(() => running = false);
    }
  }

  Widget statusBar() => _Status(
    loading: running,
    message: status,
    onCancel: _inFlight == null ? null : () => _inFlight!.cancel(),
    onDismiss: status == null ? null : () => setState(() => status = null),
  );
}

// ─────────────────────────────────────────────────────────────────────
// Offscreen — capture(): widgets that never enter this screen's tree.
// ─────────────────────────────────────────────────────────────────────

class _OffscreenTab extends StatefulWidget {
  const _OffscreenTab();

  @override
  State<_OffscreenTab> createState() => _OffscreenTabState();
}

class _OffscreenTabState extends State<_OffscreenTab>
    with _CaptureRunner, AutomaticKeepAliveClientMixin {
  MuralImage? _shot;

  @override
  bool get wantKeepAlive => true;

  Future<void> _shoot(String label, MuralTask<MuralImage> Function() start) =>
      runOp(
        label,
        start,
        describe: (result) {
          final shot = result! as MuralImage;
          setState(() => _shot = shot);
          return '✓ $label → ${shot.width}×${shot.height}, '
              '${shot.byteCount} bytes';
        },
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        statusBar(),
        Expanded(
          child: ListView(
            key: const ValueKey('demo-list'),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            children: [
              const _Section('Pixel ratio'),
              _Op(
                icon: Icons.looks_one,
                title: 'Transcript @1x',
                subtitle: 'A chat transcript that is never on screen',
                onRun: () => _shoot(
                  'Transcript @1x',
                  () => mural.capture(
                    const _TranscriptDemo(messages: 12),
                    context: context,
                    stage: const MuralStage(
                      constraints: BoxConstraints(maxWidth: 360),
                      background: Colors.white,
                    ),
                  ),
                ),
              ),
              _Op(
                icon: Icons.looks_3,
                title: 'Transcript @3x',
                subtitle: 'Same widget, three output pixels per logical',
                onRun: () => _shoot(
                  'Transcript @3x',
                  () => mural.capture(
                    const _TranscriptDemo(messages: 12),
                    context: context,
                    options: const MuralOptions(pixelRatio: 3),
                    stage: const MuralStage(
                      constraints: BoxConstraints(maxWidth: 360),
                      background: Colors.white,
                    ),
                  ),
                ),
              ),
              const _Section('Staging'),
              _Op(
                icon: Icons.straighten,
                title: 'Narrow constraints',
                subtitle: 'maxWidth 220 — the transcript reflows',
                onRun: () => _shoot(
                  'Narrow constraints',
                  () => mural.capture(
                    const _TranscriptDemo(messages: 6),
                    context: context,
                    stage: const MuralStage(
                      constraints: BoxConstraints(maxWidth: 220),
                      background: Colors.white,
                    ),
                  ),
                ),
              ),
              _Op(
                icon: Icons.blur_on,
                title: 'Transparent background',
                subtitle: 'No stage background — checkerboard shows alpha',
                onRun: () => _shoot(
                  'Transparent background',
                  () => mural.capture(
                    const _BadgeDemo(),
                    context: context,
                    options: const MuralOptions(pixelRatio: 2),
                  ),
                ),
              ),
              _Op(
                icon: Icons.palette,
                title: 'Themed card',
                subtitle: 'Follows the app theme — toggle dark and re-run',
                onRun: () => _shoot(
                  'Themed card',
                  () => mural.capture(
                    const _ThemedCardDemo(),
                    context: context,
                    options: const MuralOptions(pixelRatio: 2),
                  ),
                ),
              ),
              _Op(
                icon: Icons.format_textdirection_r_to_l,
                title: 'Right-to-left',
                subtitle: 'Directionality is part of the staged context',
                onRun: () => _shoot(
                  'Right-to-left',
                  () => mural.capture(
                    const Directionality(
                      textDirection: TextDirection.rtl,
                      child: _TranscriptDemo(messages: 4),
                    ),
                    context: context,
                    stage: const MuralStage(
                      constraints: BoxConstraints(maxWidth: 300),
                      background: Colors.white,
                    ),
                  ),
                ),
              ),
              const _Section('Readiness — signals, never timers'),
              _Op(
                icon: Icons.image,
                title: 'Image via precache',
                subtitle: 'ready: (context) => precacheImage(photo, context)',
                onRun: () async {
                  final photo = MemoryImage(await _demoPhotoPng());
                  if (!context.mounted) {
                    return;
                  }
                  await _shoot(
                    'Image via precache',
                    () => mural.capture(
                      Padding(
                        padding: const EdgeInsets.all(8),
                        // fit is explicit: without it Image defaults to
                        // BoxFit.scaleDown, which parks a smaller original in the middle
                        // of the slot instead of filling it.
                        child: Image(
                          image: photo,
                          width: 96,
                          height: 96,
                          fit: BoxFit.fill,
                        ),
                      ),
                      context: context,
                      options: const MuralOptions(pixelRatio: 2),
                      stage: MuralStage(
                        background: Colors.white,
                        ready: (context) => precacheImage(photo, context),
                      ),
                    ),
                  );
                },
              ),
              _Op(
                icon: Icons.hourglass_bottom,
                title: 'Delayed data',
                subtitle: 'The widget loads its own data; ready awaits it',
                onRun: () {
                  // A simulated fetch the WIDGET owns. The capture waits
                  // for the same future — a deterministic signal, not a
                  // guessed delay.
                  final fetch = Future<String>.delayed(
                    const Duration(milliseconds: 300),
                    () => 'Data arrived after 300 ms',
                  );
                  unawaited(
                    _shoot(
                      'Delayed data',
                      () => mural.capture(
                        _ProfileCardDemo(data: fetch),
                        context: context,
                        options: const MuralOptions(pixelRatio: 2),
                        stage: MuralStage(
                          background: Colors.white,
                          ready: (_) => fetch,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const _Section('Typed errors'),
              _Op(
                icon: Icons.crop_free,
                title: 'Empty widget',
                subtitle: 'Lays out to zero size → MuralLayoutError',
                onRun: () => runOp(
                  'Empty widget',
                  () =>
                      mural.capture(const SizedBox.shrink(), context: context),
                ),
              ),
              _Op(
                icon: Icons.all_inclusive,
                title: 'Unbounded widget',
                subtitle: 'Infinite height cannot capture — the error is typed',
                onRun: () => runOp(
                  'Unbounded widget',
                  () => mural.capture(
                    const Column(children: [Spacer(), Text('bottom')]),
                    context: context,
                  ),
                ),
              ),
              _Op(
                icon: Icons.bug_report,
                title: 'Throwing build',
                subtitle: 'The widget throws → MuralBuildError with cause',
                onRun: () => runOp(
                  'Throwing build',
                  () => mural.capture(
                    Builder(builder: (_) => throw StateError('demo boom')),
                    context: context,
                  ),
                ),
              ),
              if (_shot != null) ...[
                const _Section('Result'),
                _ShotCard(
                  bytes: _shot!.bytes,
                  caption:
                      '${_shot!.width}×${_shot!.height} · '
                      '${_shot!.byteCount} bytes',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// On screen — captureBoundary(): the frozen moment.
// ─────────────────────────────────────────────────────────────────────

class _BoundaryTab extends StatefulWidget {
  const _BoundaryTab();

  @override
  State<_BoundaryTab> createState() => _BoundaryTabState();
}

class _BoundaryTabState extends State<_BoundaryTab>
    with
        _CaptureRunner,
        AutomaticKeepAliveClientMixin,
        SingleTickerProviderStateMixin {
  final GlobalKey _muralKey = GlobalKey();
  final GlobalKey _plainKey = GlobalKey();
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();
  final List<MuralImage> _burst = [];
  MuralImage? _shot;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _freeze() => runOp(
    'Freeze the moment',
    // The snapshot happens synchronously inside this call — the result
    // is this exact frame, even though the dial keeps spinning while
    // the pixels develop.
    () => mural.captureBoundary(
      _muralKey,
      options: const MuralOptions(pixelRatio: 2),
    ),
    describe: (result) {
      final shot = result! as MuralImage;
      setState(() => _shot = shot);
      return '✓ froze the moment → ${shot.width}×${shot.height}';
    },
  );

  /// Three shots, one per animation third — every trigger the caller
  /// chooses is moment-exact, so a burst is just three calls.
  Future<void> _burstSeries() async {
    setState(() {
      _burst.clear();
      running = true;
      status = 'Burst of three…';
    });
    try {
      for (var i = 0; i < 3; i++) {
        final shot = await mural.captureBoundary(_muralKey);
        setState(() => _burst.add(shot));
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
      setState(() => status = '✓ burst captured 3 distinct moments');
    } on MuralError catch (e) {
      setState(() => status = 'Error: $e');
    } finally {
      setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        statusBar(),
        Expanded(
          child: ListView(
            key: const ValueKey('demo-list'),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            children: [
              const _Section('Live subject'),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: MuralBoundary(
                    key: _muralKey,
                    child: SizedBox(
                      width: 120,
                      height: 120,
                      child: AnimatedBuilder(
                        animation: _spin,
                        builder: (_, _) =>
                            CustomPaint(painter: _DialPainter(_spin.value)),
                      ),
                    ),
                  ),
                ),
              ),
              const _Section('Capture'),
              _Op(
                icon: Icons.center_focus_strong,
                title: 'Freeze the moment',
                subtitle: 'Synchronous snapshot — mid-animation, no tearing',
                onRun: _freeze,
              ),
              _Op(
                icon: Icons.burst_mode,
                title: 'Burst of three',
                subtitle: 'Any trigger works: three calls, three moments',
                onRun: _burstSeries,
              ),
              _Op(
                icon: Icons.filter_frames,
                title: 'Plain RepaintBoundary',
                subtitle: 'Also works, within the GPU texture limit',
                onRun: () => runOp(
                  'Plain RepaintBoundary',
                  () => mural.captureBoundary(_plainKey),
                  describe: (result) {
                    final shot = result! as MuralImage;
                    setState(() => _shot = shot);
                    return '✓ plain boundary → ${shot.width}×${shot.height}';
                  },
                ),
              ),
              Center(
                child: RepaintBoundary(
                  key: _plainKey,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: _BadgeDemo(),
                  ),
                ),
              ),
              const _Section('Typed errors'),
              _Op(
                icon: Icons.link_off,
                title: 'Unmounted key',
                subtitle: 'Nothing to capture → MuralBoundaryError',
                onRun: () => runOp(
                  'Unmounted key',
                  () => mural.captureBoundary(GlobalKey()),
                ),
              ),
              if (_burst.isNotEmpty) ...[
                const _Section('Burst — three distinct moments'),
                Row(
                  children: [
                    for (final shot in _burst)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: _ShotCard(bytes: shot.bytes, caption: ''),
                        ),
                      ),
                  ],
                ),
              ],
              if (_shot != null) ...[
                const _Section('Result'),
                _ShotCard(
                  bytes: _shot!.bytes,
                  caption: '${_shot!.width}×${_shot!.height}',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Stream — captureInto(): progress, budgets, formats, cancellation.
// ─────────────────────────────────────────────────────────────────────

class _StreamTab extends StatefulWidget {
  const _StreamTab();

  @override
  State<_StreamTab> createState() => _StreamTabState();
}

class _StreamTabState extends State<_StreamTab>
    with _CaptureRunner, AutomaticKeepAliveClientMixin {
  double _fraction = 0;
  String _phase = '';
  Uint8List? _png;
  String? _caption;

  @override
  bool get wantKeepAlive => true;

  void _watch(MuralTask<Object?> task) {
    task.progress.listen((p) {
      setState(() {
        _fraction = p.fraction;
        _phase = switch (p) {
          MuralLayoutProgress() => 'laying out',
          MuralCaptureProgress(:final tilesDone, :final tileCount) =>
            'capturing tile $tilesDone/$tileCount',
          MuralEncodeProgress(:final bytesEmitted) =>
            'encoded $bytesEmitted bytes',
        };
      });
    });
  }

  Future<void> _streamPoster() async {
    final chunks = <List<int>>[];
    await runOp(
      'Stream the poster',
      () {
        final task = mural.captureInto(
          _ChunkSink(chunks),
          const _PosterDemo(),
          context: context,
          // A deliberately tight budget: many bands, identical pixels.
          options: const MuralOptions(pixelRatio: 2, memoryLimitBytes: 1 << 20),
        );
        _watch(task);
        return task;
      },
      describe: (result) {
        final info = result! as MuralImageInfo;
        final assembled = BytesBuilder(copy: false);
        for (final chunk in chunks) {
          assembled.add(chunk);
        }
        setState(() {
          _png = assembled.takeBytes();
          _caption = '${info.width}×${info.height}';
        });
        return '✓ streamed ${chunks.length} chunks, ${info.byteCount} bytes '
            '(${info.width}×${info.height})';
      },
    );
  }

  Future<void> _streamHuge() => runOp(
    '10,000-row capture',
    () {
      // 10,000 rows ≈ 200,000 output pixels tall — far beyond any GPU
      // texture limit, streamed into a counting sink so the image never
      // sits in memory.
      final task = mural.captureInto(
        _CountingSink(),
        const _BigListDemo(rows: 10000),
        context: context,
        options: const MuralOptions(memoryLimitBytes: 8 << 20),
        stage: const MuralStage(constraints: BoxConstraints(maxWidth: 240)),
      );
      _watch(task);
      return task;
    },
    describe: (result) {
      final info = result! as MuralImageInfo;
      return '✓ huge: ${info.width}×${info.height} '
          '(${info.byteCount} bytes) — beyond any texture limit';
    },
  );

  Future<void> _rawRgba() => runOp(
    'Raw straight RGBA',
    () => mural.capture(
      const _BadgeDemo(),
      context: context,
      options: const MuralOptions(format: MuralFormat.rawRgba),
    ),
    describe: (result) {
      final shot = result! as MuralImage;
      return '✓ rawRgba: ${shot.width}×${shot.height} = '
          '${shot.bytes.length} bytes (w×h×4), straight alpha';
    },
  );

  Future<void> _cancelable() => runOp('Start, then cancel', () {
    final task = mural.captureInto(
      _CountingSink(),
      const _BigListDemo(rows: 10000),
      context: context,
      options: const MuralOptions(memoryLimitBytes: 1 << 20),
      stage: const MuralStage(constraints: BoxConstraints(maxWidth: 240)),
    );
    _watch(task);
    return task;
  });

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        statusBar(),
        Expanded(
          child: ListView(
            key: const ValueKey('demo-list'),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            children: [
              const _Section('Progress'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: _fraction),
                    const SizedBox(height: 4),
                    Text(_phase, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const _Section('Stream'),
              _Op(
                icon: Icons.water,
                title: 'Stream the poster',
                subtitle: '1 MB working budget — bands flow to a sink',
                onRun: _streamPoster,
              ),
              _Op(
                icon: Icons.unfold_more,
                title: '10,000-row capture',
                subtitle: 'Far beyond the GPU texture limit (#118024)',
                onRun: _streamHuge,
              ),
              _Op(
                icon: Icons.cancel_schedule_send,
                title: 'Start, then cancel',
                subtitle: 'Tap Cancel in the status bar → MuralCancelled',
                onRun: _cancelable,
              ),
              const _Section('Formats'),
              _Op(
                icon: Icons.grain,
                title: 'Raw straight RGBA',
                subtitle: 'The escape hatch into your own encoder',
                onRun: _rawRgba,
              ),
              if (_png != null) ...[
                const _Section('Result'),
                _ShotCard(bytes: _png!, caption: _caption ?? ''),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Demo subjects — the widgets that get captured.
// ─────────────────────────────────────────────────────────────────────

/// A chat transcript. Never on screen in the Offscreen demos.
class _TranscriptDemo extends StatelessWidget {
  const _TranscriptDemo({required this.messages});

  final int messages;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < messages; i++)
          Align(
            // Directional on purpose: under RTL the whole transcript
            // mirrors — incoming bubbles jump to the right, outgoing to
            // the left — which is what the Right-to-left op demonstrates.
            alignment: i.isEven
                ? AlignmentDirectional.centerStart
                : AlignmentDirectional.centerEnd,
            child: Container(
              margin: const EdgeInsets.all(6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: i.isEven ? Colors.indigo.shade100 : Colors.indigo,
                // The flat "tail" corner hugs the speaker's side, so the
                // mirror is visible per bubble, not just per row.
                borderRadius: i.isEven
                    ? const BorderRadiusDirectional.only(
                        topStart: Radius.circular(2),
                        topEnd: Radius.circular(12),
                        bottomStart: Radius.circular(12),
                        bottomEnd: Radius.circular(12),
                      )
                    : const BorderRadiusDirectional.only(
                        topStart: Radius.circular(12),
                        topEnd: Radius.circular(2),
                        bottomStart: Radius.circular(12),
                        bottomEnd: Radius.circular(12),
                      ),
              ),
              child: Text(
                'Message ${i + 1} of the transcript',
                style: TextStyle(
                  color: i.isEven ? Colors.black87 : Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A round badge over nothing — captured without a stage background its
/// corners stay transparent, which the checkerboard viewer proves.
class _BadgeDemo extends StatelessWidget {
  const _BadgeDemo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [Colors.deepOrange, Colors.pink]),
      ),
      alignment: Alignment.center,
      child: const Text(
        'mural',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Built from the ambient theme — Card, colors, and text styles come
/// from whatever theme the CALLER's context carries at capture time.
class _ThemedCardDemo extends StatelessWidget {
  const _ThemedCardDemo();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Material components (ListTile, InkWell…) need a Material
    // ancestor. On screen a Scaffold provides one; an offscreen tree
    // has no Scaffold, so the captured widget brings its own.
    return Material(
      color: cs.surface,
      child: SizedBox(
        width: 260,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Card(
            child: ListTile(
              leading: Icon(Icons.palette, color: cs.primary),
              title: const Text('Themed card'),
              subtitle: Text(
                Theme.of(context).brightness == Brightness.dark
                    ? 'captured in dark'
                    : 'captured in light',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A widget that loads its own data — the delayed-ready scenario. The
/// first frame shows the placeholder; the ready signal (the same
/// future) gates the capture until the data frame.
class _ProfileCardDemo extends StatelessWidget {
  const _ProfileCardDemo({required this.data});

  final Future<String> data;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<String>(
        future: data,
        builder: (_, snap) => Row(
          children: [
            const Icon(Icons.person, size: 32),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                snap.data ?? 'loading…',
                style: const TextStyle(color: Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A poster-sized gradient grid — enough rows to force many bands under
/// the Stream demo's 1 MB budget.
class _PosterDemo extends StatelessWidget {
  const _PosterDemo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      height: 1200,
      child: CustomPaint(painter: _PosterPainter()),
    );
  }
}

class _PosterPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const rows = 24;
    const columns = 8;
    final cell = Size(size.width / columns, size.height / rows);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < columns; x++) {
        canvas.drawRect(
          Offset(x * cell.width, y * cell.height) & cell,
          Paint()
            ..color = HSVColor.fromAHSV(
              1,
              (x * 45 + y * 15) % 360,
              0.6,
              0.95,
            ).toColor(),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Ten thousand rows, painted cheaply — the flutter#118024 case: output
/// far taller than any GPU texture.
class _BigListDemo extends StatelessWidget {
  const _BigListDemo({required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: rows * 20,
      child: CustomPaint(painter: _RowsPainter(rows)),
    );
  }
}

class _RowsPainter extends CustomPainter {
  _RowsPainter(this.rows);

  final int rows;

  @override
  void paint(Canvas canvas, Size size) {
    final rowHeight = size.height / rows;
    for (var i = 0; i < rows; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * rowHeight, size.width, rowHeight),
        Paint()..color = i.isEven ? Colors.indigo.shade50 : Colors.white,
      );
      canvas.drawCircle(
        Offset(12, i * rowHeight + rowHeight / 2),
        4,
        Paint()..color = Colors.indigo,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The spinning dial the On-screen demos capture mid-flight.
class _DialPainter extends CustomPainter {
  _DialPainter(this.turns);

  final double turns;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(center, radius, Paint()..color = Colors.indigo.shade50);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.indigo,
    );
    final angle = turns * 2 * math.pi;
    canvas.drawLine(
      center,
      center + Offset.fromDirection(angle - math.pi / 2, radius * 0.8),
      Paint()
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = Colors.deepOrange,
    );
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) =>
      oldDelegate.turns != turns;
}

// ─────────────────────────────────────────────────────────────────────
// Chrome — the shared design system (status bar, sections, op cards,
// the checkerboard shot viewer).
// ─────────────────────────────────────────────────────────────────────

class _Status extends StatelessWidget {
  const _Status({
    required this.loading,
    this.message,
    this.onDismiss,
    this.onCancel,
  });

  final bool loading;
  final String? message;
  final VoidCallback? onDismiss;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    if (!loading && message == null) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    final isError = message?.startsWith('Error') ?? false;
    final bg = loading
        ? cs.primaryContainer
        : (isError ? cs.errorContainer : cs.tertiaryContainer);
    final fg = loading
        ? cs.onPrimaryContainer
        : (isError ? cs.onErrorContainer : cs.onTertiaryContainer);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: bg,
      child: Row(
        children: [
          if (loading) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              message ?? '',
              key: const ValueKey('status-text'),
              style: TextStyle(color: fg, fontSize: 13),
              maxLines: 4,
            ),
          ),
          if (loading && onCancel != null)
            TextButton.icon(
              onPressed: onCancel,
              icon: Icon(Icons.cancel, size: 16, color: fg),
              label: Text('Cancel', style: TextStyle(color: fg, fontSize: 12)),
            ),
          if (!loading && onDismiss != null)
            GestureDetector(
              onTap: onDismiss,
              child: Icon(Icons.close, size: 16, color: fg),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 4, left: 4),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _Op extends StatelessWidget {
  const _Op({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onRun,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 2),
    child: ListTile(
      leading: Icon(icon, size: 22),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle != null
          ? Text(subtitle!, style: const TextStyle(fontSize: 12))
          : null,
      trailing: SizedBox(
        width: 64,
        height: 34,
        child: FilledButton.tonal(
          // Stable handle for the journeys ('run:<title>').
          key: ValueKey('run:$title'),
          onPressed: onRun,
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            textStyle: const TextStyle(fontSize: 13),
          ),
          child: const Text('Run'),
        ),
      ),
      dense: true,
      visualDensity: VisualDensity.compact,
    ),
  );
}

/// A captured result on a checkerboard (so transparency is visible),
/// with its caption. Tap to inspect full-screen with pan + zoom.
class _ShotCard extends StatelessWidget {
  const _ShotCard({required this.bytes, required this.caption});

  final Uint8List bytes;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              child: InteractiveViewer(
                maxScale: 8,
                child: CustomPaint(
                  painter: _CheckerboardPainter(),
                  child: Image.memory(bytes),
                ),
              ),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            constraints: const BoxConstraints(maxHeight: 280),
            child: CustomPaint(
              painter: _CheckerboardPainter(),
              // cacheWidth keeps huge captures cheap to display.
              child: Image.memory(bytes, cacheWidth: 720, fit: BoxFit.contain),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(caption, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 8.0;
    final light = Paint()..color = const Color(0xFFEEEEEE);
    final dark = Paint()..color = const Color(0xFFCCCCCC);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, cell, cell),
          ((x / cell + y / cell) % 2 == 0) ? light : dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Sinks ───────────────────────────────────────────────────────────

final class _ChunkSink implements Sink<List<int>> {
  _ChunkSink(this.chunks);

  final List<List<int>> chunks;

  @override
  void add(List<int> data) => chunks.add(data);

  @override
  void close() {}
}

/// Counts bytes and drops them — the 10,000-row capture's destination,
/// proving the image never has to exist anywhere.
final class _CountingSink implements Sink<List<int>> {
  int total = 0;

  @override
  void add(List<int> data) => total += data.length;

  @override
  void close() {}
}

/// A small photo for the precache demo, generated through the engine so
/// the bytes are always a valid PNG: draw → rasterize → encode.
/// MemoryImage then decodes it through the real async image pipeline —
/// exactly what the ready recipe waits for.
Future<Uint8List> _demoPhotoPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 96, 96));
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 96, 96),
    Paint()..color = Colors.deepOrange,
  );
  canvas.drawCircle(const Offset(48, 48), 30, Paint()..color = Colors.white);
  final picture = recorder.endRecording();
  final image = await picture.toImage(96, 96);
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
