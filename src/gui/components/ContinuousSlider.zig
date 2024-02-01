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
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const Button = GuiComponent.Button;
const Label = GuiComponent.Label;

const ContinuousSlider = @This();

const border: f32 = 3;
const fontSize: f32 = 16;

var texture: Texture = undefined;

pos: Vec2f,
size: Vec2f,
minValue: f32,
maxValue: f32,
callback: *const fn(f32) void,
formatter: *const fn(NeverFailingAllocator, f32) []const u8,
currentValue: f32,
currentText: []const u8,
label: *Label,
button: *Button,
mouseAnchor: f32 = undefined,

pub fn __init() void {
	texture = Texture.initFromFile("assets/cubyz/ui/slider.png");
}

pub fn __deinit() void {
	texture.deinit();
}

pub fn init(pos: Vec2f, width: f32, minValue: f32, maxValue: f32, initialValue: f32, callback: *const fn(f32) void, formatter: *const fn(NeverFailingAllocator, f32) []const u8) *ContinuousSlider {
	const initialText = formatter(main.globalAllocator, initialValue);
	const label = Label.init(undefined, width - 3*border, initialText, .center);
	const button = Button.initText(.{0, 0}, undefined, "", .{});
	const self = main.globalAllocator.create(ContinuousSlider);
	self.* = ContinuousSlider {
		.pos = pos,
		.size = undefined,
		.minValue = minValue,
		.maxValue = maxValue,
		.callback = callback,
		.formatter = formatter,
		.currentValue = initialValue,
		.currentText = initialText,
		.label = label,
		.button = button,
	};
	self.button.size = .{16, 16};
	self.button.pos[1] = self.label.size[1] + 3.5*border;
	self.size = Vec2f{@max(width, self.label.size[0] + 3*border), self.label.size[1] + self.button.size[1] + 5*border};
	self.setButtonPosFromValue();
	return self;
}

pub fn deinit(self: *const ContinuousSlider) void {
	self.label.deinit();
	self.button.deinit();
	main.globalAllocator.free(self.currentText);
	main.globalAllocator.destroy(self);
}

pub fn toComponent(self: *ContinuousSlider) GuiComponent {
	return GuiComponent {
		.continuousSlider = self
	};
}

fn setButtonPosFromValue(self: *ContinuousSlider) void {
	const range: f32 = self.size[0] - 3*border - self.button.size[0];
	const len: f32 = self.maxValue - self.minValue;
	self.button.pos[0] = 1.5*border + range*(0.5 + (self.currentValue - self.minValue))/len;
	self.updateLabel(self.currentValue, self.size[0]);
}

fn updateLabel(self: *ContinuousSlider, newValue: f32, width: f32) void {
	main.globalAllocator.free(self.currentText);
	self.currentText = self.formatter(main.globalAllocator, newValue);
	const label = Label.init(undefined, width - 3*border, self.currentText, .center);
	self.label.deinit();
	self.label = label;
}

fn updateValueFromButtonPos(self: *ContinuousSlider) void {
	const range: f32 = self.size[0] - 3*border - self.button.size[0];
	const len: f32 = self.maxValue - self.minValue;
	const value: f32 = (self.button.pos[0] - 1.5*border)/range*len + self.minValue;
	if(value != self.currentValue) {
		self.currentValue = value;
		self.updateLabel(value, self.size[0]);
		self.callback(value);
	}
}

pub fn updateHovered(self: *ContinuousSlider, mousePosition: Vec2f) void {
	if(GuiComponent.contains(self.button.pos, self.button.size, mousePosition - self.pos)) {
		self.button.updateHovered(mousePosition - self.pos);
	}
}

pub fn mainButtonPressed(self: *ContinuousSlider, mousePosition: Vec2f) void {
	if(GuiComponent.contains(self.button.pos, self.button.size, mousePosition - self.pos)) {
		self.button.mainButtonPressed(mousePosition - self.pos);
		self.mouseAnchor = mousePosition[0] - self.button.pos[0];
	}
}

pub fn mainButtonReleased(self: *ContinuousSlider, _: Vec2f) void {
	self.button.mainButtonReleased(undefined);
}

pub fn render(self: *ContinuousSlider, mousePosition: Vec2f) void {
	texture.bindTo(0);
	Button.shader.bind();
	draw.setColor(0xff000000);
	draw.customShadedRect(Button.buttonUniforms, self.pos, self.size);

	const range: f32 = self.size[0] - 3*border - self.button.size[0];
	draw.setColor(0x80000000);
	draw.rect(self.pos + Vec2f{1.5*border + self.button.size[0]/2, self.button.pos[1] + self.button.size[1]/2 - border}, .{range, 2*border});

	self.label.pos = self.pos + @as(Vec2f, @splat(1.5*border));
	self.label.render(mousePosition);

	if(self.button.pressed) {
		self.button.pos[0] = mousePosition[0] - self.mouseAnchor;
		self.button.pos[0] = @min(@max(self.button.pos[0], 1.5*border), 1.5*border + range - 0.001);
		self.updateValueFromButtonPos();
	}
	const oldTranslation = draw.setTranslation(self.pos);
	defer draw.restoreTranslation(oldTranslation);
	self.button.render(mousePosition - self.pos);
}