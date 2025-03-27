const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const Blueprint = main.blueprint.Blueprint;
const List = main.List;
const ListUnmanaged = main.ListUnmanaged;
const AliasTable = main.utils.AliasTable;
const Neighbor = main.chunk.Neighbor;
const Block = main.blocks.Block;
const Degrees = main.rotation.Degrees;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

var arena = main.heap.NeverFailingArenaAllocator.init(main.globalAllocator);
const arenaAllocator = arena.allocator();

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

pub fn registerChildBlock(numericId: u16, stringId: []const u8) void {
	const index: u16 = @intCast(childBlockNumericIdMap.count());
	childBlockNumericIdMap.put(arenaAllocator.allocator, numericId, index) catch unreachable;
	// Take only color name from the ID.
	var iterator = std.mem.splitBackwardsScalar(u8, stringId, '/');
	const colorName = iterator.first();
	childBlockStringId.append(arenaAllocator, arenaAllocator.dupe(u8, colorName));
	std.log.debug("Structure child block '{s}' {} ('{s}' {}) ", .{colorName, index, stringId, numericId});
}

pub fn registerBlueprints(blueprints: *std.StringHashMap([]u8)) !void {
	std.debug.assert(blueprintCache.capacity() == 0);

	originBlockNumericId = main.blocks.parseBlock(originBlockStringId).typ;
	std.log.debug("Origin block numeric id: {}", .{originBlockNumericId});

	blueprintCache.ensureTotalCapacity(arenaAllocator.allocator, blueprints.count()) catch unreachable;

	var iterator = blueprints.iterator();
	while(iterator.next()) |entry| {
		const stringId = entry.key_ptr.*;
		const blueprint0 = Blueprint.load(arenaAllocator, entry.value_ptr.*) catch |err| {
			std.log.err("Could not load blueprint {s}: {s}", .{stringId, @errorName(err)});
			continue;
		};

		const rotatedBlueprints = arenaAllocator.create([4]BlueprintEntry);
		rotatedBlueprints.* = .{
			BlueprintEntry.init(blueprint0, stringId) catch continue,
			BlueprintEntry.init(blueprint0.rotateZ(arenaAllocator, .@"90"), stringId) catch continue,
			BlueprintEntry.init(blueprint0.rotateZ(arenaAllocator, .@"180"), stringId) catch continue,
			BlueprintEntry.init(blueprint0.rotateZ(arenaAllocator, .@"270"), stringId) catch continue,
		};

		blueprintCache.put(arenaAllocator.allocator, arenaAllocator.dupe(u8, stringId), rotatedBlueprints) catch unreachable;
		std.log.debug("Registered blueprint: {s}", .{stringId});
	}
}

pub fn reset() void {
	childBlockNumericIdMap = .{};
	childBlockStringId = .{};
	blueprintCache = .{};

	_ = arena.reset(.free_all);
}
