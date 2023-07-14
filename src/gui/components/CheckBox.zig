const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const Shader = graphics.Shader;
const TextBuffer = graphics.TextBuffer;
const Texture = graphics.Texture;
const random = main.random;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const Button = GuiComponent.Button;
const Label = GuiComponent.Label;

const CheckBox = @This();

const border: f32 = 3;
const fontSize: f32 = 16;
const boxSize: f32 = 16;

var textureChecked: Texture = undefined;
var textureEmpty: Texture = undefined;

pos: Vec2f,
size: Vec2f,
state: bool = false,
pressed: bool = false,
hovered: bool = false,
onAction: *const fn(bool) void,
label: *Label,

pub fn __init() !void {
	textureChecked = try Texture.initFromFile("assets/cubyz/ui/checked_box.png");
	textureEmpty = try Texture.initFromFile("assets/cubyz/ui/box.png");
}

pub fn __deinit() void {
	textureChecked.deinit();
	textureEmpty.deinit();
}

pub fn init(pos: Vec2f, width: f32, text: []const u8, initialValue: bool, onAction: *const fn(bool) void) Allocator.Error!*CheckBox {
	const label = (try Label.init(undefined, width - 3*border - boxSize, text, .left));
	const self = try main.globalAllocator.create(CheckBox);
	self.* = CheckBox {
		.pos = pos,
		.size = Vec2f{@max(width, label.size[0] + 3*border + boxSize), label.size[1] + 3*border},
		.state = initialValue,
		.onAction = onAction,
		.label = label,
	};
	return self;
}

pub fn deinit(self: *const CheckBox) void {
	self.label.deinit();
	main.globalAllocator.destroy(self);
}

pub fn toComponent(self: *CheckBox) GuiComponent {
	return GuiComponent {
		.checkBox = self
	};
}

pub fn updateHovered(self: *CheckBox, _: Vec2f) void {
	self.hovered = true;
}

pub fn mainButtonPressed(self: *CheckBox, _: Vec2f) void {
	self.pressed = true;
}

pub fn mainButtonReleased(self: *CheckBox, mousePosition: Vec2f) void {
	if(self.pressed) {
		self.pressed = false;
		if(GuiComponent.contains(self.pos, self.size, mousePosition)) {
			self.state = !self.state;
			self.onAction(self.state);
		}
	}
}

pub fn render(self: *CheckBox, mousePosition: Vec2f) !void {
	if(self.state) {
		textureChecked.bindTo(0);
	} else {
		textureEmpty.bindTo(0);
	}
	Button.shader.bind();
	graphics.c.glUniform1i(Button.buttonUniforms.pressed, 0);
	if(self.pressed) {
		draw.setColor(0xff000000);
		graphics.c.glUniform1i(Button.buttonUniforms.pressed, 1);
	} else if(GuiComponent.contains(self.pos, self.size, mousePosition) and self.hovered) {
		draw.setColor(0xff000040);
	} else {
		draw.setColor(0xff000000);
	}
	self.hovered = false;
	draw.customShadedRect(Button.buttonUniforms, self.pos + Vec2f{0, self.size[1]/2 - boxSize/2}, @as(Vec2f, @splat(boxSize)));
	graphics.c.glUniform1i(Button.buttonUniforms.pressed, 0);
	const textPos = self.pos + Vec2f{boxSize/2, 0} + self.size/@as(Vec2f, @splat(2.0)) - self.label.size/@as(Vec2f, @splat(2.0));
	self.label.pos = textPos;
	try self.label.render(mousePosition - textPos);
}