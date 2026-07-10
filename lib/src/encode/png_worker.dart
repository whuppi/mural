/// Selects the PNG worker implementation per platform: a dedicated
/// isolate on native targets, the browser's native `CompressionStream`
/// on the web, and an inline cooperative encoder anywhere else.
///
/// The conditions are the platform splits the compilers guarantee:
/// worker isolates exist exactly where `dart:io` does, and the browser
/// APIs exist exactly where `dart:js_interop` does.
library;

export 'png_worker_stub.dart'
    if (dart.library.io) 'png_worker_native.dart'
    if (dart.library.js_interop) 'png_worker_web.dart';
