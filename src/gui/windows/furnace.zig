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

pub var window = GuiWindow{
	.relativePosition = .{
		.{.attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle}},
		.{.attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .upper, .otherAttachmentPoint = .lower}},
	},
	.contentSize = Vec2f{64*8, 64*4},
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;

var furnaceInventory: Inventory = undefined;

var inputSlot: *ItemSlot = undefined;
var fuelSlot: [3]*ItemSlot = undefined;
var outputSlot: *ItemSlot = undefined;

var fireLevelTexture: [4]Texture = undefined;

var fireLevel: u8 = 0;

var requireUpdate = false;

pub fn init() void {
	fireLevelTexture[0] = Texture.initFromFile("assets/cubyz/ui/furnace/fire_unlit.png");
	fireLevelTexture[1] = Texture.initFromFile("assets/cubyz/ui/furnace/fire_lit_tier_1.png");
	fireLevelTexture[2] = Texture.initFromFile("assets/cubyz/ui/furnace/fire_lit_tier_2.png");
	fireLevelTexture[3] = Texture.initFromFile("assets/cubyz/ui/furnace/fire_lit_tier_3.png");
}

pub fn deinit() void {
	for(fireLevelTexture) |texture| {
		texture.deinit();
	}
}

fn openWindow() void {
	const mainLayout = HorizontalList.init();
	{
		const leftGrid = VerticalList.init(.{0, 0}, 300, 0);
		{
			const row = HorizontalList.init();
			row.add(inputSlot);
			leftGrid.add(row);
		}
		{
			const row = HorizontalList.init();
			for(0..3) |_| {
				row.add(Icon.init(.{0, 0}, .{32, 32}, fireLevelTexture[fireLevel], false));
			}
			leftGrid.add(row);
		}
		{
			const row = HorizontalList.init();
			for(0..3) |i| {
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

			row.add(outputSlot);
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

fn initInventory() void {
	const blockPosition = main.renderer.MeshSelection.selectedBlockPos.?;

	furnaceInventory = Inventory.init(main.globalAllocator, 5, .{.furnace = .{.x = blockPosition[0], .y = blockPosition[1], .z = blockPosition[2]}}, .other);

	inputSlot = ItemSlot.init(.{0, 0}, furnaceInventory, 0, .default, .normal);
	for(0..3) |i| {
		fuelSlot[i] = ItemSlot.init(.{0, 0}, furnaceInventory, @truncate(i + 1), .default, .normal);
	}
	outputSlot = ItemSlot.init(.{0, 0}, furnaceInventory, 4, .craftingResult, .takeOnly);
}

fn deinitInventory() void {
	main.game.Player.inventory.depositOrDrop(furnaceInventory);
	furnaceInventory.deinit(main.globalAllocator);
}

pub fn update() void {
	if(requireUpdate) {
		closeWindow();
		openWindow();
	}
}

pub fn onOpen() void {
	initInventory();
	openWindow();
}

pub fn onClose() void {
	closeWindow();
	deinitInventory();
}
