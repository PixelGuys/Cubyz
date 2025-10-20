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
const launchConfig = @import("../settings.zig").launchConfig;

pub const BlockDrop = struct {
    items: []const items.ItemStack,
    chance: f32,
};

// MARK: Tick
pub var tickFunctions: utils.NamedCallbacks(TickFunctions, TickFunction) = undefined;
pub const TickFunction = fn (block: Block, _chunk: *chunk.ServerChunk, x: i32, y: i32, z: i32) void;
pub const TickFunctions = struct {};

pub const TickEvent = struct {
    function: *const TickFunction,
    chance: f32,

    pub fn loadFromZon(zon: ZonElement) ?TickEvent {
        const functionName = zon.get(?[]const u8, "name", null) orelse return null;

        const function = tickFunctions.getFunctionPointer(functionName) orelse {
            std.log.err("Could not find TickFunction {s}.", .{functionName});
            return null;
        };

        return TickEvent{ .function = function, .chance = zon.get(f32, "chance", 1) };
    }

    pub fn tryRandomTick(self: *const TickEvent, block: Block, _chunk: *chunk.ServerChunk, x: i32, y: i32, z: i32) void {
        if (self.chance >= 1.0 or main.random.nextFloat(&main.seed) < self.chance) {
            self.function(block, _chunk, x, y, z);
        }
    }
};

// MARK: Touch
pub var touchFunctions: utils.NamedCallbacks(TouchFunctions, TouchFunction) = undefined;
pub const TouchFunction = fn (block: Block, entity: Entity, posX: i32, posY: i32, posZ: i32, isEntityInside: bool) void;
pub const TouchFunctions = struct {};

pub const Block = packed struct { // MARK: Block
    typ: u16,
    data: u16,

    pub const air = Block{ .typ = 0, .data = 0 };

    pub fn toInt(self: Block) u32 {
        return @as(u32, self.typ) | @as(u32, self.data) << 16;
    }
    pub fn fromInt(self: u32) Block {
        return Block{ .typ = @truncate(self), .data = @intCast(self >> 16) };
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
        return .{ .typ = self.typ, .data = self.mode().rotateZ(self.data, angle) };
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
fn SortedBlockProperties(comptime DataType: type) type {
    const panicMsg = "Out of memory when allocating Sorted Block Properties! Increase maxSortedBlockProperties in launchConfig.";

    const Cmp = struct {
        fn less(target: u32, candidate: u32) std.math.Order {
            if (target == candidate) return .eq;
            if (target < candidate) return .lt;
            return .gt;
        }
    };

    // if the block id is in the array, then the property value is true, otherwise false.
    if (DataType == bool) {
        return struct {
            const Self = @This();
            pub const __is_sorted_block_property = true;
            pub const __property_data_type = bool;

            idxLookup: std.ArrayList(u32) = undefined,

            // TODO: DEBUG - REMOVE LATER
            debugGetCount: u64 = 0,
            debugBinarySearchTime: u64 = 0,
            debugLinearSearchTime: u64 = 0,
            // END OF DEBUG

            pub fn init(allocator: std.mem.Allocator) Self {
                return .{
                    .idxLookup = std.ArrayList(u32).init(allocator),
                    // TODO: DEBUG - REMOVE LATER
                    .debugGetCount = 0,
                    .debugBinarySearchTime = 0,
                    .debugLinearSearchTime = 0,
                    // END OF DEBUG
                };
            }

            pub fn deinit(self: *Self) void {
                self.idxLookup.deinit();
            }

            pub fn get(self: *Self, blockId: u32) bool {
                // TODO: DEBUG - REMOVE LATER
                self.debugGetCount += 1;
                // END OF DEBUG

                const slice = self.idxLookup.items;

                // TODO: DEBUG - REMOVE LATER
                const binaryStart = std.time.nanoTimestamp();
                // END OF DEBUG

                const result = std.sort.binarySearch(
                    u32,
                    slice,
                    blockId,
                    Cmp.less,
                );

                // TODO: DEBUG - REMOVE LATER
                const binaryEnd = std.time.nanoTimestamp();
                self.debugBinarySearchTime += @intCast(binaryEnd - binaryStart);
                
                const linearStart = std.time.nanoTimestamp();
                _ = std.mem.indexOfScalar(u32, slice, blockId);
                const linearEnd = std.time.nanoTimestamp();
                self.debugLinearSearchTime += @intCast(linearEnd - linearStart);
                // END OF DEBUG

                return result != null;
            }

            pub fn add(self: *Self, blockId: u32, propVal: bool) void {
                if (propVal == false) return;

                const slice = self.idxLookup.items;
                const insertIdx = std.sort.lowerBound(
                    u32,
                    slice,
                    blockId,
                    Cmp.less,
                );

                self.idxLookup.insert(insertIdx, blockId) catch @panic(panicMsg);
            }

            pub fn clear(self: *Self) void {
                self.idxLookup.clearRetainingCapacity();
            }

            // TODO: DEBUG - REMOVE LATER
            pub fn resetDebugCounters(self: *Self) void {
                self.debugGetCount = 0;
                self.debugBinarySearchTime = 0;
                self.debugLinearSearchTime = 0;
            }
            // END OF DEBUG
        };
    } else {
        return struct {
            const Self = @This();
            pub const __is_sorted_block_property = true;
            pub const __property_data_type = DataType;

            idxLookup: std.ArrayList(u32) = undefined,
            data: std.ArrayList(DataType) = undefined,

            // TODO: DEBUG - REMOVE LATER
            debugGetCount: u64 = 0,
            debugBinarySearchTime: u64 = 0,
            debugLinearSearchTime: u64 = 0,
            // END OF DEBUG

            pub fn init(allocator: std.mem.Allocator) Self {
                return .{
                    .idxLookup = std.ArrayList(u32).init(allocator),
                    .data = std.ArrayList(DataType).init(allocator),
                    // TODO: DEBUG - REMOVE LATER
                    .debugGetCount = 0,
                    .debugBinarySearchTime = 0,
                    .debugLinearSearchTime = 0,
                    // END OF DEBUG
                };
            }

            pub fn deinit(self: *Self) void {
                self.idxLookup.deinit();
                self.data.deinit();
            }

            fn getIdx(self: *Self, blockId: u32) ?usize {
                const slice = self.idxLookup.items;

                // TODO: DEBUG - REMOVE LATER
                const binaryStart = std.time.nanoTimestamp();
                // END OF DEBUG

                const result = std.sort.binarySearch(
                    u32,
                    slice,
                    blockId,
                    Cmp.less,
                );

                // TODO: DEBUG - REMOVE LATER
                const binaryEnd = std.time.nanoTimestamp();
                self.debugBinarySearchTime += @intCast(binaryEnd - binaryStart);
                // END OF DEBUG

                return result;
            }

            pub fn get(self: *Self, blockId: u32) ?DataType {
                // TODO: DEBUG - REMOVE LATER
                self.debugGetCount += 1;
                const linearStart = std.time.nanoTimestamp();
                _ = std.mem.indexOfScalar(u32, self.idxLookup.items, blockId);
                const linearEnd = std.time.nanoTimestamp();
                self.debugLinearSearchTime += @intCast(linearEnd - linearStart);
                // END OF DEBUG

                const idx = self.getIdx(blockId) orelse return null;
                return self.data.items[idx];
            }

            pub fn add(self: *Self, blockId: u32, propVal: DataType) void {
                const slice = self.idxLookup.items;
                const insertIdx = std.sort.lowerBound(u32, slice, blockId, Cmp.less);
                
                self.idxLookup.insert(insertIdx, blockId) catch @panic(panicMsg);
                self.data.insert(insertIdx, propVal) catch @panic(panicMsg);
            }

            pub fn clear(self: *Self) void {
                self.idxLookup.clearRetainingCapacity();
                self.data.clearRetainingCapacity();
            }

            // TODO: DEBUG - REMOVE LATER
            pub fn resetDebugCounters(self: *Self) void {
                self.debugGetCount = 0;
                self.debugBinarySearchTime = 0;
                self.debugLinearSearchTime = 0;
            }
            // END OF DEBUG
        };
    }
}

fn isSortedProp(comptime T: type) bool {
    comptime if (@typeInfo(T) != .@"struct") return false;
    return @hasDecl(T, "__is_sorted_block_property");
}

pub fn resetSortedProperties() void {
    inline for (@typeInfo(BlockProps).@"struct".decls) |decl| {
        const sortedProp = &@field(BlockProps, decl.name);

        if (comptime isSortedProp(@TypeOf(sortedProp.*))) {
            std.log.info("Cleared \'{s}\' from {d} entries", .{ decl.name, sortedProp.idxLookup.items.len });
            sortedProp.clear();
        }
    }
}

pub fn initSortedProperties(comptime allocator: std.mem.Allocator) void {
    inline for (@typeInfo(BlockProps).@"struct".decls) |decl| {
        const sortedProp = &@field(BlockProps, decl.name);
        const sortedPropType = @TypeOf(sortedProp.*);

        if (comptime isSortedProp(sortedPropType)) {
            sortedProp.* = SortedBlockProperties(sortedPropType.__property_data_type).init(allocator);
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
    pub var sortedAllowOres: SortedBlockProperties(bool) = undefined;
    // TODO: Tick event is accessed like a milion times for no reason. FIX IT
    pub var sortedTickEvent: SortedBlockProperties(TickEvent) = undefined;
    pub var sortedTouchFunction: SortedBlockProperties(*const TouchFunction) = undefined;
    pub var sortedBlockEntity: SortedBlockProperties(*BlockEntityType) = undefined;

    /// GUI that is opened on click.
    pub var sortedGui: SortedBlockProperties([]u8) = undefined;
};

// TODO: DEBUG - REMOVE LATER
pub fn debugSortedBlockProperties() void {
    std.log.info("=== SortedBlockProperties Performance Report ===", .{});
    
    inline for (@typeInfo(BlockProps).@"struct".decls) |decl| {
        const sortedProp = &@field(BlockProps, decl.name);
        const sortedPropType = @TypeOf(sortedProp.*);

        if (comptime isSortedProp(sortedPropType)) {
            const getCount = sortedProp.debugGetCount;
            const binarySearchTimeNs = sortedProp.debugBinarySearchTime;
            const linearSearchTimeNs = sortedProp.debugLinearSearchTime;
            
            const binarySearchTimeMs = @as(f64, @floatFromInt(binarySearchTimeNs)) / 1_000_000.0;
            const linearSearchTimeMs = @as(f64, @floatFromInt(linearSearchTimeNs)) / 1_000_000.0;
            
            std.log.info("Property: {s} | Num of entries: {d}", .{decl.name, sortedProp.idxLookup.items.len});
            std.log.info("  get() calls: {d}", .{getCount});
            std.log.info("  Binary search time: {d:.3}ms", .{binarySearchTimeMs});
            std.log.info("  Linear search time (alternative): {d:.3}ms", .{linearSearchTimeMs});
            
            if (linearSearchTimeMs > 0) {
                const speedup = linearSearchTimeMs / binarySearchTimeMs;
                std.log.info("  Speedup: {d:.2}x", .{speedup});
            }
            
            sortedProp.resetDebugCounters();
        }
    }
    
    std.log.info("==============================================", .{});
}
    // END OF DEBUG