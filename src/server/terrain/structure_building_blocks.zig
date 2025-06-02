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

var arena = main.heap.NeverFailingArenaAllocator.init(main.globalAllocator);
const arenaAllocator = arena.allocator();

var structureCache: std.StringHashMapUnmanaged(StructureBuildingBlock) = .{};
var blueprintCache: std.StringHashMapUnmanaged(*[4]BlueprintEntry) = .{};
var childrenToResolve: List(struct {parentId: []const u8, colorName: []const u8, colorIndex: usize, childIndex: usize, structureId: []const u8}) = undefined;

const originBlockStringId = "cubyz:sbb/origin";
var originBlockNumericId: u16 = 0;

// Maps global child block numeric ID to index used to locally represent that child block.
var childBlockNumericIdMap: std.AutoHashMapUnmanaged(u16, u16) = .{};
var childBlockStringId: ListUnmanaged([]const u8) = .{};

const BlueprintEntry = struct {
	blueprint: Blueprint,
	originBlock: StructureBlock,
	childBlocks: []StructureBlock,

	const StructureBlock = struct {
		x: u16,
		y: u16,
		z: u16,
		index: u16,
		data: u16,

		pub inline fn direction(self: StructureBlock) Neighbor {
			return @enumFromInt(self.data);
		}

		pub inline fn pos(self: StructureBlock) Vec3i {
			return Vec3i{self.x, self.y, self.z};
		}

		pub fn id(self: StructureBlock) []const u8 {
			return childBlockStringId.items[self.index];
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
								.index = std.math.maxInt(u16),
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
		self.childBlocks = arenaAllocator.dupe(StructureBlock, childBlocks.items);

		return self;
	}
};

pub fn isChildBlock(block: Block) bool {
	return childBlockNumericIdMap.contains(block.typ);
}

pub fn isOriginBlock(block: Block) bool {
	return block.typ == originBlockNumericId;
}

pub const StructureBuildingBlock = struct {
	id: []const u8,
	children: []AliasTable(Child),
	blueprints: *[4]BlueprintEntry,

	fn initFromZon(stringId: []const u8, zon: ZonElement) !StructureBuildingBlock {
		const blueprintId = zon.get(?[]const u8, "blueprint", null) orelse {
			std.log.err("['{s}'] Missing blueprint field.", .{stringId});
			return error.MissingBlueprintIdField;
		};
		const blueprintsTemplate = blueprintCache.get(blueprintId) orelse {
			std.log.err("['{s}'] Could not find blueprint '{s}'.", .{stringId, blueprintId});
			return error.MissingBlueprint;
		};

		const blueprints = arenaAllocator.create([4]BlueprintEntry);
		blueprints.* = blueprintsTemplate.*;

		const self = StructureBuildingBlock{
			.id = stringId,
			.children = arenaAllocator.alloc(AliasTable(Child), childBlockStringId.items.len),
			.blueprints = blueprints,
		};
		const childrenZon = zon.getChild("children");
		for(childBlockStringId.items, 0..) |colorName, colorIndex| {
			self.children[colorIndex] = try initChildTableFromZon(stringId, colorName, colorIndex, childrenZon.getChild(colorName));
		}
		self.updateBlueprintChildLists();
		return self;
	}
	pub fn updateBlueprintChildLists(self: StructureBuildingBlock) void {
		for(self.children, 0..) |child, index| found: {
			if(child.items.len == 0) continue;

			for(self.blueprints[0].childBlocks) |blueprintChild| {
				if(blueprintChild.index != index) continue;
				break :found;
			}
			std.log.err("['{s}'] Blueprint doesn't contain child '{s}' but configuration for it was specified.", .{self.id, childBlockStringId.items[index]});
		}
		for(self.blueprints, 0..) |*blueprint, index| {
			var childBlocks: ListUnmanaged(BlueprintEntry.StructureBlock) = .{};
			defer childBlocks.deinit(main.stackAllocator);

			for(blueprint.childBlocks) |child| {
				if(self.children[child.index].items.len == 0) {
					if(index == 0) std.log.err("['{s}'] Missing child structure configuration for child '{s}'", .{self.id, child.id()});
					continue;
				}
				childBlocks.append(main.stackAllocator, child);
			}
			blueprint.childBlocks = arenaAllocator.dupe(BlueprintEntry.StructureBlock, childBlocks.items);
		}
	}
	pub fn initInline(sbbId: []const u8) !StructureBuildingBlock {
		const blueprintsTemplate = blueprintCache.get(sbbId) orelse {
			std.log.err("['{s}'] Could not find blueprint '{s}'.", .{sbbId, sbbId});
			return error.MissingBlueprint;
		};

		const blueprints = arenaAllocator.create([4]BlueprintEntry);
		blueprints.* = blueprintsTemplate.*;
		for(blueprints, 0..) |*blueprint, index| {
			if(index == 0) {
				for(blueprint.childBlocks) |child| std.log.err("['{s}'] Missing child structure configuration for child '{s}'", .{sbbId, child.id()});
			}
			blueprint.childBlocks = &.{};
		}

		return .{
			.id = sbbId,
			.children = &.{},
			.blueprints = blueprints,
		};
	}
	pub fn getBlueprint(self: StructureBuildingBlock, rotation: Degrees) *BlueprintEntry {
		return &self.blueprints[@intFromEnum(rotation)];
	}
	pub fn pickChild(self: StructureBuildingBlock, block: BlueprintEntry.StructureBlock, seed: *u64) ?*const StructureBuildingBlock {
		return self.children[block.index].sample(seed).structure;
	}
};

fn initChildTableFromZon(parentId: []const u8, colorName: []const u8, colorIndex: usize, zon: ZonElement) !AliasTable(Child) {
	if(zon == .null) return .init(arenaAllocator, &.{});
	if(zon != .array) {
		std.log.err("['{s}'->'{s}'] Incorrect child data structure, array expected.", .{parentId, colorName});
		return .init(arenaAllocator, &.{});
	}
	if(zon.array.items.len == 0) {
		std.log.err("['{s}'->'{s}'] Empty children list not allowed. Remove 'children' field or add child structure configurations.", .{parentId, colorName});
		return .init(arenaAllocator, &.{});
	}
	const list = arenaAllocator.alloc(Child, zon.array.items.len);
	for(zon.array.items, 0..) |entry, childIndex| {
		list[childIndex] = try Child.initFromZon(parentId, colorName, colorIndex, childIndex, entry);
	}
	return .init(arenaAllocator, list);
}

const Child = struct {
	structure: ?*StructureBuildingBlock,
	chance: f32,

	fn initFromZon(parentId: []const u8, colorName: []const u8, colorIndex: usize, childIndex: usize, zon: ZonElement) !Child {
		const structureId = zon.get(?[]const u8, "structure", null);
		if(structureId != null and structureId.?.len != 0) {
			childrenToResolve.append(.{.parentId = parentId, .colorName = colorName, .colorIndex = colorIndex, .childIndex = childIndex, .structureId = structureId.?});
		}
		return .{
			.structure = null,
			.chance = zon.get(f32, "chance", 1.0),
		};
	}
};

pub fn registerSBB(structures: *Assets.ZonHashMap) !void {
	std.debug.assert(structureCache.capacity() == 0);
	structureCache.ensureTotalCapacity(arenaAllocator.allocator, structures.count()) catch unreachable;
	childrenToResolve = .init(main.stackAllocator);
	defer childrenToResolve.deinit();
	{
		var iterator = structures.iterator();
		while(iterator.next()) |entry| {
			const value = StructureBuildingBlock.initFromZon(entry.key_ptr.*, entry.value_ptr.*) catch |err| {
				std.log.err("Could not register structure building block '{s}' ({s})", .{entry.key_ptr.*, @errorName(err)});
				continue;
			};
			const key = arenaAllocator.dupe(u8, entry.key_ptr.*);
			structureCache.put(arenaAllocator.allocator, key, value) catch unreachable;
			std.log.debug("Registered structure building block: '{s}'", .{entry.key_ptr.*});
		}
	}
	{
		var keyIterator = blueprintCache.keyIterator();
		while(keyIterator.next()) |key_ptr| {
			const blueprintId = key_ptr.*;

			if(structureCache.contains(blueprintId)) continue;

			const value = StructureBuildingBlock.initInline(blueprintId) catch |err| {
				std.log.err("Could not register inline structure building block '{s}' ({s})", .{blueprintId, @errorName(err)});
				continue;
			};
			const key = arenaAllocator.dupe(u8, blueprintId);
			structureCache.put(arenaAllocator.allocator, key, value) catch unreachable;
			std.log.debug("Registered inline structure building block: '{s}'", .{blueprintId});
		}
	}
	{
		for(childrenToResolve.items) |entry| {
			const parent = structureCache.getPtr(entry.parentId).?;
			const child = getByStringId(entry.structureId) orelse {
				std.log.err("Could not find child structure nor blueprint '{s}' for child resolution.", .{entry.structureId});
				continue;
			};

			if(parent.children.len <= entry.colorIndex) {
				main.utils.panicWithMessage("Error resolving child structure '{s}'->'{s}'->'{d}' to '{s}'", .{entry.parentId, entry.colorName, entry.childIndex, entry.structureId});
			}

			const childColor = parent.children[entry.colorIndex];

			std.log.debug("Resolved child structure '{s}'->'{s}'->'{d}' to '{s}'", .{entry.parentId, entry.colorName, entry.childIndex, entry.structureId});
			childColor.items[entry.childIndex].structure = child;
		}
	}
}

pub fn registerChildBlock(numericId: u16, stringId: []const u8) void {
	std.debug.assert(numericId != 0);

	const index: u16 = @intCast(childBlockNumericIdMap.count());
	childBlockNumericIdMap.put(arenaAllocator.allocator, numericId, index) catch unreachable;
	// Take only color name from the ID.
	var iterator = std.mem.splitBackwardsScalar(u8, stringId, '/');
	const colorName = iterator.first();
	childBlockStringId.append(arenaAllocator, arenaAllocator.dupe(u8, colorName));
}

pub fn registerBlueprints(blueprints: *Assets.BytesHashMap) !void {
	std.debug.assert(blueprintCache.capacity() == 0);

	originBlockNumericId = main.blocks.parseBlock(originBlockStringId).typ;
	std.debug.assert(originBlockNumericId != 0);

	blueprintCache.ensureTotalCapacity(arenaAllocator.allocator, blueprints.count()) catch unreachable;

	var iterator = blueprints.iterator();
	while(iterator.next()) |entry| {
		const stringId = entry.key_ptr.*;
		// Rotated copies need to be made before initializing BlueprintEntry as it removes origin and child blocks.
		const blueprint0 = Blueprint.load(arenaAllocator, entry.value_ptr.*) catch |err| {
			std.log.err("Could not load blueprint '{s}' ({s})", .{stringId, @errorName(err)});
			continue;
		};
		const blueprint90 = blueprint0.rotateZ(arenaAllocator, .@"90");
		const blueprint180 = blueprint0.rotateZ(arenaAllocator, .@"180");
		const blueprint270 = blueprint0.rotateZ(arenaAllocator, .@"270");

		const rotatedBlueprints = arenaAllocator.create([4]BlueprintEntry);

		rotatedBlueprints.* = .{
			BlueprintEntry.init(blueprint0, stringId) catch continue,
			BlueprintEntry.init(blueprint90, stringId) catch continue,
			BlueprintEntry.init(blueprint180, stringId) catch continue,
			BlueprintEntry.init(blueprint270, stringId) catch continue,
		};

		blueprintCache.put(arenaAllocator.allocator, arenaAllocator.dupe(u8, stringId), rotatedBlueprints) catch unreachable;
		std.log.debug("Registered blueprint: '{s}'", .{stringId});
	}
}

pub fn getByStringId(stringId: []const u8) ?*StructureBuildingBlock {
	return structureCache.getPtr(stringId);
}

pub fn reset() void {
	childBlockNumericIdMap = .{};
	childBlockStringId = .{};
	structureCache = .{};
	blueprintCache = .{};

	_ = arena.reset(.free_all);
}
