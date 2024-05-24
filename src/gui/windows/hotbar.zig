const std = @import("std");

const main = @import("root");
const ItemStack = main.items.ItemStack;
const Player = main.game.Player;
const Vec2f = main.vec.Vec2f;
const Texture = main.graphics.Texture;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const HorizontalList = GuiComponent.HorizontalList;
const ItemSlot = GuiComponent.ItemSlot;
const Icon = GuiComponent.Icon;

pub var window = GuiWindow {
	.relativePosition = .{
		.{ .attachedToFrame = .{.selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle} },
		.{ .attachedToFrame = .{.selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper} },
	},
	.contentSize = Vec2f{64*12, 64},
	.isHud = true,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
	.scale = 0.75,
};

var itemSlots: [12]*ItemSlot = undefined;

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
	const list = HorizontalList.init();
	for(0..12) |i| {
		itemSlots[i] = ItemSlot.init(.{0, 0}, Player.inventory__SEND_CHANGES_TO_SERVER.items[i], &vtable, i, .default, .normal);
		list.add(itemSlots[i]);
	}
	list.finish(.{0, 0}, .center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.size();
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
	for(&itemSlots, 0..) |slot, i| {
		slot.updateItemStack(Player.inventory__SEND_CHANGES_TO_SERVER.items[i]);
	}
	itemSlots[Player.selectedSlot].hovered = true;
}