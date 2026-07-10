/// Per-platform rasterization behavior, verified against engine source
/// and pinned by the web batteries. `dart.library.js_interop` selects
/// the web engine's constraints; every other target gets the native
/// engines' guarantees.
library;

export 'raster_policy_native.dart'
    if (dart.library.js_interop) 'raster_policy_web.dart';
