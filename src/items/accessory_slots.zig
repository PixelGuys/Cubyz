const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const Assets = main.assets.Assets;

pub const AccessorySlot = struct {
	id: []const u8,
	count: u32,

	pub fn init(id: []const u8, zon: ZonElement) AccessorySlot {
		return .{
			.id = id,
			.count = zon.get(u32, "count", 1),
		};
	}
};

var accessorySlots: main.ListUnmanaged(AccessorySlot) = .{};
var accessorySlotsById: std.StringHashMapUnmanaged(*AccessorySlot) = .{};
var totalSlotCount: u32 = 0;

fn register(id: []const u8, zon: ZonElement) void {
	const accessorySlot = AccessorySlot.init(id, zon);
	accessorySlots.append(main.worldArena, accessorySlot);
	const slotPtr = &accessorySlots.items[accessorySlots.items.len - 1];
	accessorySlotsById.put(main.worldArena.allocator, slotPtr.id, slotPtr) catch unreachable;
	totalSlotCount += slotPtr.count;
	std.log.debug("Registered accessory slot: {s}", .{slotPtr.id});
}

pub fn registerAccessorySlots(accessorySlotMap: *const Assets.ZonHashMap) void {
	var iterator = accessorySlotMap.iterator();
	while (iterator.next()) |entry| {
		register(entry.key_ptr.*, entry.value_ptr.*);
	}
}

pub fn getAccessorySlots() []const AccessorySlot {
	return accessorySlots.items;
}

pub fn getById(id: []const u8) ?*AccessorySlot {
	return accessorySlotsById.get(id);
}

pub fn getByIndex(index: u32) ?*AccessorySlot {
	return accessorySlots.items[index];
}

pub fn getTotalSlotCount() u32 {
	return totalSlotCount;
}

pub fn reset() void {
	accessorySlotsById = .{};
	totalSlotCount = 0;
}
