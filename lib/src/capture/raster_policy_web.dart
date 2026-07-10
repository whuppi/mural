/// The web engine flattens a scene from live layer state inside the
/// `Scene.toImage` CALL (synchronously, before its first await) — and
/// building the next scene from the same layer tree hollows out the
/// previous one (last-built scene wins). Rasterization must therefore
/// start inside the snapshot loop, scene by scene, to both capture the
/// frozen moment and survive the next scene build.
const bool eagerTileRasterization = true;

/// The web engine returns premultiplied bytes even when
/// `ImageByteFormat.rawStraightRgba` is requested; readbacks must be
/// unpremultiplied in Dart to honor the straight-alpha contract.
const bool unpremultiplyReadback = true;
