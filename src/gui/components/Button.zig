const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const Image = graphics.Image;
const Shader = graphics.Shader;
const TextBuffer = graphics.TextBuffer;
const Texture = graphics.Texture;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const Label = GuiComponent.Label;

const Button = @This();

const border: f32 = 3;
const fontSize: f32 = 16;

var texture: Texture = undefined;
pub var shader: Shader = undefined;
pub var buttonUniforms: struct {
	screen: c_int,
	start: c_int,
	size: c_int,
	color: c_int,
	scale: c_int,

	image: c_int,
	pressed: c_int,
} = undefined;

pressed: bool = false,
onAction: *const fn() void,
textSize: Vec2f,
label: Label,

pub fn __init() !void {
	shader = try Shader.create("assets/cubyz/shaders/ui/button.vs", "assets/cubyz/shaders/ui/button.fs");
	buttonUniforms = shader.bulkGetUniformLocation(@TypeOf(buttonUniforms));
	shader.bind();
	graphics.c.glUniform1i(buttonUniforms.image, 0);
	texture = Texture.init();
	const image = try Image.readFromFile(main.threadAllocator, "assets/cubyz/ui/button.png");
	defer image.deinit(main.threadAllocator);
	try texture.generate(image);
}

pub fn __deinit() void {
	shader.delete();
	texture.deinit();
}

fn defaultOnAction() void {}

pub fn init(pos: Vec2f, width: f32, text: []const u8, onAction: ?*const fn() void) Allocator.Error!GuiComponent {
	const labelComponent = try Label.init(undefined, width - 3*border, text, .center);
	var self = Button {
		.onAction = if(onAction) |a| a else &defaultOnAction,
		.label = labelComponent.impl.label,
		.textSize = labelComponent.size,
	};
	return GuiComponent {
		.pos = pos,
		.size = Vec2f{width, self.textSize[1] + 3*border},
		.impl = .{.button = self}
	};
}

pub fn deinit(self: Button) void {
	self.label.deinit();
}

pub fn mainButtonPressed(self: *Button, _: Vec2f, _: Vec2f, _: Vec2f) void {
	self.pressed = true;
}

pub fn mainButtonReleased(self: *Button, pos: Vec2f, size: Vec2f, mousePosition: Vec2f) void {
	if(self.pressed) {
		self.pressed = false;
		if(GuiComponent.contains(pos, size, mousePosition)) {
			self.onAction();
		}
	}
}

pub fn render(self: *Button, pos: Vec2f, size: Vec2f, mousePosition: Vec2f) !void {
	graphics.c.glActiveTexture(graphics.c.GL_TEXTURE0);
	texture.bind();
	shader.bind();
	graphics.c.glUniform1i(buttonUniforms.pressed, 0);
	if(self.pressed) {
		draw.setColor(0xff000000);
		graphics.c.glUniform1i(buttonUniforms.pressed, 1);
	} else if(GuiComponent.contains(pos, size, mousePosition)) {
		draw.setColor(0xff000040);
	} else {
		draw.setColor(0xff000000);
	}
	draw.customShadedRect(buttonUniforms, pos, size);
	graphics.c.glUniform1i(buttonUniforms.pressed, 0);
	const textPos = pos + size/@splat(2, @as(f32, 2.0)) - self.textSize/@splat(2, @as(f32, 2.0));
	try self.label.render(textPos, self.textSize, mousePosition - textPos);
}