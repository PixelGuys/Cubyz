const std = @import("std");

const main = @import("root");
const blocks = main.blocks;
const ServerChunk = main.chunk.ServerChunk;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;
const vec = @import("main.vec");
const Vec3f = main.vec.Vec3f;
const Vec3d = main.vec.Vec3d;

pub const SimpleStructureModel = struct { // MARK: SimpleStructureModel
	const GenerationMode = enum {
		floor,
		ceiling,
		floor_and_ceiling,
		air,
		underground,
	};
	const VTable = struct {
		loadModel: *const fn(arenaAllocator: NeverFailingAllocator, parameters: ZonElement) *anyopaque,
		generate: *const fn(self: *anyopaque, x: i32, y: i32, z: i32, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView, seed: *u64, isCeiling: bool) void,
		hashFunction: *const fn(self: *anyopaque) u64,
		generationMode: GenerationMode,
	};

	vtable: VTable,
	data: *anyopaque,
	chance: f32,
	priority: f32,
	generationMode: GenerationMode,

	pub fn initModel(parameters: ZonElement) ?SimpleStructureModel {
		const id = parameters.get([]const u8, "id", "");
		const vtable = modelRegistry.get(id) orelse {
			std.log.err("Couldn't find structure model with id {s}", .{id});
			return null;
		};
		return SimpleStructureModel {
			.vtable = vtable,
			.data = vtable.loadModel(arena.allocator(), parameters),
			.chance = parameters.get(f32, "chance", 0.1),
			.priority = parameters.get(f32, "priority", 1),
			.generationMode = std.meta.stringToEnum(GenerationMode, parameters.get([]const u8, "generationMode", "")) orelse vtable.generationMode,
		};
	}

	pub fn generate(self: SimpleStructureModel, x: i32, y: i32, z: i32, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView, seed: *u64, isCeiling: bool) void {
		self.vtable.generate(self.data, x, y, z, chunk, caveMap, seed, isCeiling);
	}


	var modelRegistry: std.StringHashMapUnmanaged(VTable) = .{};
	var arena: main.utils.NeverFailingArenaAllocator = .init(main.globalAllocator);

	pub fn reset() void {
		std.debug.assert(arena.reset(.free_all));
	}

	pub fn registerGenerator(comptime Generator: type) void {
		var self: VTable = undefined;
		self.loadModel = @ptrCast(&Generator.loadModel);
		self.generate = @ptrCast(&Generator.generate);
		self.hashFunction = @ptrCast(&struct {
			fn hash(ptr: *Generator) u64 {
				return hashGeneric(ptr.*);
			}
		}.hash);
		self.generationMode = Generator.generationMode;
		modelRegistry.put(main.globalAllocator.allocator, Generator.id, self) catch unreachable;
	}

	fn getHash(self: SimpleStructureModel) u64 {
		return self.vtable.hashFunction(self.data);
	}
};

const Stripe = struct { // MARK: Stripe
	direction: ?Vec3d,
	block: main.blocks.Block,
	minDistance: f64,
	maxDistance: f64,
	minOffset: f64,
	maxOffset: f64,
	minWidth: f64,
	maxWidth: f64,

	pub fn init(parameters: ZonElement) Stripe {
		var dir: ?Vec3d = parameters.get(?Vec3d, "direction", null);
		if(dir != null) {
			dir = main.vec.normalize(dir.?);
		}

		const block: main.blocks.Block = blocks.getBlockById(parameters.get([]const u8, "block", ""));
		
		var minDistance: f64 = 0;
		var maxDistance: f64 = 0;
		if (parameters.object.get("distance")) |dist| {
			minDistance = dist.as(f64, 0);
			maxDistance = dist.as(f64, 0);
		} else {
			minDistance = parameters.get(f64, "minDistance", 0);
			maxDistance = parameters.get(f64, "maxDistance", 0);
		}

		var minOffset: f64 = 0;
		var maxOffset: f64 = 0;
		if (parameters.object.get("offset")) |off| {
			minOffset = off.as(f64, 0);
			maxOffset = off.as(f64, 0);
		} else {
			minOffset = parameters.get(f64, "minOffset", 0);
			maxOffset = parameters.get(f64, "maxOffset", 0);
		}

		var minWidth: f64 = 0;
		var maxWidth: f64 = 0;
		if (parameters.object.get("width")) |width| {
			minWidth = width.as(f64, 0);
			maxWidth = width.as(f64, 0);
		} else {
			minWidth = parameters.get(f64, "minWidth", 0);
			maxWidth = parameters.get(f64, "maxWidth", 0);
		}

		return Stripe {
			.direction = dir,
			.block = block,

			.minDistance = minDistance,
			.maxDistance = maxDistance,

			.minOffset = minOffset,
			.maxOffset = maxOffset,

			.minWidth = minWidth,
			.maxWidth = maxWidth,
		};
	}
};

fn hashGeneric(input: anytype) u64 {
	const T = @TypeOf(input);
	return switch(@typeInfo(T)) {
		.bool => @intFromBool(input),
		.@"enum" => @intFromEnum(input),
		.int, .float => @as(std.meta.Int(.unsigned, @bitSizeOf(T)), @bitCast(input)),
		.@"struct" => blk: {
			if(@hasDecl(T, "getHash")) {
				break :blk input.getHash();
			}
			var result: u64 = 0;
			inline for(@typeInfo(T).@"struct".fields) |field| {
				result ^= hashGeneric(@field(input, field.name))*%hashGeneric(@as([]const u8, field.name));
			}
			break :blk result;
		},
		.optional => if(input) |_input| hashGeneric(_input) else 0,
		.pointer => switch(@typeInfo(T).pointer.size) {
			.One => blk: {
				if(@typeInfo(@typeInfo(T).pointer.child) == .@"fn") break :blk 0;
				if(@typeInfo(T).pointer.child == Biome) return hashGeneric(input.id);
				if(@typeInfo(T).pointer.child == anyopaque) break :blk 0;
				break :blk hashGeneric(input.*);
			},
			.Slice => blk: {
				var result: u64 = 0;
				for(input) |val| {
					result = result*%33 +% hashGeneric(val);
				}
				break :blk result;
			},
			else => @compileError("Unsupported type " ++ @typeName(T)),
		},
		.array => blk: {
			var result: u64 = 0;
			for(input) |val| {
				result = result*%33 +% hashGeneric(val);
			}
			break :blk result;
		},
		.vector => blk: {
			var result: u64 = 0;
			inline for(0..@typeInfo(T).vector.len) |i| {
				result = result*%33 +% hashGeneric(input[i]);
			}
			break :blk result;
		},
		else => @compileError("Unsupported type " ++ @typeName(T)),
	};
}

pub const Interpolation = enum(u8) {
	none,
	linear,
	square,
};

fn u32ToVec3(color: u32) Vec3f {
	const r = @as(f32, @floatFromInt((color >> 16) & 0xFF)) / 255.0;
	const g = @as(f32, @floatFromInt((color >> 8) & 0xFF)) / 255.0;
	const b = @as(f32, @floatFromInt(color & 0xFF)) / 255.0;
	
	return .{ r, g, b };
}

/// A climate region with special ground, plants and structures.
pub const Biome = struct { // MARK: Biome
	pub const GenerationProperties = packed struct(u15) {
		// pairs of opposite properties. In-between values are allowed.
		hot: bool = false,
		temperate: bool = false,
		cold: bool = false,

		inland: bool = false,
		land: bool = false,
		ocean: bool = false,

		wet: bool = false,
		neitherWetNorDry: bool = false,
		dry: bool = false,

		barren: bool = false,
		balanced: bool = false,
		overgrown: bool = false,

		mountain: bool = false,
		lowTerrain: bool = false,
		antiMountain: bool = false, //???

		pub const mask: u15 = 0b001001001001001;

		pub fn fromZon(zon: ZonElement, initMidValues: bool) GenerationProperties {
			var result: GenerationProperties = .{};
			for(zon.toSlice()) |child| {
				const property = child.as([]const u8, "");
				inline for(@typeInfo(GenerationProperties).@"struct".fields) |field| {
					if(std.mem.eql(u8, field.name, property)) {
						@field(result, field.name) = true;
					}
				}
			}
			if(initMidValues) {
				// Fill all mid values if no value was specified in a group:
				const val: u15 = @bitCast(result);
				const empty = ~val & ~val >> 1 & ~val >> 2 & mask;
				result = @bitCast(val | empty << 1);
			}
			return result;
		}
	};

	properties: GenerationProperties,
	isCave: bool,
	radius: f32,
	radiusVariation: f32,
	minHeight: i32,
	maxHeight: i32,
	interpolation: Interpolation,
	interpolationWeight: f32,
	roughness: f32,
	hills: f32,
	mountains: f32,
	caves: f32,
	caveRadiusFactor: f32,
	crystals: u32,
	stoneBlock: main.blocks.Block,
	fogLower: f32,
	fogHigher: f32,
	fogDensity: f32,
	fogColor: Vec3f,
	id: []const u8,
	paletteId: u32,
	structure: BlockStructure = undefined,
	/// Whether the starting point of a river can be in this biome. If false rivers will be able to flow through this biome anyways.
	supportsRivers: bool, // TODO: Reimplement rivers.
	/// The first members in this array will get prioritized.
	vegetationModels: []SimpleStructureModel = &.{},
	stripes: []Stripe = &.{},
	subBiomes: main.utils.AliasTable(*const Biome) = .{.items = &.{}, .aliasData = &.{}},
	transitionBiomes: []TransitionBiome = &.{},
	maxSubBiomeCount: f32,
	subBiomeTotalChance: f32 = 0,
	preferredMusic: []const u8, // TODO: Support multiple possibilities that are chosen based on time and danger.
	isValidPlayerSpawn: bool,
	chance: f32,

	pub fn init(self: *Biome, id: []const u8, paletteId: u32, zon: ZonElement) void {
		const minRadius = zon.get(f32, "radius", zon.get(f32, "minRadius", 256));
		const maxRadius = zon.get(f32, "maxRadius", minRadius);
		self.* = Biome {
			.id = main.globalAllocator.dupe(u8, id),
			.paletteId = paletteId,
			.properties = GenerationProperties.fromZon(zon.getChild("properties"), true),
			.isCave = zon.get(bool, "isCave", false),
			.radius = (maxRadius + minRadius)/2,
			.radiusVariation = (maxRadius - minRadius)/2,
			.stoneBlock = blocks.getBlockById(zon.get([]const u8, "stoneBlock", "cubyz:stone")),
			.fogColor = u32ToVec3(zon.get(u32, "fogColor", 0xffccccff)),
			.fogDensity = zon.get(f32, "fogDensity", 1.0)/15.0/128.0,
			.fogLower = zon.get(f32, "fogLower", 100.0),
			.fogHigher = zon.get(f32, "fogHigher", 1000.0),
			.roughness = zon.get(f32, "roughness", 0),
			.hills = zon.get(f32, "hills", 0),
			.mountains = zon.get(f32, "mountains", 0),
			.interpolation = std.meta.stringToEnum(Interpolation, zon.get([]const u8, "interpolation", "square")) orelse .square,
			.interpolationWeight = @max(zon.get(f32, "interpolationWeight", 1), std.math.floatMin(f32)),
			.caves = zon.get(f32, "caves", -0.375),
			.caveRadiusFactor = @max(-2, @min(2, zon.get(f32, "caveRadiusFactor", 1))),
			.crystals = zon.get(u32, "crystals", 0),
			.minHeight = zon.get(i32, "minHeight", std.math.minInt(i32)),
			.maxHeight = zon.get(i32, "maxHeight", std.math.maxInt(i32)),
			.supportsRivers = zon.get(bool, "rivers", false),
			.preferredMusic = main.globalAllocator.dupe(u8, zon.get([]const u8, "music", "cubyz:cubyz")),
			.isValidPlayerSpawn = zon.get(bool, "validPlayerSpawn", false),
			.chance = zon.get(f32, "chance", if(zon == .null) 0 else 1),
			.maxSubBiomeCount = zon.get(f32, "maxSubBiomeCount", std.math.floatMax(f32)),
		};
		if(self.minHeight > self.maxHeight) {
			std.log.err("Biome {s} has invalid height range ({}, {})", .{self.id, self.minHeight, self.maxHeight});
		}
		const parentBiomeList = zon.getChild("parentBiomes");
		for(parentBiomeList.toSlice()) |parent| {
			const result = unfinishedSubBiomes.getOrPutValue(main.globalAllocator.allocator, parent.get([]const u8, "id", ""), .{}) catch unreachable;
			result.value_ptr.append(main.globalAllocator, .{.biomeId = self.id, .chance = parent.get(f32, "chance", 1)});
		}

		const transitionBiomeList = zon.getChild("transitionBiomes").toSlice();
		if(transitionBiomeList.len != 0) {
			const transitionBiomes = main.globalAllocator.alloc(UnfinishedTransitionBiomeData, transitionBiomeList.len);
			for(transitionBiomes, transitionBiomeList) |*dst, src| {
				dst.* = .{
					.biomeId = src.get([]const u8, "id", ""),
					.chance = src.get(f32, "chance", 1),
					.propertyMask = GenerationProperties.fromZon(src.getChild("properties"), false),
					.width = src.get(u8, "width", 2),
					.keepOriginalTerrain = src.get(f32, "keepOriginalTerrain", 0),
				};
				// Fill all unspecified property groups:
				var properties: u15 = @bitCast(dst.propertyMask);
				const empty = ~properties & ~properties >> 1 & ~properties >> 2 & GenerationProperties.mask;
				properties |= empty | empty << 1 | empty << 2;
				dst.propertyMask = @bitCast(properties);
			}
			unfinishedTransitionBiomes.put(main.globalAllocator.allocator, self.id, transitionBiomes) catch unreachable;
		}

		self.structure = BlockStructure.init(main.globalAllocator, zon.getChild("ground_structure"));
		
		const structures = zon.getChild("structures");
		var vegetation = main.ListUnmanaged(SimpleStructureModel){};
		var totalChance: f32 = 0;
		defer vegetation.deinit(main.stackAllocator);
		for(structures.toSlice()) |elem| {
			if(SimpleStructureModel.initModel(elem)) |model| {
				vegetation.append(main.stackAllocator, model);
				totalChance += model.chance;
			}
		}
		if(totalChance > 1) {
			for(vegetation.items) |*model| {
				model.chance /= totalChance;
			}
		}
		self.vegetationModels = main.globalAllocator.dupe(SimpleStructureModel, vegetation.items);

		const stripes = zon.getChild("stripes");
		self.stripes = main.globalAllocator.alloc(Stripe, stripes.toSlice().len);
		for (stripes.toSlice(), 0..) |elem, i| {
			self.stripes[i] = Stripe.init(elem);
		}
	}

	pub fn deinit(self: *Biome) void {
		self.subBiomes.deinit(main.globalAllocator);
		self.structure.deinit(main.globalAllocator);
		main.globalAllocator.free(self.transitionBiomes);
		main.globalAllocator.free(self.vegetationModels);
		main.globalAllocator.free(self.stripes);
		main.globalAllocator.free(self.preferredMusic);
		main.globalAllocator.free(self.id);
	}

	fn getCheckSum(self: *Biome) u64 {
		return hashGeneric(self.*);
	}
};

/// Stores the vertical ground structure of a biome from top to bottom.
pub const BlockStructure = struct { // MARK: BlockStructure
	pub const BlockStack = struct {
		block: main.blocks.Block = .{.typ = 0, .data = 0},
		min: u31 = 0,
		max: u31 = 0,

		fn init(self: *BlockStack, string: []const u8) !void {
			var tokenIt = std.mem.tokenizeAny(u8, string, &std.ascii.whitespace);
			const first = tokenIt.next() orelse return error.@"String is empty.";
			var blockId: []const u8 = first;
			if(tokenIt.next()) |second| {
				self.min = try std.fmt.parseInt(u31, first, 0);
				if(tokenIt.next()) |third| {
					const fourth = tokenIt.next() orelse return error.@"Expected 1, 2 or 4 parameters, found 3.";
					if(!std.mem.eql(u8, second, "to")) return error.@"Expected layout '<min> to <max> <block>'. Missing 'to'.";
					self.max = try std.fmt.parseInt(u31, third, 0);
					blockId = fourth;
					if(tokenIt.next() != null) return error.@"Found too many parameters. Expected 1, 2 or 4.";
					if(self.max < self.min) return error.@"The max value must be bigger than the min value.";
				} else {
					self.max = self.min;
					blockId = second;
				}
			} else {
				self.min = 1;
				self.max = 1;
			}
			self.block = blocks.getBlockById(blockId);
		}
	};
	structure: []BlockStack,

	pub fn init(allocator: NeverFailingAllocator, zonArray: ZonElement) BlockStructure {
		const blockStackDescriptions = zonArray.toSlice();
		const self = BlockStructure {
			.structure = allocator.alloc(BlockStack, blockStackDescriptions.len),
		};
		for(blockStackDescriptions, self.structure) |zonString, *blockStack| {
			blockStack.init(zonString.as([]const u8, "That's not a zon string.")) catch |err| {
				std.log.err("Couldn't parse blockStack '{s}': {s} Removing it.", .{zonString.as([]const u8, "(not a zon string)"), @errorName(err)});
				blockStack.* = .{};
			};
		}
		return self;
	}

	pub fn deinit(self: BlockStructure, allocator: NeverFailingAllocator) void {
		allocator.free(self.structure);
	}

	pub fn addSubTerranian(self: BlockStructure, chunk: *ServerChunk, startingDepth: i32, minDepth: i32, x: i32, y: i32, seed: *u64) i32 {
		var depth = startingDepth;
		for(self.structure) |blockStack| {
			const total = blockStack.min + main.random.nextIntBounded(u32, seed, @as(u32, 1) + blockStack.max - blockStack.min);
			for(0..total) |_| {
				if(chunk.liesInChunk(x, y, depth)) {
					chunk.updateBlockInGeneration(x, y, depth, blockStack.block);
				}
				depth -%= chunk.super.pos.voxelSize;
				if(depth -% minDepth <= 0)
					return depth +% chunk.super.pos.voxelSize;
			}
		}
		return depth +% chunk.super.pos.voxelSize;
	}
};

pub const TreeNode = union(enum) { // MARK: TreeNode
	leaf: struct {
		totalChance: f64 = 0,
		aliasTable: main.utils.AliasTable(Biome) = undefined,
	},
	branch: struct {
		lowerBorder: f32,
		upperBorder: f32,
		children: [3]*TreeNode,
	},

	pub fn init(allocator: NeverFailingAllocator, currentSlice: []Biome, parameterShift: u5) *TreeNode {
		const self = allocator.create(TreeNode);
		if(currentSlice.len <= 1 or parameterShift >= @bitSizeOf(Biome.GenerationProperties)) {
			self.* = .{.leaf = .{}};
			for(currentSlice) |biome| {
				self.leaf.totalChance += biome.chance;
			}
			self.leaf.aliasTable = .init(allocator, currentSlice);
			return self;
		}
		var chanceLower: f32 = 0;
		var chanceMiddle: f32 = 0;
		var chanceUpper: f32 = 0;
		for(currentSlice) |*biome| {
			var properties: u32 = @as(u15, @bitCast(biome.properties));
			properties >>= parameterShift;
			properties = properties & 7;
			if(properties == 1) {
				chanceLower += biome.chance;
			} else if(properties == 4) {
				chanceUpper += biome.chance;
			} else {
				chanceMiddle += biome.chance;
			}
		}
		const totalChance = chanceLower + chanceMiddle + chanceUpper;
		chanceLower /= totalChance;
		chanceMiddle /= totalChance;
		chanceUpper /= totalChance;

		self.* = .{
			.branch = .{
				.lowerBorder = terrain.noise.ValueNoise.percentile(chanceLower),
				.upperBorder = terrain.noise.ValueNoise.percentile(chanceLower + chanceMiddle),
				.children = undefined,
			}
		};

		// Partition the slice:
		var lowerIndex: usize = undefined;
		var upperIndex: usize = undefined;
		{
			var lists: [3]main.ListUnmanaged(Biome) = .{
				.initCapacity(main.stackAllocator, currentSlice.len),
				.initCapacity(main.stackAllocator, currentSlice.len),
				.initCapacity(main.stackAllocator, currentSlice.len),
			};
			defer for(lists) |list| {
				list.deinit(main.stackAllocator);
			};
			for(currentSlice) |biome| {
				var properties: u32 = @as(u15, @bitCast(biome.properties));
				properties >>= parameterShift;
				const valueMap = [8]usize{1, 0, 1, 1, 2, 1, 1, 1};
				lists[valueMap[properties & 7]].appendAssumeCapacity(biome);
			}
			lowerIndex = lists[0].items.len;
			@memcpy(currentSlice[0..lowerIndex], lists[0].items);
			upperIndex = lowerIndex + lists[1].items.len;
			@memcpy(currentSlice[lowerIndex..upperIndex], lists[1].items);
			@memcpy(currentSlice[upperIndex..], lists[2].items);
		}

		self.branch.children[0] = TreeNode.init(allocator, currentSlice[0..lowerIndex], parameterShift+3);
		self.branch.children[1] = TreeNode.init(allocator, currentSlice[lowerIndex..upperIndex], parameterShift+3);
		self.branch.children[2] = TreeNode.init(allocator, currentSlice[upperIndex..], parameterShift+3);

		return self;
	}

	pub fn deinit(self: *TreeNode, allocator: NeverFailingAllocator) void {
		switch(self.*) {
			.leaf => |leaf| {
				leaf.aliasTable.deinit(allocator);
			},
			.branch => |branch| {
				for(branch.children) |child| {
					child.deinit(allocator);
				}
			}
		}
		allocator.destroy(self);
	}

	pub fn getBiome(self: *const TreeNode, seed: *u64, x: i32, y: i32, depth: usize) *const Biome {
		switch(self.*) {
			.leaf => |leaf| {
				var biomeSeed = main.random.initSeed2D(seed.*, main.vec.Vec2i{x, y});
				const result = leaf.aliasTable.sample(&biomeSeed);
				return result;
			},
			.branch => |branch| {
				const wavelength = main.server.world.?.chunkManager.terrainGenerationProfile.climateWavelengths[depth];
				const value = terrain.noise.ValueNoise.samplePoint2D(@as(f32, @floatFromInt(x))/wavelength, @as(f32, @floatFromInt(y))/wavelength, main.random.nextInt(u32, seed));
				var index: u2 = 0;
				if(value >= branch.lowerBorder) {
					if(value >= branch.upperBorder) {
						index = 2;
					} else {
						index = 1;
					}
				}
				return branch.children[index].getBiome(seed, x, y, depth + 1);
			}
		}
	}
};

// MARK: init/register
var finishedLoading: bool = false;
var biomes: main.List(Biome) = undefined;
var caveBiomes: main.List(Biome) = undefined;
var biomesById: std.StringHashMap(*Biome) = undefined;
pub var byTypeBiomes: *TreeNode = undefined;

const UnfinishedSubBiomeData = struct {
	biomeId: []const u8,
	chance: f32,
	pub fn getItem(self: UnfinishedSubBiomeData) *const Biome {
		return getById(self.biomeId);
	}
};
var unfinishedSubBiomes: std.StringHashMapUnmanaged(main.ListUnmanaged(UnfinishedSubBiomeData)) = .{};

const UnfinishedTransitionBiomeData = struct {
	biomeId: []const u8,
	chance: f32,
	propertyMask: Biome.GenerationProperties,
	width: u8,
	keepOriginalTerrain: f32,
};
const TransitionBiome = struct {
	biome: *const Biome,
	chance: f32,
	propertyMask: Biome.GenerationProperties,
	width: u8,
	keepOriginalTerrain: f32,
};
var unfinishedTransitionBiomes: std.StringHashMapUnmanaged([]UnfinishedTransitionBiomeData) = .{};

pub fn init() void {
	biomes = .init(main.globalAllocator);
	caveBiomes = .init(main.globalAllocator);
	biomesById = .init(main.globalAllocator.allocator);
	const list = @import("simple_structures/_list.zig");
	inline for(@typeInfo(list).@"struct".decls) |decl| {
		SimpleStructureModel.registerGenerator(@field(list, decl.name));
	}
}

pub fn reset() void {
	SimpleStructureModel.reset();
	finishedLoading = false;
	for(biomes.items) |*biome| {
		biome.deinit();
	}
	for(caveBiomes.items) |*biome| {
		biome.deinit();
	}
	biomes.clearRetainingCapacity();
	caveBiomes.clearRetainingCapacity();
	biomesById.clearRetainingCapacity();
	byTypeBiomes.deinit(main.globalAllocator);
}

pub fn deinit() void {
	for(biomes.items) |*biome| {
		biome.deinit();
	}
	biomes.deinit();
	caveBiomes.deinit();
	biomesById.deinit();
	// TODO? byTypeBiomes.deinit(main.globalAllocator);
	SimpleStructureModel.modelRegistry.clearAndFree(main.globalAllocator.allocator);
}

pub fn register(id: []const u8, paletteId: u32, zon: ZonElement) void {
	std.log.debug("Registered biome: {s}", .{id});
	std.debug.assert(!finishedLoading);
	var biome: Biome = undefined;
	biome.init(id, paletteId, zon);
	if(biome.isCave) {
		caveBiomes.append(biome);
	} else {
		biomes.append(biome);
	}
}

pub fn finishLoading() void {
	std.debug.assert(!finishedLoading);
	finishedLoading = true;
	var nonZeroBiomes: usize = biomes.items.len;
	for(0..biomes.items.len) |_i| {
		const i = biomes.items.len - _i - 1;
		if(biomes.items[i].chance == 0) {
			nonZeroBiomes -= 1;
			const biome = biomes.items[i];
			for(i..nonZeroBiomes) |j| {
				biomes.items[j] = biomes.items[j + 1];
			}
			biomes.items[nonZeroBiomes] = biome;
		}
	}
	byTypeBiomes = TreeNode.init(main.globalAllocator, biomes.items[0..nonZeroBiomes], 0);
	for(biomes.items) |*biome| {
		biomesById.put(biome.id, biome) catch unreachable;
	}
	for(caveBiomes.items) |*biome| {
		biomesById.put(biome.id, biome) catch unreachable;
	}
	var subBiomeIterator = unfinishedSubBiomes.iterator();
	while(subBiomeIterator.next()) |subBiomeData| {
		const subBiomeDataList = subBiomeData.value_ptr;
		defer subBiomeDataList.deinit(main.globalAllocator);
		const parentBiome = biomesById.get(subBiomeData.key_ptr.*) orelse {
			std.log.err("Couldn't find biome with id {s}. Cannot add sub-biomes.", .{subBiomeData.key_ptr.*});
			continue;
		};
		for(subBiomeDataList.items) |item| {
			parentBiome.subBiomeTotalChance += item.chance;
		}
		parentBiome.subBiomes = .initFromContext(main.globalAllocator, subBiomeDataList.items);
	}
	unfinishedSubBiomes.clearAndFree(main.globalAllocator.allocator);

	var transitionBiomeIterator = unfinishedTransitionBiomes.iterator();
	while(transitionBiomeIterator.next()) |transitionBiomeData| {
		const parentBiome = biomesById.get(transitionBiomeData.key_ptr.*) orelse unreachable;
		const transitionBiomes = transitionBiomeData.value_ptr.*;
		parentBiome.transitionBiomes = main.globalAllocator.alloc(TransitionBiome, transitionBiomes.len);
		for(parentBiome.transitionBiomes, transitionBiomes) |*res, src| {
			res.* = .{
				.biome = biomesById.get(src.biomeId) orelse {
					std.log.err("Skipping transition biome with unknown id {s}", .{src.biomeId});
					res.* = .{
						.biome = &biomes.items[0],
						.chance = 0,
						.propertyMask = .{},
						.width = 0,
						.keepOriginalTerrain = 0,
					};
					continue;
				},
				.chance = src.chance,
				.propertyMask = src.propertyMask,
				.width = src.width,
				.keepOriginalTerrain = src.keepOriginalTerrain,
			};
		}
		main.globalAllocator.free(transitionBiomes);
	}
	unfinishedTransitionBiomes.clearAndFree(main.globalAllocator.allocator);
}

pub fn hasRegistered(id: []const u8) bool {
	for(biomes.items) |*biome| {
		if(std.mem.eql(u8, biome.id, id)) {
			return true;
		}
	}
	for(caveBiomes.items) |*biome| {
		if(std.mem.eql(u8, biome.id, id)) {
			return true;
		}
	}
	return false;
}

pub fn getById(id: []const u8) *const Biome {
	std.debug.assert(finishedLoading);
	return biomesById.get(id) orelse {
		std.log.err("Couldn't find biome with id {s}. Replacing it with some other biome.", .{id});
		return &biomes.items[0];
	};
}

pub fn getPlaceholderBiome() *const Biome {
	return &biomes.items[0];
}

pub fn getCaveBiomes() []const Biome {
	return caveBiomes.items;
}

/// A checksum that can be used to check for changes i nthe biomes being used.
pub fn getBiomeCheckSum(seed: u64) u64 {
	var result: u64 = seed;
	for(biomes.items) |*biome| {
		result ^= biome.getCheckSum();
	}
	for(caveBiomes.items) |*biome| {
		result ^= biome.getCheckSum();
	}
	return result;
}