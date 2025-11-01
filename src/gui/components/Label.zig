const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const TextBuffer = graphics.TextBuffer;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;

const Label = @This();

pos: Vec2f,
size: Vec2f,
maxWidth: f32,
text: TextBuffer,
fontSize: f32 = 16,
alpha: f32 = 1,

pub fn init(pos: Vec2f, maxWidth: f32, text: []const u8, alignment: TextBuffer.Alignment) *Label {
	const self = main.globalAllocator.create(Label);
	self.* = Label{
		.pos = pos,
		.size = undefined,
		.maxWidth = maxWidth,
		.text = TextBuffer.init(main.globalAllocator, text, .{}, false, alignment),
	};
	self.size = self.text.calculateLineBreaks(self.fontSize, maxWidth);
	return self;
}

pub fn scaleFontSize(self: *Label, scale: f32) void {
	self.setFontSize(self.fontSize * scale);
}

pub fn setFontSize(self: *Label, newSize: f32) void {
	self.fontSize = newSize;
	self.size = self.text.calculateLineBreaks(self.fontSize, self.maxWidth);
}

pub fn deinit(self: *const Label) void {
	self.text.deinit();
	main.globalAllocator.destroy(self);
}

pub fn toComponent(self: *Label) GuiComponent {
	return .{.label = self};
}

pub fn updateText(self: *Label, newText: []const u8) void {
	const alignment = self.text.alignment;
	self.text.deinit();
	self.text = TextBuffer.init(main.globalAllocator, newText, .{}, false, alignment);
	self.size = self.text.calculateLineBreaks(self.fontSize, self.size[0]);
}

pub fn render(self: *Label, _: Vec2f) void {
	draw.setColor(@as(u32, @intFromFloat(self.alpha*255)) << 24);
	self.text.render(self.pos[0], self.pos[1], self.fontSize);
}
