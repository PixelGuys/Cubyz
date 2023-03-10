const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const Image = graphics.Image;
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

state: bool = false,
pressed: bool = false,
onAction: *const fn(bool) void,
textSize: Vec2f,
label: Label,

pub fn __init() !void {
	textureChecked = Texture.init();
	const imageChecked = try Image.readFromFile(main.threadAllocator, "assets/cubyz/ui/checked_box.png");
	defer imageChecked.deinit(main.threadAllocator);
	try textureChecked.generate(imageChecked);

	textureEmpty = Texture.init();
	const imageEmpty = try Image.readFromFile(main.threadAllocator, "assets/cubyz/ui/box.png");
	defer imageEmpty.deinit(main.threadAllocator);
	try textureEmpty.generate(imageEmpty);
}

pub fn __deinit() void {
	textureChecked.deinit();
	textureEmpty.deinit();
}

pub fn init(pos: Vec2f, width: f32, text: []const u8, initialValue: bool, onAction: *const fn(bool) void) Allocator.Error!GuiComponent {
	const labelComponent = try Label.init(undefined, width - 3*border - boxSize, text, .left);
	var self = CheckBox {
		.state = initialValue,
		.onAction = onAction,
		.label = labelComponent.impl.label,
		.textSize = labelComponent.size,
	};
	return GuiComponent {
		.pos = pos,
		.size = Vec2f{@max(width, self.textSize[0] + 3*border + boxSize), self.textSize[1] + 3*border},
		.impl = .{.checkBox = self}
	};
}

pub fn deinit(self: CheckBox) void {
	self.label.deinit();
}

pub fn mainButtonPressed(self: *CheckBox, _: Vec2f, _: Vec2f, _: Vec2f) void {
	self.pressed = true;
}

pub fn mainButtonReleased(self: *CheckBox, pos: Vec2f, size: Vec2f, mousePosition: Vec2f) void {
	if(self.pressed) {
		self.pressed = false;
		if(GuiComponent.contains(pos, size, mousePosition)) {
			self.state = !self.state;
			self.onAction(self.state);
		}
	}
}

pub fn render(self: *CheckBox, pos: Vec2f, size: Vec2f, mousePosition: Vec2f) !void {
	graphics.c.glActiveTexture(graphics.c.GL_TEXTURE0);
	if(self.state) {
		textureChecked.bind();
	} else {
		textureEmpty.bind();
	}
	Button.shader.bind();
	graphics.c.glUniform1i(Button.buttonUniforms.pressed, 0);
	if(self.pressed) {
		draw.setColor(0xff000000);
		graphics.c.glUniform1i(Button.buttonUniforms.pressed, 1);
	} else if(GuiComponent.contains(pos, size, mousePosition)) {
		draw.setColor(0xff000040);
	} else {
		draw.setColor(0xff000000);
	}
	draw.customShadedRect(Button.buttonUniforms, pos + Vec2f{0, size[1]/2 - boxSize/2}, @splat(2, boxSize));
	graphics.c.glUniform1i(Button.buttonUniforms.pressed, 0);
	const textPos = pos + Vec2f{boxSize/2, 0} + size/@splat(2, @as(f32, 2.0)) - self.textSize/@splat(2, @as(f32, 2.0));
	try self.label.render(textPos, self.textSize, mousePosition - textPos);
}