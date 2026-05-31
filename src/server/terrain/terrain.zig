const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const biomes = @import("biomes.zig");
pub const noise = @import("noise/noise.zig");
pub const structures = @import("structures.zig");
const Biome = biomes.Biome;

pub const ClimateMap = @import("ClimateMap.zig");

pub const SurfaceMap = @import("SurfaceMap.zig");

pub const LightMap = @import("LightMap.zig");

pub const CaveBiomeMap = @import("CaveBiomeMap.zig");

pub const CaveMap = @import("CaveMap.zig");

pub const cave_layers = @import("cave_layers.zig");

pub const StructureMap = @import("StructureMap.zig");

pub const sbb = @import("sbb.zig");

pub const sdf = @import("sdf.zig");

pub const chunk_generators = @import("chunkgen/_list.zig");

pub const GeneratorState = enum { enabled, disabled };

/// A generator for setting the actual Blocks in each Chunk.
pub const BlockGenerator = struct {
	init: *const fn (parameters: ZonElement) void,
	generate: *const fn (seed: u64, chunk: *main.chunk.ServerChunk, caveMap: CaveMap.CaveMapView, biomeMap: CaveBiomeMap.CaveBiomeMapView) void,
	/// Used to prioritize certain generators over others.
	priority: i32,
	/// To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the world-seed with the generator specific seed.
	generatorSeed: u64,
	defaultState: GeneratorState,

	const generatorRegistry: std.StaticStringMap(BlockGenerator) = .initComptime(blk: {
		const decls = @typeInfo(chunk_generators).@"struct".decls;
		var generators: [decls.len]struct { []const u8, BlockGenerator } = undefined;
		for (0..decls.len) |i| {
			const Generator = @field(chunk_generators, decls[i].name);
			generators[i] = .{Generator.id, .{
				.init = &Generator.init,
				.generate = &Generator.generate,
				.priority = Generator.priority,
				.generatorSeed = Generator.generatorSeed,
				.defaultState = Generator.defaultState,
			}};
		}
		break :blk generators;
	});

	fn getAndInitGenerators(allocator: NeverFailingAllocator, settings: ZonElement) []const BlockGenerator {
		var list: main.ListUnmanaged(BlockGenerator) = .initCapacity(allocator, generatorRegistry.values().len);
		for (generatorRegistry.keys(), generatorRegistry.values()) |id, generator| {
			const generatorSettings = settings.getChild(id);
			if (generatorSettings.get(GeneratorState, "state", generator.defaultState) == .disabled) continue;
			generator.init(generatorSettings);
			list.appendAssumeCapacity(generator);
		}
		const lessThan = struct {
			fn lessThan(_: void, lhs: BlockGenerator, rhs: BlockGenerator) bool {
				return lhs.priority < rhs.priority;
			}
		}.lessThan;
		std.sort.insertion(BlockGenerator, list.items, {}, lessThan);
		return list.toOwnedSlice(allocator);
	}
};

/// Lists all the Generators and Biomes that should be used for a given world.
/// TODO: Generator/Biome blackslisting (from the world creation menu).
/// TODO: Generator settings (from the world creation menu).
pub const TerrainGenerationProfile = struct {
	mapFragmentGenerator: SurfaceMap.MapGenerator = undefined,
	climateGenerator: ClimateMap.ClimateMapGenerator = undefined,
	caveBiomeGenerators: []const CaveBiomeMap.CaveBiomeGenerator = undefined,
	caveGenerators: []const CaveMap.CaveGenerator = undefined,
	structureMapGenerators: []const StructureMap.StructureMapGenerator = undefined,
	generators: []const BlockGenerator = undefined,
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
	const t1 = main.timestamp();
	noise.BlueNoise.load();
	std.log.info("Blue noise took {} ms to load", .{t1.durationTo(main.timestamp()).toMilliseconds()});
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
