const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const BaseItem = main.items.BaseItem;
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const TextBuffer = graphics.TextBuffer;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;

const ImmutableItemSlot = @This();

var texture: Texture = undefined;
const border: f32 = 3;

pos: Vec2f,
size: Vec2f = .{24 + 2*border, 24 + 2*border},
item: *BaseItem,
amount: u32,
text: TextBuffer,
textSize: Vec2f = .{0, 0},

pub fn __init() !void {
	texture = try Texture.initFromFile("assets/cubyz/ui/inventory/immutable_slot.png");
}

pub fn __deinit() void {
	texture.deinit();
}

pub fn init(pos: Vec2f, item: *BaseItem, amount: u32) Allocator.Error!*ImmutableItemSlot {
	const self = try gui.allocator.create(ImmutableItemSlot);
	var buf: [16]u8 = undefined;
	self.* = ImmutableItemSlot {
		.item = item,
		.amount = amount,
		.pos = pos,
		.text = try TextBuffer.init(gui.allocator, std.fmt.bufPrint(&buf, "{}", .{amount}) catch "∞", .{}, false, .right),
	};
	self.textSize = try self.text.calculateLineBreaks(8, self.size[0] - 2*border);
	return self;
}

pub fn deinit(self: *const ImmutableItemSlot) void {
	self.text.deinit();
	gui.allocator.destroy(self);
}

pub fn toComponent(self: *ImmutableItemSlot) GuiComponent {
	return GuiComponent{
		.immutableItemSlot = self
	};
}

pub fn render(self: *ImmutableItemSlot, _: Vec2f) !void {
	draw.setColor(0xffffffff);
	texture.bindTo(0);
	draw.boundImage(self.pos, self.size);
	const itemTexture = try self.item.getTexture();
	itemTexture.bindTo(0);
	draw.setColor(0xff000000);
	draw.boundImage(self.pos + @splat(2, border) + Vec2f{1.0, 1.0}, self.size - @splat(2, 2*border));
	draw.setColor(0xffffffff);
	draw.boundImage(self.pos + @splat(2, border), self.size - @splat(2, 2*border));
	if(self.amount != 1) {
		try self.text.render(self.pos[0] + self.size[0] - self.textSize[0] - border, self.pos[1] + self.size[1] - self.textSize[1] - border, 8);
	}
}