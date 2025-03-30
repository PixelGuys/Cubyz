const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const Texture = graphics.Texture;
const Vec2f = main.vec.Vec2f;

const gui = @import("gui.zig");

const size: f32 = 16;

var texture: Texture = undefined;

pub fn init() void {
	texture = Texture.initFromFile("assets/cubyz/ui/gamepad_cursor.png");
}

pub fn deinit() void {
	texture.deinit();
}

pub fn render() void {
	if(main.Window.lastUsedMouse or main.Window.grabbed) return;
	texture.bindTo(0);
	graphics.draw.setColor(0xffffffff);
	const mousePos = main.Window.getMousePosition();
	graphics.draw.boundImage(@as(Vec2f, @splat(-size/2.0)) + (mousePos/@as(Vec2f, @splat(gui.scale))), .{size, size});
}
