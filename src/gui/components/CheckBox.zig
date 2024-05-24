const std = @import("std");

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

var textureCheckedNormal: Texture = undefined;
var textureCheckedHovered: Texture = undefined;
var textureCheckedPressed: Texture = undefined;
var textureEmptyNormal: Texture = undefined;
var textureEmptyHovered: Texture = undefined;
var textureEmptyPressed: Texture = undefined;

pos: Vec2f,
size: Vec2f,
state: bool = false,
pressed: bool = false,
hovered: bool = false,
onAction: *const fn(bool) void,
label: *Label,

pub fn __init() void {
	textureCheckedNormal = Texture.initFromFile("assets/cubyz/ui/checked_box.png");
	textureCheckedHovered = Texture.initFromFile("assets/cubyz/ui/checked_box_hovered.png");
	textureCheckedPressed = Texture.initFromFile("assets/cubyz/ui/checked_box_pressed.png");
	textureEmptyNormal = Texture.initFromFile("assets/cubyz/ui/box.png");
	textureEmptyHovered = Texture.initFromFile("assets/cubyz/ui/box_hovered.png");
	textureEmptyPressed = Texture.initFromFile("assets/cubyz/ui/box_pressed.png");
}

pub fn __deinit() void {
	textureCheckedNormal.deinit();
	textureCheckedHovered.deinit();
	textureCheckedPressed.deinit();
	textureEmptyNormal.deinit();
	textureEmptyHovered.deinit();
	textureEmptyPressed.deinit();
}

pub fn init(pos: Vec2f, width: f32, text: []const u8, initialValue: bool, onAction: *const fn(bool) void) *CheckBox {
	const label = Label.init(undefined, width - 3*border - boxSize, text, .left);
	const self = main.globalAllocator.create(CheckBox);
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

pub fn render(self: *CheckBox, mousePosition: Vec2f) void {
	if(self.state) {
		if(self.pressed) {
			textureCheckedPressed.bindTo(0);
		} else if(GuiComponent.contains(self.pos, self.size, mousePosition) and self.hovered) {
			textureCheckedHovered.bindTo(0);
		} else {
			textureCheckedNormal.bindTo(0);
		}
	} else {
		if(self.pressed) {
			textureEmptyPressed.bindTo(0);
		} else if(GuiComponent.contains(self.pos, self.size, mousePosition) and self.hovered) {
			textureEmptyHovered.bindTo(0);
		} else {
			textureEmptyNormal.bindTo(0);
		}
	}
	Button.shader.bind();
	self.hovered = false;
	draw.customShadedRect(Button.buttonUniforms, self.pos + Vec2f{0, self.size[1]/2 - boxSize/2}, @as(Vec2f, @splat(boxSize)));
	const textPos = self.pos + Vec2f{boxSize/2, 0} + self.size/@as(Vec2f, @splat(2.0)) - self.label.size/@as(Vec2f, @splat(2.0));
	self.label.pos = textPos;
	self.label.render(mousePosition - textPos);
}