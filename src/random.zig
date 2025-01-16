const std = @import("std");

const main = @import("root");
const Vec2f = main.vec.Vec2f;
const Vec2i = main.vec.Vec2i;
const Vec3i = main.vec.Vec3i;

const multiplier: u64 = 0x5deece66d;
const addend: u64 = 0xb;
const mask: u64 = (1 << 48) - 1;

pub fn scrambleSeed(seed: *u64) void {
	seed.* = (seed.* ^ multiplier) & mask;
}

fn nextWithBitSize(comptime T: type, seed: *u64, bitSize: u6) T {
	seed.* = ((seed.*)*%multiplier +% addend) & mask;
	return @intCast((seed.* >> (48 - bitSize)) & std.math.maxInt(T));
}

fn next(comptime T: type, seed: *u64) T {
	return nextWithBitSize(T, seed, @bitSizeOf(T));
}

pub fn nextInt(comptime T: type, seed: *u64) T {
	if(@bitSizeOf(T) > 32) {
		var result: T = 0;
		for(0..(@bitSizeOf(T)+31)/32) |_| {
			result = result<<5 | next(u32, seed);
		}
		return result;
	} else {
		return next(T, seed);
	}
}

pub fn nextIntBounded(comptime T: type, seed: *u64, bound: T) T {
	if(@typeInfo(T) != .int) @compileError("Type must be integer.");
	if(@typeInfo(T).int.signedness == .signed) return nextIntBounded(std.meta.Int(.unsigned, @bitSizeOf(T) - 1), seed, @intCast(bound));
	const bitSize = std.math.log2_int_ceil(T, bound);
	var result = nextWithBitSize(T, seed, bitSize);
	while(result >= bound) {
		result = nextWithBitSize(T, seed, bitSize);
	}
	return result;
}

pub fn nextFloat(seed: *u64) f32 {
	return @as(f32, @floatFromInt(nextInt(u24, seed)))/(1 << 24);
}

pub fn nextFloatSigned(seed: *u64) f32 {
	return @as(f32, @floatFromInt(@as(i24, @bitCast(nextInt(u24, seed)))))/(1 << 23);
}

pub fn nextFloatVector(len: comptime_int, seed: *u64) @Vector(len, f32) {
	var result: @Vector(len, f32) = undefined;
	inline for(0..len) |i| {
		result[i] = nextFloat(seed);
	}
	return result;
}

pub fn nextFloatVectorSigned(len: comptime_int, seed: *u64) @Vector(len, f32) {
	var result: @Vector(len, f32) = undefined;
	inline for(0..len) |i| {
		result[i] = nextFloatSigned(seed);
	}
	return result;
}

pub fn nextDouble(seed: *u64) f64 {
	const lower: u52 = nextInt(u32, seed);
	const upper: u52 = nextInt(u20, seed);
	return @as(f64, @floatFromInt(upper<<32 | lower))/(1 << 52);
}

pub fn nextDoubleSigned(seed: *u64) f64 {
	const lower: i52 = nextInt(u32, seed);
	const upper: i52 = nextInt(u20, seed);
	return @as(f64, @floatFromInt(upper<<32 | lower))/(1 << 51);
}

pub fn nextDoubleVector(len: comptime_int, seed: *u64) @Vector(len, f64) {
	var result: @Vector(len, f64) = undefined;
	inline for(0..len) |i| {
		result[i] = nextDouble(seed);
	}
	return result;
}

pub fn nextDoubleVectorSigned(len: comptime_int, seed: *u64) @Vector(len, f64) {
	var result: @Vector(len, f64) = undefined;
	inline for(0..len) |i| {
		result[i] = nextDoubleSigned(seed);
	}
	return result;
}

pub fn nextPointInUnitCircle(seed: *u64) Vec2f {
	while(true) {
		const x: f32 = nextFloatSigned(seed);
		const y: f32 = nextFloatSigned(seed);
		if(x*x + y*y < 1) {
			return Vec2f{x, y};
		}
	}
}

pub fn initSeed3D(worldSeed: u64, pos: Vec3i) u64 {
	const fac = Vec3i {11248723, 105436839, 45399083};
	const seed = @reduce(.Xor, fac *% pos);
	return @as(u32, @bitCast(seed)) ^ worldSeed;
}

pub fn initSeed2D(worldSeed: u64, pos: Vec2i) u64 {
	const fac = Vec2i {11248723, 105436839};
	const seed = @reduce(.Xor, fac *% pos);
	return @as(u32, @bitCast(seed)) ^ worldSeed;
}