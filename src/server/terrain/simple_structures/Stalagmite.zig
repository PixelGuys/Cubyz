const std = @import("std");

const main = @import("root");
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const CaveMap = terrain.CaveMap;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

pub const id = "cubyz:stalagmite";

pub const generationMode = .floor_and_ceiling;

const Stalagmite = @This();

blockType: u16,
size: f32,
sizeVariation: f32,

pub fn loadModel(arenaAllocator: NeverFailingAllocator, parameters: ZonElement) *Stalagmite {
	const self = arenaAllocator.create(Stalagmite);
	self.* = .{
		.blockType = main.blocks.getByID(parameters.get([]const u8, "block", "cubyz:stalagmite")),
		.size = parameters.get(f32, "size", 12),
		.sizeVariation = parameters.get(f32, "size_variation", 8),
	};
	return self;
}

pub fn generate(self: *Stalagmite, x: i32, y: i32, z: i32, chunk: *main.chunk.ServerChunk, _: terrain.CaveMap.CaveMapView, seed: *u64, isCeiling: bool) void {
	const relX: f32 = @as(f32, @floatFromInt(x)) + main.random.nextFloat(seed);
	const relY: f32 = @as(f32, @floatFromInt(y)) + main.random.nextFloat(seed);
	var relZ: f32 = @as(f32, @floatFromInt(z)) + main.random.nextFloat(seed);

	var length = self.size + random.nextFloat(seed)*self.sizeVariation;

	const delZ: f32 = if(isCeiling) -1 else 1;
	relZ -= delZ*length/4;
	length += length/4;

	var j: f32 = 0;
	while(j < length) {
		const z2 = relZ + delZ*j;
		var size: f32 = 0;
		size = (length - j)/4;
		const xMin: i32 = @intFromFloat(relX - size);
		const xMax: i32 = @intFromFloat(relX + size);
		const yMin: i32 = @intFromFloat(relY - size);
		const yMax: i32 = @intFromFloat(relY + size);
		const zMin: i32 = @intFromFloat(z2 - size);
		const zMax: i32 = @intFromFloat(z2 + size);
		var x3: i32 = xMin;
		while(x3 <= xMax) : (x3 += 1) {
			var y3: i32 = yMin;
			while(y3 <= yMax) : (y3 += 1) {
				var z3: i32 = zMin;
				while(z3 <= zMax) : (z3 += 1) {
					const dist = vec.lengthSquare(Vec3f{@as(f32, @floatFromInt(x3)) - relX, @as(f32, @floatFromInt(y3)) - relY, @as(f32, @floatFromInt(z3)) - z2});
					if(dist < size*size) {
						if(x3 >= 0 and x3 < chunk.super.width and y3 >= 0 and y3 < chunk.super.width and z3 >= 0 and z3 < chunk.super.width) {
							const block: main.blocks.Block = chunk.getBlock(x3, y3, z3);
							if(block.typ == 0 or block.degradable() or block.blockClass() == .fluid) {
								chunk.updateBlockInGeneration(x3, y3, z3, .{.typ = self.blockType, .data = 0}); // TODO: Use natural standard.
							}
						}
					}
				}
			}
		}
		if(size > 2) size = 2;
		j += size/2; // Make sure there are no stalagmite bits floating in the air.
		if(size < 0.5) break; // Also preventing floating stalagmite bits.
	}
}
