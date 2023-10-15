const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Player = main.game.Player;
const ItemStack = main.items.ItemStack;
const Vec2f = main.vec.Vec2f;
const Texture = main.graphics.Texture;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = GuiComponent.Button;
const HorizontalList = GuiComponent.HorizontalList;
const VerticalList = GuiComponent.VerticalList;
const ItemSlot = GuiComponent.ItemSlot;

const hotbar = @import("hotbar.zig");

pub var window = GuiWindow {
	.relativePosition = .{
		.{ .attachedToWindow = .{.reference = &hotbar.window, .selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle} },
		.{ .attachedToWindow = .{.reference = &hotbar.window, .selfAttachmentPoint = .upper, .otherAttachmentPoint = .lower} },
	},
	.contentSize = Vec2f{64*8, 64*4},
	.id = "inventory",
};

const padding: f32 = 8;

var craftingIcon: Texture = undefined;

pub fn init() !void {
	craftingIcon = try Texture.initFromFile("assets/cubyz/ui/inventory/crafting_icon.png");
}

pub fn deinit() void {
	craftingIcon.deinit();
}

var itemSlots: [24]*ItemSlot = undefined;

pub fn tryAddingItems(index: usize, source: *ItemStack, amount: u16) void {
	Player.mutex.lock();
	defer Player.mutex.unlock();
	const destination = &Player.inventory__SEND_CHANGES_TO_SERVER.items[index];
	if(destination.item != null and !std.meta.eql(source.item, destination.item)) return;
	destination.item = source.item;
	const actual = destination.add(amount);
	source.amount -= actual;
	if(source.amount == 0) source.item = null;
	main.network.Protocols.genericUpdate.sendInventory_full(main.game.world.?.conn, Player.inventory__SEND_CHANGES_TO_SERVER) catch |err| { // TODO(post-java): Add better options to the protocol.
		std.log.err("Got error while trying to send inventory data: {s}", .{@errorName(err)});
	};
}

pub fn tryTakingItems(index: usize, destination: *ItemStack, _amount: u16) void {
	var amount = _amount;
	Player.mutex.lock();
	defer Player.mutex.unlock();
	const source = &Player.inventory__SEND_CHANGES_TO_SERVER.items[index];
	if(destination.item != null and !std.meta.eql(source.item, destination.item)) return;
	if(source.item == null) return;
	amount = @min(amount, source.amount);
	destination.item = source.item;
	const actual = destination.add(amount);
	source.amount -= actual;
	if(source.amount == 0) source.item = null;
	main.network.Protocols.genericUpdate.sendInventory_full(main.game.world.?.conn, Player.inventory__SEND_CHANGES_TO_SERVER) catch |err| { // TODO(post-java): Add better options to the protocol.
		std.log.err("Got error while trying to send inventory data: {s}", .{@errorName(err)});
	};
}

pub fn trySwappingItems(index: usize, source: *ItemStack) void {
	Player.mutex.lock();
	defer Player.mutex.unlock();
	const destination = &Player.inventory__SEND_CHANGES_TO_SERVER.items[index];
	const swap = destination.*;
	destination.* = source.*;
	source.* = swap;
	main.network.Protocols.genericUpdate.sendInventory_full(main.game.world.?.conn, Player.inventory__SEND_CHANGES_TO_SERVER) catch |err| { // TODO(post-java): Add better options to the protocol.
		std.log.err("Got error while trying to send inventory data: {s}", .{@errorName(err)});
	};
}

const vtable = ItemSlot.VTable {
	.tryAddingItems = &tryAddingItems,
	.tryTakingItems = &tryTakingItems,
	.trySwappingItems = &trySwappingItems,
};

pub fn onOpen() Allocator.Error!void {
	var list = try VerticalList.init(.{padding, padding + 16}, 300, 0);
	// Some miscellanious slots and buttons:
	// TODO: armor slots, backpack slot + stack-based backpack inventory, other items maybe?
	{
		var row = try HorizontalList.init();
		try row.add(try Button.initIcon(.{0, 0}, .{24, 24}, craftingIcon, true, gui.openWindowCallback("inventory_crafting")));
		try list.add(row);
	}
	// Inventory:
	for(1..4) |y| {
		var row = try HorizontalList.init();
		for(0..8) |x| {
			var index: usize = y*8 + x;
			const slot = try ItemSlot.init(.{0, 0}, Player.inventory__SEND_CHANGES_TO_SERVER.items[index], &vtable, index);
			itemSlots[index - 8] = slot;
			try row.add(slot);
		}
		try list.add(row);
	}
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}

pub fn update() Allocator.Error!void {
	Player.mutex.lock();
	defer Player.mutex.unlock();
	for(&itemSlots, 8..) |slot, i| {
		try slot.updateItemStack(Player.inventory__SEND_CHANGES_TO_SERVER.items[i]);
	}
}