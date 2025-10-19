const std = @import("std");

const main = @import("main");
const Tag = main.Tag;
const items = @import("../items.zig");
const utils = main.utils;
const chunk = @import("../chunk.zig");
const Neighbor = chunk.Neighbor;
const Chunk = chunk.Chunk;
const Entity = main.server.Entity;
const rotation = @import("../rotation.zig");
const RotationMode = rotation.RotationMode;
const Degrees = rotation.Degrees;
const block_entity = @import("block_entity.zig");
const BlockEntityType = block_entity.BlockEntityType;
const ZonElement = @import("../zon.zig").ZonElement;

pub const BlockDrop = struct {
	items: []const items.ItemStack,
	chance: f32,
};

// MARK: Tick
pub var tickFunctions: utils.NamedCallbacks(TickFunctions, TickFunction) = undefined;
pub const TickFunction = fn(block: Block, _chunk: *chunk.ServerChunk, x: i32, y: i32, z: i32) void;
pub const TickFunctions = struct { };

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
		return BlockProps.sortedAllowOres.get(self.typ);
	}

	/// GUI that is opened on click.
	pub inline fn gui(self: Block) []u8 {
		return BlockProps.sortedGui.get(self.typ) orelse "";
	}

	pub inline fn tickEvent(self: Block) ?TickEvent {
		return BlockProps.sortedTickEvent.get(self.typ);
	}

	pub inline fn touchFunction(self: Block) ?*const TouchFunction {
		return BlockProps.sortedTouchFunction.get(self.typ);
	}

	pub fn blockEntity(self: Block) ?*BlockEntityType {
		return BlockProps.sortedBlockEntity.get(self.typ);
	}

	pub fn canBeChangedInto(self: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) main.rotation.RotationMode.CanBeChangedInto {
		return newBlock.mode().canBeChangedInto(self, newBlock, item, shouldDropSourceBlockOnSuccess);
	}
};

// MARK: Sorted Block Properties
fn SortedBlockProperties(comptime sortedBlockSize: usize, comptime DataType: type) type {
	const Cmp = struct {
		fn less(target: u32, candidate: u32) std.math.Order {
			if(target == candidate) return .eq;
			if(target < candidate) return .lt;
			return .gt;
		}
	};

	// if the block id is in the array, then the property value is true, otherwise false.
	if(DataType == bool) {
		return struct {
			const Self = @This();

			allocatedSize: usize = 0,
			idxLookup: [sortedBlockSize]u32 = undefined,

			pub fn get(self: *const Self, blockId: u32) bool {
				const slice = self.idxLookup[0..self.allocatedSize];

				_ = std.sort.binarySearch(
					u32,
					slice,
					blockId,
					Cmp.less,
				) orelse return false;

				return true;
			}

			pub fn add(self: *Self, blockId: u32, propVal: bool) void {
				if(propVal == false) {
					return;
				}

				if(self.allocatedSize + 1 > sortedBlockSize) {
					@panic("Failed to add block property. Consider increasing the size of the array");
				}

				const slice = self.idxLookup[0..self.allocatedSize];

				const insertIdx = std.sort.lowerBound(u32, slice, blockId, Cmp.less);

				std.mem.copyBackwards(u32, self.idxLookup[(insertIdx + 1) .. self.allocatedSize + 1], self.idxLookup[insertIdx..self.allocatedSize]);

				self.idxLookup[insertIdx] = blockId;

				self.allocatedSize += 1;
			}

			pub fn clear(self: *Self) void {
				self.allocatedSize = 0;
			}
		};
	} else {
		return struct {
			const Self = @This();

			allocatedSize: usize = 0,
			idxLookup: [sortedBlockSize]u32 = undefined,
			data: [sortedBlockSize]DataType = undefined,

			fn compare(target: u32, candidate: u32) std.math.Order {
				if(target == candidate) return .eq;
				if(target < candidate) return .lt;
				return .gt;
			}

			fn getIdx(self: *const Self, blockId: u32) ?usize {
				const slice = self.idxLookup[0..self.allocatedSize];

				return std.sort.binarySearch(
					u32,
					slice,
					blockId,
					compare,
				);
			}

			pub fn get(self: *const Self, blockId: u32) ?DataType {
				const idx = getIdx(self, blockId) orelse return null;
				return self.data[idx];
			}

			pub fn add(self: *Self, blockId: u32, propVal: DataType) void {
				if(self.allocatedSize + 1 > sortedBlockSize) {
					@panic("Failed to add block property. Consider increasing the size of the array");
				}

				const slice = self.idxLookup[0..self.allocatedSize];

				const insertIdx = std.sort.lowerBound(u32, slice, blockId, compare);

				std.mem.copyBackwards(u32, self.idxLookup[(insertIdx + 1) .. self.allocatedSize + 1], self.idxLookup[insertIdx..self.allocatedSize]);

				std.mem.copyBackwards(DataType, self.data[(insertIdx + 1) .. self.allocatedSize + 1], self.data[insertIdx..self.allocatedSize]);

				self.idxLookup[insertIdx] = blockId;
				self.data[insertIdx] = propVal;

				self.allocatedSize += 1;
			}

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

pub fn resetSortedProperties() void {
	inline for(@typeInfo(BlockProps).@"struct".decls) |decl| {
		const sortedProp = &@field(BlockProps, decl.name);

		if(comptime isSortedProp(@TypeOf(sortedProp.*))) {
			std.log.info("Cleared \'{s}\' from {d} entries", .{decl.name, sortedProp.allocatedSize});
			sortedProp.clear();
		}
	}
}

pub const maxBlockCount: usize = 65536; // 16 bit limit

// Structure wrapper allows resetting sorted properies by fn resetSortedProperties()
pub const BlockProps = struct {
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
	/// with ~100-300 entries instead of creating arrays with maxBlockCount (65536) entries.
	/// Magic Value - Increase it if you need to store more block properties.
	/// Consider creating a separate variable with a comment for a specific property if only one needs a larger size.
	pub const maxSortedBlockProperties: usize = 100;

	pub var sortedAllowOres: SortedBlockProperties(maxSortedBlockProperties, bool) = .{};
	// TODO: Tick event is accessed like a milion times for no reason. FIX IT
	pub var sortedTickEvent: SortedBlockProperties(maxSortedBlockProperties, TickEvent) = .{};
	pub var sortedTouchFunction: SortedBlockProperties(maxSortedBlockProperties, *const TouchFunction) = .{};
	pub var sortedBlockEntity: SortedBlockProperties(maxSortedBlockProperties, *BlockEntityType) = .{};

	/// GUI that is opened on click.
	pub var sortedGui: SortedBlockProperties(maxSortedBlockProperties, []u8) = .{};
};