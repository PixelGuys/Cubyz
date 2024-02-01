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

const DiscreteSlider = @This();

const border: f32 = 3;
const fontSize: f32 = 16;

var texture: Texture = undefined;

pos: Vec2f,
size: Vec2f,
callback: *const fn(u16) void,
currentSelection: u16,
text: []const u8,
currentText: []u8,
values: [][]const u8,
label: *Label,
button: *Button,
mouseAnchor: f32 = undefined,

pub fn __init() void {
	texture = Texture.initFromFile("assets/cubyz/ui/slider.png");
}

pub fn __deinit() void {
	texture.deinit();
}

pub fn init(pos: Vec2f, width: f32, text: []const u8, comptime fmt: []const u8, valueList: anytype, initialValue: u16, callback: *const fn(u16) void) *DiscreteSlider {
	const values = main.globalAllocator.alloc([]const u8, valueList.len);
	var maxLen: usize = 0;
	for(valueList, 0..) |value, i| {
		values[i] = std.fmt.allocPrint(main.globalAllocator.allocator, fmt, .{value}) catch unreachable;
		maxLen = @max(maxLen, values[i].len);
	}

	const initialText = main.globalAllocator.alloc(u8, text.len + maxLen);
	@memcpy(initialText[0..text.len], text);
	@memset(initialText[text.len..], ' ');
	const label = Label.init(undefined, width - 3*border, initialText, .center);
	const button = Button.initText(.{0, 0}, undefined, "", .{});
	const self = main.globalAllocator.create(DiscreteSlider);
	self.* = DiscreteSlider {
		.pos = pos,
		.size = undefined,
		.callback = callback,
		.currentSelection = initialValue,
		.text = text,
		.currentText = initialText,
		.label = label,
		.button = button,
		.values = values,
	};
	self.button.size = .{16, 16};
	self.button.pos[1] = self.label.size[1] + 3.5*border;
	self.size = Vec2f{@max(width, self.label.size[0] + 3*border), self.label.size[1] + self.button.size[1] + 5*border};
	self.setButtonPosFromValue();
	return self;
}

pub fn deinit(self: *const DiscreteSlider) void {
	self.label.deinit();
	self.button.deinit();
	for(self.values) |value| {
		main.globalAllocator.free(value);
	}
	main.globalAllocator.free(self.values);
	main.globalAllocator.free(self.currentText);
	main.globalAllocator.destroy(self);
}

pub fn toComponent(self: *DiscreteSlider) GuiComponent {
	return GuiComponent {
		.discreteSlider = self
	};
}

fn setButtonPosFromValue(self: *DiscreteSlider) void {
	const range: f32 = self.size[0] - 3*border - self.button.size[0];
	const len: f32 = @floatFromInt(self.values.len);
	const selection: f32 = @floatFromInt(self.currentSelection);
	self.button.pos[0] = 1.5*border + range*(0.5 + selection)/len;
	self.updateLabel(self.values[self.currentSelection], self.size[0]);
}

fn updateLabel(self: *DiscreteSlider, newValue: []const u8, width: f32) void {
	main.globalAllocator.free(self.currentText);
	self.currentText = main.globalAllocator.alloc(u8, newValue.len + self.text.len);
	@memcpy(self.currentText[0..self.text.len], self.text);
	@memcpy(self.currentText[self.text.len..], newValue);
	const label = Label.init(undefined, width - 3*border, self.currentText, .center);
	self.label.deinit();
	self.label = label;
}

fn updateValueFromButtonPos(self: *DiscreteSlider) void {
	const range: f32 = self.size[0] - 3*border - self.button.size[0];
	const len: f32 = @floatFromInt(self.values.len);
	const selection: u16 = @intFromFloat((self.button.pos[0] - 1.5*border)/range*len);
	if(selection != self.currentSelection) {
		self.currentSelection = selection;
		self.updateLabel(self.values[selection], self.size[0]);
		self.callback(selection);
	}
}

pub fn updateHovered(self: *DiscreteSlider, mousePosition: Vec2f) void {
	if(GuiComponent.contains(self.button.pos, self.button.size, mousePosition - self.pos)) {
		self.button.updateHovered(mousePosition - self.pos);
	}
}

pub fn mainButtonPressed(self: *DiscreteSlider, mousePosition: Vec2f) void {
	if(GuiComponent.contains(self.button.pos, self.button.size, mousePosition - self.pos)) {
		self.button.mainButtonPressed(mousePosition - self.pos);
		self.mouseAnchor = mousePosition[0] - self.button.pos[0];
	}
}

pub fn mainButtonReleased(self: *DiscreteSlider, _: Vec2f) void {
	self.button.mainButtonReleased(undefined);
}

pub fn render(self: *DiscreteSlider, mousePosition: Vec2f) void {
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