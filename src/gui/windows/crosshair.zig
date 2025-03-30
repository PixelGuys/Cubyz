const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const Shader = graphics.Shader;
const Texture = graphics.Texture;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

const size: f32 = 64;
pub var window = GuiWindow{
	.contentSize = Vec2f{size, size},
	.showTitleBar = false,
	.hasBackground = false,
	.isHud = true,
	.hideIfMouseIsGrabbed = false,
	.closeable = false,
};

var texture: Texture = undefined;

pub fn init() void {
	texture = Texture.initFromFile("assets/cubyz/ui/hud/crosshair.png");
}

pub fn deinit() void {
	texture.deinit();
}

pub fn render() void {
	texture.bindTo(0);
	graphics.draw.setColor(0xffffffff);
	graphics.draw.boundImage(.{0, 0}, .{size, size});
}
