/// Native engines retain each scene's display lists independently, so a
/// snapshot can hold scenes and rasterize them lazily — one tile's GPU
/// memory at a time, the property that makes unbounded captures fit the
/// memory budget.
const bool eagerTileRasterization = false;

/// Native engines honor `ImageByteFormat.rawStraightRgba`; readbacks
/// arrive straight and need no conversion.
const bool unpremultiplyReadback = false;
