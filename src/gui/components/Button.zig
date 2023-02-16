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

const Button = @This();

pressed: bool = false,
onAction: *const fn() void,
text: TextBuffer,

pub fn init(pos: Vec2f, size: Vec2f, allocator: Allocator, text: []const u8, onAction: *const fn() void) Allocator.Error!GuiComponent {
	const self = Button {
		.onAction = onAction,
		.text = try TextBuffer.init(allocator, text, .{}, false),
	};
	return GuiComponent {
		.pos = pos,
		.size = size,
		.impl = .{.button = self}
	};
}

pub fn deinit(self: Button) void {
	self.text.deinit();
}

pub fn mainButtonPressed(self: *Button, _: *const GuiComponent, _: Vec2f) void {
	self.pressed = true;
}

pub fn mainButtonReleased(self: *Button, component: *const GuiComponent, mousePosition: Vec2f) void {
	if(self.pressed) {
		self.pressed = false;
		if(component.contains(mousePosition)) {
			self.onAction();
		}
	}
}

const buttonColor: [5]u32 = [_]u32{
	0xff9ca6bf, // center
	0xffa6b0cc, // top
	0xffa0aac4, // right
	0xff919ab3, // bottom
	0xff97a1ba, // left
};

const buttonPressedColor: [5]u32 = [_]u32{
	0xff929ab3, // center
	0xff878fa6, // top
	0xff8e96ad, // right
	0xff9ca5bf, // bottom
	0xff969fb8, // left
};

const buttonHoveredColor: [5]u32 = [_]u32{
	0xff9ca6dd, // center
	0xffa6b0ea, // top
	0xffa0aae2, // right
	0xff919ad1, // bottom
	0xff97a1d8, // left
};

pub fn render(self: *Button, component: *const GuiComponent, mousePosition: Vec2f) !void {
	// TODO: I should really just add a proper button texture.
	const border: f32 = 3;
	var colors = &buttonColor;
	if(component.contains(mousePosition)) {
		colors = &buttonHoveredColor;
	}
	if(self.pressed) {
		colors = &buttonPressedColor;
	}
	draw.setColor(colors[0]);
	draw.rect(component.pos + @splat(2, border), component.size - @splat(2, 2*border));
	draw.setColor(colors[1]);
	draw.rect(component.pos, Vec2f{component.size[0] - border, border});
	draw.setColor(colors[2]);
	draw.rect(component.pos + Vec2f{component.size[0] - border, 0}, Vec2f{border, component.size[1] - border});
	draw.setColor(colors[3]);
	draw.rect(component.pos + Vec2f{border, component.size[1] - border}, Vec2f{component.size[0] - border, border});
	draw.setColor(colors[4]);
	draw.rect(component.pos + Vec2f{0, border}, Vec2f{border, component.size[1] - border});
	const textSize = try self.text.calculateLineBreaks(16, component.size[0]); // TODO
	const textPos = component.pos + component.size/@splat(2, @as(f32, 2.0)) - textSize/@splat(2, @as(f32, 2.0));
	try self.text.render(textPos[0], textPos[1], 16);
}