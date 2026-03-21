const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const Texture = graphics.Texture;
const draw = graphics.draw;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const Label = @import("../components/Label.zig");
const Icon = @import("../components/Icon.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.relativePosition = .{.{.ratio = 0.5}, .{.ratio = 0.25}},
	.closeable = false,
	.hasBackground = false,
	.showTitleBar = false,
};

const padding: f32 = 8;

var wordmark: Texture = undefined;

pub fn init() void {
	wordmark = Texture.initFromFile("assets/cubyz/ui/wordmark.png");
}

pub fn deinit() void {
	wordmark.deinit();
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 2);
	list.add(Icon.init(.{0, 0}, .{360, 104}, wordmark, false));
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
