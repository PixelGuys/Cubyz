const std = @import("std");

const main = @import("root");
const Vec3i = main.vec.Vec3i;

const multiplier: u64 = 0x5deece66d;
const addend: u64 = 0xb;
const mask: u64 = (1 << 48) - 1;

const doubleUnit: f64 = 1.0/@intToFloat(f64, 1 << 53);

pub fn scrambleSeed(seed: *u64) void {
	seed.* = (seed.* ^ multiplier) & mask;
}

fn nextWithBitSize(comptime T: type, seed: *u64, bitSize: u6) T {
	seed.* = ((seed.*)*%multiplier +% addend) & mask;
	return @intCast(T, (seed.* >> (48 - bitSize)) & std.math.maxInt(T));
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
	if(@typeInfo(T) != .Int) @compileError("Type must be integer.");
	if(@typeInfo(T).Int.signedness == .signed) @compileError("Type must be unsigned.");
	var bitSize = std.math.log2_int_ceil(T, bound);
	var result = nextWithBitSize(T, seed, bitSize);
	while(result >= bound) {
		result = nextWithBitSize(T, seed, bitSize);
	}
	return result;
}

pub fn nextFloat(seed: *u64) f32 {
	return @intToFloat(f32, nextInt(u24, seed))/@intToFloat(f32, 1 << 24);
}

pub fn nextDouble(seed: *u64) f64 {
	const lower: u52 = nextInt(u32, seed);
	const upper: u52 = nextInt(u20, seed);
	return @intToFloat(f64, upper<<32 | lower)/@intToFloat(f64, 1 << 52);
}

pub fn initSeed3D(worldSeed: u64, pos: Vec3i) u64 {
	const fac = Vec3i {11248723, 105436839, 45399083};
	const seed = @reduce(.Xor, fac *% pos);
	return @bitCast(u32, seed) ^ worldSeed;
}