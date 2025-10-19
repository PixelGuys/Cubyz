const std = @import("std");

const main = @import("main");
const Tag = main.Tag;
const ZonElement = @import("../zon.zig").ZonElement;
const rotation = @import("../rotation.zig");
const block_entity = @import("block_entity.zig");
const block_props = @import("block_props.zig");
const block_meshes = @import("block_meshes.zig");
const sbb = main.server.terrain.structure_building_blocks;
const blueprint = main.blueprint;
const Assets = main.assets.Assets;
const items = @import("../items.zig");

pub const Block = block_props.Block;
pub const BlockProps = block_props.BlockProps;
pub const meshes = block_meshes.meshes;
pub const BlockDrop = block_props.BlockDrop;

var arenaAllocator = main.heap.NeverFailingArenaAllocator.init(main.globalAllocator);
const arena = arenaAllocator.allocator();

/// Ores can be found underground in veins.
/// TODO: Add support for non-stone ores.
pub const Ore = struct {
	/// average size of a vein in blocks
	size: f32,
	/// average density of a vein
	density: f32,
	/// average veins per chunk
	veins: f32,
	/// maximum height this ore can be generated
	maxHeight: i32,
	minHeight: i32,

	blockType: u16,
};

var reverseIndices = std.StringHashMap(u16).init(arena.allocator);

var size: u32 = 0;

pub var ores: main.List(Ore) = .init(arena);

pub fn init() void {}

pub fn deinit() void {
	arenaAllocator.deinit();
}

pub fn register(_: []const u8, id: []const u8, zon: ZonElement) u16 {
	BlockProps.id[size] = arena.dupe(u8, id);
	reverseIndices.put(BlockProps.id[size], @intCast(size)) catch unreachable;

	BlockProps.mode[size] = rotation.getByID(zon.get([]const u8, "rotation", "cubyz:no_rotation"));
	BlockProps.blockHealth[size] = zon.get(f32, "blockHealth", 1);
	BlockProps.blockResistance[size] = zon.get(f32, "blockResistance", 0);

	BlockProps.blockTags[size] = Tag.loadTagsFromZon(arena, zon.getChild("tags"));
	if(BlockProps.blockTags[size].len == 0) std.log.err("Block {s} is missing 'tags' field", .{id});
	for(BlockProps.blockTags[size]) |tag| {
		if(tag == Tag.sbbChild) {
			sbb.registerChildBlock(@intCast(size), BlockProps.id[size]);
			break;
		}
	}
	BlockProps.light[size] = zon.get(u32, "emittedLight", 0);
	BlockProps.absorption[size] = zon.get(u32, "absorbedLight", 0xffffff);
	BlockProps.degradable[size] = zon.get(bool, "degradable", false);
	BlockProps.selectable[size] = zon.get(bool, "selectable", true);
	BlockProps.replacable[size] = zon.get(bool, "replacable", false);
	BlockProps.transparent[size] = zon.get(bool, "transparent", false);
	BlockProps.collide[size] = zon.get(bool, "collide", true);
	BlockProps.alwaysViewThrough[size] = zon.get(bool, "alwaysViewThrough", false);
	BlockProps.viewThrough[size] = zon.get(bool, "viewThrough", false) or BlockProps.transparent[size] or BlockProps.alwaysViewThrough[size];
	BlockProps.hasBackFace[size] = zon.get(bool, "hasBackFace", false);
	BlockProps.friction[size] = zon.get(f32, "friction", 20);
	BlockProps.bounciness[size] = zon.get(f32, "bounciness", 0.0);
	BlockProps.density[size] = zon.get(f32, "density", 0.001);
	BlockProps.terminalVelocity[size] = zon.get(f32, "terminalVelocity", 90);
	BlockProps.mobility[size] = zon.get(f32, "mobility", 1.0);

	{
		// bool properties are added to the sorted array only when the prop val is true.
		BlockProps.sortedAllowOres.add(size, zon.get(bool, "allowOres", false));

		const guidata = arena.dupe(u8, zon.get([]const u8, "gui", ""));
		if(guidata.len != 0) {
			BlockProps.sortedGui.add(size, guidata);
		}

		const tickEventData = block_props.TickEvent.loadFromZon(zon.getChild("tickEvent"));
		if(tickEventData) |tickEvent| {
			BlockProps.sortedTickEvent.add(size, tickEvent);
		}

		if(zon.get(?[]const u8, "touchFunction", null)) |touchFunctionName| {
			const functionData = block_props.touchFunctions.getFunctionPointer(touchFunctionName);

			if(functionData) |function| {
				BlockProps.sortedTouchFunction.add(size, function);
			} else {
				std.log.err("Could not find TouchFunction {s}!", .{touchFunctionName});
			}
		}

		const blockEntityData = block_entity.getByID(zon.get(?[]const u8, "blockEntity", null));
		if(blockEntityData) |blockEntity| {
			BlockProps.sortedBlockEntity.add(size, blockEntity);
		}
	}

	const oreProperties = zon.getChild("ore");
	if(oreProperties != .null) blk: {
		if(!std.mem.eql(u8, zon.get([]const u8, "rotation", "cubyz:no_rotation"), "cubyz:ore")) {
			std.log.err("Ore must have rotation mode \"cubyz:ore\"!", .{});
			break :blk;
		}
		ores.append(Ore{
			.veins = oreProperties.get(f32, "veins", 0),
			.size = oreProperties.get(f32, "size", 0),
			.maxHeight = oreProperties.get(i32, "height", 0),
			.minHeight = oreProperties.get(i32, "minHeight", std.math.minInt(i32)),
			.density = oreProperties.get(f32, "density", 0.5),
			.blockType = @intCast(size),
		});
	}

	defer size += 1;
	std.log.debug("Registered block: {d: >5} '{s}'", .{size, id});
	return @intCast(size);
}

fn registerBlockDrop(typ: u16, zon: ZonElement) void {
	const drops = zon.getChild("drops").toSlice();
	BlockProps.blockDrops[typ] = arena.alloc(BlockDrop, drops.len);

	for(drops, 0..) |blockDrop, i| {
		BlockProps.blockDrops[typ][i].chance = blockDrop.get(f32, "chance", 1);
		const itemZons = blockDrop.getChild("items").toSlice();
		var resultItems = main.List(items.ItemStack).initCapacity(main.stackAllocator, itemZons.len);
		defer resultItems.deinit();

		for(itemZons) |itemZon| {
			var string = itemZon.as([]const u8, "auto");
			string = std.mem.trim(u8, string, " ");
			var iterator = std.mem.splitScalar(u8, string, ' ');
			var name = iterator.first();
			var amount: u16 = 1;
			while(iterator.next()) |next| {
				if(next.len == 0) continue; // skip multiple spaces.
				amount = std.fmt.parseInt(u16, name, 0) catch 1;
				name = next;
				break;
			}

			if(std.mem.eql(u8, name, "auto")) {
				name = BlockProps.id[typ];
			}

			const item = items.BaseItemIndex.fromId(name) orelse continue;
			resultItems.append(.{.item = .{.baseItem = item}, .amount = amount});
		}

		BlockProps.blockDrops[typ][i].items = arena.dupe(items.ItemStack, resultItems.items);
	}
}

fn registerLodReplacement(typ: u16, zon: ZonElement) void {
	if(zon.get(?[]const u8, "lodReplacement", null)) |replacement| {
		BlockProps.lodReplacement[typ] = getTypeById(replacement);
	} else {
		BlockProps.lodReplacement[typ] = typ;
	}
}

fn registerOpaqueVariant(typ: u16, zon: ZonElement) void {
	if(zon.get(?[]const u8, "opaqueVariant", null)) |replacement| {
		BlockProps.opaqueVariant[typ] = getTypeById(replacement);
	} else {
		BlockProps.opaqueVariant[typ] = typ;
	}
}

pub fn finishBlocks(zonElements: Assets.ZonHashMap) void {
	var i: u16 = 0;
	while(i < size) : (i += 1) {
		registerBlockDrop(i, zonElements.get(BlockProps.id[i]) orelse continue);
	}
	i = 0;
	while(i < size) : (i += 1) {
		registerLodReplacement(i, zonElements.get(BlockProps.id[i]) orelse continue);
		registerOpaqueVariant(i, zonElements.get(BlockProps.id[i]) orelse continue);
	}
	blueprint.registerVoidBlock(parseBlock("cubyz:void"));
}

pub fn reset() void {
	size = 0;
	ores.clearAndFree();
	meshes.reset();
	_ = arenaAllocator.reset(.free_all);
	reverseIndices = .init(arena.allocator);

	block_props.resetSortedProperties();
}

pub fn getTypeById(id: []const u8) u16 {
	if(reverseIndices.get(id)) |result| {
		return result;
	} else {
		std.log.err("Couldn't find block {s}. Replacing it with air...", .{id});
		return 0;
	}
}

fn parseBlockData(fullBlockId: []const u8, data: []const u8) ?u16 {
	if(std.mem.containsAtLeastScalar(u8, data, 1, ':')) {
		const oreChild = parseBlock(data);
		if(oreChild.data != 0) {
			std.log.warn("Error while parsing ore block data of '{s}': Parent block data must be 0.", .{fullBlockId});
		}
		return oreChild.typ;
	}
	return std.fmt.parseInt(u16, data, 0) catch |err| {
		std.log.err("Error while parsing block data of '{s}': {s}", .{fullBlockId, @errorName(err)});
		return null;
	};
}

pub fn parseBlock(data: []const u8) Block {
	var id: []const u8 = data;
	var blockData: ?u16 = null;
	if(std.mem.indexOfScalarPos(u8, data, 1 + (std.mem.indexOfScalar(u8, data, ':') orelse 0), ':')) |pos| {
		id = data[0..pos];
		blockData = parseBlockData(data, data[pos + 1 ..]);
	}
	if(reverseIndices.get(id)) |resultType| {
		var result: Block = .{.typ = resultType, .data = 0};
		result.data = blockData orelse result.mode().naturalStandard;
		return result;
	} else {
		std.log.err("Couldn't find block {s}. Replacing it with air...", .{id});
		return .{.typ = 0, .data = 0};
	}
}

pub fn getBlockById(idAndData: []const u8) !u16 {
	const addonNameSeparatorIndex = std.mem.indexOfScalar(u8, idAndData, ':') orelse return error.MissingAddonNameSeparator;
	const blockIdEndIndex = std.mem.indexOfScalarPos(u8, idAndData, 1 + addonNameSeparatorIndex, ':') orelse idAndData.len;
	const id = idAndData[0..blockIdEndIndex];
	return reverseIndices.get(id) orelse return error.NotFound;
}

pub fn getBlockData(idLikeString: []const u8) !?u16 {
	const addonNameSeparatorIndex = std.mem.indexOfScalar(u8, idLikeString, ':') orelse return error.MissingAddonNameSeparator;
	const blockIdEndIndex = std.mem.indexOfScalarPos(u8, idLikeString, 1 + addonNameSeparatorIndex, ':') orelse return null;
	const dataString = idLikeString[blockIdEndIndex + 1 ..];
	if(dataString.len == 0) return error.EmptyDataString;
	return std.fmt.parseInt(u16, dataString, 0) catch return error.InvalidData;
}

pub fn hasRegistered(id: []const u8) bool {
	return reverseIndices.contains(id);
}