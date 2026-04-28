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
size: Vec2f = @splat(sizeWithBorder),
inventory: *BagInventory,
hovered: bool = false,
pressed: bool = false,

pub fn globalInit() void {
	texture = Texture.initFromFile("assets/cubyz/ui/inventory/bag_slot.png");
}

pub fn __deinit() void {
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

pub fn mainButtonReleased(self: *BagSlot, _: Vec2f) void {
	if (self.pressed) {
		const carried = gui.inventory.carried;
		if (carried.getAmount(0) != 0) {
			main.sync.ClientSide.executeCommand(.{.moveToPlayerBag = .{.amount = carried.getAmount(0), .source = .{.inv = carried.super, .slot = 0}}});
		} else {
			main.sync.ClientSide.executeCommand(.{.takeFromPlayerBag = .init(&.{carried}, std.math.maxInt(u16))});
		}
		self.pressed = false;
	}
}

pub fn render(self: *BagSlot, _: Vec2f) void {
	draw.setColor(0xffffffff);
	texture.bindTo(0);
	draw.boundImage(self.pos, self.size);

	for (0..5) |_i| {
		const i = 4 - _i;
		const item = self.inventory.peek(i).item;
		if (item == .null) continue;
		const opacity: f32 = std.math.pow(f32, 0.5, @as(f32, @floatFromInt(i)));
		draw.setColor(0xffffff | @as(u32, @intFromFloat(opacity*255)) << 24);
		const itemTexture = item.getTexture();
		itemTexture.bindTo(0);
		draw.boundImage(self.pos + @as(Vec2f, @splat(border)), self.size - @as(Vec2f, @splat(2*border)));
	}

	const topItem = self.inventory.peek(0);
	const shouldRenderStackSizeText = topItem.item.stackSize() > 1;
	if (shouldRenderStackSizeText) {
		var buf: [16]u8 = undefined;
		var text = TextBuffer.init(
			main.stackAllocator,
			std.fmt.bufPrint(&buf, "{}", .{topItem.amount}) catch "∞",
			.{.color = if (topItem.amount == 0) 0xff0000 else 0xffffff},
			false,
			.right,
		);
		defer text.deinit();
		const textSize = text.calculateLineBreaks(8, self.size[0] - 2*border);
		text.render(self.pos[0] + self.size[0] - textSize[0] - border, self.pos[1] + self.size[1] - textSize[1] - border, 8);
	}
	if (topItem.item == .proceduralItem) {
		const proceduralItem = topItem.item.proceduralItem;
		const durabilityPercentage = @as(f32, @floatFromInt(proceduralItem.durability))/proceduralItem.getProperty(.maxDurability);

		if (durabilityPercentage < 1) {
			const width = durabilityPercentage*(self.size[0] - 2*border);
			draw.setColor(0xff000000);
			draw.rect(self.pos + Vec2f{border, 15*(self.size[1] - border)/16.0}, .{self.size[0] - 2*border, (self.size[1] - 2*border)/16.0});

			const red = std.math.lossyCast(u8, (2 - durabilityPercentage*2)*255);
			const green = std.math.lossyCast(u8, durabilityPercentage*2*255);

			draw.setColor(0xff000000 | (@as(u32, @intCast(red)) << 16) | (@as(u32, @intCast(green)) << 8));
			draw.rect(self.pos + Vec2f{border, 15*(self.size[1] - border)/16.0}, .{width, (self.size[1] - 2*border)/16.0});
		}
	}

	if (self.hovered) {
		self.hovered = false;
		draw.setColor(0x300000ff);
		draw.rect(self.pos, self.size);
	}
}
