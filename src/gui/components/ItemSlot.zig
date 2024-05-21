const std = @import("std");

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

const border: f32 = 2;

pub const VTable = struct {
	tryAddingItems: *const fn(usize, *ItemStack, u16) void = &defaultAddingItems,
	tryTakingItems: *const fn(usize, *ItemStack, u16) void = &defaultTakingItems,
	trySwappingItems: *const fn(usize, *ItemStack) void = &defaultSwappingItems,

	fn defaultAddingItems(_: usize, _: *ItemStack, _: u16) void {}
	fn defaultTakingItems(_: usize, _: *ItemStack, _: u16) void {}
	fn defaultSwappingItems(_: usize, _: *ItemStack) void {}
};

const Mode = enum {
	normal,
	takeOnly,
	immutable,
};

pos: Vec2f,
size: Vec2f = .{32 + 2*border, 32 + 2*border},
itemStack: ItemStack,
text: TextBuffer,
textSize: Vec2f = .{0, 0},
hovered: bool = false,
pressed: bool = false,
renderFrame: bool = true,
userData: usize,
vtable: *const VTable,
texture: Texture,
mode: Mode,

var defaultTexture: Texture = undefined;
var immutableTexture: Texture = undefined;
var craftingResultTexture: Texture = undefined;
const TextureParamType = union(enum) {
	default: void,
	immutable: void,
	craftingResult: void,
	custom: Texture,
	fn value(self: TextureParamType) Texture {
		return switch(self) {
			.default => defaultTexture,
			.immutable => immutableTexture,
			.craftingResult => craftingResultTexture,
			.custom => |t| t,
		};
	}
};

pub fn __init() void {
	defaultTexture = Texture.initFromFile("assets/cubyz/ui/inventory/slot.png");
	immutableTexture = Texture.initFromFile("assets/cubyz/ui/inventory/immutable_slot.png");
	craftingResultTexture = Texture.initFromFile("assets/cubyz/ui/inventory/crafting_result_slot.png");
}

pub fn __deinit() void {
	defaultTexture.deinit();
	immutableTexture.deinit();
	craftingResultTexture.deinit();
}

pub fn init(pos: Vec2f, itemStack: ItemStack, vtable: *const VTable, userData: usize, texture: TextureParamType, mode: Mode) *ItemSlot {
	const self = main.globalAllocator.create(ItemSlot);
	var buf: [16]u8 = undefined;
	self.* = ItemSlot {
		.itemStack = itemStack,
		.vtable = vtable,
		.userData = userData,
		.pos = pos,
		.text = TextBuffer.init(main.globalAllocator, std.fmt.bufPrint(&buf, "{}", .{itemStack.amount}) catch "∞", .{}, false, .right),
		.texture = texture.value(),
		.mode = mode,
	};
	self.textSize = self.text.calculateLineBreaks(8, self.size[0] - 2*border);
	return self;
}

pub fn deinit(self: *const ItemSlot) void {
	self.text.deinit();
	main.globalAllocator.destroy(self);
}

pub fn tryAddingItems(self: *ItemSlot, source: *ItemStack, desiredAmount: u16) void {
	std.debug.assert(source.item != null);
	std.debug.assert(desiredAmount <= source.amount);
	self.vtable.tryAddingItems(self.userData, source, desiredAmount);
}

pub fn tryTakingItems(self: *ItemSlot, destination: *ItemStack, desiredAmount: u16) void {
	self.vtable.tryTakingItems(self.userData, destination, desiredAmount);
}

pub fn trySwappingItems(self: *ItemSlot, destination: *ItemStack) void {
	self.vtable.trySwappingItems(self.userData, destination);
}

pub fn updateItemStack(self: *ItemSlot, newStack: ItemStack) void {
	const oldAmount = self.itemStack.amount;
	self.itemStack = newStack;
	if(oldAmount != newStack.amount) {
		self.refreshText();
	}
}

fn refreshText(self: *ItemSlot) void {
	self.text.deinit();
	var buf: [16]u8 = undefined;
	self.text = TextBuffer.init(
		main.globalAllocator,
		std.fmt.bufPrint(&buf, "{}", .{self.itemStack.amount}) catch "∞",
		.{.color = if(self.itemStack.amount == 0) 0xff0000 else 0xffffff},
		false,
		.right
	);
	self.textSize = self.text.calculateLineBreaks(8, self.size[0] - 2*border);
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

pub fn render(self: *ItemSlot, _: Vec2f) void {
	draw.setColor(0xffffffff);
	if(self.renderFrame) {
		self.texture.bindTo(0);
		draw.boundImage(self.pos, self.size);
	}
	if(self.itemStack.item) |item| {
		const itemTexture = item.getTexture();
		itemTexture.bindTo(0);
		draw.setColor(0xff000000);
		draw.boundImage(self.pos + @as(Vec2f, @splat(border)) + Vec2f{1.0, 1.0}, self.size - @as(Vec2f, @splat(2*border)));
		draw.setColor(0xffffffff);
		draw.boundImage(self.pos + @as(Vec2f, @splat(border)), self.size - @as(Vec2f, @splat(2*border)));
		if(self.itemStack.amount != 1) {
			self.text.render(self.pos[0] + self.size[0] - self.textSize[0] - border, self.pos[1] + self.size[1] - self.textSize[1] - border, 8);
		}
	}
	if(self.pressed) {
		draw.setColor(0x80808080);
		draw.rect(self.pos, self.size);
	} else if(self.hovered) {
		if(self.mode != .immutable) {
			self.hovered = false;
			draw.setColor(0x300000ff);
			draw.rect(self.pos, self.size);
		}
	}
}