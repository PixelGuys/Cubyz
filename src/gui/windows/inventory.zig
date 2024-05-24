const std = @import("std");

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
	.contentSize = Vec2f{64*10, 64*3},
	.scale = 0.75,
};

const padding: f32 = 8;

var craftingIcon: Texture = undefined;

pub fn init() void {
	craftingIcon = Texture.initFromFile("assets/cubyz/ui/inventory/crafting_icon.png");
}

pub fn deinit() void {
	craftingIcon.deinit();
}

var itemSlots: [20]*ItemSlot = undefined;

pub fn tryAddingItems(index: usize, source: *ItemStack, desiredAmount: u16) void {
	Player.mutex.lock();
	defer Player.mutex.unlock();
	const destination = &Player.inventory__SEND_CHANGES_TO_SERVER.items[index];
	if(destination.item != null and !std.meta.eql(source.item, destination.item)) return;
	const actual = destination.add(source.item.?, desiredAmount);
	source.amount -= actual;
	if(source.amount == 0) source.item = null;
	main.network.Protocols.genericUpdate.sendInventory_full(main.game.world.?.conn, Player.inventory__SEND_CHANGES_TO_SERVER); // TODO(post-java): Add better options to the protocol.
}

pub fn tryTakingItems(index: usize, destination: *ItemStack, desiredAmount: u16) void {
	var amount = desiredAmount;
	Player.mutex.lock();
	defer Player.mutex.unlock();
	const source = &Player.inventory__SEND_CHANGES_TO_SERVER.items[index];
	if(destination.item != null and !std.meta.eql(source.item, destination.item)) return;
	if(source.item == null) return;
	amount = @min(amount, source.amount);
	const actual = destination.add(source.item.?, amount);
	source.amount -= actual;
	if(source.amount == 0) source.item = null;
	main.network.Protocols.genericUpdate.sendInventory_full(main.game.world.?.conn, Player.inventory__SEND_CHANGES_TO_SERVER); // TODO(post-java): Add better options to the protocol.
}

pub fn trySwappingItems(index: usize, source: *ItemStack) void {
	Player.mutex.lock();
	defer Player.mutex.unlock();
	const destination = &Player.inventory__SEND_CHANGES_TO_SERVER.items[index];
	const swap = destination.*;
	destination.* = source.*;
	source.* = swap;
	main.network.Protocols.genericUpdate.sendInventory_full(main.game.world.?.conn, Player.inventory__SEND_CHANGES_TO_SERVER); // TODO(post-java): Add better options to the protocol.
}

const vtable = ItemSlot.VTable {
	.tryAddingItems = &tryAddingItems,
	.tryTakingItems = &tryTakingItems,
	.trySwappingItems = &trySwappingItems,
};

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, padding + 16}, 300, 0);
	// Some miscellanious slots and buttons:
	// TODO: armor slots, backpack slot + stack-based backpack inventory, other items maybe?
	{
		const row = HorizontalList.init();
		row.add(Button.initIcon(.{0, 0}, .{32, 32}, craftingIcon, true, gui.openWindowCallback("inventory_crafting")));
		list.add(row);
	}
	for(0..2) |y| {
		const row = HorizontalList.init();
		for(0..10) |x| {
			const index: usize = 12 + y*10 + x;
			const slot = ItemSlot.init(.{0, 0}, Player.inventory__SEND_CHANGES_TO_SERVER.items[index], &vtable, index, .default, .normal);
			itemSlots[index - 12] = slot;
			row.add(slot);
		}
		list.add(row);
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

pub fn update() void {
	Player.mutex.lock();
	defer Player.mutex.unlock();
	for(&itemSlots, 12..) |slot, i| {
		slot.updateItemStack(Player.inventory__SEND_CHANGES_TO_SERVER.items[i]);
	}
}