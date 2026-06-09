const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const Assets = main.assets.Assets;

pub const AccessorySlot = struct {
	id: []const u8,
	count: u32,
	positionHint: u32,
	image: ?main.graphics.Image,
	texture: ?main.graphics.Texture,

	pub fn init(assetFolder: []const u8, id: []const u8, zon: ZonElement) AccessorySlot {
		var self: AccessorySlot = .{
			.id = id,
			.count = zon.get(u32, "count", 1),
			.positionHint = zon.get(u32, "position_hint", std.math.maxInt(u32)),
			.image = null,
			.texture = null,
		};

		if (zon.get(?[]const u8, "texture", null)) |texture| {
			var split = std.mem.splitScalar(u8, id, ':');
			const mod = split.first();
			var texturePath: []const u8 = &.{};
			defer main.stackAllocator.free(texturePath);
			var replacementTexturePath: []const u8 = &.{};
			defer main.stackAllocator.free(replacementTexturePath);
			texturePath = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{s}/accessory_slots/textures/{s}", .{assetFolder, mod, texture}) catch unreachable;
			replacementTexturePath = std.fmt.allocPrint(main.stackAllocator.allocator, "assets/{s}/accessory_slots/textures/{s}", .{mod, texture}) catch unreachable;

			self.image = main.graphics.Image.readFromFile(main.worldArena, texturePath) catch main.graphics.Image.readFromFile(main.worldArena, replacementTexturePath) catch blk: {
				std.log.err("Accessory texture not found in {s} and {s}.", .{texturePath, replacementTexturePath});
				break :blk null;
			};
		}
		return self;
	}
	pub fn getTexture(self: *AccessorySlot) ?main.graphics.Texture {
		if (self.texture) |texture| {
			return texture;
		} else if (self.image) |img| {
			self.texture = main.graphics.Texture.init();
			self.texture.?.generate(img);
			return self.texture.?;
		} else {
			return null;
		}
	}
	pub fn deinit(self: AccessorySlot) void {
		if (self.texture) |tex| {
			tex.deinit();
		}
	}
};

var accessorySlots: main.ListUnmanaged(AccessorySlot) = .{};
var accessorySlotsById: std.StringHashMapUnmanaged(*AccessorySlot) = .{};
var totalSlotCount: u32 = 0;

fn register(assetFolder: []const u8, id: []const u8, zon: ZonElement) void {
	const accessorySlot = AccessorySlot.init(assetFolder, id, zon);
	accessorySlots.append(main.worldArena, accessorySlot);
	totalSlotCount += accessorySlot.count;
	std.log.debug("Registered accessory slot: {s}", .{accessorySlot.id});
}

pub fn registerAccessorySlots(assetFolder: []const u8, accessorySlotMap: *const Assets.ZonHashMap) void {
	var iterator = accessorySlotMap.iterator();
	while (iterator.next()) |entry| {
		register(assetFolder, entry.key_ptr.*, entry.value_ptr.*);
	}
	std.mem.sort(AccessorySlot, accessorySlots.items, {}, lessThan);
	for (accessorySlots.items) |*accessorySlot| {
		accessorySlotsById.put(main.worldArena.allocator, accessorySlot.id, accessorySlot) catch unreachable;
	}
}

fn lessThan(_: void, lhs: AccessorySlot, rhs: AccessorySlot) bool {
	if (lhs.positionHint < rhs.positionHint) return true;
	if (lhs.positionHint > rhs.positionHint) return false;
	return std.ascii.orderIgnoreCase(lhs.id, rhs.id) == .gt;
}

pub fn getAccessorySlots() []AccessorySlot {
	return accessorySlots.items;
}

pub fn getById(id: []const u8) ?*AccessorySlot {
	return accessorySlotsById.get(id);
}

pub fn getByIndex(index: u32) *AccessorySlot {
	return &accessorySlots.items[index];
}

pub fn getTotalSlotCount() u32 {
	return totalSlotCount;
}

pub fn reset() void {
	for (accessorySlots.items) |slot| {
		slot.deinit();
	}
	accessorySlots = .{};
	accessorySlotsById = .{};
	totalSlotCount = 0;
}
