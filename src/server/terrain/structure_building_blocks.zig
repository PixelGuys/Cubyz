const std = @import("std");

const main = @import("root");
const ZonElement = main.ZonElement;
const Blueprint = main.blueprint.Blueprint;
const List = main.List;
const AliasTable = main.utils.AliasTable;
const Neighbor = main.chunk.Neighbor;
const Block = main.blocks.Block;
const parseBlock = main.blocks.parseBlock;
const Degrees = main.rotation.Degrees;
const hashInt = main.utils.hashInt;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

var arena = main.heap.NeverFailingArenaAllocator.init(main.globalAllocator);
const arenaAllocator = arena.allocator();

var structureCache: ?std.StringHashMapUnmanaged(StructureBuildingBlock) = null;
var blueprintCache: ?std.StringHashMapUnmanaged([4]*BlueprintEntry) = null;
var childrenToResolve: List(struct {parentId: []const u8, colorName: []const u8, colorIndex: usize, childIndex: usize, structureId: []const u8}) = undefined;

const BlueprintEntry = struct {
	blueprint: Blueprint,
	info: Info,

	fn init(blueprint: Blueprint, stringId: []const u8) !*BlueprintEntry {
		const self = arenaAllocator.create(BlueprintEntry);
		self.* = .{
			.blueprint = blueprint,
			.info = try Info.initFromBlueprint(arenaAllocator, blueprint, stringId),
		};
		return self;
	}

	const Info = struct {
		const StructureBlock = struct {
			x: i32,
			y: i32,
			z: i32,
			index: u32,
			block: Block,

			pub inline fn direction(self: StructureBlock) Neighbor {
				return @enumFromInt(self.block.data);
			}
		};

		originBlock: StructureBlock,
		childrenBlocks: List(StructureBlock),

		fn deinit(self: Info) void {
			self.childrenBlocks.deinit();
		}
		fn initFromBlueprint(allocator: NeverFailingAllocator, blueprint: Blueprint, stringId: ?[]const u8) !Info {
			var info: Info = .{
				.originBlock = undefined,
				.childrenBlocks = List(StructureBlock).init(allocator),
			};
			errdefer info.deinit();

			var hasOrigin = false;

			for(0..blueprint.blocks.width) |x| {
				for(0..blueprint.blocks.depth) |y| {
					for(0..blueprint.blocks.height) |z| {
						const block = blueprint.blocks.get(x, y, z);
						if(isOriginBlock(block)) {
							if(hasOrigin) {
								std.log.err("[{s}] Multiple origin blocks found.", .{stringId orelse ""});
								return error.MultipleOriginBlocks;
							} else {
								info.originBlock = StructureBlock{
									.x = @intCast(x),
									.y = @intCast(y),
									.z = @intCast(z),
									.index = std.math.maxInt(u32),
									.block = block,
								};
								hasOrigin = true;
							}
						} else if(isChildBlock(block)) {
							info.childrenBlocks.append(StructureBlock{
								.x = @intCast(x),
								.y = @intCast(y),
								.z = @intCast(z),
								.index = childBlockNumericIdMap.get(block.typ) orelse return error.ChildBlockNotRecognized,
								.block = block,
							});
						}
					}
				}
			}
			if(!hasOrigin) {
				std.log.err("[{s}] No origin block found.", .{stringId orelse ""});
				return error.NoOriginBlock;
			}
			return info;
		}
	};
};

pub fn isChildBlock(block: Block) bool {
	return childBlockNumericIdMap.contains(block.typ);
}

pub fn isOriginBlock(block: Block) bool {
	return block.typ == originBlockNumericId;
}

const originBlockStringId = "cubyz:sbb/origin";
var originBlockNumericId: u16 = 0;

// Maps global child block numeric ID to index used to locally represent that child block.
var childBlockNumericIdMap: std.AutoHashMapUnmanaged(u16, u16) = .{};
var childBlockStringId: [20][]const u8 = undefined;

pub const StructureBuildingBlock = struct {
	children: [20]AliasTable(Child),
	blueprint: [4]*BlueprintEntry,

	fn initFromZon(stringId: []const u8, zon: ZonElement) !StructureBuildingBlock {
		const blueprintId = zon.get(?[]const u8, "blueprint", null);
		if(blueprintId == null) {
			std.log.err("['{s}'] Missing blueprint field.", .{stringId});
			return error.MissingBlueprintIdField;
		}
		const blueprintRef = blueprintCache.?.get(blueprintId.?);
		if(blueprintRef == null) {
			std.log.err("['{s}'] Could not find blueprint '{s}'.", .{stringId, blueprintId.?});
			return error.MissingBlueprint;
		}
		var self = StructureBuildingBlock{
			.children = undefined,
			.blueprint = blueprintRef.?,
		};
		const childrenZon = zon.getChild("children");
		for(childBlockStringId, 0..) |colorName, colorIndex| {
			self.children[colorIndex] = initChildTableFromZon(stringId, colorName, colorIndex, childrenZon.getChild(colorName));
		}
		return self;
	}
	pub fn getBlueprint(self: StructureBuildingBlock, rotation: Degrees) *BlueprintEntry {
		return self.blueprint[@intFromEnum(rotation)];
	}
	pub fn pickChild(self: StructureBuildingBlock, block: BlueprintEntry.Info.StructureBlock, seed: *u64) Child {
		return self.children[block.index].sample(seed).*;
	}
};

fn initChildTableFromZon(parentId: []const u8, colorName: []const u8, colorIndex: usize, zon: ZonElement) AliasTable(Child) {
	if(zon == .null) return .init(arenaAllocator, &[0]Child{});
	if(zon != .array) {
		std.log.err("['{s}'->'{s}'] Incorrect child data structure, array expected.", .{parentId, colorName});
		return .init(arenaAllocator, &[0]Child{});
	}
	if(zon.array.items.len == 0) {
		std.log.warn("['{s}'->'{s}'] Empty children list.", .{parentId, colorName});
		return .init(arenaAllocator, &[0]Child{});
	}
	var list = arenaAllocator.alloc(Child, zon.array.items.len);
	for(zon.array.items, 0..) |entry, childIndex| {
		list[childIndex] = Child.initFromZon(parentId, colorName, colorIndex, childIndex, entry);
	}
	return .init(arenaAllocator, list);
}

const Child = struct {
	structure: *StructureBuildingBlock,
	chance: f32,

	fn initFromZon(parentId: []const u8, colorName: []const u8, colorIndex: usize, childIndex: usize, zon: ZonElement) Child {
		const structureId = zon.get([]const u8, "structure", "");
		if(structureId.len == 0) {
			std.log.warn("['{s}'->'{s}'->'{d}'] Child node has empty structure field.", .{parentId, colorName, childIndex});
		}
		childrenToResolve.append(.{.parentId = parentId, .colorName = colorName, .colorIndex = colorIndex, .childIndex = childIndex, .structureId = structureId});
		return .{
			.structure = undefined,
			.chance = zon.get(f32, "chance", 1.0),
		};
	}
};

pub fn registerSBB(structures: *std.StringHashMap(ZonElement)) !void {
	if(structureCache != null) {
		std.log.err("Attempting to register new SBBs without resetting cache.", .{});
		return error.AlreadyRegistered;
	}
	std.log.debug("Registering {} structure building blocks", .{structures.count()});
	structureCache = .{};
	structureCache.?.ensureTotalCapacity(arenaAllocator.allocator, structures.count()) catch unreachable;
	childrenToResolve = .init(main.stackAllocator);
	{
		var iterator = structures.iterator();
		while(iterator.next()) |entry| {
			const value = StructureBuildingBlock.initFromZon(entry.key_ptr.*, entry.value_ptr.*) catch continue;
			const key = arenaAllocator.dupe(u8, entry.key_ptr.*);
			const result = structureCache.?.getOrPut(arenaAllocator.allocator, key) catch unreachable;

			if(result.found_existing) {
				std.log.err("Ignoring duplicated structure building block: '{s}'", .{entry.key_ptr.*});
				continue;
			}
			result.value_ptr.* = value;
			std.log.debug("Registered structure building block: '{s}'", .{entry.key_ptr.*});
		}
	}
	{
		for(childrenToResolve.items) |entry| {
			const parent = structureCache.?.getPtr(entry.parentId) orelse {
				std.log.err("Could not find parent structure '{s}' for child resolution.", .{entry.structureId});
				continue;
			};
			const child = structureCache.?.getPtr(entry.structureId) orelse {
				std.log.err("Could not find child structure '{s}' for child resolution.", .{entry.structureId});
				continue;
			};

			std.log.debug("Resolving child structure '{s}'->'{s}'->'{d}' to '{s}'", .{entry.parentId, entry.colorName, entry.childIndex, entry.structureId});
			parent.children[entry.colorIndex].items[entry.childIndex].structure = child;
			continue;
		}
		childrenToResolve.deinit();
	}
	std.log.debug("Registered {} structure building blocks", .{structureCache.?.count()});
}

pub fn registerChildBlock(numericId: u16, stringId: []const u8) void {
	const index: u16 = @intCast(childBlockNumericIdMap.count());
	childBlockNumericIdMap.put(arenaAllocator.allocator, numericId, index) catch unreachable;
	// Take only color name from the ID.
	var iterator = std.mem.splitBackwardsScalar(u8, stringId, '/');
	const colorName = iterator.next().?;
	childBlockStringId[index] = arenaAllocator.dupe(u8, colorName);
	std.log.debug("Child block '{s}' {} ('{s}' {}) ", .{colorName, index, stringId, numericId});
}

pub fn registerBlueprints(blueprints: *std.StringHashMap([]u8)) !void {
	if(blueprintCache != null) {
		std.log.err("Attempting to register new blueprints without resetting cache.", .{});
		return error.AlreadyRegistered;
	}

	originBlockNumericId = parseBlock(originBlockStringId).typ;
	std.log.debug("Origin block numeric id: {}", .{originBlockNumericId});
	std.log.debug("Registering {} blueprints", .{blueprints.count()});

	blueprintCache = .{};
	blueprintCache.?.ensureTotalCapacity(arenaAllocator.allocator, blueprints.count()) catch unreachable;

	var iterator = blueprints.iterator();
	while(iterator.next()) |entry| {
		const stringId = entry.key_ptr.*;
		const blueprint0 = Blueprint.load(arenaAllocator, entry.value_ptr.*) catch |err| {
			std.log.err("Could not load blueprint {s}: {s}", .{stringId, @errorName(err)});
			continue;
		};
		const blueprint90 = blueprint0.rotateZ(arenaAllocator, .@"90");
		const blueprint180 = blueprint0.rotateZ(arenaAllocator, .@"180");
		const blueprint270 = blueprint0.rotateZ(arenaAllocator, .@"270");

		blueprintCache.?.put(
			arenaAllocator.allocator,
			arenaAllocator.dupe(u8, stringId),
			.{
				BlueprintEntry.init(blueprint0, stringId) catch continue,
				BlueprintEntry.init(blueprint90, stringId) catch continue,
				BlueprintEntry.init(blueprint180, stringId) catch continue,
				BlueprintEntry.init(blueprint270, stringId) catch continue,
			},
		) catch unreachable;
		std.log.debug("Registered blueprint: {s}", .{stringId});
	}
	std.log.debug("Registered {} blueprints", .{blueprintCache.?.count()});
}

pub fn getByStringId(stringId: []const u8) ?*StructureBuildingBlock {
	return structureCache.?.getPtr(stringId);
}

pub fn reset() void {
	_ = arena.reset(.free_all);

	childBlockNumericIdMap.deinit(arenaAllocator.allocator);
	childBlockNumericIdMap = .{};
	structureCache = null;
	blueprintCache = null;
}
