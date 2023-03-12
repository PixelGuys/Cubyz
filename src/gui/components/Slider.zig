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

const Slider = @This();

const border: f32 = 3;
const fontSize: f32 = 16;

var texture: Texture = undefined;

callback: *const fn(u16) void,
currentSelection: u16,
text: []const u8,
currentText: []u8,
values: [][]const u8,
label: Label,
labelSize: Vec2f,
button: Button,
buttonSize: Vec2f,
buttonPos: Vec2f = .{0, 0},
mouseAnchor: f32 = undefined,

pub fn __init() !void {
	texture = Texture.init();
	const image = try Image.readFromFile(main.threadAllocator, "assets/cubyz/ui/slider.png");
	defer image.deinit(main.threadAllocator);
	try texture.generate(image);
}

pub fn __deinit() void {
	texture.deinit();
}

pub fn init(pos: Vec2f, width: f32, text: []const u8, comptime fmt: []const u8, valueList: anytype, initialValue: u16, callback: *const fn(u16) void) Allocator.Error!GuiComponent {
	var values = try gui.allocator.alloc([]const u8, valueList.len);
	var maxLen: usize = 0;
	for(valueList, 0..) |value, i| {
		values[i] = try std.fmt.allocPrint(gui.allocator, fmt, .{value});
		maxLen = @max(maxLen, values[i].len);
	}

	const initialText = try gui.allocator.alloc(u8, text.len + maxLen);
	std.mem.copy(u8, initialText, text);
	std.mem.set(u8, initialText[text.len..], ' ');
	const labelComponent = try Label.init(undefined, width - 3*border, initialText, .center);
	const buttonComponent = try Button.init(undefined, undefined, "", null);
	var self = Slider {
		.callback = callback,
		.currentSelection = initialValue,
		.text = text,
		.currentText = initialText,
		.label = labelComponent.impl.label,
		.button = buttonComponent.impl.button,
		.labelSize = labelComponent.size,
		.buttonSize = .{16, 16},
		.values = values,
	};
	self.buttonPos[1] = self.labelSize[1] + 3.5*border;
	const size = Vec2f{@max(width, self.labelSize[0] + 3*border), self.labelSize[1] + self.buttonSize[1] + 5*border};
	try self.setButtonPosFromValue(size);
	return GuiComponent {
		.pos = pos,
		.size = size,
		.impl = .{.slider = self}
	};
}

pub fn deinit(self: Slider) void {
	self.label.deinit();
	self.button.deinit();
	for(self.values) |value| {
		gui.allocator.free(value);
	}
	gui.allocator.free(self.values);
	gui.allocator.free(self.currentText);
}

fn setButtonPosFromValue(self: *Slider, size: Vec2f) !void {
	const range: f32 = size[0] - 3*border - self.buttonSize[0];
	self.buttonPos[0] = 1.5*border + range*(0.5 + @intToFloat(f32, self.currentSelection))/@intToFloat(f32, self.values.len);
	try self.updateLabel(self.values[self.currentSelection], size[0]);
}

fn updateLabel(self: *Slider, newValue: []const u8, width: f32) !void {
	gui.allocator.free(self.currentText);
	self.currentText = try gui.allocator.alloc(u8, newValue.len + self.text.len);
	std.mem.copy(u8, self.currentText, self.text);
	std.mem.copy(u8, self.currentText[self.text.len..], newValue);
	const labelComponent = try Label.init(undefined, width - 3*border, self.currentText, .center);
	self.label.deinit();
	self.label = labelComponent.impl.label;
}

fn updateValueFromButtonPos(self: *Slider, size: Vec2f) !void {
	const range: f32 = size[0] - 3*border - self.buttonSize[0];
	const selection = @floatToInt(u16, (self.buttonPos[0] - 1.5*border)/range*@intToFloat(f32, self.values.len));
	if(selection != self.currentSelection) {
		self.currentSelection = selection;
		try self.updateLabel(self.values[selection], size[0]);
		self.callback(selection);
	}
}

pub fn updateHovered(self: *Slider, pos: Vec2f, _: Vec2f, mousePosition: Vec2f) void {
	if(GuiComponent.contains(self.buttonPos + pos, self.buttonSize, mousePosition)) {
		self.button.updateHovered(self.buttonPos, self.buttonSize, mousePosition - pos);
	}
}

pub fn mainButtonPressed(self: *Slider, pos: Vec2f, _: Vec2f, mousePosition: Vec2f) void {
	if(GuiComponent.contains(self.buttonPos, self.buttonSize, mousePosition - pos)) {
		self.button.mainButtonPressed(self.buttonPos, self.buttonSize, mousePosition - pos);
		self.mouseAnchor = mousePosition[0] - self.buttonPos[0];
	}
}

pub fn mainButtonReleased(self: *Slider, _: Vec2f, _: Vec2f, _: Vec2f) void {
	self.button.mainButtonReleased(undefined, undefined, undefined);
}

pub fn render(self: *Slider, pos: Vec2f, size: Vec2f, mousePosition: Vec2f) !void {
	graphics.c.glActiveTexture(graphics.c.GL_TEXTURE0);
	texture.bind();
	Button.shader.bind();
	draw.setColor(0xff000000);
	draw.customShadedRect(Button.buttonUniforms, pos, size);

	const range: f32 = size[0] - 3*border - self.buttonSize[0];
	draw.setColor(0x80000000);
	draw.rect(pos + Vec2f{1.5*border + self.buttonSize[0]/2, self.buttonPos[1] + self.buttonSize[1]/2 - border}, .{range, 2*border});

	const labelPos = pos + @splat(2, 1.5*border);
	try self.label.render(labelPos, self.labelSize, mousePosition);

	if(self.button.pressed) {
		self.buttonPos[0] = mousePosition[0] - self.mouseAnchor;
		self.buttonPos[0] = @min(@max(self.buttonPos[0], 1.5*border), 1.5*border + range - 0.001);
		try self.updateValueFromButtonPos(size);
	}
	try self.button.render(pos + self.buttonPos, self.buttonSize, mousePosition);
}