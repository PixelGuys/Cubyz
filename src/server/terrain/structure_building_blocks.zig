const std = @import("std");

const main = @import("main");
const Vec3i = main.vec.Vec3i;
const ZonElement = main.ZonElement;
const Blueprint = main.blueprint.Blueprint;
const List = main.List;
const ListUnmanaged = main.ListUnmanaged;
const AliasTable = main.utils.AliasTable;
const Neighbor = main.chunk.Neighbor;
const Block = main.blocks.Block;
const Degrees = main.rotation.Degrees;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const Assets = main.assets.Assets;

var structureList: ListUnmanaged(StructureBuildingBlock) = .{};
var structureMap: std.StringHashMapUnmanaged(StructureIndex) = .{};

var blueprintList: ListUnmanaged([4]BlueprintEntry) = .{};
var blueprintMap: std.StringHashMapUnmanaged(BlueprintIndex) = .{};

var childrenToResolve: List(struct {structureId: []const u8, structure: *?*StructureBuildingBlock}) = undefined;

const originBlockStringId = "cubyz:sbb/origin";
var originBlockNumericId: u16 = 0;

var childBlockNumericIdMap: std.AutoHashMapUnmanaged(GlobalBlockIndex, LocalBlockIndex) = .{};
var childBlockName: ListUnmanaged([]const u8) = .{};
var childBlockNameToLocalIndex: std.StringHashMapUnmanaged(LocalBlockIndex) = .{};

pub const BlueprintIndex = enum(u32) {
	_,

	pub fn fromId(_id: []const u8) ?BlueprintIndex {
		return blueprintMap.get(_id);
	}
	pub fn get(self: BlueprintIndex) [4]BlueprintEntry {
		return blueprintList.items[@intFromEnum(self)];
	}
};

pub const StructureIndex = enum(u32) {
	_,

	pub fn fromId(_id: []const u8) ?StructureIndex {
		return structureMap.get(_id);
	}
	pub fn get(self: StructureIndex) *StructureBuildingBlock {
		return &structureList.items[@intFromEnum(self)];
	}
};

pub const LocalBlockIndex = enum(u16) {
	origin = std.math.maxInt(u16),
	_,

	pub fn name(self: LocalBlockIndex) []const u8 {
		return childBlockName.items[@intFromEnum(self)];
	}
	pub fn fromName(_name: []const u8) ?LocalBlockIndex {
		return childBlockNameToLocalIndex.get(_name) orelse return null;
	}
};
pub const GlobalBlockIndex = u16;

const Blueprints = struct {
	items: ?[4]BlueprintEntry,
	chance: f32,
};

const BlueprintEntry = struct {
	blueprint: Blueprint,
	originBlock: StructureBlock,
	childBlocks: []StructureBlock,

	const StructureBlock = struct {
		x: u16,
		y: u16,
		z: u16,
		index: LocalBlockIndex,
		data: u16,

		pub inline fn direction(self: StructureBlock) Neighbor {
			return @enumFromInt(self.data);
		}

		pub inline fn pos(self: StructureBlock) Vec3i {
			return Vec3i{self.x, self.y, self.z};
		}

		pub fn id(self: StructureBlock) []const u8 {
			return self.index.name();
		}
	};

	fn init(blueprint: Blueprint, stringId: []const u8) !BlueprintEntry {
		var self: BlueprintEntry = .{
			.blueprint = blueprint,
			.originBlock = undefined,
			.childBlocks = undefined,
		};

		var hasOrigin = false;
		var childBlocks: ListUnmanaged(StructureBlock) = .{};
		defer childBlocks.deinit(main.stackAllocator);

		for(0..blueprint.blocks.width) |x| {
			for(0..blueprint.blocks.depth) |y| {
				for(0..blueprint.blocks.height) |z| {
					const block = blueprint.blocks.get(x, y, z);
					if(isOriginBlock(block)) {
						if(hasOrigin) {
							std.log.err("[{s}] Multiple origin blocks found.", .{stringId});
							return error.MultipleOriginBlocks;
						} else {
							self.originBlock = StructureBlock{
								.x = @intCast(x),
								.y = @intCast(y),
								.z = @intCast(z),
								.index = LocalBlockIndex.origin,
								.data = block.data,
							};
							hasOrigin = true;
							self.blueprint.blocks.set(x, y, z, main.blueprint.getVoidBlock());
						}
					} else if(isChildBlock(block)) {
						const childBlockLocalId = childBlockNumericIdMap.get(block.typ) orelse return error.ChildBlockNotRecognized;
						childBlocks.append(main.stackAllocator, .{
							.x = @intCast(x),
							.y = @intCast(y),
							.z = @intCast(z),
							.index = childBlockLocalId,
							.data = block.data,
						});
						self.blueprint.blocks.set(x, y, z, main.blueprint.getVoidBlock());
					}
				}
			}
		}
		if(!hasOrigin) {
			std.log.err("[{s}] No origin block found.", .{stringId});
			return error.NoOriginBlock;
		}
		self.childBlocks = main.worldArena.dupe(StructureBlock, childBlocks.items);

		return self;
	}
};

pub fn isChildBlock(block: Block) bool {
	return childBlockNumericIdMap.contains(block.typ);
}

pub fn isOriginBlock(block: Block) bool {
	return block.typ == originBlockNumericId;
}

pub const RotationMode = enum {
	fixed,
	random,
	inherit,
};

pub const Rotation = union(RotationMode) {
	fixed: FixedRotation,
	random: void,
	inherit: void,

	pub const FixedRotation = enum(u2) {
		@"0" = 0,
		@"90" = 1,
		@"180" = 2,
		@"270" = 3,
	};

	pub fn apply(self: Rotation, rotation: FixedRotation) FixedRotation {
		return switch(self) {
			.fixed => |fixed| @enumFromInt(@intFromEnum(rotation) +% @intFromEnum(fixed)),
			.random, .inherit => rotation,
		};
	}
	pub fn getInitialRotation(self: Rotation, seed: *u64) Rotation {
		return switch(self) {
			.fixed => self,
			.random => sampleRandom(seed),
			.inherit => .{.fixed = .@"0"},
		};
	}
	fn sampleRandom(seed: *u64) Rotation {
		return .{.fixed = @enumFromInt(main.random.nextInt(u2, seed))};
	}
	pub fn getChildRotation(self: Rotation, seed: *u64, child: Rotation, direction: Neighbor) Rotation {
		return switch(direction) {
			.dirDown, .dirUp => switch(child) {
				.random => sampleRandom(seed),
				.inherit => self,
				else => |r| r,
			},
			else => .{.fixed = .@"0"},
		};
	}
	pub fn fromZon(zon: ZonElement) error{UnknownString, UnknownType}!Rotation {
		return switch(zon) {
			.string, .stringOwned => |str| {
				if(std.meta.stringToEnum(FixedRotation, str)) |r| {
					return .{.fixed = r};
				}
				if(std.meta.stringToEnum(RotationMode, str)) |mode| {
					return switch(mode) {
						.fixed => .{.fixed = .@"0"},
						.random => .{.random = {}},
						.inherit => .{.inherit = {}},
					};
				}
				return error.UnknownString;
			},
			.int => |value| .{.fixed = @enumFromInt(@abs(@divTrunc(value, 90))%4)},
			.float => |value| .{.fixed = @enumFromInt(@abs(@as(u64, @intFromFloat(value/90.0)))%4)},
			.null => Rotation.random,
			else => return error.UnknownType,
		};
	}
};

pub const StructureBuildingBlock = struct {
	id: []const u8,
	children: []?*StructureBuildingBlock,
	blueprints: AliasTable(Blueprints),
	rotation: Rotation,

	fn initFromZon(stringId: []const u8, zon: ZonElement) !StructureBuildingBlock {
		const zonBlueprintsList = zon.getChild("blueprints");
		if(zonBlueprintsList == .null) {
			std.log.err("['{s}'] Missing 'blueprints' field.", .{stringId});
			return error.MissingBlueprintsField;
		}
		if(zonBlueprintsList != .array) {
			std.log.err("['{s}'] 'blueprints' field must contain a list.", .{stringId});
			return error.InvalidType;
		}
		if(zonBlueprintsList.array.items.len == 0) {
			std.log.err("['{s}'] Empty 'blueprints' list not allowed.", .{stringId});
			return error.EmptyBlueprintsList;
		}
		const blueprintArray = main.worldArena.alloc(Blueprints, zonBlueprintsList.array.items.len);
		for(zonBlueprintsList.array.items, 0..) |zonBlueprintConfig, index| {
			if(zonBlueprintConfig != .object) {
				std.log.err("['{s}'->'{}'] Invalid blueprint configuration (object expected, got {s}).", .{stringId, index, @tagName(zonBlueprintConfig)});
				return error.InvalidBlueprintConfig;
			}
			const chance = zonBlueprintConfig.get(f32, "chance", 1.0);

			if(!zonBlueprintConfig.object.contains("id")) {
				std.log.err("['{s}'] Blueprint configuration ({}): Missing 'id' field. Use null for empty entry.", .{stringId, index});
				blueprintArray[index] = Blueprints{.items = null, .chance = chance};
				continue;
			}
			switch(zonBlueprintConfig.getChild("id")) {
				.string, .stringOwned => |_id| {
					const blueprints = BlueprintIndex.fromId(_id) orelse {
						std.log.err("['{s}'] Could not find blueprint '{s}'.", .{stringId, _id});
						return error.MissingBlueprint;
					};
					blueprintArray[index] = Blueprints{.items = blueprints.get(), .chance = chance};
				},
				.null => blueprintArray[index] = Blueprints{.items = null, .chance = chance},
				else => |e| std.log.err("['{s}'] Blueprint entry must be an object, found {s}.", .{stringId, @tagName(e)}),
			}
		}

		const rotationParam = zon.getChild("rotation");
		const rotation = Rotation.fromZon(rotationParam) catch |err| blk: {
			switch(err) {
				error.UnknownString => std.log.err("['{s}'] specified unknown rotation '{s}'", .{stringId, rotationParam.as([]const u8, "")}),
				error.UnknownType => std.log.err("['{s}'] unsupported type of rotation field '{s}'", .{stringId, @tagName(rotationParam)}),
			}
			break :blk .inherit;
		};

		const self = StructureBuildingBlock{
			.id = stringId,
			.children = main.worldArena.alloc(?*StructureBuildingBlock, childBlockName.items.len),
			.blueprints = .init(main.worldArena, blueprintArray),
			.rotation = rotation,
		};
		@memset(self.children, null);

		const zonChildrenDict = zon.getChild("children");
		switch(zonChildrenDict) {
			.null => {},
			.object => {
				var childrenDictIterator = zonChildrenDict.object.iterator();
				while(childrenDictIterator.next()) |entry| {
					if(LocalBlockIndex.fromName(entry.key_ptr.*)) |localIndex| {
						switch(entry.value_ptr.*) {
							.string, .stringOwned => |_id| childrenToResolve.append(.{.structureId = _id, .structure = &self.children[@intFromEnum(localIndex)]}),
							.null => std.log.err("['{s}'] Child '{s}' ID can not be null. Leave child key undefined if it is not used by blueprints.", .{stringId, localIndex.name()}),
							else => |e| std.log.err("['{s}'->'{s}'] Value has to be a string ID of one of the structures, found {s}.", .{stringId, localIndex.name(), @tagName(e)}),
						}
					} else {
						std.log.err("['{s}'] Unexpected configuration key '{s}'", .{stringId, entry.key_ptr.*});
						continue;
					}
				}
			},
			else => |e| std.log.err("['{s}'] Children configuration must be an object, found {s}.", .{stringId, @tagName(e)}),
		}
		return self;
	}
	pub fn postResolutionChecks(self: StructureBuildingBlock) void {
		// Collect all unique child blocks used in blueprints of this SBB.
		var childBlocksInBlueprints: ListUnmanaged(LocalBlockIndex) = .{};
		defer childBlocksInBlueprints.deinit(main.stackAllocator);

		for(self.blueprints.items, 0..) |blueprints, blueprintIndex| {
			if(blueprints.items == null) continue;

			for(blueprints.items.?[0].childBlocks) |child| {
				if(std.mem.containsAtLeastScalar(LocalBlockIndex, childBlocksInBlueprints.items, 1, child.index)) continue;
				childBlocksInBlueprints.append(main.stackAllocator, child.index);
				// Check that all child blocks present in any of the blueprints have corresponding configurations.
				if(self.children[@intFromEnum(child.index)] != null) continue;
				std.log.err("['{s}'] Blueprint ({}) requires child block {s} but no configuration was specified for it.", .{self.id, blueprintIndex, child.id()});
			}
		}
		// Check that all configured child blocks are used somewhere in one of the blueprints.
		for(self.children, 0..) |child, childBlockIndex| {
			if(child == null) continue;
			if(std.mem.containsAtLeastScalar(LocalBlockIndex, childBlocksInBlueprints.items, 1, @enumFromInt(childBlockIndex))) continue;
			std.log.err("['{s}'] None of the blueprints contains a child '{s}' but configuration for it was specified.", .{self.id, @as(LocalBlockIndex, @enumFromInt(childBlockIndex)).name()});
		}
	}
	pub fn getBlueprints(self: StructureBuildingBlock, seed: *u64) *?[4]BlueprintEntry {
		return &self.blueprints.sample(seed).items;
	}
	pub fn getChildStructure(self: StructureBuildingBlock, block: BlueprintEntry.StructureBlock) ?*const StructureBuildingBlock {
		return self.children[@intFromEnum(block.index)];
	}
};

pub fn registerSBB(structures: *Assets.ZonHashMap) !void {
	std.debug.assert(structureList.items.len == 0);
	std.debug.assert(structureMap.capacity() == 0);

	structureList.ensureCapacity(main.worldArena, structures.count());
	structureMap.ensureTotalCapacity(main.worldArena.allocator, structures.count()) catch unreachable;

	childrenToResolve = .init(main.stackAllocator);
	defer childrenToResolve.deinit();
	{
		var iterator = structures.iterator();
		var loadedCount: u32 = 0;
		while(iterator.next()) |entry| {
			structureList.appendAssumeCapacity(StructureBuildingBlock.initFromZon(entry.key_ptr.*, entry.value_ptr.*) catch |err| {
				std.log.err("Could not register structure building block '{s}' ({s})", .{entry.key_ptr.*, @errorName(err)});
				continue;
			});

			const key = main.worldArena.dupe(u8, entry.key_ptr.*);
			structureMap.put(main.worldArena.allocator, key, @enumFromInt(loadedCount)) catch unreachable;

			std.log.debug("Registered structure building block: '{s}'", .{entry.key_ptr.*});
			loadedCount += 1;
		}
	}
	{
		for(childrenToResolve.items) |entry| {
			const childStructure = StructureIndex.fromId(entry.structureId) orelse {
				std.log.err("Could not find child structure '{s}' for child resolution.", .{entry.structureId});
				continue;
			};
			entry.structure.* = childStructure.get();
		}
	}
	for(structureList.items) |sbb| sbb.postResolutionChecks();
}

pub fn registerChildBlock(numericId: u16, stringId: []const u8) void {
	std.debug.assert(numericId != 0);

	const index: u16 = @intCast(childBlockNumericIdMap.count());
	childBlockNumericIdMap.put(main.worldArena.allocator, numericId, @enumFromInt(index)) catch unreachable;
	// Take only color name from the ID.
	var iterator = std.mem.splitBackwardsScalar(u8, stringId, '/');
	const colorName = iterator.first();
	const colorNameDupe = main.worldArena.dupe(u8, colorName);
	childBlockName.append(main.worldArena, colorNameDupe);

	childBlockNameToLocalIndex.put(main.worldArena.allocator, colorNameDupe, @enumFromInt(index)) catch unreachable;
}

pub fn registerBlueprints(blueprints: *Assets.BytesHashMap) !void {
	std.debug.assert(blueprintList.items.len == 0);
	std.debug.assert(blueprintMap.capacity() == 0);

	blueprintList.resize(main.worldArena, blueprints.count());
	blueprintMap.ensureTotalCapacity(main.worldArena.allocator, blueprints.count()) catch unreachable;

	originBlockNumericId = main.blocks.parseBlock(originBlockStringId).typ;
	std.debug.assert(originBlockNumericId != 0);

	var iterator = blueprints.iterator();
	var index: u32 = 0;
	while(iterator.next()) |entry| {
		defer index += 1;

		const stringId = entry.key_ptr.*;

		// Rotated copies need to be made before initializing BlueprintEntry as to removes origin and child blocks.
		const blueprint0 = Blueprint.load(main.worldArena, entry.value_ptr.*) catch |err| {
			std.log.err("Could not load blueprint '{s}' ({s})", .{stringId, @errorName(err)});
			continue;
		};
		const blueprint90 = blueprint0.rotateZ(main.worldArena, .@"90");
		const blueprint180 = blueprint0.rotateZ(main.worldArena, .@"180");
		const blueprint270 = blueprint0.rotateZ(main.worldArena, .@"270");

		blueprintList.items[index][0] = BlueprintEntry.init(blueprint0, stringId) catch continue;
		blueprintList.items[index][1] = BlueprintEntry.init(blueprint90, stringId) catch continue;
		blueprintList.items[index][2] = BlueprintEntry.init(blueprint180, stringId) catch continue;
		blueprintList.items[index][3] = BlueprintEntry.init(blueprint270, stringId) catch continue;

		blueprintMap.put(main.worldArena.allocator, main.worldArena.dupe(u8, stringId), @enumFromInt(index)) catch unreachable;
		std.log.debug("Registered blueprint: '{s}'", .{stringId});
	}
}

pub fn getByStringId(stringId: []const u8) ?*StructureBuildingBlock {
	if(structureMap.get(stringId)) |index| return index.get();
	return null;
}

pub fn reset() void {
	childBlockNumericIdMap = .{};
	childBlockName = .{};
	childBlockNameToLocalIndex = .{};

	structureList = .{};
	structureMap = .{};

	blueprintList = .{};
	blueprintMap = .{};
}
