const std = @import("std");

const main = @import("main");
const BagInventory = main.items.Inventory.BagInventory;
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const TextBuffer = graphics.TextBuffer;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;

const BagSlot = @This();

const border: f32 = 2;

pub const sizeWithBorder = 32 + 2*border;

var texture: Texture = undefined;

pos: Vec2f,
size: Vec2f = .{sizeWithBorder, sizeWithBorder + 8},
inventory: *BagInventory,
hovered: bool = false,
pressed: bool = false,

pub fn globalInit() void {
	texture = Texture.initFromFile("assets/cubyz/ui/inventory/bag_slot.png");
}

pub fn globalDeinit() void {
	texture.deinit();
}

pub fn init(pos: Vec2f, inventory: *BagInventory) *BagSlot {
	const self = main.globalAllocator.create(BagSlot);
	self.* = .{
		.inventory = inventory,
		.pos = pos,
	};
	return self;
}

pub fn deinit(self: *const BagSlot) void {
	main.globalAllocator.destroy(self);
}

pub fn toComponent(self: *BagSlot) GuiComponent {
	return .{.bagSlot = self};
}

pub fn updateHovered(self: *BagSlot, _: Vec2f) main.callbacks.Result {
	self.hovered = true;
	gui.hoveredItemSlot = null;
	return .handled;
}

pub fn mainButtonPressed(self: *BagSlot, _: Vec2f) main.callbacks.Result {
	self.pressed = true;
	return .handled;
}

pub fn mainButtonReleased(self: *BagSlot, mousePosition: Vec2f) void {
	if (self.pressed) {
		self.pressed = false;
		if (GuiComponent.contains(self.pos, self.size, mousePosition)) {
			const carried = gui.inventory.carried;
			if (carried.getAmount(0) != 0) {
				main.sync.ClientSide.executeCommand(.{.moveToPlayerBag = .{.amount = carried.getAmount(0), .source = .{.inv = carried.super, .slot = 0}}});
			} else {
				main.sync.ClientSide.executeCommand(.{.takeFromPlayerBag = .init(&.{carried}, std.math.maxInt(u16))});
			}
		}
	}
}

pub fn render(self: *BagSlot, _: Vec2f) void {
	draw.setColor(0xffffffff);
	texture.bindTo(0);
	draw.boundImage(self.pos, @splat(sizeWithBorder));

	for (0..5) |_i| {
		const i = 4 - _i;
		const item = self.inventory.peek(i).item;
		if (item == .null) continue;
		const opacity: f32 = std.math.pow(f32, 0.5, @as(f32, @floatFromInt(i)));
		draw.setColor(0xffffff | @as(u32, @trunc(opacity*255)) << 24);
		item.render(self.pos, @splat(sizeWithBorder), border);
	}

	const topItem = self.inventory.peek(0);
	const shouldRenderStackSizeText = topItem.item.stackSize() > 1;
	if (shouldRenderStackSizeText) {
		var amount: usize = topItem.amount;
		for (1..self.inventory.slots.items.len) |i| {
			const otherItem = self.inventory.peek(i);
			if (!std.meta.eql(topItem.item, otherItem.item)) break;
			amount += otherItem.amount;
		}
		var buf: [16]u8 = undefined;
		var text = TextBuffer.init(
			main.stackAllocator,
			std.fmt.bufPrint(&buf, "{}", .{amount}) catch "∞",
			.{.color = if (amount == 0) 0xff0000 else 0xffffff},
			false,
			.right,
		);
		defer text.deinit();
		const textSize = text.calculateLineBreaks(8, self.size[0] - 2*border);
		text.render(self.pos[0] + sizeWithBorder - textSize[0] - border, self.pos[1] + sizeWithBorder - textSize[1] - border, 8);
	}

	draw.setColor(0xffffffff);
	draw.print("{}/{}", .{self.inventory.slots.items.len, self.inventory.sizeLimit}, self.pos[0], self.pos[1] + sizeWithBorder, 8, .left);

	if (self.hovered) {
		self.hovered = false;
		draw.setColor(0x300000ff);
		draw.rect(self.pos, @splat(sizeWithBorder));
	}
}
