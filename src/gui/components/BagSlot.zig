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

const borderSize: f32 = 2;
pub const tileSize = 32;
const widgetWidth = 2*borderSize + tileSize;
const widgetHeight = 4*borderSize + 2*tileSize;

var texture: Texture = undefined;

pos: Vec2f,
size: Vec2f = .{widgetWidth, widgetHeight + 8},
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
			if (main.KeyBoard.key("mainGuiButton").modsOnPress.shift) {
				main.sync.client.executeCommand(.{.takeFromPlayerBag = .init(&.{main.game.Player.inventory}, std.math.maxInt(u16))});
				return;
			}
			if (carried.getAmount(0) != 0) {
				main.sync.client.executeCommand(.{.moveToPlayerBag = .{.amount = carried.getAmount(0), .source = .{.inv = carried.super, .slot = 0}}});
			} else {
				main.sync.client.executeCommand(.{.takeFromPlayerBag = .init(&.{carried}, std.math.maxInt(u16))});
			}
		}
	}
}

pub fn render(self: *BagSlot, _: Vec2f) void {
	texture.bindTo(0);
	draw.boundImage(self.pos, Vec2f{widgetWidth, widgetHeight});

	for (0..5) |j| {
		const i = 4 - j;
		const isEven = j%2 == 0;
		const item = self.inventory.peek(i).item;
		if (item == .null) continue;
		const opacity: f32 = if (i == 0) 1.0 else 0.8;
		const oldColor = draw.setColor(0xffffff | @as(u32, @trunc(opacity*255)) << 24);
		defer draw.restoreColor(oldColor);
		item.render(self.pos + Vec2f{borderSize - if (isEven) borderSize else 0.0, @as(f32, @floatFromInt(i*8))}, @splat(widgetWidth), borderSize);
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
		const textSize = text.calculateLineBreaks(8, self.size[0] - 2*borderSize);
		text.render(self.pos[0] + widgetWidth - textSize[0] - borderSize, self.pos[1] + widgetHeight - textSize[1] - borderSize, 8);
	}

	draw.print("{}/{}", .{self.inventory.slots.items.len, self.inventory.sizeLimit}, self.pos[0], self.pos[1] + widgetHeight, 8);

	if (self.hovered) {
		self.hovered = false;
		const oldColor = draw.setColor(0x300000ff);
		defer draw.restoreColor(oldColor);
		draw.rect(self.pos, Vec2f{widgetWidth, widgetHeight});
	}
}
