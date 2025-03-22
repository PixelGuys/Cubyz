const std = @import("std");

const main = @import("main.zig");
const terrain = main.server.terrain;
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
const arena_allocator = arena.allocator();

var structureCache: ?std.StringHashMapUnmanaged(StructureBuildingBlock) = null;
var blueprintCache: ?std.StringHashMapUnmanaged([4]*BlueprintEntry) = null;

const BlueprintEntry = struct {
	blueprint: Blueprint,
	info: Info,

	fn init(blueprint: Blueprint, stringId: []const u8) !*BlueprintEntry {
		const self = arena_allocator.create(BlueprintEntry);
		self.* = .{
			.blueprint = blueprint,
			.info = try Info.initFromBlueprint(arena_allocator, blueprint, stringId),
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
	children: Children,
	blueprint: [4]*BlueprintEntry,

	fn initFromZon(stringId: []const u8, zon: ZonElement) !StructureBuildingBlock {
		const blueprintId = zon.get(?[]const u8, "blueprint", null);
		if(blueprintId == null) {
			std.log.err("[{s}] Missing blueprint field.", .{stringId});
			return error.MissingBlueprintIdField;
		}

		const blueprintRef = blueprintCache.?.get(blueprintId.?);
		if(blueprintRef == null) {
			std.log.err("[{s}] Could not find blueprint '{s}'.", .{stringId, blueprintId.?});
			return error.MissingBlueprint;
		}

		return StructureBuildingBlock{
			.children = Children.initFromZon(stringId, zon.getChild("children")),
			.blueprint = blueprintRef.?,
		};
	}
	fn finalize(self: *StructureBuildingBlock) !void {
		try self.children.finalize();
	}
	pub fn getBlueprint(self: StructureBuildingBlock, rotation: Degrees) *BlueprintEntry {
		return self.blueprint[@intFromEnum(rotation)];
	}
};

const Children = struct {
	colors: [20]AliasTable(Child),

	fn initFromZon(stringId: []const u8, zon: ZonElement) Children {
		var self: @This() = .{.colors = undefined};
		for(childBlockStringId, 0..) |colorName, i| {
			self.colors[i] = initChildTableFromZon(colorName, stringId, zon.getChild(colorName));
		}
		return self;
	}
	fn finalize(self: *Children) !void {
		for(self.colors) |color| {
			for(color.items) |*c| try c.finalize();
		}
	}
	pub fn pickChild(self: Children, block: BlueprintEntry.Info.StructureBlock, seed: *u64) Child {
		return self.colors[block.index].sample(seed).*;
	}
};

fn initChildTableFromZon(childName: []const u8, stringId: []const u8, zon: ZonElement) AliasTable(Child) {
	if(zon == .null) return .init(arena_allocator, &[0]Child{});
	if(zon != .array) {
		std.log.err("[{s}->{s}] Incorrect child data structure, array expected.", .{stringId, childName});
		return .init(arena_allocator, &[0]Child{});
	}
	if(zon.array.items.len == 0) {
		std.log.warn("[{s}->{s}] Empty children list.", .{stringId, childName});
		return .init(arena_allocator, &[0]Child{});
	}
	var list = arena_allocator.alloc(Child, zon.array.items.len);
	for(zon.array.items, 0..) |entry, i| {
		list[i] = Child.initFromZon(childName, stringId, i, entry);
	}
	return .init(arena_allocator, list);
}

const Child = struct {
	structureId: []const u8,
	structure: *StructureBuildingBlock,
	chance: f32,

	fn initFromZon(childName: []const u8, stringId: []const u8, i: usize, zon: ZonElement) Child {
		const self = Child{
			.structureId = arena_allocator.dupe(u8, zon.get([]const u8, "structure", "")),
			.structure = undefined,
			.chance = zon.get(f32, "chance", 1.0),
		};
		if(self.structureId.len == 0) {
			std.log.warn("[{s}->{s}->{}] Child node has empty structure field.", .{stringId, childName, i});
		}
		return self;
	}
	fn finalize(self: *Child) !void {
		self.structure = structureCache.?.getPtr(self.structureId) orelse {
			std.log.err("Could not find structure building block with id '{s}'.", .{self.structureId});
			return error.MissingStructure;
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
	structureCache.?.ensureTotalCapacity(arena_allocator.allocator, structures.count()) catch unreachable;
	{
		var iterator = structures.iterator();
		while(iterator.next()) |entry| {
			const value = StructureBuildingBlock.initFromZon(entry.key_ptr.*, entry.value_ptr.*) catch continue;
			const key = arena_allocator.dupe(u8, entry.key_ptr.*);
			const result = structureCache.?.getOrPut(arena_allocator.allocator, key) catch unreachable;

			if(result.found_existing) {
				std.log.err("Ignoring duplicated structure building block: '{s}'", .{entry.key_ptr.*});
				continue;
			}
			result.value_ptr.* = value;
			std.log.debug("Registered structure building block: '{s}'", .{entry.key_ptr.*});
		}
	}
	{
		var failedSBBs = List([]const u8).init(main.stackAllocator);
		var iterator = structureCache.?.iterator();
		while(iterator.next()) |entry| {
			entry.value_ptr.*.finalize() catch |err| {
				std.log.err("Could not finalize structure building block {s}: {s}", .{entry.key_ptr.*, @errorName(err)});
				failedSBBs.append(entry.key_ptr.*);
			};
		}
		// Blueprints which couldn't be finalized should always be an mistake in configuration, hence should not appear in release builds.
		// Therefore those blueprints are not explicitly freed here. They will be freed with the arena, so they will not accumulate.
		for(failedSBBs.items) |sbbId| {
			_ = structureCache.?.remove(sbbId);
		}
	}
	std.log.debug("Registered {} structure building blocks", .{structureCache.?.count()});
}

pub fn registerChildBlock(numericId: u16, stringId: []const u8) void {
	const index: u16 = @intCast(childBlockNumericIdMap.count());
	childBlockNumericIdMap.put(arena_allocator.allocator, numericId, index) catch unreachable;
	// Take only color name from the ID.
	var iterator = std.mem.splitBackwardsScalar(u8, stringId, '/');
	const colorName = iterator.next().?;
	childBlockStringId[index] = arena_allocator.dupe(u8, colorName);
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
	blueprintCache.?.ensureTotalCapacity(arena_allocator.allocator, blueprints.count()) catch unreachable;

	var iterator = blueprints.iterator();
	while(iterator.next()) |entry| {
		const stringId = entry.key_ptr.*;
		const blueprint0 = Blueprint.load(arena_allocator, entry.value_ptr.*) catch |err| {
			std.log.err("Could not load blueprint {s}: {s}", .{stringId, @errorName(err)});
			continue;
		};
		const blueprint90 = blueprint0.rotateZ(arena_allocator, .@"90");
		const blueprint180 = blueprint0.rotateZ(arena_allocator, .@"180");
		const blueprint270 = blueprint0.rotateZ(arena_allocator, .@"270");

		blueprintCache.?.put(
			arena_allocator.allocator,
			arena_allocator.dupe(u8, stringId),
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

	childBlockNumericIdMap.deinit(arena_allocator.allocator);
	childBlockNumericIdMap = .{};
	structureCache = null;
	blueprintCache = null;
}
