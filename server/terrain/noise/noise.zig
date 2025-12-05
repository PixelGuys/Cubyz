/// Like FractalNoise, except in 3D and it generates values on demand and caches results, instead of generating everything at once.
pub const CachedFractalNoise3D = @import("CachedFractalNoise3D.zig");

/// Like FractalNoise, except in 1D.
pub const FractalNoise1D = @import("FractalNoise1D.zig");

/// Like FractalNoise, except in 3D.
pub const FractalNoise3D = @import("FractalNoise3D.zig");

/// Uses a recursive subdivision algorithm to generate a noise map.
pub const FractalNoise = @import("FractalNoise.zig");

/// Like FractalNoise, except it generates values on demand and caches results, instead of generating everything at once.
pub const CachedFractalNoise = @import("CachedFractalNoise.zig");

/// The same as fractal noise, but uses random weigths during interpolation phase.
/// This generates a rough terrain with some cliffs.
pub const RandomlyWeightedFractalNoise = @import("RandomlyWeightedFractalNoise.zig");

/// Blue noise (aka Poisson Disk Sampling) is a pattern that ensures that all points have a minimum distance towards their neigbors.
/// This contains a static blue noise pattern that is calculated once and then used everywhere around the world. because it is so big the player will never notice issues.
pub const BlueNoise = @import("BlueNoise.zig");

pub const PerlinNoise = @import("PerlinNoise.zig");

pub const ValueNoise = @import("ValueNoise.zig");
