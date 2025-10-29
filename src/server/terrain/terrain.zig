const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const biomes = @import("biomes.zig");
pub const noise = @import("noise/noise.zig");
const Biome = biomes.Biome;

pub const ClimateMap = @import("ClimateMap.zig");

pub const SurfaceMap = @import("SurfaceMap.zig");

pub const LightMap = @import("LightMap.zig");

pub const CaveBiomeMap = @import("CaveBiomeMap.zig");

pub const CaveMap = @import("CaveMap.zig");

pub const StructureMap = @import("StructureMap.zig");

pub const structure_building_blocks = @import("structure_building_blocks.zig");

/// A generator for setting the actual Blocks in each Chunk.
pub const BlockGenerator = struct {
	init: *const fn(parameters: ZonElement) void,
	generate: *const fn(seed: u64, chunk: *main.chunk.ServerChunk, caveMap: CaveMap.CaveMapView, biomeMap: CaveBiomeMap.CaveBiomeMapView) void,
	/// Used to prioritize certain generators over others.
	priority: i32,
	/// To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the world-seed with the generator specific seed.
	generatorSeed: u64,

	var generatorRegistry: std.StringHashMapUnmanaged(BlockGenerator) = .{};

	pub fn registerGenerator(comptime GeneratorType: type) void {
		const self = BlockGenerator{
			.init = &GeneratorType.init,
			.generate = &GeneratorType.generate,
			.priority = GeneratorType.priority,
			.generatorSeed = GeneratorType.generatorSeed,
		};
		generatorRegistry.put(main.globalAllocator.allocator, GeneratorType.id, self) catch unreachable;
	}

	fn getAndInitGenerators(allocator: NeverFailingAllocator, settings: ZonElement) []BlockGenerator {
		const list = allocator.alloc(BlockGenerator, generatorRegistry.size);
		var iterator = generatorRegistry.iterator();
		var i: usize = 0;
		while(iterator.next()) |generator| {
			list[i] = generator.value_ptr.*;
			list[i].init(settings.getChild(generator.key_ptr.*));
			i += 1;
		}
		const lessThan = struct {
			fn lessThan(_: void, lhs: BlockGenerator, rhs: BlockGenerator) bool {
				return lhs.priority < rhs.priority;
			}
		}.lessThan;
		std.sort.insertion(BlockGenerator, list, {}, lessThan);
		return list;
	}
};

/// Lists all the Generators and Biomes that should be used for a given world.
/// TODO: Generator/Biome blackslisting (from the world creation menu).
/// TODO: Generator settings (from the world creation menu).
pub const TerrainGenerationProfile = struct {
	mapFragmentGenerator: SurfaceMap.MapGenerator = undefined,
	climateGenerator: ClimateMap.ClimateMapGenerator = undefined,
	caveBiomeGenerators: []CaveBiomeMap.CaveBiomeGenerator = undefined,
	caveGenerators: []CaveMap.CaveGenerator = undefined,
	structureMapGenerators: []StructureMap.StructureMapGenerator = undefined,
	generators: []BlockGenerator = undefined,
	climateWavelengths: [5]f32 = undefined,
	seed: u64,

	pub fn init(settings: ZonElement, seed: u64) !TerrainGenerationProfile {
		var self = TerrainGenerationProfile{
			.seed = seed,
		};
		var generator = settings.getChild("mapGenerator");
		self.mapFragmentGenerator = try SurfaceMap.MapGenerator.getGeneratorById(generator.get([]const u8, "id", "cubyz:mapgen_v1"));
		self.mapFragmentGenerator.init(generator);

		generator = settings.getChild("climateGenerator");
		self.climateGenerator = try ClimateMap.ClimateMapGenerator.getGeneratorById(generator.get([]const u8, "id", "cubyz:polar_circles"));
		self.climateGenerator.init(generator);

		generator = settings.getChild("caveBiomeGenerators");
		self.caveBiomeGenerators = CaveBiomeMap.CaveBiomeGenerator.getAndInitGenerators(main.worldArena, generator);

		generator = settings.getChild("caveGenerators");
		self.caveGenerators = CaveMap.CaveGenerator.getAndInitGenerators(main.worldArena, generator);

		generator = settings.getChild("structureMapGenerators");
		self.structureMapGenerators = StructureMap.StructureMapGenerator.getAndInitGenerators(main.worldArena, generator);

		generator = settings.getChild("generators");
		self.generators = BlockGenerator.getAndInitGenerators(main.worldArena, generator);

		const climateWavelengths = settings.getChild("climateWavelengths");
		self.climateWavelengths[0] = climateWavelengths.get(f32, "hot_cold", 2400);
		self.climateWavelengths[1] = climateWavelengths.get(f32, "land_ocean", 3200);
		self.climateWavelengths[2] = climateWavelengths.get(f32, "wet_dry", 2400);
		self.climateWavelengths[3] = climateWavelengths.get(f32, "vegetation", 2400);
		self.climateWavelengths[4] = climateWavelengths.get(f32, "mountain", 500);

		return self;
	}
};

pub fn globalInit() void {
	SurfaceMap.globalInit();
	ClimateMap.globalInit();
	CaveBiomeMap.globalInit();
	CaveMap.globalInit();
	StructureMap.globalInit();
	const list = @import("chunkgen/_list.zig");
	inline for(@typeInfo(list).@"struct".decls) |decl| {
		BlockGenerator.registerGenerator(@field(list, decl.name));
	}
	const t1 = std.time.milliTimestamp();
	noise.BlueNoise.load();
	std.log.info("Blue noise took {} ms to load", .{std.time.milliTimestamp() -% t1});
}

pub fn globalDeinit() void {
	CaveBiomeMap.globalDeinit();
	CaveMap.globalDeinit();
	StructureMap.globalDeinit();
	ClimateMap.globalDeinit();
	SurfaceMap.globalDeinit();
	BlockGenerator.generatorRegistry.clearAndFree(main.globalAllocator.allocator);
}

pub fn init(profile: TerrainGenerationProfile) void {
	CaveBiomeMap.init(profile);
	CaveMap.init(profile);
	StructureMap.init(profile);
	ClimateMap.init(profile);
	SurfaceMap.init(profile);
}

pub fn deinit() void {
	CaveBiomeMap.deinit();
	CaveMap.deinit();
	StructureMap.deinit();
	ClimateMap.deinit();
	SurfaceMap.deinit();
	LightMap.deinit();
}
