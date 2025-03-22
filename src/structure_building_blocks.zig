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
									.block = block,
								};
								hasOrigin = true;
							}
						} else if(isChildBlock(block)) {
							info.childrenBlocks.append(StructureBlock{
								.x = @intCast(x),
								.y = @intCast(y),
								.z = @intCast(z),
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
	for(childrenBlockNumericId) |numericId| {
		if(block.typ == numericId) return true;
	}
	return false;
}

pub fn isOriginBlock(block: Block) bool {
	return block.typ == originBlockNumericId;
}

const originBlockStringId = "cubyz:sbb/origin";
var originBlockNumericId: u16 = 0;

const maxRotationCacheSize: usize = 1024;

const childrenBlockStringId = [_][]const u8{
	"cubyz:sbb/child/aqua",
	"cubyz:sbb/child/black",
	"cubyz:sbb/child/blue",
	"cubyz:sbb/child/brown",
	"cubyz:sbb/child/crimson",
	"cubyz:sbb/child/cyan",
	"cubyz:sbb/child/dark_grey",
	"cubyz:sbb/child/green",
	"cubyz:sbb/child/grey",
	"cubyz:sbb/child/indigo",
	"cubyz:sbb/child/lime",
	"cubyz:sbb/child/magenta",
	"cubyz:sbb/child/orange",
	"cubyz:sbb/child/pink",
	"cubyz:sbb/child/purple",
	"cubyz:sbb/child/red",
	"cubyz:sbb/child/violet",
	"cubyz:sbb/child/viridian",
	"cubyz:sbb/child/white",
	"cubyz:sbb/child/yellow",
};
var childrenBlockNumericId = [_]u16{
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
};

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
	colors: std.AutoHashMapUnmanaged(u16, ?AliasTable(Child)),

	fn initFromZon(stringId: []const u8, zon: ZonElement) Children {
		var self: @This() = .{.colors = .{}};

		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[0], initChildTableFromZon("aqua", stringId, zon.getChild("aqua"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[1], initChildTableFromZon("black", stringId, zon.getChild("black"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[2], initChildTableFromZon("blue", stringId, zon.getChild("blue"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[3], initChildTableFromZon("brown", stringId, zon.getChild("brown"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[4], initChildTableFromZon("crimson", stringId, zon.getChild("crimson"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[5], initChildTableFromZon("cyan", stringId, zon.getChild("cyan"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[6], initChildTableFromZon("dark_grey", stringId, zon.getChild("dark_grey"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[7], initChildTableFromZon("green", stringId, zon.getChild("green"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[8], initChildTableFromZon("grey", stringId, zon.getChild("grey"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[9], initChildTableFromZon("indigo", stringId, zon.getChild("indigo"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[10], initChildTableFromZon("lime", stringId, zon.getChild("lime"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[11], initChildTableFromZon("magenta", stringId, zon.getChild("magenta"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[12], initChildTableFromZon("orange", stringId, zon.getChild("orange"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[13], initChildTableFromZon("pink", stringId, zon.getChild("pink"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[14], initChildTableFromZon("purple", stringId, zon.getChild("purple"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[15], initChildTableFromZon("red", stringId, zon.getChild("red"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[16], initChildTableFromZon("violet", stringId, zon.getChild("violet"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[17], initChildTableFromZon("viridian", stringId, zon.getChild("viridian"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[18], initChildTableFromZon("white", stringId, zon.getChild("white"))) catch unreachable;
		self.colors.put(arena_allocator.allocator, childrenBlockNumericId[19], initChildTableFromZon("yellow", stringId, zon.getChild("yellow"))) catch unreachable;

		return self;
	}
	fn finalize(self: *Children) !void {
		var iterator = self.colors.iterator();
		while(iterator.next()) |entry| {
			if(entry.value_ptr.*) |table| {
				for(table.items) |*c| try c.finalize();
			}
		}
	}
	pub fn pickChild(self: Children, block: Block, seed: *u64) ?Child {
		if(self.colors.get(block.typ)) |c| if(c) |collection|
			return collection.sample(seed).*;
		return null;
	}
};

fn initChildTableFromZon(comptime childName: []const u8, stringId: []const u8, zon: ZonElement) ?AliasTable(Child) {
	if(zon == .null) return null;
	if(zon != .array) {
		std.log.err("[{s}->{s}] Incorrect child data structure, array expected.", .{stringId, childName});
		return null;
	}
	if(zon.array.items.len == 0) {
		std.log.warn("[{s}->{s}] Empty children list.", .{stringId, childName});
		return null;
	}
	var list = arena_allocator.alloc(Child, zon.array.items.len);
	for(zon.array.items, 0..) |entry, i| {
		list[i] = Child.initFromZon(childName, stringId, i, entry);
	}
	return AliasTable(Child).init(arena_allocator, list);
}

const Child = struct {
	structureId: []const u8,
	structure: *StructureBuildingBlock,
	chance: f32,

	fn initFromZon(comptime childName: []const u8, stringId: []const u8, i: usize, zon: ZonElement) Child {
		const self = Child{
			.structureId = arena_allocator.dupe(u8, zon.get([]const u8, "structure", "")),
			.structure = undefined,
			.chance = zon.get(f32, "chance", 0.0),
		};
		if(self.chance == 0) {
			std.log.warn("[{s}->{s}->{}] Child node has has 0.0 spawn chance.", .{stringId, childName, i});
		}
		if(self.chance < 0.0 or self.chance > 1.0) {
			std.log.warn("[{s}->{s}->{}] Child node has spawn chance outside of [0, 1] range ({}).", .{stringId, childName, i, self.chance});
		}
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
	std.log.debug("Registering {} structure building blocks", .{structures.count()});
	if(structureCache != null) {
		std.log.err("Attempting to register new SBBs without resetting cache.", .{});
		return error.AlreadyRegistered;
	}
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

pub fn registerBlueprints(blueprints: *std.StringHashMap([]u8)) !void {
	if(blueprintCache != null) {
		std.log.err("Attempting to register new blueprints without resetting cache.", .{});
		return error.AlreadyRegistered;
	}

	originBlockNumericId = parseBlock(originBlockStringId).typ;
	std.log.debug("Origin block numeric id: {}", .{originBlockNumericId});
	for(0..childrenBlockNumericId.len) |i| {
		childrenBlockNumericId[i] = parseBlock(childrenBlockStringId[i]).typ;
		std.log.debug("Child block '{s}'' numeric id: {}", .{childrenBlockStringId[i], childrenBlockNumericId[i]});
	}

	std.log.info("Registering {} blueprints", .{blueprints.count()});

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
		std.log.info("Registered blueprint: {s}", .{stringId});
	}
	std.log.debug("Registered {} blueprints", .{blueprintCache.?.count()});
}

pub fn getByStringId(stringId: []const u8) ?*StructureBuildingBlock {
	return structureCache.?.getPtr(stringId);
}

pub fn reset() void {
	_ = arena.reset(.free_all);

	structureCache = null;
	blueprintCache = null;
}
