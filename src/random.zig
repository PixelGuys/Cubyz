const std = @import("std");

const multiplier: u64 = 0x5deece66d;
const addend: u64 = 0xb;
const mask: u64 = (1 << 48) - 1;

const doubleUnit: f64 = 1.0/@intToFloat(f64, 1 << 53);

pub fn scrambleSeed(seed: *u64) void {
	seed.* = (seed.* ^ multiplier) & mask;
}

fn nextWithBitSize(T: type, seed: *u64, bitSize: u6) T {
	seed.* = ((seed.*)*multiplier + addend) & mask;
	return @intCast(T, (seed >> (48 - bitSize)) & std.math.maxInt(T));
}

fn next(T: type, seed: *u64) T {
	nextWithBitSize(T, seed, @bitSizeOf(T));
}

pub fn nextInt(T: type, seed: *u64) T {
	if(@bitSizeOf(T) > 48) {
		@compileError("Did not yet implement support for bigger numbers.");
	} else {
		return next(T, seed);
	}
}

pub fn nextIntBounded(T: type, seed: *u64, bound: T) T {
	var bitSize = std.math.log2_int_ceil(bound);
	var result = nextWithBitSize(T, seed, bitSize);
	while(result >= bound) {
		result = nextWithBitSize(T, seed, bitSize);
	}
	return result;
}

pub fn nextFloat(seed: *u64) f32 {
	return @intToFloat(f32, nextInt(u24, seed))/@intToFloat(f32, 1 << 24);
}