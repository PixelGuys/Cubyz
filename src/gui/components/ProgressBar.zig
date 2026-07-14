const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const TextBuffer = graphics.TextBuffer;
const Texture = graphics.Texture;
const random = main.random;
const vec = main.vec;
const Vec2f = vec.Vec2f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const Button = GuiComponent.Button;
const Label = GuiComponent.Label;

const ProgressBar = @This();

const border: f32 = 3;
const fontSize: f32 = 16;

var texture: Texture = undefined;

pos: Vec2f,
size: Vec2f,
minValue: f32,
maxValue: f32,
callback: *const fn (f32) void,
formatter: *const fn (NeverFailingAllocator, f32) []const u8,
currentValue: f32,
currentText: []const u8,
label: *Label,
mouseAnchor: f32 = undefined,

pub fn globalInit() void {
	texture = Texture.initFromFile("assets/cubyz/ui/slider.png");
}

pub fn globalDeinit() void {
	texture.deinit();
}

pub fn init(pos: Vec2f, width: f32, callback: *const fn (f32) void, formatter: *const fn (NeverFailingAllocator, f32) []const u8) *ProgressBar {
	const minValue = 0;
	const maxValue = 100;
	const initialValue = 0;
	const initialText = formatter(main.globalAllocator, initialValue);
	const label = Label.init(undefined, width - 3*border, initialText, .center);
	const self = main.globalAllocator.create(ProgressBar);
	self.* = ProgressBar{
		.pos = pos,
		.size = undefined,
		.minValue = minValue,
		.maxValue = maxValue,
		.callback = callback,
		.formatter = formatter,
		.currentValue = initialValue,
		.currentText = initialText,
		.label = label,
	};
	self.size = Vec2f{@max(width, self.label.size[0] + 3*border), self.label.size[1] + 5*border};
	self.updateLabel(self.currentValue, self.size[0]);
	return self;
}

pub fn toComponent(self: *ProgressBar) GuiComponent {
	return .{.progressBar = self};
}

fn updateLabel(self: *ProgressBar, newValue: f32, width: f32) void {
	main.globalAllocator.free(self.currentText);
	self.currentText = self.formatter(main.globalAllocator, newValue);
	const label = Label.init(undefined, width - 3*border, self.currentText, .center);
	self.label.deinit();
	self.label = label;
}

inline fn getBarSize(self: *ProgressBar) Vec2f {
	const range: f32 = self.size[0] - 3*border;
	return .{range, 2*border};
}

pub fn deinit(self: *const ProgressBar) void {
	self.label.deinit();
	main.globalAllocator.free(self.currentText);
	main.globalAllocator.destroy(self);
}

pub fn render(self: *ProgressBar, mousePosition: Vec2f) void {
	texture.bindTo(0);
	Button.pipeline.bind(draw.getScissor());
	draw.customShadedRect(Button.buttonUniforms, self.pos, self.size);

	{
		const oldColor = draw.setColor(0x80000000);
		defer draw.restoreColor(oldColor);
		draw.rect(self.pos, self.getBarSize());
	}

	self.label.pos = self.pos + @as(Vec2f, @splat(1.5*border));
	self.label.render(mousePosition);

	drawBar(self);

	const oldTranslation = draw.setTranslation(self.pos);
	defer draw.restoreTranslation(oldTranslation);
}

fn drawBar(self: *ProgressBar) void {
	const oldColor = draw.setColor(0x300000ff);
	defer draw.restoreColor(oldColor);
	const range: f32 = self.size[0] - 3*border;
	const len: f32 = self.maxValue - self.minValue;
	const val = std.math.clamp(self.currentValue, self.minValue, self.maxValue);
	const horizontalProgress = 1.5*border + range*(val - self.minValue)/len;
	var newPos: Vec2f = self.pos;
	newPos[0] = newPos[0];
	var newSize: Vec2f = self.size;
	newSize[0] = horizontalProgress;
	draw.rect(newPos, newSize);
}
