const std = @import("std");

const main = @import("root");
const Inventory = main.items.Inventory;
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

const Mode = enum {
	normal,
	takeOnly,
	immutable,
};

pos: Vec2f,
size: Vec2f = .{32 + 2*border, 32 + 2*border},
inventory: Inventory,
itemSlot: u32,
lastItemAmount: u16 = 0,
text: TextBuffer,
textSize: Vec2f = .{0, 0},
hovered: bool = false,
pressed: bool = false,
renderFrame: bool = true,
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

pub fn init(pos: Vec2f, inventory: Inventory, itemSlot: u32, texture: TextureParamType, mode: Mode) *ItemSlot {
	const self = main.globalAllocator.create(ItemSlot);
	const amount = inventory.getAmount(itemSlot);
	var buf: [16]u8 = undefined;
	self.* = ItemSlot {
		.inventory = inventory,
		.itemSlot = itemSlot,
		.pos = pos,
		.text = TextBuffer.init(main.globalAllocator, std.fmt.bufPrint(&buf, "{}", .{amount}) catch "∞", .{}, false, .right),
		.lastItemAmount = amount,
		.texture = texture.value(),
		.mode = mode,
	};
	self.textSize = self.text.calculateLineBreaks(8, self.size[0] - 2*border);
	return self;
}

pub fn deinit(self: *const ItemSlot) void {
	main.gui.inventory.deleteItemSlotReferences(self);
	self.text.deinit();
	main.globalAllocator.destroy(self);
}

fn refreshText(self: *ItemSlot) void {
	const amount = self.inventory.getAmount(self.itemSlot);
	if(self.lastItemAmount == amount) return;
	self.text.deinit();
	var buf: [16]u8 = undefined;
	self.text = TextBuffer.init(
		main.globalAllocator,
		std.fmt.bufPrint(&buf, "{}", .{amount}) catch "∞",
		.{.color = if(amount == 0) 0xff0000 else 0xffffff},
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
	self.refreshText();
	draw.setColor(0xffffffff);
	if(self.renderFrame) {
		self.texture.bindTo(0);
		draw.boundImage(self.pos, self.size);
	}
	if(self.inventory.getItem(self.itemSlot)) |item| {
		const itemTexture = item.getTexture();
		itemTexture.bindTo(0);
		draw.setColor(0xff000000);
		draw.boundImage(self.pos + @as(Vec2f, @splat(border)) + Vec2f{1.0, 1.0}, self.size - @as(Vec2f, @splat(2*border)));
		draw.setColor(0xffffffff);
		draw.boundImage(self.pos + @as(Vec2f, @splat(border)), self.size - @as(Vec2f, @splat(2*border)));
		if(self.inventory.getAmount(self.itemSlot) != 1) {
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