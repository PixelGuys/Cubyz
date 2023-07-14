const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const ItemStack = main.items.ItemStack;
const Item = main.items.Items;
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

pub const VTable = struct {
	tryAddingItems: *const fn(usize, *ItemStack, u16) void,
	tryTakingItems: *const fn(usize, *ItemStack, u16) void,
	trySwappingItems: *const fn(usize, *ItemStack) void,
};

pos: Vec2f,
size: Vec2f = .{24 + 2*border, 24 + 2*border},
itemStack: ItemStack,
text: TextBuffer,
textSize: Vec2f = .{0, 0},
hovered: bool = false,
pressed: bool = false,
renderFrame: bool = true,
userData: usize,
vtable: *const VTable,

pub fn __init() !void {
	texture = try Texture.initFromFile("assets/cubyz/ui/inventory/slot.png");
}

pub fn __deinit() void {
	texture.deinit();
}

pub fn init(pos: Vec2f, itemStack: ItemStack, vtable: *const VTable, userData: usize) Allocator.Error!*ItemSlot {
	const self = try main.globalAllocator.create(ItemSlot);
	var buf: [16]u8 = undefined;
	self.* = ItemSlot {
		.itemStack = itemStack,
		.vtable = vtable,
		.userData = userData,
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

pub fn tryAddingItems(self: *ItemSlot, source: *ItemStack, amount: u16) void {
	std.debug.assert(source.item != null);
	std.debug.assert(amount <= source.amount);
	self.vtable.tryAddingItems(self.userData, source, amount);
}

pub fn tryTakingItems(self: *ItemSlot, destination: *ItemStack, amount: u16) void {
	self.vtable.tryTakingItems(self.userData, destination, amount);
}

pub fn trySwappingItems(self: *ItemSlot, destination: *ItemStack) void {
	self.vtable.trySwappingItems(self.userData, destination);
}

pub fn updateItemStack(self: *ItemSlot, newStack: ItemStack) !void {
	const oldAmount = self.itemStack.amount;
	self.itemStack = newStack;
	if(oldAmount != newStack.amount) {
		try self.refreshText();
	}
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

pub fn mainButtonReleased(self: *ItemSlot, _: Vec2f) void {
	if(self.pressed) {
		self.pressed = false;
	}
}

pub fn render(self: *ItemSlot, _: Vec2f) !void {
	draw.setColor(0xffffffff);
	if(self.renderFrame) {
		texture.bindTo(0);
		draw.boundImage(self.pos, self.size);
	}
	if(self.itemStack.item) |item| {
		const itemTexture = try item.getTexture();
		itemTexture.bindTo(0);
		draw.setColor(0xff000000);
		draw.boundImage(self.pos + @as(Vec2f, @splat(border)) + Vec2f{1.0, 1.0}, self.size - @as(Vec2f, @splat(2*border)));
		draw.setColor(0xffffffff);
		draw.boundImage(self.pos + @as(Vec2f, @splat(border)), self.size - @as(Vec2f, @splat(2*border)));
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