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

const ItemSlot = @This();

var texture: Texture = undefined;
const border: f32 = 2;

pos: Vec2f,
size: Vec2f = .{24 + 2*border, 24 + 2*border},
itemStack: *ItemStack,
oldStack: ItemStack,
text: TextBuffer,
textSize: Vec2f = .{0, 0},
hovered: bool = false,
pressed: bool = false,
renderFrame: bool = true,

pub fn __init() !void {
	texture = try Texture.initFromFile("assets/cubyz/ui/inventory/slot.png");
}

pub fn __deinit() void {
	texture.deinit();
}

pub fn init(pos: Vec2f, itemStack: *ItemStack) Allocator.Error!*ItemSlot {
	const self = try main.globalAllocator.create(ItemSlot);
	var buf: [16]u8 = undefined;
	self.* = ItemSlot {
		.itemStack = itemStack,
		.oldStack = itemStack.*,
		.pos = pos,
		.text = try TextBuffer.init(main.globalAllocator, std.fmt.bufPrint(&buf, "{}", .{self.itemStack.amount}) catch "∞", .{}, false, .right),
	};
	self.textSize = try self.text.calculateLineBreaks(8, self.size[0] - 2*border);
	return self;
}

pub fn deinit(self: *const ItemSlot) void {
	self.text.deinit();
	main.globalAllocator.destroy(self);
}

fn refreshText(self: *ItemSlot) !void {
	self.text.deinit();
	var buf: [16]u8 = undefined;
	self.text = try TextBuffer.init(
		main.globalAllocator,
		std.fmt.bufPrint(&buf, "{}", .{self.itemStack.amount}) catch "∞",
		.{.color = if(self.itemStack.amount == 0) 0xff0000 else 0xffffff},
		false,
		.right
	);
	self.textSize = try self.text.calculateLineBreaks(8, self.size[0] - 2*border);
}

pub fn toComponent(self: *ItemSlot) GuiComponent {
	return GuiComponent{
		.itemSlot = self
	};
}

pub fn updateHovered(self: *ItemSlot, _: Vec2f) void {
	self.hovered = true;
	gui.hoveredItemSlot = self;
}

pub fn mainButtonPressed(self: *ItemSlot, _: Vec2f) void {
	self.pressed = true;
}

pub fn render(self: *ItemSlot, _: Vec2f) !void {
	const newStack = self.itemStack.*;
	if(newStack.amount != self.oldStack.amount) {
		try self.refreshText();
		self.oldStack.amount = newStack.amount;
	}
	draw.setColor(0xffffffff);
	if(self.renderFrame) {
		texture.bindTo(0);
		draw.boundImage(self.pos, self.size);
	}
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