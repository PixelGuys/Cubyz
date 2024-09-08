const std = @import("std");

const main = @import("root");
const graphics = main.graphics;
const Shader = graphics.Shader;
const Texture = graphics.Texture;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

const size: f32 = 64;
pub var window = GuiWindow {
	.contentSize = Vec2f{size, size},
	.showTitleBar = false,
	.hasBackground = false,
	.isHud = false,
	.hideIfMouseIsGrabbed = true,
	.closeable = true,
};

var texture: Texture = undefined;

pub fn init() void {
	texture = Texture.initFromFile("assets/cubyz/ui/hud/crosshair.png");
	main.gui.openWindow("cursor");
}

pub fn deinit() void {
	texture.deinit();
}

pub fn render() void {
	if (main.Window.lastUsedMouse) return;
	texture.bindTo(0);
	graphics.draw.setColor(0xffffffff);
	const mousePos = main.Window.getMousePosition();
	window.pos = mousePos / @as(Vec2f, @splat(window.scale * gui.scale));
	graphics.draw.boundImage(@as(Vec2f, @splat(-size / 2.0)), .{size, size});
}
