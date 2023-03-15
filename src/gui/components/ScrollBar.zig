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

const ScrollBar = @This();

const fontSize: f32 = 16;

var texture: Texture = undefined;

currentState: f32,
button: Button,
buttonSize: Vec2f,
buttonPos: Vec2f = .{0, 0},
mouseAnchor: f32 = undefined,

pub fn __init() !void {
	texture = try Texture.initFromFile("assets/cubyz/ui/scrollbar.png");
}

pub fn __deinit() void {
	texture.deinit();
}

pub fn init(pos: Vec2f, width: f32, height: f32, initialState: f32) Allocator.Error!GuiComponent {
	const buttonComponent = try Button.init(undefined, undefined, "", null);
	var self = ScrollBar {
		.currentState = initialState,
		.button = buttonComponent.impl.button,
		.buttonSize = .{width, 16},
	};
	const size = Vec2f{width, height};
	self.setButtonPosFromValue(size);
	return GuiComponent {
		.pos = pos,
		.size = size,
		.impl = .{.scrollBar = self}
	};
}

pub fn deinit(self: ScrollBar) void {
	self.button.deinit();
}

fn setButtonPosFromValue(self: *ScrollBar, size: Vec2f) void {
	const range: f32 = size[1] - self.buttonSize[1];
	self.buttonPos[1] = range*self.currentState;
}

fn updateValueFromButtonPos(self: *ScrollBar, size: Vec2f) void {
	const range: f32 = size[1] - self.buttonSize[1];
	const value = self.buttonPos[1]/range;
	if(value != self.currentState) {
		self.currentState = value;
	}
}

pub fn scroll(self: *ScrollBar, offset: f32) void {
	self.currentState += offset;
	self.currentState = @min(1, @max(0, self.currentState));
}

pub fn updateHovered(self: *ScrollBar, pos: Vec2f, _: Vec2f, mousePosition: Vec2f) void {
	if(GuiComponent.contains(self.buttonPos + pos, self.buttonSize, mousePosition)) {
		self.button.updateHovered(self.buttonPos, self.buttonSize, mousePosition - pos);
	}
}

pub fn mainButtonPressed(self: *ScrollBar, pos: Vec2f, _: Vec2f, mousePosition: Vec2f) void {
	if(GuiComponent.contains(self.buttonPos, self.buttonSize, mousePosition - pos)) {
		self.button.mainButtonPressed(self.buttonPos, self.buttonSize, mousePosition - pos);
		self.mouseAnchor = mousePosition[1] - self.buttonPos[1];
	}
}

pub fn mainButtonReleased(self: *ScrollBar, _: Vec2f, _: Vec2f, _: Vec2f) void {
	self.button.mainButtonReleased(undefined, undefined, undefined);
}

pub fn render(self: *ScrollBar, pos: Vec2f, size: Vec2f, mousePosition: Vec2f) !void {
	graphics.c.glActiveTexture(graphics.c.GL_TEXTURE0);
	texture.bind();
	Button.shader.bind();
	draw.setColor(0xff000000);
	draw.customShadedRect(Button.buttonUniforms, pos, size);

	const range: f32 = size[1] - self.buttonSize[1];
	self.setButtonPosFromValue(size);
	if(self.button.pressed) {
		self.buttonPos[1] = mousePosition[1] - self.mouseAnchor;
		self.buttonPos[1] = @min(@max(self.buttonPos[1], 0), range - 0.001);
		self.updateValueFromButtonPos(size);
	}
	try self.button.render(pos + self.buttonPos, self.buttonSize, mousePosition);
}