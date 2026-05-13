const std = @import("std");
const sign = std.math.sign;

const main = @import("main");
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const biomes = terrain.biomes;
const noise = terrain.noise;
const large_structure_map = terrain.large_structure_map;
const LargeStructureMapFragment = large_structure_map.LargeStructureMapFragment;
const SurfaceMap = terrain.SurfaceMap;
const MapFragment = SurfaceMap.MapFragment;
const CaveMapView = terrain.CaveMap.CaveMapView;
const CaveBiomeMapView = terrain.CaveBiomeMap.CaveBiomeMapView;
const ServerChunk = main.chunk.ServerChunk;
const vec = main.vec;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;

pub const id = "cubyz:large_biome_sdf";

pub const priority = 131072;

pub const generatorSeed = 0x582657686981298;

pub const defaultState = .enabled;

pub fn init(parameters: ZonElement) void {
	_ = parameters;
}

pub fn generate(map: *LargeStructureMapFragment, worldSeed: u64) void { // TODO: Why is this so slow in debug mode? Is it my laptop or some other factor?
	const size = LargeStructureMapFragment.size;
	const largestSdfSize = 512;
	const biomeMap = CaveBiomeMapView.init(main.stackAllocator, .{.wx = map.pos[0], .wy = map.pos[1], .wz = map.pos[2], .voxelSize = 1 << main.settings.highestSupportedLod}, size, largestSdfSize);
	defer biomeMap.deinit();

	const margin: Vec3i = @splat(largestSdfSize + terrain.CaveBiomeMap.CaveBiomeMapFragment.caveBiomeSize);
	const mapSize: Vec3i = @splat(LargeStructureMapFragment.size);
	const biomePoints = biomeMap.getCaveBiomesInRange(main.stackAllocator, map.pos -% margin, map.pos +% margin +% mapSize);
	defer main.stackAllocator.free(biomePoints);

	for (biomePoints) |biomePoint| {
		const distance = map.pos -% biomePoint.worldPos;
		if (@reduce(.Or, distance +% mapSize < biomePoint.biome.maxSdfExtend.min)) continue;
		if (@reduce(.Or, distance > biomePoint.biome.maxSdfExtend.max)) continue;
		var seed = main.random.initSeed3D(worldSeed, biomePoint.worldPos);
		var biomePos = biomePoint.worldPos;
		biomePos[2] +%= biomeMap.getCaveBiomeOffset(biomePos[0], biomePos[1]);
		for (biomePoint.biome.caveSdfModels) |sdfModel| {
			const amount: usize = @floor(sdfModel.minAmount + main.random.nextFloat(&seed)*(sdfModel.maxAmount - sdfModel.minAmount) + main.random.nextFloat(&seed));
			for (0..amount) |_| {
				const sdfInstance = sdfModel.instantiate(map.allocator, biomePos, map.pos, &seed);
				map.addSdf(sdfInstance);
			}
		}
	}
}
