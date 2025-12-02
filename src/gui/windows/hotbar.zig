const std = @import("std");

const main = @import("main");
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

pub var window = GuiWindow{
	.relativePosition = .{
		.{.attachedToFrame = .{.selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle}},
		.{.attachedToFrame = .{.selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper}},
	},
	.contentSize = Vec2f{64*12, 64},
	.isHud = true,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
	.closeable = false,
	.scale = 0.75,
};

var hotbarSlotTexture: Texture = undefined;

pub fn init() void {
	hotbarSlotTexture = Texture.initFromFile("assets/cubyz/ui/inventory/hotbar_slot.png");
}

pub fn deinit() void {
	hotbarSlotTexture.deinit();
}

var itemSlots: [12]*ItemSlot = undefined;

pub fn onOpen() void {
	const list = HorizontalList.init();
	for(0..12) |i| {
		itemSlots[i] = ItemSlot.init(.{0, 0}, Player.hotbar, @intCast(i), .{.custom = hotbarSlotTexture}, .normal);
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
	itemSlots[Player.selectedSlot].hovered = true;
}
