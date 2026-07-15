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
const ProgressBar = GuiComponent.ProgressBar;

const inventory = @import("inventory.zig");

pub var window = GuiWindow{
	.relativePosition = .{
		.{.attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle}},
		.{.attachedToWindow = .{.reference = &inventory.window, .selfAttachmentPoint = .upper, .otherAttachmentPoint = .lower}},
	},
	.contentSize = Vec2f{64*10, 64*3},
	.scale = 0.75,
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;
var itemSlots: main.List(*ItemSlot) = .empty;
var craftingIcon: Texture = undefined;
var progressBar: *ProgressBar = undefined;
var currentSetRecipe: ?main.items.Recipe = undefined;

pub fn init() void {
	craftingIcon = Texture.initFromFile("assets/cubyz/ui/inventory/crafting_icon.png");
}

pub fn deinit() void {
	itemSlots.clearAndFree(main.globalAllocator);
	craftingIcon.deinit();
}

pub var openInventory: main.items.Inventory.ClientInventory = undefined;

pub fn setInventory(selectedInventory: main.items.Inventory.ClientInventory) void {
	openInventory = selectedInventory;
}

fn delayCallback(newValue: f32) void {
	std.log.debug("hahe {}", .{newValue});
}

fn delayFormatter(allocator: main.heap.NeverFailingAllocator, value: f32) []const u8 {
	return std.fmt.allocPrint(allocator.allocator, "#ffffffhelp me figure this out: {d:.0} ms", .{value/1.0e6}) catch unreachable;
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, padding + 16}, 300, 0);
	
	{
		const row = HorizontalList.init();
		row.add(Button.initIcon(.{32, 0}, .{32, 32}, craftingIcon, .{.onAction = gui.openWindowCallback("autocrafter_recipe_select")}));
		list.add(row);
	}

	const row = HorizontalList.init();
	for (0..2) |x| {
		const index: usize = x;
		const slot = ItemSlot.init(.{0, 0}, openInventory, @intCast(index), .default, .normal);
		itemSlots.append(main.globalAllocator, slot);
		row.add(slot);
	}
	
	const outputSlot: comptime_int = 2;
	const slot = ItemSlot.init(.{32, 0}, openInventory, @intCast(outputSlot), .default, .takeOnly);
	row.add(slot);
	itemSlots.append(main.globalAllocator, slot);
	list.add(row);

	progressBar = ProgressBar.init(.{0, 0}, 128, &delayCallback, &delayFormatter, .{.onAction = .init(craft)});
	list.add(progressBar);

	list.finish(.center);
	window.shiftClickableInventory = openInventory;
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	openInventory.deinit(main.globalAllocator);

	itemSlots.clearRetainingCapacity();
	if (window.rootComponent) |*comp| {
		comp.deinit();
		window.rootComponent = null;
	}
}

pub fn update() void {
	if (currentSetRecipe != null) progressBar.currentValue += 1;
}

pub fn setRecipe(recipe: main.items.Recipe) void {
	currentSetRecipe = recipe;
}

fn craft() void {
	main.sync.client.executeCommand(.{.craftFrom = .init(&.{openInventory}, &.{openInventory}, &(currentSetRecipe orelse return))});
}
