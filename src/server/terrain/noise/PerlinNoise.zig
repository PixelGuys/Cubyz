const std = @import("std");

const main = @import("main");
const Array2D = main.utils.Array2D;
const random = main.random;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

// TODO: Simplify with Vec2f and Vec2i.

const Context = struct {
	xGridPoints: Array2D(f32) = undefined,
	yGridPoints: Array2D(f32) = undefined,
	l1: u64,
	l2: u64,
	l3: u64,
	resolution: u31 = undefined,
	resolutionMask: i32 = undefined,

	fn generateGradient(self: Context, x: i32, y: i32, i: i32, resolution: u32) f32 {
		var seed: u64 = self.l1*%@as(u32, @bitCast(x)) +% self.l2*%@as(u32, @bitCast(y)) +% self.l3*%@as(u32, @bitCast(i)) +% resolution; // TODO: Use random.initSeed3D();
		random.scrambleSeed(&seed);
		return 2*random.nextFloat(&seed) - 1;
	}

	fn getGradientX(self: Context, x: i32, y: i32) f32 {
		return self.xGridPoints.get(@intCast(x), @intCast(y));
	}

	fn getGradientY(self: Context, x: i32, y: i32) f32 {
		return self.yGridPoints.get(@intCast(x), @intCast(y));
	}

	/// Function to linearly interpolate between a0 and a1
	fn lerp(a0: f32, a1: f32, w: f32) f32 {
		return a0 + w*(a1 - a0);
	}

	fn sCurve(x: f32) f32 {
		return 3*x*x - 2*x*x*x;
	}

	/// Computes the dot product of the distance and gradient vectors.
	fn dotGridGradient(self: Context, ix: i32, iy: i32, x: f32, y: f32) f32 {
		// Compute the distance vector
		const dx = x/@as(f32, @floatFromInt(self.resolution)) - @as(f32, @floatFromInt(ix));
		const dy = y/@as(f32, @floatFromInt(self.resolution)) - @as(f32, @floatFromInt(iy));

		// Compute the dot-product
		var gx = self.getGradientX(ix, iy);
		var gy = self.getGradientY(ix, iy);
		const gr = @sqrt(gx*gx + gy*gy);
		gx /= gr;
		gy /= gr;
		return dx*gx + dy*gy;
	}

	fn perlin(self: Context, x: i32, y: i32) f32 {
		// Determine grid cell coordinates
		const x0 = @divFloor(x, self.resolution);
		const x1 = x0 + 1;
		const y0 = @divFloor(y, self.resolution);
		const y1 = y0 + 1;

		// Determine interpolation weights using s-curve for smoother edges.
		const sx = sCurve(@as(f32, @floatFromInt(x & self.resolutionMask))/@as(f32, @floatFromInt(self.resolution)));
		const sy = sCurve(@as(f32, @floatFromInt(y & self.resolutionMask))/@as(f32, @floatFromInt(self.resolution)));

		// Interpolate between grid point gradients
		const n00 = self.dotGridGradient(x0, y0, @floatFromInt(x), @floatFromInt(y));
		const n01 = self.dotGridGradient(x0, y1, @floatFromInt(x), @floatFromInt(y));
		const n10 = self.dotGridGradient(x1, y0, @floatFromInt(x), @floatFromInt(y));
		const n11 = self.dotGridGradient(x1, y1, @floatFromInt(x), @floatFromInt(y));
		const n0 = lerp(n00, n01, sy);
		const n1 = lerp(n10, n11, sy);
		const n = lerp(n0, n1, sx);
		return n*@sqrt(2.0);
	}

	// Calculate all grid points that will be needed to prevent double calculating them.
	fn calculateGridPoints(self: *Context, allocator: NeverFailingAllocator, x: i32, y: i32, _width: u31, _height: u31, scale: u31) void {
		// Create one gridpoint more, just in case...
		const width = _width + scale;
		const height = _height + scale;
		const resolutionShift = @ctz(scale);
		// Determine grid cell coordinates of all cells that points can be in:
		self.xGridPoints = Array2D(f32).init(allocator, width/scale + 3, height/scale + 3); // Simply assume the absolute maximum number of grid points are generated.
		self.yGridPoints = Array2D(f32).init(allocator, width/scale + 3, height/scale + 3); // Simply assume the absolute maximum number of grid points are generated.
		var numX: u31 = 0;
		var numY: u31 = undefined;
		var x0: i32 = 0;
		var ix: i32 = x;
		while(ix != x +% width) : (ix +%= scale) {
			numY = 0;
			x0 = ix >> resolutionShift;
			var y0: i32 = 0;
			var iy: i32 = y;
			while(iy != y +% width) : (iy +%= scale) {
				y0 = iy >> resolutionShift;
				self.xGridPoints.ptr(numX, numY).* = self.generateGradient(x0, y0, 0, resolutionShift);
				self.yGridPoints.ptr(numX, numY).* = self.generateGradient(x0, y0, 1, resolutionShift);
				numY += 1;
			}
			self.xGridPoints.ptr(numX, numY).* = self.generateGradient(x0, y0 + 1, 0, resolutionShift);
			self.yGridPoints.ptr(numX, numY).* = self.generateGradient(x0, y0 + 1, 1, resolutionShift);
			numX += 1;
		}
		numY = 0;
		var y0: i32 = 0;
		var iy: i32 = y;
		while(iy != y +% width) : (iy +%= scale) {
			y0 = iy >> resolutionShift;
			self.xGridPoints.ptr(numX, numY).* = self.generateGradient(x0 + 1, y0, 0, resolutionShift);
			self.yGridPoints.ptr(numX, numY).* = self.generateGradient(x0 + 1, y0, 1, resolutionShift);
			numY += 1;
		}
		self.xGridPoints.ptr(numX, numY).* = self.generateGradient(x0 + 1, y0 + 1, 0, resolutionShift);
		self.yGridPoints.ptr(numX, numY).* = self.generateGradient(x0 + 1, y0 + 1, 1, resolutionShift);
		numX += 1;
	}

	fn freeGridPoints(self: *Context, allocator: NeverFailingAllocator) void {
		self.yGridPoints.deinit(allocator);
		self.xGridPoints.deinit(allocator);
		self.yGridPoints = undefined;
		self.xGridPoints = undefined;
	}
};

/// Returns a smooth map of floats with values between 0 and 1.
pub fn generateSmoothNoise(allocator: NeverFailingAllocator, x: i32, y: i32, width: u31, height: u31, maxScale: u31, minScale: u31, worldSeed: u64, voxelSize: u31, reductionFactor: f32) Array2D(f32) {
	const map = Array2D(f32).init(allocator, width/voxelSize, height/voxelSize);
	@memset(map.mem, 0);
	var seed = worldSeed;
	random.scrambleSeed(&seed);
	var context = Context{
		.l1 = random.nextInt(u64, &seed),
		.l2 = random.nextInt(u64, &seed),
		.l3 = random.nextInt(u64, &seed),
	};
	var fac = 1/((1 - std.math.pow(f32, reductionFactor, @as(f32, @floatFromInt(@ctz(maxScale/minScale) + 1))))/(1 - reductionFactor)); // geometric series.
	var scale = maxScale;
	while(scale >= minScale) : (scale >>= 1) {
		context.resolution = scale;
		context.resolutionMask = scale - 1;
		const x0 = x & ~context.resolutionMask;
		const y0 = y & ~context.resolutionMask;
		context.calculateGridPoints(main.stackAllocator, x, y, width, height, scale);
		defer context.freeGridPoints(main.stackAllocator);

		var x1 = x;
		while(x1 -% width -% x < 0) : (x1 +%= voxelSize) {
			var y1 = y;
			while(y1 -% y -% height < 0) : (y1 +%= voxelSize) {
				map.ptr(@as(u32, @intCast(x1 -% x))/voxelSize, @as(u32, @intCast(y1 -% y))/voxelSize).* += @abs(context.perlin(x1 -% x0, y1 -% y0))*fac;
			}
		}
		fac *= reductionFactor;
	}
	return map;
}
