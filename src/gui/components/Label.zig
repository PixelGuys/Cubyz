const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const TextBuffer = graphics.TextBuffer;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;

const Label = @This();

const fontSize: f32 = 16;

text: TextBuffer,
textSize: Vec2f = undefined,

pub fn init(allocator: Allocator, pos: Vec2f, maxWidth: f32, text: []const u8) Allocator.Error!GuiComponent {
	var self = Label {
		.text = try TextBuffer.init(allocator, text, .{}, false),
	};
	self.textSize = try self.text.calculateLineBreaks(fontSize, maxWidth);
	return GuiComponent {
		.pos = pos,
		.size = self.textSize,
		.impl = .{.label = self}
	};
}

pub fn deinit(self: Label) void {
	self.text.deinit();
}

pub fn render(self: *Label, pos: Vec2f, _: Vec2f, _: Vec2f) !void {
	try self.text.render(pos[0], pos[1], fontSize);
}