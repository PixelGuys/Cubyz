const std = @import("std");

const main = @import("main");
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

pub var window = GuiWindow{
	.relativePosition = .{
		.{.attachedToWindow = .{.reference = &hotbar.window, .selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle}},
		.{.attachedToWindow = .{.reference = &hotbar.window, .selfAttachmentPoint = .upper, .otherAttachmentPoint = .lower}},
	},
	.contentSize = Vec2f{64*10, 64*3},
	.scale = 0.75,
	.isHud = true,
	.closeable = false,
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

pub fn onOpen() void {
	const rootComponent = VerticalList.init(.{padding, padding + 16}, 300, 0);
	// Some miscellanious slots and buttons:
	// TODO: armor slots, backpack slot + stack-based backpack inventory, other items maybe?
	{
		const row = HorizontalList.init();
		row.add(Button.initIcon(.{32, 0}, .{32, 32}, craftingIcon, .{.onAction = gui.openWindowCallback("inventory_crafting")}));
		rootComponent.add(row);
	}

	const inventorySpace = HorizontalList.init();
	blk: {
		inventorySpace.add(GuiComponent.BagSlot.init(.{0, 0}, main.entity.components.@"cubyz:bag".client.getBag(main.game.Player.id) orelse break :blk));
	}

	const inventoryGrid = VerticalList.init(.{0, 0}, 200, 0);
	makeInventoryGrid(inventoryGrid);

	inventorySpace.add(inventoryGrid);
	rootComponent.add(inventorySpace);

	rootComponent.finish(.center);
	window.rootComponent = rootComponent.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

fn makeInventoryGrid(parent: *VerticalList) void {
	for (0..2) |y| {
		const row = HorizontalList.init();
		for (0..10) |x| {
			const index: usize = 12 + y*10 + x;
			const slot = ItemSlot.init(.{0, 0}, Player.inventory, @intCast(index), .default, .normal);
			itemSlots[index - 12] = slot;
			row.add(slot);
		}
		parent.add(row);
	}
}

pub fn onClose() void {
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
