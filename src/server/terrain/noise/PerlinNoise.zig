const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Array2D = main.utils.Array2D;
const random = main.random;

// TODO: Simplify with Vec2f and Vec2i.

const Context = struct {
	xGridPoints: Array2D(f32) = undefined,
	yGridPoints: Array2D(f32) = undefined,
	l1: u64,
	l2: u64,
	l3: u64,
	resultion: u31 = undefined,
	resultionMask: i32 = undefined,

	fn generateGradient(self: Context, x: i32, y: i32, i: i32, resolution: u32) f32 {
		var seed: u64 = self.l1*%@bitCast(u32, x) +% self.l2*%@bitCast(u32, y) +% self.l3*%@bitCast(u32, i) +% resolution;
		random.scrambleSeed(&seed);
		return 2*random.nextFloat(&seed) - 1;
	}

	fn getGradientX(self: Context, x: i32, y: i32) f32 {
		return self.xGridPoints.get(@intCast(usize, x), @intCast(usize, y));
	}

	fn getGradientY(self: Context, x: i32, y: i32) f32 {
		return self.yGridPoints.get(@intCast(usize, x), @intCast(usize, y));
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
		const dx = x/@intToFloat(f32, self.resultion) - @intToFloat(f32, ix);
		const dy = y/@intToFloat(f32, self.resultion) - @intToFloat(f32, iy);

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
		const x0 = @divFloor(x, self.resultion);
		const x1 = x0 + 1;
		const y0 = @divFloor(y, self.resultion);
		const y1 = y0 + 1;

		// Determine interpolation weights using s-curve for smoother edges.
		const sx = sCurve(@intToFloat(f32, x & self.resultionMask)/@intToFloat(f32, self.resultion));
		const sy = sCurve(@intToFloat(f32, y & self.resultionMask)/@intToFloat(f32, self.resultion));

		// Interpolate between grid point gradients
		const n00 = self.dotGridGradient(x0, y0, @intToFloat(f32, x), @intToFloat(f32, y));
		const n01 = self.dotGridGradient(x0, y1, @intToFloat(f32, x), @intToFloat(f32, y));
		const n10 = self.dotGridGradient(x1, y0, @intToFloat(f32, x), @intToFloat(f32, y));
		const n11 = self.dotGridGradient(x1, y1, @intToFloat(f32, x), @intToFloat(f32, y));
		const n0 = lerp(n00, n01, sy);
		const n1 = lerp(n10, n11, sy);
		const n = lerp(n0, n1, sx);
		return n*@sqrt(2.0);
	}
	
	// Calculate all grid points that will be needed to prevent double calculating them.
	fn calculateGridPoints(self: *Context, allocator: Allocator, x: i32, y: i32, _width: u31, _height: u31, scale: u31) !void {
		// Create one gridpoint more, just in case...
		const width = _width + scale;
		const height = _height + scale;
		const resolutionShift = @ctz(scale);
		// Determine grid cell coordinates of all cells that points can be in:
		self.xGridPoints = try Array2D(f32).init(allocator, width/scale + 3, height/scale + 3); // Simply assume the absolute maximum number of grid points are generated.
		self.yGridPoints = try Array2D(f32).init(allocator, width/scale + 3, height/scale + 3); // Simply assume the absolute maximum number of grid points are generated.
		var numX: u31 = 0;
		var numY: u31 = undefined;
		var x0: i32 = 0;
		var ix: i32 = x;
		while(ix < x+width) : (ix += scale) {
			numY = 0;
			x0 = ix >> resolutionShift;
			var y0: i32 = 0;
			var iy: i32 = y;
			while(iy < y+width) : (iy += scale) {
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
		while(iy < y+width) : (iy += scale) {
			y0 = iy >> resolutionShift;
			self.xGridPoints.ptr(numX, numY).* = self.generateGradient(x0+1, y0, 0, resolutionShift);
			self.yGridPoints.ptr(numX, numY).* = self.generateGradient(x0+1, y0, 1, resolutionShift);
			numY += 1;
		}
		self.xGridPoints.ptr(numX, numY).* = self.generateGradient(x0+1, y0 + 1, 0, resolutionShift);
		self.yGridPoints.ptr(numX, numY).* = self.generateGradient(x0+1, y0 + 1, 1, resolutionShift);
		numX += 1;
	}

	fn freeGridPoints(self: *Context, allocator: Allocator) void {
		self.xGridPoints.deinit(allocator);
		self.yGridPoints.deinit(allocator);
		self.xGridPoints = undefined;
		self.yGridPoints = undefined;
	}
};

/// Returns a ridgid map of floats with values between 0 and 1.
pub fn generateRidgidNoise(allocator: Allocator, x: i32, y: i32, width: u31, height: u31, maxScale: u31, minScale: u31, worldSeed: u64, voxelSize: u31, reductionFactor: f32) !Array2D(f32) {
	const map = try Array2D(f32).init(allocator, width/voxelSize, height/voxelSize);
	var seed = worldSeed;
	random.scrambleSeed(&seed);
	var context = Context {
		.l1 = random.nextInt(u64, &seed),
		.l2 = random.nextInt(u64, &seed),
		.l3 = random.nextInt(u64, &seed),
	};
	var fac = 1/((1 - std.math.pow(f32, reductionFactor, @ctz(maxScale/minScale)+1))/(1 - reductionFactor)); // geometric series.
	var scale = maxScale;
	while(scale >= minScale) : (scale >>= 1) {
		context.resultion = scale;
		context.resultionMask = scale - 1;
		const x0 = x & ~context.resultionMask;
		const y0 = y & ~context.resultionMask;
		try context.calculateGridPoints(main.threadAllocator, x, y, width, height, scale);
		defer context.freeGridPoints(main.threadAllocator);

		var x1 = x;
		while(x1 -% width -% x < 0) : (x1 += voxelSize) {
			var y1 = y;
			while(y1 -% y -% height < 0) : (y1 += voxelSize) {
				map.ptr(@intCast(u32, x1 - x)/voxelSize, @intCast(u32, y1 - y)/voxelSize).* += (1 - @fabs(context.perlin(x1-x0, y1-y0)))*fac;
			}
		}
		fac *= reductionFactor;
	}
	return map;
}

/// Returns a smooth map of floats with values between 0 and 1.
pub fn generateSmoothNoise(allocator: Allocator, x: i32, y: i32, width: u31, height: u31, maxScale: u31, minScale: u31, worldSeed: u64, voxelSize: u31, reductionFactor: f32) !Array2D(f32) {
	const map = try Array2D(f32).init(allocator, width/voxelSize, height/voxelSize);
	var seed = worldSeed;
	random.scrambleSeed(&seed);
	var context = Context {
		.l1 = random.nextInt(u64, &seed),
		.l2 = random.nextInt(u64, &seed),
		.l3 = random.nextInt(u64, &seed),
	};
	var fac = 1/((1 - std.math.pow(f32, reductionFactor, @intToFloat(f32, @ctz(maxScale/minScale)+1)))/(1 - reductionFactor)); // geometric series.
	var scale = maxScale;
	while(scale >= minScale) : (scale >>= 1) {
		context.resultion = scale;
		context.resultionMask = scale - 1;
		const x0 = x & ~context.resultionMask;
		const y0 = y & ~context.resultionMask;
		try context.calculateGridPoints(main.threadAllocator, x, y, width, height, scale);
		defer context.freeGridPoints(main.threadAllocator);

		var x1 = x;
		while(x1 -% width -% x < 0) : (x1 += voxelSize) {
			var y1 = y;
			while(y1 -% y -% height < 0) : (y1 += voxelSize) {
				map.ptr(@intCast(u32, x1 - x)/voxelSize, @intCast(u32, y1 - y)/voxelSize).* += @fabs(context.perlin(x1-x0, y1-y0))*fac;
			}
		}
		fac *= reductionFactor;
	}
	return map;
}