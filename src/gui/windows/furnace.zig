const std = @import("std");

const main = @import("main");
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

pub var window = GuiWindow{
	.relativePosition = .{
		.{.attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle}},
		.{.attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .upper, .otherAttachmentPoint = .lower}},
	},
	.contentSize = Vec2f{64*8, 64*4},
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;

var openInventory: Inventory = undefined;

var inputSlot: [2]*ItemSlot = undefined;
var fuelSlot: [1]*ItemSlot = undefined;
var outputSlot: [1]*ItemSlot = undefined;

var fireLevelTexture: [2]Texture = undefined;

var fireLevel: u8 = 0;

var requireUpdate = false;

pub fn init() void {
	fireLevelTexture[0] = Texture.initFromFile("assets/cubyz/ui/furnace/fire_unlit.png");
	fireLevelTexture[1] = Texture.initFromFile("assets/cubyz/ui/furnace/fire_lit.png");
}

pub fn deinit() void {
	for(fireLevelTexture) |texture| {
		texture.deinit();
	}
}

fn openWindow() void {
	var slotIndex: u32 = 0;
	const mainLayout = HorizontalList.init();
	{
		const leftGrid = VerticalList.init(.{0, 0}, 300, 0);
		{
			const row = HorizontalList.init();
			for(0..2) |i| {
				inputSlot[i] = ItemSlot.init(.{0, 0}, openInventory, @intCast(slotIndex), .default, .normal);
				slotIndex += 1;
				row.add(inputSlot[i]);
			}
			leftGrid.add(row);
		}
		{
			const row = HorizontalList.init();
			for(0..2) |_| {
				row.add(Icon.init(.{0, 0}, .{32, 32}, fireLevelTexture[fireLevel], false));
			}
			leftGrid.add(row);
		}
		{
			const row = HorizontalList.init();
			for(0..1) |i| {
				fuelSlot[i] = ItemSlot.init(.{0, 0}, openInventory, @intCast(slotIndex), .craftingResult, .takeOnly);
				slotIndex += 1;
				row.add(fuelSlot[i]);
			}
			leftGrid.add(row);
		}
		leftGrid.finish(.center);
		mainLayout.add(leftGrid);
	}
	{
		const rightGrid = VerticalList.init(.{0, 0}, 300, 0);
		{
			const row = HorizontalList.init();
			row.add(Icon.init(.{0, 0}, .{32, 32}, inventory_crafting.arrowTexture, false));

			for(0..1) |i| {
				outputSlot[i] = ItemSlot.init(.{0, 0}, openInventory, @intCast(slotIndex), .default, .normal);
				slotIndex += 1;
				row.add(outputSlot[i]);
			}
			rightGrid.add(row);
		}
		rightGrid.finish(.center);
		mainLayout.add(rightGrid);
	}
	mainLayout.finish(.{padding, padding + 16}, .center);

	window.rootComponent = mainLayout.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

fn closeWindow() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
		window.rootComponent = null;
	}
}

pub fn setInventory(selectedInventory: main.items.Inventory) void {
	openInventory = selectedInventory;
}

pub fn update() void {
	if(requireUpdate) {
		closeWindow();
		openWindow();
	}
}

pub fn onOpen() void {
	openWindow();
}

pub fn onClose() void {
	openInventory.deinit(main.globalAllocator);

	closeWindow();
}
