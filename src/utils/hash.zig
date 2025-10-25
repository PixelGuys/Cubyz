const std = @import("std");
const main = @import("main");

const Biome = main.server.terrain.biomes;
const Structures = main.server.terrain.structures;
const StructureTable = Structures.StructureTable;

pub fn hashGeneric(input: anytype) u64 {
	const T = @TypeOf(input);
	return switch(@typeInfo(T)) {
		.bool => hashCombine(hashInt(@intFromBool(input)), 0xbf58476d1ce4e5b9),
		.@"enum" => hashCombine(hashInt(@as(u64, @intFromEnum(input))), 0x94d049bb133111eb),
		.int, .float => blk: {
			const value = @as(std.meta.Int(.unsigned, @bitSizeOf(T)), @bitCast(input));
			break :blk hashInt(@as(u64, value));
		},
		.@"struct" => blk: {
			if(@hasDecl(T, "getHash")) {
				break :blk input.getHash();
			}
			var result: u64 = hashGeneric(@typeName(T));
			inline for(@typeInfo(T).@"struct".fields) |field| {
				const keyHash = hashGeneric(@as([]const u8, field.name));
				const valueHash = hashGeneric(@field(input, field.name));
				const keyValueHash = hashCombine(keyHash, valueHash);
				result = hashCombine(result, keyValueHash);
			}
			break :blk result;
		},
		.optional => if(input) |_input| hashGeneric(_input) else 0,
		.pointer => switch(@typeInfo(T).pointer.size) {
			.one => blk: {
				if(@typeInfo(@typeInfo(T).pointer.child) == .@"fn") break :blk 0;
				if(@typeInfo(T).pointer.child == Biome) return hashGeneric(input.id);
				if(@typeInfo(T).pointer.child == anyopaque) break :blk 0;
				if(@typeInfo(T).pointer.child == Structures) return hashGeneric(input.id);
				if(@typeInfo(T).pointer.child == StructureTable) return hashGeneric(input.id);
				break :blk hashGeneric(input.*);
			},
			.slice => blk: {
				var result: u64 = hashInt(input.len);
				for(input) |val| {
					const valueHash = hashGeneric(val);
					result = hashCombine(result, valueHash);
				}
				break :blk result;
			},
			else => @compileError("Unsupported type " ++ @typeName(T)),
		},
		.array => blk: {
			var result: u64 = 0xbf58476d1ce4e5b9;
			for(input) |val| {
				const valueHash = hashGeneric(val);
				result = hashCombine(result, valueHash);
			}
			break :blk result;
		},
		.vector => blk: {
			var result: u64 = 0x94d049bb133111eb;
			inline for(0..@typeInfo(T).vector.len) |i| {
				const valueHash = hashGeneric(input[i]);
				result = hashCombine(result, valueHash);
			}
			break :blk result;
		},
		else => @compileError("Unsupported type " ++ @typeName(T)),
	};
}

// https://stackoverflow.com/questions/5889238/why-is-xor-the-default-way-to-combine-hashes
pub fn hashCombine(left: u64, right: u64) u64 {
	return left ^ (right +% 0x517cc1b727220a95 +% (left << 6) +% (left >> 2));
}

// https://stackoverflow.com/questions/664014/what-integer-hash-function-are-good-that-accepts-an-integer-hash-key
pub fn hashInt(input: u64) u64 {
	var x = input;
	x = (x ^ (x >> 30))*%0xbf58476d1ce4e5b9;
	x = (x ^ (x >> 27))*%0x94d049bb133111eb;
	x = x ^ (x >> 31);
	return x;
}
