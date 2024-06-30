const std = @import("std");

const main = @import("root");
const blocks = main.blocks;
const ServerChunk = main.chunk.ServerChunk;
const JsonElement = main.JsonElement;
const terrain = main.server.terrain;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;
const vec = @import("main.vec");
const Vec3f = main.vec.Vec3f;
const Vec3d = main.vec.Vec3d;

const StructureModel = struct {
	const VTable = struct {
		loadModel: *const fn(arenaAllocator: NeverFailingAllocator, parameters: JsonElement) *anyopaque,
		generate: *const fn(self: *anyopaque, x: i32, y: i32, z: i32, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView, seed: *u64) void,
		hashFunction: *const fn(self: *anyopaque) u64,
	};

	vtable: VTable,
	data: *anyopaque,
	chance: f32,

	pub fn initModel(parameters: JsonElement) ?StructureModel {
		const id = parameters.get([]const u8, "id", "");
		const vtable = modelRegistry.get(id) orelse {
			std.log.err("Couldn't find structure model with id {s}", .{id});
			return null;
		};
		return StructureModel {
			.vtable = vtable,
			.data = vtable.loadModel(arena.allocator(), parameters),
			.chance = parameters.get(f32, "chance", 0.5),
		};
	}

	pub fn generate(self: StructureModel, x: i32, y: i32, z: i32, chunk: *ServerChunk, caveMap: terrain.CaveMap.CaveMapView, seed: *u64) void {
		self.vtable.generate(self.data, x, y, z, chunk, caveMap, seed);
	}


	var modelRegistry: std.StringHashMapUnmanaged(VTable) = .{};
	var arena: main.utils.NeverFailingArenaAllocator = main.utils.NeverFailingArenaAllocator.init(main.globalAllocator);

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
		modelRegistry.put(main.globalAllocator.allocator, Generator.id, self) catch unreachable;
	}

	fn getHash(self: StructureModel) u64 {
		return self.vtable.hashFunction(self.data);
	}
};

const Stripe = struct {
	direction: ?Vec3d,
	block: u16,
	minDistance: f64,
	maxDistance: f64,
	minOffset: f64,
	maxOffset: f64,
	minWidth: f64,
	maxWidth: f64,

	pub fn init(parameters: JsonElement) Stripe {
		var dir: ?Vec3d = parameters.get(?Vec3d, "direction", null);
		if(dir != null) {
			dir = main.vec.normalize(dir.?);
		}

		const block: u16 = blocks.getByID(parameters.get([]const u8, "block", ""));
		
		var minDistance: f64 = 0;
		var maxDistance: f64 = 0;
		if (parameters.JsonObject.get("distance")) |dist| {
			minDistance = dist.as(f64, 0);
			maxDistance = dist.as(f64, 0);
		} else {
			minDistance = parameters.get(f64, "minDistance", 0);
			maxDistance = parameters.get(f64, "maxDistance", 0);
		}

		var minOffset: f64 = 0;
		var maxOffset: f64 = 0;
		if (parameters.JsonObject.get("offset")) |off| {
			minOffset = off.as(f64, 0);
			maxOffset = off.as(f64, 0);
		} else {
			minOffset = parameters.get(f64, "minOffset", 0);
			maxOffset = parameters.get(f64, "maxOffset", 0);
		}

		var minWidth: f64 = 0;
		var maxWidth: f64 = 0;
		if (parameters.JsonObject.get("width")) |width| {
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
		.Bool => @intFromBool(input),
		.Enum => @intFromEnum(input),
		.Int, .Float => @as(std.meta.Int(.unsigned, @bitSizeOf(T)), @bitCast(input)),
		.Struct => blk: {
			if(@hasDecl(T, "getHash")) {
				break :blk input.getHash();
			}
			var result: u64 = 0;
			inline for(@typeInfo(T).Struct.fields) |field| {
				result ^= hashGeneric(@field(input, field.name))*%hashGeneric(@as([]const u8, field.name));
			}
			break :blk result;
		},
		.Optional => if(input) |_input| hashGeneric(_input) else 0,
		.Pointer => switch(@typeInfo(T).Pointer.size) {
			.One => blk: {
				if(@typeInfo(@typeInfo(T).Pointer.child) == .Fn) break :blk 0;
				if(@typeInfo(T).Pointer.child == anyopaque) break :blk 0;
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
		.Array => blk: {
			var result: u64 = 0;
			for(input) |val| {
				result = result*%33 +% hashGeneric(val);
			}
			break :blk result;
		},
		.Vector => blk: {
			var result: u64 = 0;
			inline for(0..@typeInfo(T).Vector.len) |i| {
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
pub const Biome = struct {
	const GenerationProperties = packed struct(u8) {
		// pairs of opposite properties. In-between values are allowed.
		hot: bool = false,
		cold: bool = false,

		inland: bool = false,
		ocean: bool = false,

		wet: bool = false,
		dry: bool = false,

		mountain: bool = false,
		antiMountain: bool = false, //???

		pub fn fromJson(json: JsonElement) GenerationProperties {
			var result: GenerationProperties = .{};
			for(json.toSlice()) |child| {
				const property = child.as([]const u8, "");
				inline for(@typeInfo(GenerationProperties).Struct.fields) |field| {
					if(std.mem.eql(u8, field.name, property)) {
						@field(result, field.name) = true;
					}
				}
			}
			return result;
		}
	};

	properties: GenerationProperties,
	isCave: bool,
	radius: f32,
	minHeight: i32,
	maxHeight: i32,
	interpolation: Interpolation,
	roughness: f32,
	hills: f32,
	mountains: f32,
	caves: f32,
	crystals: u32,
	stalagmites: u32,
	stalagmiteBlock: u16,
	stoneBlockType: u16,
	fogDensity: f32,
	fogColor: Vec3f,
	id: []const u8,
	paletteId: u32,
	structure: BlockStructure = undefined,
	/// Whether the starting point of a river can be in this biome. If false rivers will be able to flow through this biome anyways.
	supportsRivers: bool, // TODO: Reimplement rivers.
	/// The first members in this array will get prioritized.
	vegetationModels: []StructureModel = &.{},
	stripes: []Stripe = &.{},
	subBiomes: main.utils.AliasTable(*const Biome) = .{.items = &.{}, .aliasData = &.{}},
	maxSubBiomeCount: f32,
	subBiomeTotalChance: f32 = 0,
	preferredMusic: []const u8, // TODO: Support multiple possibilities that are chosen based on time and danger.
	isValidPlayerSpawn: bool,
	chance: f32,

	pub fn init(self: *Biome, id: []const u8, paletteId: u32, json: JsonElement) void {
		self.* = Biome {
			.id = main.globalAllocator.dupe(u8, id),
			.paletteId = paletteId,
			.properties = GenerationProperties.fromJson(json.getChild("properties")),
			.isCave = json.get(bool, "isCave", false),
			.radius = json.get(f32, "radius", 256),
			.stoneBlockType = blocks.getByID(json.get([]const u8, "stoneBlock", "cubyz:stone")),
			.fogColor = u32ToVec3(json.get(u32, "fogColor", 0xffccccff)),
			.fogDensity = json.get(f32, "fogDensity", 1.0)/15.0/128.0,
			.roughness = json.get(f32, "roughness", 0),
			.hills = json.get(f32, "hills", 0),
			.mountains = json.get(f32, "mountains", 0),
			.interpolation = std.meta.stringToEnum(Interpolation, json.get([]const u8, "interpolation", "square")) orelse .square,
			.caves = json.get(f32, "caves", -0.375),
			.crystals = json.get(u32, "crystals", 0),
			.stalagmites = json.get(u32, "stalagmites", 0),
			.stalagmiteBlock = blocks.getByID(json.get([]const u8, "stalagmiteBlock", "cubyz:limestone")),
			.minHeight = json.get(i32, "minHeight", std.math.minInt(i32)),
			.maxHeight = json.get(i32, "maxHeight", std.math.maxInt(i32)),
			.supportsRivers = json.get(bool, "rivers", false),
			.preferredMusic = main.globalAllocator.dupe(u8, json.get([]const u8, "music", "")),
			.isValidPlayerSpawn = json.get(bool, "validPlayerSpawn", false),
			.chance = json.get(f32, "chance", if(json == .JsonNull) 0 else 1),
			.maxSubBiomeCount = json.get(f32, "maxSubBiomeCount", std.math.floatMax(f32)),
		};
		if(self.minHeight > self.maxHeight) {
			std.log.warn("Biome {s} has invalid height range ({}, {})", .{self.id, self.minHeight, self.maxHeight});
		}
		const parentBiomeList = json.getChild("parentBiomes");
		for(parentBiomeList.toSlice()) |parent| {
			const result = unfinishedSubBiomes.getOrPutValue(main.globalAllocator.allocator, parent.get([]const u8, "id", ""), .{}) catch unreachable;
			result.value_ptr.append(main.globalAllocator, .{.biomeId = self.id, .chance = parent.get(f32, "chance", 1)});
		}

		self.structure = BlockStructure.init(main.globalAllocator, json.getChild("ground_structure"));
		
		const structures = json.getChild("structures");
		var vegetation = main.ListUnmanaged(StructureModel){};
		defer vegetation.deinit(main.stackAllocator);
		for(structures.toSlice()) |elem| {
			if(StructureModel.initModel(elem)) |model| {
				vegetation.append(main.stackAllocator, model);
			}
		}
		self.vegetationModels = main.globalAllocator.dupe(StructureModel, vegetation.items);

		const stripes = json.getChild("stripes");
		self.stripes = main.globalAllocator.alloc(Stripe, stripes.toSlice().len);
		for (stripes.toSlice(), 0..) |elem, i| {
			self.stripes[i] = Stripe.init(elem);
		}
	}

	pub fn deinit(self: *Biome) void {
		self.subBiomes.deinit(main.globalAllocator);
		self.structure.deinit(main.globalAllocator);
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
pub const BlockStructure = struct {
	pub const BlockStack = struct {
		blockType: u16 = 0,
		min: u31 = 0,
		max: u31 = 0,

		fn init(self: *BlockStack, string: []const u8) !void {
			var tokenIt = std.mem.tokenize(u8, string, &std.ascii.whitespace);
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
			self.blockType = blocks.getByID(blockId);
		}
	};
	structure: []BlockStack,

	pub fn init(allocator: NeverFailingAllocator, jsonArray: JsonElement) BlockStructure {
		const blockStackDescriptions = jsonArray.toSlice();
		const self = BlockStructure {
			.structure = allocator.alloc(BlockStack, blockStackDescriptions.len),
		};
		for(blockStackDescriptions, self.structure) |jsonString, *blockStack| {
			blockStack.init(jsonString.as([]const u8, "That's not a json string.")) catch |err| {
				std.log.warn("Couldn't parse blockStack '{s}': {s} Removing it.", .{jsonString.as([]const u8, "(not a json string)"), @errorName(err)});
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
				const block = blocks.Block{.typ = blockStack.blockType, .data = 0};
				// TODO: block = block.mode().getNaturalStandard(block);
				if(chunk.liesInChunk(x, y, depth)) {
					chunk.updateBlockInGeneration(x, y, depth, block);
				}
				depth -%= chunk.super.pos.voxelSize;
				if(depth -% minDepth <= 0)
					return depth +% chunk.super.pos.voxelSize;
			}
		}
		return depth +% chunk.super.pos.voxelSize;
	}
};

pub const TreeNode = union(enum) {
	leaf: struct {
		totalChance: f64 = 0,
		aliasTable: main.utils.AliasTable(Biome) = undefined,
	},
	branch: struct {
		amplitude: f32,
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
			self.leaf.aliasTable = main.utils.AliasTable(Biome).init(allocator, currentSlice);
			return self;
		}
		var chanceLower: f32 = 0;
		var chanceMiddle: f32 = 0;
		var chanceUpper: f32 = 0;
		for(currentSlice) |*biome| {
			var properties: u32 = @as(u8, @bitCast(biome.properties));
			properties >>= parameterShift;
			properties = properties & 3;
			if(properties == 0) {
				chanceMiddle += biome.chance;
			} else if(properties == 1) {
				chanceLower += biome.chance;
			} else if(properties == 2) {
				chanceUpper += biome.chance;
			} else unreachable;
		}
		const totalChance = chanceLower + chanceMiddle + chanceUpper;
		chanceLower /= totalChance;
		chanceMiddle /= totalChance;
		chanceUpper /= totalChance;

		self.* = .{
			.branch = .{
				.amplitude = 1024, // TODO!
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
				main.ListUnmanaged(Biome).initCapacity(main.stackAllocator, currentSlice.len),
				main.ListUnmanaged(Biome).initCapacity(main.stackAllocator, currentSlice.len),
				main.ListUnmanaged(Biome).initCapacity(main.stackAllocator, currentSlice.len),
			};
			defer for(lists) |list| {
				list.deinit(main.stackAllocator);
			};
			for(currentSlice) |biome| {
				var properties: u32 = @as(u8, @bitCast(biome.properties));
				properties >>= parameterShift;
				const valueMap = [_]usize{1, 0, 2, 1};
				lists[valueMap[properties & 3]].appendAssumeCapacity(biome);
			}
			lowerIndex = lists[0].items.len;
			@memcpy(currentSlice[0..lowerIndex], lists[0].items);
			upperIndex = lowerIndex + lists[1].items.len;
			@memcpy(currentSlice[lowerIndex..upperIndex], lists[1].items);
			@memcpy(currentSlice[upperIndex..], lists[2].items);
		}

		self.branch.children[0] = TreeNode.init(allocator, currentSlice[0..lowerIndex], parameterShift+2);
		self.branch.children[1] = TreeNode.init(allocator, currentSlice[lowerIndex..upperIndex], parameterShift+2);
		self.branch.children[2] = TreeNode.init(allocator, currentSlice[upperIndex..], parameterShift+2);

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

	pub fn getBiome(self: *const TreeNode, seed: *u64, x: i32, y: i32) *const Biome {
		switch(self.*) {
			.leaf => |leaf| {
				var biomeSeed = main.random.initSeed2D(seed.*, main.vec.Vec2i{x, y});
				const result = leaf.aliasTable.sample(&biomeSeed);
				return result;
			},
			.branch => |branch| {
				const value = terrain.noise.ValueNoise.samplePoint2D(@as(f32, @floatFromInt(x))/branch.amplitude, @as(f32, @floatFromInt(y))/branch.amplitude, main.random.nextInt(u32, seed));
				var index: u2 = 0;
				if(value >= branch.lowerBorder) {
					if(value >= branch.upperBorder) {
						index = 2;
					} else {
						index = 1;
					}
				}
				return branch.children[index].getBiome(seed, x, y);
			}
		}
	}
};

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

pub fn init() void {
	biomes = main.List(Biome).init(main.globalAllocator);
	caveBiomes = main.List(Biome).init(main.globalAllocator);
	biomesById = std.StringHashMap(*Biome).init(main.globalAllocator.allocator);
	const list = @import("structures/_list.zig");
	inline for(@typeInfo(list).Struct.decls) |decl| {
		StructureModel.registerGenerator(@field(list, decl.name));
	}
}

pub fn reset() void {
	StructureModel.reset();
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
	StructureModel.modelRegistry.clearAndFree(main.globalAllocator.allocator);
}

pub fn register(id: []const u8, paletteId: u32, json: JsonElement) void {
	std.log.debug("Registered biome: {s}", .{id});
	std.debug.assert(!finishedLoading);
	var biome: Biome = undefined;
	biome.init(id, paletteId, json);
	if(biome.isCave) {
		caveBiomes.append(biome);
	} else {
		biomes.append(biome);
	}
}

pub fn finishLoading() void {
	std.debug.assert(!finishedLoading);
	finishedLoading = true;
	byTypeBiomes = TreeNode.init(main.globalAllocator, biomes.items, 0);
	for(biomes.items) |*biome| {
		biomesById.put(biome.id, biome) catch unreachable;
	}
	for(caveBiomes.items) |*biome| {
		biomesById.put(biome.id, biome) catch unreachable;
	}
	var subBiomeIterator = unfinishedSubBiomes.iterator();
	while(subBiomeIterator.next()) |subBiomeData| {
		const parentBiome = biomesById.get(subBiomeData.key_ptr.*) orelse {
			std.log.warn("Couldn't find biome with id {s}. Cannot add sub-biomes.", .{subBiomeData.key_ptr.*});
			continue;
		};
		const subBiomeDataList = subBiomeData.value_ptr;
		for(subBiomeDataList.items) |item| {
			parentBiome.subBiomeTotalChance += item.chance;
		}
		parentBiome.subBiomes = main.utils.AliasTable(*const Biome).initFromContext(main.globalAllocator, subBiomeDataList.items);
		subBiomeDataList.deinit(main.globalAllocator);
	}
	unfinishedSubBiomes.clearAndFree(main.globalAllocator.allocator);
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
		std.log.warn("Couldn't find biome with id {s}. Replacing it with some other biome.", .{id});
		return &biomes.items[0];
	};
}

pub fn getRandomly(typ: Biome.Type, seed: *u64) *const Biome {
	return byTypeBiomes[@intFromEnum(typ)].getRandomly(seed);
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