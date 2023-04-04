const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const ItemStack = main.items.ItemStack;
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const TextBuffer = graphics.TextBuffer;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;

const CraftingResultSlot = @This();

var texture: Texture = undefined;
const border: f32 = 3;

pos: Vec2f,
size: Vec2f = .{24 + 2*border, 24 + 2*border},
itemStack: ItemStack,
text: TextBuffer,
textSize: Vec2f = .{0, 0},
onTake: gui.Callback,
hovered: bool = false,
pressed: bool = false,

pub fn __init() !void {
	texture = try Texture.initFromFile("assets/cubyz/ui/inventory/crafting_result_slot.png");
}

pub fn __deinit() void {
	texture.deinit();
}

pub fn init(pos: Vec2f, itemStack: ItemStack, onTake: gui.Callback) Allocator.Error!*CraftingResultSlot {
	const self = try gui.allocator.create(CraftingResultSlot);
	var buf: [16]u8 = undefined;
	self.* = CraftingResultSlot {
		.itemStack = itemStack,
		.pos = pos,
		.text = try TextBuffer.init(gui.allocator, std.fmt.bufPrint(&buf, "{}", .{self.itemStack.amount}) catch "∞", .{}, false, .right),
		.onTake = onTake,
	};
	self.textSize = try self.text.calculateLineBreaks(8, self.size[0] - 2*border);
	return self;
}

pub fn deinit(self: *const CraftingResultSlot) void {
	self.text.deinit();
	gui.allocator.destroy(self);
}

pub fn toComponent(self: *CraftingResultSlot) GuiComponent {
	return GuiComponent{
		.craftingResultSlot = self
	};
}

pub fn updateHovered(self: *CraftingResultSlot, _: Vec2f) void {
	self.hovered = true;
	gui.hoveredCraftingSlot = self;
}

pub fn mainButtonPressed(self: *CraftingResultSlot, _: Vec2f) void {
	self.pressed = true;
}

pub fn mainButtonReleased(self: *CraftingResultSlot, mousePosition: Vec2f) void {
	if(self.pressed) {
		self.pressed = false;
		if(GuiComponent.contains(self.pos, self.size, mousePosition)) {
			if(self.itemStack.item == null) return;
			if(gui.inventory.carriedItemStack.item == null or std.meta.eql(self.itemStack.item, gui.inventory.carriedItemStack.item)) {
				if(std.math.add(u16, gui.inventory.carriedItemStack.amount, self.itemStack.amount) catch null) |nextAmount| if(nextAmount <= self.itemStack.item.?.stackSize()) {
					const itemStack = self.itemStack;
					self.onTake.run();
					gui.inventory.carriedItemStack.item = itemStack.item;
					gui.inventory.carriedItemStack.amount += itemStack.amount;
				};
			}
		}
	}
}

pub fn render(self: *CraftingResultSlot, _: Vec2f) !void {
	draw.setColor(0xffffffff);
	texture.bindTo(0);
	draw.boundImage(self.pos, self.size);
	if(self.itemStack.item) |item| {
		const itemTexture = try item.getTexture();
		itemTexture.bindTo(0);
		draw.setColor(0xff000000);
		draw.boundImage(self.pos + @splat(2, border) + Vec2f{1.0, 1.0}, self.size - @splat(2, 2*border));
		draw.setColor(0xffffffff);
		draw.boundImage(self.pos + @splat(2, border), self.size - @splat(2, 2*border));
		if(self.itemStack.amount != 1) {
			try self.text.render(self.pos[0] + self.size[0] - self.textSize[0] - border, self.pos[1] + self.size[1] - self.textSize[1] - border, 8);
		}
	}
	if(self.pressed) {
		draw.setColor(0x80808080);
		draw.rect(self.pos, self.size);
	} else if(self.hovered) {
		self.hovered = false;
		draw.setColor(0x300000ff);
		draw.rect(self.pos, self.size);
	}
}