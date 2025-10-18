const std = @import("std");

const main = @import("main");
const Tag = main.Tag;
const utils = main.utils;
const ZonElement = @import("zon.zig").ZonElement;
const chunk = @import("chunk.zig");
const Neighbor = chunk.Neighbor;
const Chunk = chunk.Chunk;
const graphics = @import("graphics.zig");
const SSBO = graphics.SSBO;
const Image = graphics.Image;
const Color = graphics.Color;
const TextureArray = graphics.TextureArray;
const items = @import("items.zig");
const models = @import("models.zig");
const ModelIndex = models.ModelIndex;
const rotation = @import("rotation.zig");
const RotationMode = rotation.RotationMode;
const Degrees = rotation.Degrees;
const Entity = main.server.Entity;
const block_entity = @import("block_entity.zig");
const BlockEntityType = block_entity.BlockEntityType;
const sbb = main.server.terrain.structure_building_blocks;
const blueprint = main.blueprint;
const Assets = main.assets.Assets;

var arenaAllocator = main.heap.NeverFailingArenaAllocator.init(main.globalAllocator);
const arena = arenaAllocator.allocator();

pub const maxBlockCount: usize = 65536; // 16 bit limit

pub const BlockDrop = struct {
	items: []const items.ItemStack,
	chance: f32,
};

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

// MARK: Sorted Block Properties
/// Generates a type for sorted block properties.
/// For bool type uses only ID array (presence = true), for other types also a data array.
fn SortedBlockProperties(comptime sortedBlockSize: usize, comptime DataType: type) type {
	const Cmp = struct {
			fn less(target: u32, candidate: u32) std.math.Order {
			if (target == candidate) return .eq;
			if (target < candidate) return .lt;
			return .gt;
		}
	};

// For bool block properties, we don't need additional data array,
	// if the block id is in the array, then the property value is true, otherwise false.
	if(DataType == bool)
	{
		return struct {
			const Self = @This();

			allocatedSize: usize = 0,
			idxLookup: [sortedBlockSize]u32 = undefined,

			/// Checks if block has the property (true if ID is in the array).
			pub fn getBlockPropertyValue(self: *const Self, blockId: u32) bool {
				const slice = self.idxLookup[0..self.allocatedSize];

				_ = std.sort.binarySearch(
					u32,
					slice,
					blockId,
					Cmp.less,
				) orelse return false;

				return true;
			}

			/// Adds block ID to the sorted array (only if propVal == true).
			pub fn addBlockProperty(self: *Self, blockId: u32, propVal: bool) void
			{
				if(propVal == false)
				{
					return;
				}

				if (self.allocatedSize + 1 > sortedBlockSize) {
					@panic("Failed to add block property. Consider increasing the size of the array");
				}

				const slice = self.idxLookup[0 .. self.allocatedSize];

				const insertIdx = std.sort.lowerBound(
					u32, 
					slice,
					blockId, 
					Cmp.less
				);

				std.mem.copyBackwards(
					u32,
					self.idxLookup[(insertIdx + 1) .. self.allocatedSize + 1], 
					self.idxLookup[insertIdx .. self.allocatedSize]
				);
				
				self.idxLookup[insertIdx] = blockId;

				self.allocatedSize += 1;
			}

			/// Clears the array by resetting the counter.
			pub fn clear(self: *Self) void {
				self.allocatedSize = 0;
			}
		};
	}
	else {
		return struct {
			const Self = @This();

			allocatedSize: usize = 0,
			idxLookup: [sortedBlockSize]u32 = undefined,
			data: [sortedBlockSize]DataType = undefined,

			fn compare(target: u32, candidate: u32) std.math.Order {
				if (target == candidate) return .eq;
				if (target < candidate) return .lt;
				return .gt;
			}

			/// Returns the index of a block in the sorted array, or null if not found.
			pub fn getBlockSortedIdx(self: *const Self, blockId: u32) ?usize {
				const slice = self.idxLookup[0..self.allocatedSize];

				return std.sort.binarySearch(
					u32,
					slice,
					blockId,
					compare,
				);
			}

			pub fn getBlockPropertyValue(self: *const Self, blockId: u32) ?DataType {
				const idx = getBlockSortedIdx(self, blockId) orelse return null;
				return self.data[idx];
			}

			pub fn getBlockPropertyValueByIdx(self: *const Self, blockIdx: u32) !DataType {
				if(blockIdx < self.allocatedSize) {
					return self.data[blockIdx];
				}
				else {
					return error.OutOfBounds;
				}
			}

			/// Adds a block property while maintaining sorting in both arrays (ID and data).
			pub fn addBlockProperty(self: *Self, blockId: u32, propVal: DataType) void
			{
				if (self.allocatedSize + 1 > sortedBlockSize) {
					// Too many blocks in sorted block properties. Increase its size.
					@panic("Failed to add block property. Consider increasing the size of the array");
				}

				const slice = self.idxLookup[0 .. self.allocatedSize];

				const insertIdx = std.sort.lowerBound(
					u32, 
					slice,
					blockId, 
					compare
				);

				std.mem.copyBackwards(
					u32,
					self.idxLookup[(insertIdx + 1) .. self.allocatedSize + 1], 
					self.idxLookup[insertIdx .. self.allocatedSize]
				);
				
				std.mem.copyBackwards(
					DataType,
					self.data[(insertIdx + 1) .. self.allocatedSize + 1], 
					self.data[insertIdx .. self.allocatedSize]
				);

				self.idxLookup[insertIdx] = blockId;
				self.data[insertIdx] = propVal;

				self.allocatedSize += 1;
			}

			/// Clears the array by resetting the counter.
			pub fn clear(self: *Self) void {
				self.allocatedSize = 0;
			}
		};
	}
}

fn isSortedProp(comptime T: type) bool {
    return std.meta.hasFn(T, "clear") and
           std.meta.hasFn(T, "addBlockProperty") and
           std.meta.hasFn(T, "getBlockPropertyValue");
}

/// Resets all sorted block properties.
fn resetSortedProperties() void {
    inline for (@typeInfo(BlockProps).@"struct".decls) |decl| {
        const sortedProp = &@field(BlockProps, decl.name);

        if (comptime isSortedProp(@TypeOf(sortedProp.*))) {
			std.log.info("Cleared \'{s}\' from {d} entries", .{decl.name, sortedProp.allocatedSize});
           	sortedProp.clear();
        }
    }
}

// ------------------------------------------------- MARK: Block Properties 

const BlockProps = struct {
	pub var transparent: [maxBlockCount]bool = undefined;
	pub var collide: [maxBlockCount]bool = undefined;
	pub var id: [maxBlockCount][]u8 = undefined;

	pub var blockHealth: [maxBlockCount]f32 = undefined;
	pub var blockResistance: [maxBlockCount]f32 = undefined;

	/// Whether you can replace it with another block, mainly used for fluids/gases
	pub var replacable: [maxBlockCount]bool = undefined;
	pub var selectable: [maxBlockCount]bool = undefined;
	pub var blockDrops: [maxBlockCount][]BlockDrop = undefined;
	/// Meaning undegradable parts of trees or other structures can grow through this block.
	pub var degradable: [maxBlockCount]bool = undefined;
	pub var viewThrough: [maxBlockCount]bool = undefined;
	pub var alwaysViewThrough: [maxBlockCount]bool = undefined;
	pub var hasBackFace: [maxBlockCount]bool = undefined;
	pub var blockTags: [maxBlockCount][]Tag = undefined;
	pub var light: [maxBlockCount]u32 = undefined;
	/// How much light this block absorbs if it is transparent
	pub var absorption: [maxBlockCount]u32 = undefined;
	pub var mode: [maxBlockCount]*RotationMode = undefined;
	pub var modeData: [maxBlockCount]u16 = undefined;
	pub var lodReplacement: [maxBlockCount]u16 = undefined;
	pub var opaqueVariant: [maxBlockCount]u16 = undefined;

	pub var friction: [maxBlockCount]f32 = undefined;
	pub var bounciness: [maxBlockCount]f32 = undefined;
	pub var density: [maxBlockCount]f32 = undefined;
	pub var terminalVelocity: [maxBlockCount]f32 = undefined;
	pub var mobility: [maxBlockCount]f32 = undefined;


	/// ------------------------------------------------- Sorted Block Properties
	/// These properties are rarely used, so to save memory we use sorted arrays 
	/// with ~100-200 entries instead of creating arrays with maxBlockCount (65536) entries.

	/// Magic Value - Increase it if you need to store more block properties.
	/// Consider creating a separate variable with a comment for a specific property if only one needs a larger size.
	pub const maxSortedBlockProperties: usize = 100;

	pub var sortedAllowOres: SortedBlockProperties(maxSortedBlockProperties, bool) = .{};
	//TODO: Tick event is accessed like a milion times for no reason. FIX IT 
	pub var sortedTickEvent: SortedBlockProperties(maxSortedBlockProperties, TickEvent) = .{};
	pub var sortedTouchFunction: SortedBlockProperties(maxSortedBlockProperties, *const TouchFunction) = .{};
	pub var sortedBlockEntity: SortedBlockProperties(maxSortedBlockProperties, *BlockEntityType) = .{};

	/// GUI that is opened on click.
	pub var sortedGui: SortedBlockProperties(maxSortedBlockProperties, []u8) = .{};
};

// ------------------------------------------------- End Of Block Properties 

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
		BlockProps.sortedAllowOres.addBlockProperty(size, zon.get(bool, "allowOres", false));

		const guidata = arena.dupe(u8, zon.get([]const u8, "gui", ""));
		if(guidata.len != 0) {
			BlockProps.sortedGui.addBlockProperty(size, guidata);
		}

		const tickEventData = TickEvent.loadFromZon(zon.getChild("tickEvent"));
		if (tickEventData) |tickEvent| {
			BlockProps.sortedTickEvent.addBlockProperty(size, tickEvent);
		}
		

		if(zon.get(?[]const u8, "touchFunction", null)) |touchFunctionName| {
			const functionData = touchFunctions.getFunctionPointer(touchFunctionName);

			if(functionData) |function| {
				BlockProps.sortedTouchFunction.addBlockProperty(size, function);
			}
			else {
				std.log.err("Could not find TouchFunction {s}!", .{touchFunctionName});
			}
		}

		const blockEntityData = block_entity.getByID(zon.get(?[]const u8, "blockEntity", null));
		if(blockEntityData) |blockEntity| {
			BlockProps.sortedBlockEntity.addBlockProperty(size, blockEntity);
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

	resetSortedProperties();
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

pub const Block = packed struct { // MARK: Block
	typ: u16,
	data: u16,

	pub const air = Block{.typ = 0, .data = 0};

	pub fn toInt(self: Block) u32 {
		return @as(u32, self.typ) | @as(u32, self.data) << 16;
	}
	pub fn fromInt(self: u32) Block {
		return Block{.typ = @truncate(self), .data = @intCast(self >> 16)};
	}

	pub inline fn transparent(self: Block) bool {
		return BlockProps.transparent[self.typ];
	}

	pub inline fn collide(self: Block) bool {
		return BlockProps.collide[self.typ];
	}

	pub inline fn id(self: Block) []u8 {
		return BlockProps.id[self.typ];
	}

	pub inline fn blockHealth(self: Block) f32 {
		return BlockProps.blockHealth[self.typ];
	}

	pub inline fn blockResistance(self: Block) f32 {
		return BlockProps.blockResistance[self.typ];
	}

	/// Whether you can replace it with another block, mainly used for fluids/gases
	pub inline fn replacable(self: Block) bool {
		return BlockProps.replacable[self.typ];
	}

	pub inline fn selectable(self: Block) bool {
		return BlockProps.selectable[self.typ];
	}

	pub inline fn blockDrops(self: Block) []BlockDrop {
		return BlockProps.blockDrops[self.typ];
	}

	/// Meaning undegradable parts of trees or other structures can grow through this block.
	pub inline fn degradable(self: Block) bool {
		return BlockProps.degradable[self.typ];
	}

	pub inline fn viewThrough(self: Block) bool {
		return BlockProps.viewThrough[self.typ];
	}

	/// shows backfaces even when next to the same block type
	pub inline fn alwaysViewThrough(self: Block) bool {
		return BlockProps.alwaysViewThrough[self.typ];
	}

	pub inline fn hasBackFace(self: Block) bool {
		return BlockProps.hasBackFace[self.typ];
	}

	pub inline fn blockTags(self: Block) []const Tag {
		return BlockProps.blockTags[self.typ];
	}

	pub inline fn hasTag(self: Block, tag: Tag) bool {
		return std.mem.containsAtLeastScalar(Tag, self.blockTags(), 1, tag);
	}

	pub inline fn light(self: Block) u32 {
		return BlockProps.light[self.typ];
	}

	/// How much light this block absorbs if it is transparent.
	pub inline fn absorption(self: Block) u32 {
		return BlockProps.absorption[self.typ];
	}

	pub inline fn mode(self: Block) *RotationMode {
		return BlockProps.mode[self.typ];
	}

	pub inline fn modeData(self: Block) u16 {
		return BlockProps.modeData[self.typ];
	}

	pub inline fn rotateZ(self: Block, angle: Degrees) Block {
		return .{.typ = self.typ, .data = self.mode().rotateZ(self.data, angle)};
	}

	pub inline fn lodReplacement(self: Block) u16 {
		return BlockProps.lodReplacement[self.typ];
	}

	pub inline fn opaqueVariant(self: Block) u16 {
		return BlockProps.opaqueVariant[self.typ];
	}

	pub inline fn friction(self: Block) f32 {
		return BlockProps.friction[self.typ];
	}

	pub inline fn bounciness(self: Block) f32 {
		return BlockProps.bounciness[self.typ];
	}

	pub inline fn density(self: Block) f32 {
		return BlockProps.density[self.typ];
	}

	pub inline fn terminalVelocity(self: Block) f32 {
		return BlockProps.terminalVelocity[self.typ];
	}

	pub inline fn mobility(self: Block) f32 {
		return BlockProps.mobility[self.typ];
	}

	pub inline fn allowOres(self: Block) bool {
		return BlockProps.sortedAllowOres.getBlockPropertyValue(self.typ);
	}

	/// GUI that is opened on click.
	pub inline fn gui(self: Block) []u8 {
		return BlockProps.sortedGui.getBlockPropertyValue(self.typ) orelse "";
	}

	pub inline fn tickEvent(self: Block) ?TickEvent { //TODO: Tick is called for each block every game tick ...??? fix this
		return BlockProps.sortedTickEvent.getBlockPropertyValue(self.typ);
	}

	pub inline fn touchFunction(self: Block) ?*const TouchFunction {
		return BlockProps.sortedTouchFunction.getBlockPropertyValue(self.typ);
	}

	pub fn blockEntity(self: Block) ?*BlockEntityType {
		return BlockProps.sortedBlockEntity.getBlockPropertyValue(self.typ);
	}

	pub fn canBeChangedInto(self: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) main.rotation.RotationMode.CanBeChangedInto {
		return newBlock.mode().canBeChangedInto(self, newBlock, item, shouldDropSourceBlockOnSuccess);
	}
};

// MARK: Tick
pub var tickFunctions: utils.NamedCallbacks(TickFunctions, TickFunction) = undefined;
pub const TickFunction = fn(block: Block, _chunk: *chunk.ServerChunk, x: i32, y: i32, z: i32) void;
pub const TickFunctions = struct {
	pub fn replaceWithCobble(block: Block, _chunk: *chunk.ServerChunk, x: i32, y: i32, z: i32) void {
		std.log.debug("Replace with cobblestone at ({d},{d},{d})", .{x, y, z});
		const cobblestone = parseBlock("cubyz:cobblestone");

		const wx = _chunk.super.pos.wx + x;
		const wy = _chunk.super.pos.wy + y;
		const wz = _chunk.super.pos.wz + z;

		_ = main.server.world.?.cmpxchgBlock(wx, wy, wz, block, cobblestone);
	}
};

pub const TickEvent = struct {
	function: *const TickFunction,
	chance: f32,

	pub fn loadFromZon(zon: ZonElement) ?TickEvent {
		const functionName = zon.get(?[]const u8, "name", null) orelse return null;

		const function = tickFunctions.getFunctionPointer(functionName) orelse {
			std.log.err("Could not find TickFunction {s}.", .{functionName});
			return null;
		};

		return TickEvent{.function = function, .chance = zon.get(f32, "chance", 1)};
	}

	pub fn tryRandomTick(self: *const TickEvent, block: Block, _chunk: *chunk.ServerChunk, x: i32, y: i32, z: i32) void {
		if(self.chance >= 1.0 or main.random.nextFloat(&main.seed) < self.chance) {
			self.function(block, _chunk, x, y, z);
		}
	}
};

// MARK: Touch
pub var touchFunctions: utils.NamedCallbacks(TouchFunctions, TouchFunction) = undefined;
pub const TouchFunction = fn(block: Block, entity: Entity, posX: i32, posY: i32, posZ: i32, isEntityInside: bool) void;
pub const TouchFunctions = struct {};

pub const meshes = struct { // MARK: meshes
	const AnimationData = extern struct {
		startFrame: u32,
		frames: u32,
		time: u32,
	};

	const FogData = extern struct {
		fogDensity: f32,
		fogColor: u32,
	};
	var size: u32 = 0;
	var _modelIndex: [maxBlockCount]ModelIndex = undefined;
	var textureIndices: [maxBlockCount][16]u16 = undefined;
	/// Stores the number of textures after each block was added. Used to clean additional textures when the world is switched.
	var maxTextureCount: [maxBlockCount]u32 = undefined;
	/// Number of loaded meshes. Used to determine if an update is needed.
	var loadedMeshes: u32 = 0;

	var textureIDs: main.List([]const u8) = undefined;
	var animation: main.List(AnimationData) = undefined;
	var blockTextures: main.List(Image) = undefined;
	var emissionTextures: main.List(Image) = undefined;
	var reflectivityTextures: main.List(Image) = undefined;
	var absorptionTextures: main.List(Image) = undefined;
	var textureFogData: main.List(FogData) = undefined;
	pub var textureOcclusionData: main.List(bool) = undefined;

	var arenaAllocatorForWorld: main.heap.NeverFailingArenaAllocator = undefined;
	var arenaForWorld: main.heap.NeverFailingAllocator = undefined;

	pub var blockBreakingTextures: main.List(u16) = undefined;

	const sideNames = blk: {
		var names: [6][]const u8 = undefined;
		names[Neighbor.dirDown.toInt()] = "texture_bottom";
		names[Neighbor.dirUp.toInt()] = "texture_top";
		names[Neighbor.dirPosX.toInt()] = "texture_right";
		names[Neighbor.dirNegX.toInt()] = "texture_left";
		names[Neighbor.dirPosY.toInt()] = "texture_front";
		names[Neighbor.dirNegY.toInt()] = "texture_back";
		break :blk names;
	};

	var animationSSBO: ?SSBO = null;
	var animatedTextureSSBO: ?SSBO = null;
	var fogSSBO: ?SSBO = null;

	var animationComputePipeline: graphics.ComputePipeline = undefined;
	var animationUniforms: struct {
		time: c_int,
		size: c_int,
	} = undefined;

	pub var blockTextureArray: TextureArray = undefined;
	pub var emissionTextureArray: TextureArray = undefined;
	pub var reflectivityAndAbsorptionTextureArray: TextureArray = undefined;
	pub var ditherTexture: graphics.Texture = undefined;

	const black: Color = Color{.r = 0, .g = 0, .b = 0, .a = 255};
	const magenta: Color = Color{.r = 255, .g = 0, .b = 255, .a = 255};
	var undefinedTexture = [_]Color{magenta, black, black, magenta};
	const undefinedImage = Image{.width = 2, .height = 2, .imageData = undefinedTexture[0..]};
	var emptyTexture = [_]Color{black};
	const emptyImage = Image{.width = 1, .height = 1, .imageData = emptyTexture[0..]};

	pub fn init() void {
		animationComputePipeline = graphics.ComputePipeline.init("assets/cubyz/shaders/animation_pre_processing.comp", "", &animationUniforms);
		blockTextureArray = .init();
		emissionTextureArray = .init();
		reflectivityAndAbsorptionTextureArray = .init();
		ditherTexture = .initFromMipmapFiles("assets/cubyz/blocks/textures/dither/", 64, 0.5);
		textureIDs = .init(main.globalAllocator);
		animation = .init(main.globalAllocator);
		blockTextures = .init(main.globalAllocator);
		emissionTextures = .init(main.globalAllocator);
		reflectivityTextures = .init(main.globalAllocator);
		absorptionTextures = .init(main.globalAllocator);
		textureFogData = .init(main.globalAllocator);
		textureOcclusionData = .init(main.globalAllocator);
		arenaAllocatorForWorld = .init(main.globalAllocator);
		arenaForWorld = arenaAllocatorForWorld.allocator();
		blockBreakingTextures = .init(main.globalAllocator);
	}

	pub fn deinit() void {
		if(animationSSBO) |ssbo| {
			ssbo.deinit();
		}
		if(animatedTextureSSBO) |ssbo| {
			ssbo.deinit();
		}
		if(fogSSBO) |ssbo| {
			ssbo.deinit();
		}
		animationComputePipeline.deinit();
		blockTextureArray.deinit();
		emissionTextureArray.deinit();
		reflectivityAndAbsorptionTextureArray.deinit();
		ditherTexture.deinit();
		textureIDs.deinit();
		animation.deinit();
		blockTextures.deinit();
		emissionTextures.deinit();
		reflectivityTextures.deinit();
		absorptionTextures.deinit();
		textureFogData.deinit();
		textureOcclusionData.deinit();
		arenaAllocatorForWorld.deinit();
		blockBreakingTextures.deinit();
	}

	pub fn reset() void {
		meshes.size = 0;
		loadedMeshes = 0;
		textureIDs.clearRetainingCapacity();
		animation.clearRetainingCapacity();
		blockTextures.clearRetainingCapacity();
		emissionTextures.clearRetainingCapacity();
		reflectivityTextures.clearRetainingCapacity();
		absorptionTextures.clearRetainingCapacity();
		textureFogData.clearRetainingCapacity();
		textureOcclusionData.clearRetainingCapacity();
		blockBreakingTextures.clearRetainingCapacity();
		_ = arenaAllocatorForWorld.reset(.free_all);
	}

	pub inline fn model(block: Block) ModelIndex {
		return block.mode().model(block);
	}

	pub inline fn modelIndexStart(block: Block) ModelIndex {
		return _modelIndex[block.typ];
	}

	pub inline fn fogDensity(block: Block) f32 {
		return textureFogData.items[animation.items[textureIndices[block.typ][0]].startFrame].fogDensity;
	}

	pub inline fn fogColor(block: Block) u32 {
		return textureFogData.items[animation.items[textureIndices[block.typ][0]].startFrame].fogColor;
	}

	pub inline fn hasFog(block: Block) bool {
		return fogDensity(block) != 0.0;
	}

	pub inline fn textureIndex(block: Block, orientation: usize) u16 {
		if(orientation < 16) {
			return textureIndices[block.typ][orientation];
		} else {
			return textureIndices[block.data][orientation - 16];
		}
	}

	fn extendedPath(_allocator: main.heap.NeverFailingAllocator, path: []const u8, ending: []const u8) []const u8 {
		return std.fmt.allocPrint(_allocator.allocator, "{s}{s}", .{path, ending}) catch unreachable;
	}

	fn readTextureFile(_path: []const u8, ending: []const u8, default: Image) Image {
		const path = extendedPath(main.stackAllocator, _path, ending);
		defer main.stackAllocator.free(path);
		return Image.readFromFile(arenaForWorld, path) catch default;
	}

	fn extractAnimationSlice(image: Image, frame: usize, frames: usize) Image {
		if(image.height < frames) return image;
		var startHeight = image.height/frames*frame;
		if(image.height%frames > frame) startHeight += frame else startHeight += image.height%frames;
		var endHeight = image.height/frames*(frame + 1);
		if(image.height%frames > frame + 1) endHeight += frame + 1 else endHeight += image.height%frames;
		var result = image;
		result.height = @intCast(endHeight - startHeight);
		result.imageData = result.imageData[startHeight*image.width .. endHeight*image.width];
		return result;
	}

	fn readTextureData(_path: []const u8) void {
		const path = _path[0 .. _path.len - ".png".len];
		const textureInfoPath = extendedPath(main.stackAllocator, path, ".zig.zon");
		defer main.stackAllocator.free(textureInfoPath);
		const textureInfoZon = main.files.cwd().readToZon(main.stackAllocator, textureInfoPath) catch .null;
		defer textureInfoZon.deinit(main.stackAllocator);
		const animationFrames = textureInfoZon.get(u32, "frames", 1);
		const animationTime = textureInfoZon.get(u32, "time", 1);
		animation.append(.{.startFrame = @intCast(blockTextures.items.len), .frames = animationFrames, .time = animationTime});
		const base = readTextureFile(path, ".png", Image.defaultImage);
		const emission = readTextureFile(path, "_emission.png", Image.emptyImage);
		const reflectivity = readTextureFile(path, "_reflectivity.png", Image.emptyImage);
		const absorption = readTextureFile(path, "_absorption.png", Image.whiteEmptyImage);
		for(0..animationFrames) |i| {
			blockTextures.append(extractAnimationSlice(base, i, animationFrames));
			emissionTextures.append(extractAnimationSlice(emission, i, animationFrames));
			reflectivityTextures.append(extractAnimationSlice(reflectivity, i, animationFrames));
			absorptionTextures.append(extractAnimationSlice(absorption, i, animationFrames));
			textureFogData.append(.{
				.fogDensity = textureInfoZon.get(f32, "fogDensity", 0.0),
				.fogColor = textureInfoZon.get(u32, "fogColor", 0xffffff),
			});
		}
		textureOcclusionData.append(textureInfoZon.get(bool, "hasOcclusion", true));
	}

	pub fn readTexture(_textureId: ?[]const u8, assetFolder: []const u8) !u16 {
		const textureId = _textureId orelse return error.NotFound;
		var result: u16 = undefined;
		var splitter = std.mem.splitScalar(u8, textureId, ':');
		const mod = splitter.first();
		const id = splitter.rest();
		var path = try std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{s}/blocks/textures/{s}.png", .{assetFolder, mod, id});
		defer main.stackAllocator.free(path);
		// Test if it's already in the list:
		for(textureIDs.items, 0..) |other, j| {
			if(std.mem.eql(u8, other, path)) {
				result = @intCast(j);
				return result;
			}
		}
		const file = main.files.cwd().openFile(path) catch |err| blk: {
			if(err != error.FileNotFound) {
				std.log.err("Could not open file {s}: {s}", .{path, @errorName(err)});
			}
			main.stackAllocator.free(path);
			path = try std.fmt.allocPrint(main.stackAllocator.allocator, "assets/{s}/blocks/textures/{s}.png", .{mod, id}); // Default to global assets.
			break :blk main.files.cwd().openFile(path) catch |err2| {
				std.log.err("File not found. Searched in \"{s}\" and also in the assetFolder \"{s}\"", .{path, assetFolder});
				return err2;
			};
		};
		file.close(); // It was only openend to check if it exists.
		// Otherwise read it into the list:
		result = @intCast(textureIDs.items.len);

		textureIDs.append(arenaForWorld.dupe(u8, path));
		readTextureData(path);
		return result;
	}

	pub fn getTextureIndices(zon: ZonElement, assetFolder: []const u8, textureIndicesRef: *[16]u16) void {
		const defaultIndex = readTexture(zon.get(?[]const u8, "texture", null), assetFolder) catch 0;
		inline for(textureIndicesRef, 0..) |*ref, i| {
			var textureId = zon.get(?[]const u8, std.fmt.comptimePrint("texture{}", .{i}), null);
			if(i < sideNames.len) {
				textureId = zon.get(?[]const u8, sideNames[i], textureId);
			}
			ref.* = readTexture(textureId, assetFolder) catch defaultIndex;
		}
	}

	pub fn register(assetFolder: []const u8, _: []const u8, zon: ZonElement) void {
		_modelIndex[meshes.size] = BlockProps.mode[meshes.size].createBlockModel(.{.typ = @intCast(meshes.size), .data = 0}, &BlockProps.modeData[meshes.size], zon.getChild("model"));

		// The actual model is loaded later, in the rendering thread.
		// But textures can be loaded here:

		getTextureIndices(zon, assetFolder, &textureIndices[meshes.size]);

		maxTextureCount[meshes.size] = @intCast(textureIDs.items.len);

		meshes.size += 1;
	}

	pub fn registerBlockBreakingAnimation(assetFolder: []const u8) void {
		var i: usize = 0;
		while(true) : (i += 1) {
			const path1 = std.fmt.allocPrint(main.stackAllocator.allocator, "assets/cubyz/blocks/textures/breaking/{}.png", .{i}) catch unreachable;
			defer main.stackAllocator.free(path1);
			const path2 = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/cubyz/blocks/textures/breaking/{}.png", .{assetFolder, i}) catch unreachable;
			defer main.stackAllocator.free(path2);
			if(!main.files.cwd().hasFile(path1) and !main.files.cwd().hasFile(path2)) break;

			const id = std.fmt.allocPrint(main.stackAllocator.allocator, "cubyz:breaking/{}", .{i}) catch unreachable;
			defer main.stackAllocator.free(id);
			blockBreakingTextures.append(readTexture(id, assetFolder) catch break);
		}
	}

	pub fn preProcessAnimationData(time: u32) void {
		animationComputePipeline.bind();
		graphics.c.glUniform1ui(animationUniforms.time, time);
		graphics.c.glUniform1ui(animationUniforms.size, @intCast(animation.items.len));
		graphics.c.glDispatchCompute(@intCast(@divFloor(animation.items.len + 63, 64)), 1, 1); // TODO: Replace with @divCeil once available
		graphics.c.glMemoryBarrier(graphics.c.GL_SHADER_STORAGE_BARRIER_BIT);
	}

	pub fn reloadTextures(_: usize) void {
		blockTextures.clearRetainingCapacity();
		emissionTextures.clearRetainingCapacity();
		reflectivityTextures.clearRetainingCapacity();
		absorptionTextures.clearRetainingCapacity();
		textureFogData.clearAndFree();
		textureOcclusionData.clearAndFree();
		for(textureIDs.items) |path| {
			readTextureData(path);
		}
		generateTextureArray();
	}

	pub fn generateTextureArray() void {
		const c = graphics.c;
		blockTextureArray.generate(blockTextures.items, true, true);
		c.glTexParameterf(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MAX_ANISOTROPY, @floatFromInt(main.settings.anisotropicFiltering));
		emissionTextureArray.generate(emissionTextures.items, true, false);
		c.glTexParameterf(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MAX_ANISOTROPY, @floatFromInt(main.settings.anisotropicFiltering));
		const reflectivityAndAbsorptionTextures = main.stackAllocator.alloc(Image, reflectivityTextures.items.len);
		defer main.stackAllocator.free(reflectivityAndAbsorptionTextures);
		defer for(reflectivityAndAbsorptionTextures) |texture| {
			texture.deinit(main.stackAllocator);
		};
		for(reflectivityTextures.items, absorptionTextures.items, reflectivityAndAbsorptionTextures) |reflecitivityTexture, absorptionTexture, *resultTexture| {
			const width = @max(reflecitivityTexture.width, absorptionTexture.width);
			const height = @max(reflecitivityTexture.height, absorptionTexture.height);
			resultTexture.* = Image.init(main.stackAllocator, width, height);
			for(0..width) |x| {
				for(0..height) |y| {
					const reflectivity = reflecitivityTexture.getRGB(x*reflecitivityTexture.width/width, y*reflecitivityTexture.height/height);
					const absorption = absorptionTexture.getRGB(x*absorptionTexture.width/width, y*absorptionTexture.height/height);
					resultTexture.setRGB(x, y, .{.r = absorption.r, .g = absorption.g, .b = absorption.b, .a = reflectivity.r});
				}
			}
		}
		reflectivityAndAbsorptionTextureArray.generate(reflectivityAndAbsorptionTextures, true, false);
		c.glTexParameterf(c.GL_TEXTURE_2D_ARRAY, c.GL_TEXTURE_MAX_ANISOTROPY, @floatFromInt(main.settings.anisotropicFiltering));

		// Also generate additional buffers:
		if(animationSSBO) |ssbo| {
			ssbo.deinit();
		}
		if(animatedTextureSSBO) |ssbo| {
			ssbo.deinit();
		}
		if(fogSSBO) |ssbo| {
			ssbo.deinit();
		}
		animationSSBO = SSBO.initStatic(AnimationData, animation.items);
		animationSSBO.?.bind(0);

		animatedTextureSSBO = SSBO.initStaticSize(u32, animation.items.len);
		animatedTextureSSBO.?.bind(1);
		fogSSBO = SSBO.initStatic(FogData, textureFogData.items);
		fogSSBO.?.bind(7);
	}
};
