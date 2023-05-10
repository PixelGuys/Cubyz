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

pos: Vec2f,
size: Vec2f,
currentState: f32,
button: *Button,
mouseAnchor: f32 = undefined,

pub fn __init() !void {
	texture = try Texture.initFromFile("assets/cubyz/ui/scrollbar.png");
}

pub fn __deinit() void {
	texture.deinit();
}

pub fn init(pos: Vec2f, width: f32, height: f32, initialState: f32) Allocator.Error!*ScrollBar {
	const button = try Button.initText(.{0, 0}, undefined, "", .{});
	const self = try main.globalAllocator.create(ScrollBar);
	self.* = ScrollBar {
		.pos = pos,
		.size = Vec2f{width, height},
		.currentState = initialState,
		.button = button,
	};
	self.button.size = .{width, 16};
	self.setButtonPosFromValue();
	return self;
}

pub fn deinit(self: *const ScrollBar) void {
	self.button.deinit();
	main.globalAllocator.destroy(self);
}

pub fn toComponent(self: *ScrollBar) GuiComponent {
	return GuiComponent{
		.scrollBar = self
	};
}

fn setButtonPosFromValue(self: *ScrollBar) void {
	const range: f32 = self.size[1] - self.button.size[1];
	self.button.pos[1] = range*self.currentState;
}

fn updateValueFromButtonPos(self: *ScrollBar) void {
	const range: f32 = self.size[1] - self.button.size[1];
	const value = self.button.pos[1]/range;
	if(value != self.currentState) {
		self.currentState = value;
	}
}

pub fn scroll(self: *ScrollBar, offset: f32) void {
	self.currentState += offset;
	self.currentState = @min(1.0, @max(0.0, self.currentState)); // TODO: #15644
}

pub fn updateHovered(self: *ScrollBar, mousePosition: Vec2f) void {
	if(GuiComponent.contains(self.button.pos, self.button.size, mousePosition - self.pos)) {
		self.button.updateHovered(mousePosition - self.pos);
	}
}

pub fn mainButtonPressed(self: *ScrollBar, mousePosition: Vec2f) void {
	if(GuiComponent.contains(self.button.pos, self.button.size, mousePosition - self.pos)) {
		self.button.mainButtonPressed(mousePosition - self.pos);
		self.mouseAnchor = mousePosition[1] - self.button.pos[1];
	}
}

pub fn mainButtonReleased(self: *ScrollBar, mousePosition: Vec2f) void {
	self.button.mainButtonReleased(mousePosition - self.pos);
}

pub fn render(self: *ScrollBar, mousePosition: Vec2f) !void {
	texture.bindTo(0);
	Button.shader.bind();
	draw.setColor(0xff000000);
	draw.customShadedRect(Button.buttonUniforms, self.pos, self.size);

	const range: f32 = self.size[1] - self.button.size[1];
	self.setButtonPosFromValue();
	if(self.button.pressed) {
		self.button.pos[1] = mousePosition[1] - self.mouseAnchor;
		self.button.pos[1] = @min(@max(self.button.pos[1], 0.0), range - 0.001); // TODO: #15644
		self.updateValueFromButtonPos();
	}
	const oldTranslation = draw.setTranslation(self.pos);
	defer draw.restoreTranslation(oldTranslation);
	try self.button.render(mousePosition - self.pos);
}