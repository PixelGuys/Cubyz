const std = @import("std");
const Allocator = std.mem.Allocator;

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
	.title = "Crosshair",
	.id = "crosshair",
	.showTitleBar = false,
	.hasBackground = false,
	.isHud = true,
};

var texture: Texture = undefined;

pub fn init() !void {
	texture = try Texture.initFromFile("assets/cubyz/ui/hud/crosshair.png");
}

pub fn deinit() void {
	texture.deinit();
}

pub fn render() Allocator.Error!void {
	texture.bindTo(0);
	graphics.draw.setColor(0xffffffff);
	graphics.draw.boundImage(.{0, 0}, .{size, size});
}