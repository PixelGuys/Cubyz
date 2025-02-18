const std = @import("std");

const main = @import("root");
const items = main.items;
const BaseItem = items.BaseItem;
const Inventory = items.Inventory;
const Item = items.Item;
const Tool = items.Tool;
const Player = main.game.Player;
const Texture = main.graphics.Texture;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = GuiComponent.Button;
const HorizontalList = GuiComponent.HorizontalList;
const VerticalList = GuiComponent.VerticalList;
const Icon = GuiComponent.Icon;
const ItemSlot = GuiComponent.ItemSlot;

const inventory = @import("inventory.zig");
const inventory_crafting = @import("inventory_crafting.zig");

pub var window = GuiWindow {
	.relativePosition = .{
		.{ .attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle} },
		.{ .attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .upper, .otherAttachmentPoint = .lower} },
	},
	.contentSize = Vec2f{64*8, 64*4},
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;

var inv: Inventory = undefined;

var craftingResult: *ItemSlot = undefined;

var seed: u32 = undefined;

var itemSlots: [25]*ItemSlot = undefined;

fn toggleTool(_: usize) void {

}

pub fn onOpen() void {
	seed = @truncate(@as(u128, @bitCast(std.time.nanoTimestamp())));
	inv = Inventory.init(main.globalAllocator, 26, .workbench, .other);
	const list = HorizontalList.init();
	{ // crafting grid
		const grid = VerticalList.init(.{0, 0}, 300, 0);
		// Inventory:
		for(0..5) |y| {
			const row = HorizontalList.init();
			for(0..5) |x| {
				const index = x + y*5;
				const slot = ItemSlot.init(.{0, 0}, inv, @intCast(index), .default, .normal);
				itemSlots[index] = slot;
				row.add(slot);
			}
			grid.add(row);
		}
		grid.finish(.center);
		list.add(grid);
	}
	const verticalThing = VerticalList.init(.{0, 0}, 300, padding);
	verticalThing.add(Button.initText(.{8, 0}, 104, "Test", .{.callback = &toggleTool}));
	const buttonHeight = verticalThing.size[1];
	const craftingResultList = HorizontalList.init();
	craftingResultList.add(Icon.init(.{0, 0}, .{32, 32}, inventory_crafting.arrowTexture, false));
	craftingResultList.add(ItemSlot.init(.{8, 0}, inv, 25, .craftingResult, .takeOnly));
	craftingResultList.finish(.{padding, padding}, .center);
	verticalThing.add(craftingResultList);
	verticalThing.size[1] += buttonHeight + 2*padding; // Centering the thing
	verticalThing.finish(.center);
	list.add(verticalThing);
	list.finish(.{padding, padding + 16}, .center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	main.game.Player.inventory.depositOrDrop(inv);
	inv.deinit(main.globalAllocator);
	if(window.rootComponent) |*comp| {
		comp.deinit();
		window.rootComponent = null;
	}
}
