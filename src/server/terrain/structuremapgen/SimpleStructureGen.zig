const std = @import("std");
const sign = std.math.sign;

const main = @import("root");
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const biomes = terrain.biomes;
const noise = terrain.noise;
const StructureMapFragment = terrain.StructureMap.StructureMapFragment;
const SurfaceMap = terrain.SurfaceMap;
const MapFragment = SurfaceMap.MapFragment;
const CaveBiomeMapView = terrain.CaveBiomeMap.CaveBiomeMapView;
const ServerChunk = main.chunk.ServerChunk;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const id = "cubyz:simple_structures";

pub const priority = 131072;

pub const generatorSeed = 0x7568492764892;

pub fn init(parameters: ZonElement) void {
	_ = parameters;
}

pub fn deinit() void {

}

pub fn generate(map: *StructureMapFragment, worldSeed: u64) void {
	const size = StructureMapFragment.size*map.pos.voxelSize;
	const biomeMap = CaveBiomeMapView.init(main.stackAllocator, map.pos, size, 32);
	defer biomeMap.deinit();
	const margin = 16;
	if(map.pos.voxelSize <= 4) {
		const blueNoise = noise.BlueNoise.getRegionData(main.stackAllocator, map.pos.wx -% margin, map.pos.wy -% margin, size + 2*margin, size + 2*margin);
		defer main.stackAllocator.free(blueNoise);
		var z: i32 = -32;
		while(z < size + 32) : (z += 32) {
			for(blueNoise) |coordinatePair| {
				const px = @as(i32, @intCast(coordinatePair >> 16)) - margin; // TODO: Maybe add a blue-noise iterator or something like that?
				const py = @as(i32, @intCast(coordinatePair & 0xffff)) - margin;
				const wpx = map.pos.wx +% px;
				const wpy = map.pos.wy +% py;
				const wpz = map.pos.wz +% z;
				var seed = random.initSeed3D(worldSeed, .{wpx, wpy, wpz});
				const relZ = z + 16;
				const biome = biomeMap.getBiome(px, py, relZ);
				var randomValue = random.nextFloat(&seed);
				for(biome.vegetationModels) |*model| { // TODO: Could probably use an alias table here.
					if(randomValue <  model.chance) {
						const data = map.allocator.create(SimpleStructure);
						data.* = .{
							.wx = wpx,
							.wy = wpy,
							.wz = map.pos.wz +% relZ,
							.seed = seed,
							.model = model,
						};
						map.addStructure(.{
							.data = @ptrCast(data),
							.generateFn = &SimpleStructure.generate,
						}, .{px -% margin, py -% margin, relZ -% margin -% 15}, .{px +% margin, py +% margin, relZ +% margin +% 15});
						break;
					} else {
						randomValue -= model.chance;
					}
				}
			}
		}
	} else { // TODO: Make this case work with cave-structures. Low priority because caves aren't even generated this far out.
		var px: i32 = 0;
		while(px < size + 2*margin) : (px += map.pos.voxelSize) {
			var py: i32 = 0;
			while(py < size + 2*margin) : (py += map.pos.voxelSize) {
				const wpx = px -% margin +% map.pos.wx;
				const wpy = py -% margin +% map.pos.wy;

				const relZ = biomeMap.getSurfaceHeight(wpx, wpy) -% map.pos.wz;
				if(relZ < -32 or relZ >= size + 32) continue;

				var seed = random.initSeed3D(worldSeed, .{wpx, wpy, relZ});
				var randomValue = random.nextFloat(&seed);
				const biome = biomeMap.getBiome(px, py, relZ);
				for(biome.vegetationModels) |*model| { // TODO: Could probably use an alias table here.
					var adaptedChance = model.chance/16;
					// Increase chance if there are less spawn points considered. Messes up positions, but at that distance density matters more.
					adaptedChance = 1 - std.math.pow(f32, 1 - adaptedChance, @as(f32, @floatFromInt(map.pos.voxelSize*map.pos.voxelSize)));
					if(randomValue < adaptedChance) {
						const data = map.allocator.create(SimpleStructure);
						data.* = .{
							.wx = wpx,
							.wy = wpy,
							.wz = map.pos.wz +% relZ,
							.seed = seed,
							.model = model,
						};
						map.addStructure(.{
							.data = @ptrCast(data),
							.generateFn = &SimpleStructure.generate,
						}, .{px -% margin, py -% margin, relZ -% margin -% 15}, .{px +% margin, py +% margin, relZ +% margin +% 15});
						break;
					} else {
						randomValue -= adaptedChance;
					}
				}
			}
		}
	}
}

const SimpleStructure = struct {
	model: *const biomes.SimpleStructureModel,
	seed: u64,
	wx: i32,
	wy: i32,
	wz: i32,

	pub fn generate(_self: *const anyopaque, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView) void {
		const self: *const SimpleStructure = @ptrCast(@alignCast(_self));
		var seed = self.seed;
		const px = self.wx - chunk.super.pos.wx;
		const py = self.wy - chunk.super.pos.wy;
		var relZ = self.wz -% chunk.super.pos.wz;
		var isCeiling: bool = false;
		switch(self.model.generationMode) {
			.floor => {
				if(caveMap.isSolid(px, py, relZ)) {
					relZ = caveMap.findTerrainChangeAbove(px, py, relZ);
				} else {
					relZ = caveMap.findTerrainChangeBelow(px, py, relZ) + chunk.super.pos.voxelSize;
				}
				if(relZ & ~@as(i32, 31) != self.wz -% chunk.super.pos.wz & ~@as(i32, 31)) return; // Too far from the surface.
			},
			.ceiling => {
				isCeiling = true;
				if(caveMap.isSolid(px, py, relZ)) {
					relZ = caveMap.findTerrainChangeBelow(px, py, relZ) - chunk.super.pos.voxelSize;
				} else {
					relZ = caveMap.findTerrainChangeAbove(px, py, relZ);
				}
				if(relZ & ~@as(i32, 31) != self.wz -% chunk.super.pos.wz & ~@as(i32, 31)) return; // Too far from the surface.
			},
			.floor_and_ceiling => {
				if(random.nextInt(u1, &seed) != 0) {
					if(caveMap.isSolid(px, py, relZ)) {
						relZ = caveMap.findTerrainChangeAbove(px, py, relZ);
					} else {
						relZ = caveMap.findTerrainChangeBelow(px, py, relZ) + chunk.super.pos.voxelSize;
					}
				} else {
					isCeiling = true;
					if(caveMap.isSolid(px, py, relZ)) {
						relZ = caveMap.findTerrainChangeBelow(px, py, relZ) - chunk.super.pos.voxelSize;
					} else {
						relZ = caveMap.findTerrainChangeAbove(px, py, relZ);
					}
				}
				if(relZ & ~@as(i32, 31) != self.wz -% chunk.super.pos.wz & ~@as(i32, 31)) return; // Too far from the surface.
			},
			.air => {
				relZ += -16 + random.nextIntBounded(i32, &seed, 32);
				if(caveMap.isSolid(px, py, relZ)) return;
			},
			.underground => {
				relZ += -16 + random.nextIntBounded(i32, &seed, 32);
				if(!caveMap.isSolid(px, py, relZ)) return;
			},
		}
		self.model.generate(px, py, relZ, chunk, caveMap, &seed, isCeiling);
}
};
