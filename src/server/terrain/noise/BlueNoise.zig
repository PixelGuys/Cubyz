const std = @import("std");

const main = @import("main");
const random = main.random;
const Array2D = main.utils.Array2D;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const sizeShift = 7; // TODO: Increase back to 10 once this is no longer impacting loading time.
const size = 1 << sizeShift;
const sizeMask = size - 1;
const featureShift = 2;
const featureSize = 1 << featureShift;
const featureMask = featureSize - 1;

/// Uses a simple square grid as a base.
var pattern: [size*size]u8 = undefined;

/// Loads a pre-seeded noise map that is used for world generation.
pub fn load() void { // TODO: Do this at compile time once the caching is good enough.
	@setRuntimeSafety(false); // TODO: Replace with optimizations.
	var seed: u64 = 54095248685739;
	const distSquareLimit = 8;
	const repetitions = 4;
	const iterations = 16;
	// Go through all points and try to move them randomly.
	// Ensures that the grid is valid in each step.
	// This is repeated multiple times for optimal results.
	// In the last repetition is enforced, to remove grid artifacts.
	for(0..repetitions) |_| {
		for(0..pattern.len) |i| {
			const x: i32 = @intCast(i >> sizeShift);
			const y: i32 = @intCast(i & sizeMask);
			outer: for(0..iterations) |_| {
				const point = random.nextInt(u6, &seed);
				const xOffset = point >> 3 & 7;
				const yOffset = point & 7;
				// Go through all neighbors and check validity:
				var dx: i32 = -2;
				while(dx <= 2) : (dx += 1) {
					var dy: i32 = -2;
					while(dy <= 2) : (dy += 1) {
						if(dx == 0 and dy == 0) continue; // Don't compare with itself!
						const neighbor = (x + dx & sizeMask) << sizeShift | (y + dy & sizeMask);
						const neighborPos = pattern[@intCast(neighbor)];
						const nx = (neighborPos >> 3) + (dx << featureShift);
						const ny = (neighborPos & 7) + (dy << featureShift);
						const distSqr = (nx - xOffset)*(nx - xOffset) + (ny - yOffset)*(ny - yOffset);
						if(distSqr < distSquareLimit) continue :outer;
					}
				}

				pattern[i] = point;
				break;
			}
		}
	}
}

fn sample(x: i32, y: i32) u8 {
	return pattern[@intCast(x << sizeShift | y)];
}

/// Takes a subregion of the grid. Corrdinates are returned relative to x and y compressed into 16 bits each.
pub fn getRegionData(allocator: NeverFailingAllocator, x: i32, y: i32, width: u31, height: u31) []u32 {
	const xMin = ((x & ~@as(i32, featureMask)) -% featureSize);
	const yMin = ((y & ~@as(i32, featureMask)) -% featureSize);
	const xMax = ((x +% width & ~@as(i32, featureMask)));
	const yMax = ((y +% height & ~@as(i32, featureMask)));
	var result = main.ListUnmanaged(u32).initCapacity(allocator, @intCast((((xMax -% xMin) >> featureShift) + 1)*(((yMax -% yMin) >> featureShift) + 1)));
	var xMap: i32 = xMin;
	while(xMap -% xMax <= 0) : (xMap +%= featureSize) {
		var yMap: i32 = yMin;
		while(yMap -% yMax <= 0) : (yMap +%= featureSize) {
			const val = sample(xMap >> featureShift & sizeMask, yMap >> featureShift & sizeMask);
			var xRes = xMap -% xMin;
			xRes += val >> 3;
			var yRes = yMap -% yMin;
			yRes += val & 7;
			if(xRes >= 0 and xRes < width and yRes >= 0 and yRes < height) {
				result.appendAssumeCapacity(@bitCast(xRes << 16 | yRes));
			}
		}
	}
	return result.toOwnedSlice(allocator);
}
