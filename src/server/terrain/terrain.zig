const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const JsonElement = main.JsonElement;

pub const biomes = @import("biomes.zig");
pub const noise = @import("noise/noise.zig");
const Biome = biomes.Biome;

pub const ClimateMap = @import("ClimateMap.zig");

pub const SurfaceMap = @import("SurfaceMap.zig");

pub const CaveBiomeMap = @import("CaveBiomeMap.zig");

pub const CaveMap = @import("CaveMap.zig");

/// A generator for setting the actual Blocks in each Chunk.
pub const BlockGenerator = struct {
	init: *const fn(parameters: JsonElement) void,
	deinit: *const fn() void,
	generate: *const fn(seed: u64, chunk: *main.chunk.Chunk, caveMap: CaveMap.CaveMapView, biomeMap: CaveBiomeMap.CaveBiomeMapView) Allocator.Error!void,
	/// Used to prioritize certain generators over others.
	priority: i32,
	/// To avoid duplicate seeds in similar generation algorithms, the SurfaceGenerator xors the world-seed with the generator specific seed.
	generatorSeed: u64,


	var generatorRegistry: std.StringHashMapUnmanaged(BlockGenerator) = .{};

	pub fn registerGenerator(comptime GeneratorType: type) !void {
		var self = BlockGenerator {
			.init = &GeneratorType.init,
			.deinit = &GeneratorType.deinit,
			.generate = &GeneratorType.generate,
			.priority = GeneratorType.priority,
			.generatorSeed = GeneratorType.generatorSeed,
		};
		try generatorRegistry.put(main.globalAllocator, GeneratorType.id, self);
	}

	fn getAndInitGenerators(allocator: std.mem.Allocator, settings: JsonElement) ![]BlockGenerator {
		const list = try allocator.alloc(BlockGenerator, generatorRegistry.size);
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
	generators: []BlockGenerator = undefined,
	seed: u64,

	pub fn init(settings: JsonElement, seed: u64) !TerrainGenerationProfile {
		var self = TerrainGenerationProfile {
			.seed = seed,
		};
		var generator = settings.getChild("mapGenerator");
		self.mapFragmentGenerator = try SurfaceMap.MapGenerator.getGeneratorById(generator.get([]const u8, "id", "cubyz:mapgen_v1"));
		self.mapFragmentGenerator.init(generator);

		generator = settings.getChild("climateGenerator");
		self.climateGenerator = try ClimateMap.ClimateMapGenerator.getGeneratorById(generator.get([]const u8, "id", "cubyz:polar_circles"));
		self.climateGenerator.init(generator);

		generator = settings.getChild("caveBiomeGenerators");
		self.caveBiomeGenerators = try CaveBiomeMap.CaveBiomeGenerator.getAndInitGenerators(main.globalAllocator, generator);

		generator = settings.getChild("caveGenerators");
		self.caveGenerators = try CaveMap.CaveGenerator.getAndInitGenerators(main.globalAllocator, generator);

		generator = settings.getChild("generators");
		self.generators = try BlockGenerator.getAndInitGenerators(main.globalAllocator, generator);

		return self;
	}

	pub fn deinit(self: TerrainGenerationProfile) void {
		self.mapFragmentGenerator.deinit();
		self.climateGenerator.deinit();
		for(self.caveBiomeGenerators) |generator| {
			generator.deinit();
		}
		main.globalAllocator.free(self.caveBiomeGenerators);
		for(self.caveGenerators) |generator| {
			generator.deinit();
		}
		main.globalAllocator.free(self.caveGenerators);
		for(self.generators) |generator| {
			generator.deinit();
		}
		main.globalAllocator.free(self.generators);
	}
};

pub fn initGenerators() !void {
	try SurfaceMap.initGenerators();
	try ClimateMap.initGenerators();
	try CaveBiomeMap.initGenerators();
	try CaveMap.initGenerators();
	const list = @import("chunkgen/_list.zig");
	inline for(@typeInfo(list).Struct.decls) |decl| {
		try BlockGenerator.registerGenerator(@field(list, decl.name));
	}
	const t1 = std.time.milliTimestamp();
	noise.BlueNoise.load();
	std.log.info("Blue noise took {} ms to load", .{std.time.milliTimestamp() -% t1});
}

pub fn deinitGenerators() void {
	SurfaceMap.deinitGenerators();
	ClimateMap.deinitGenerators();
	CaveBiomeMap.deinitGenerators();
	CaveMap.deinitGenerators();
	BlockGenerator.generatorRegistry.clearAndFree(main.globalAllocator);
}

pub fn init(profile: TerrainGenerationProfile) !void {
	CaveBiomeMap.init(profile);
	CaveMap.init(profile);
	ClimateMap.init(profile);
	try SurfaceMap.init(profile);
}

pub fn deinit() void {
	CaveBiomeMap.deinit();
	CaveMap.deinit();
	ClimateMap.deinit();
	SurfaceMap.deinit();
}