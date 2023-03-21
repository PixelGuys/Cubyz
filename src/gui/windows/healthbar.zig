const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

pub var window = GuiWindow {
	.contentSize = Vec2f{128, 16},
	.title = "Health Bar",
	.id = "cubyz:healthbar",
	.renderFn = &render,
	.isHud = true,
	.showTitleBar = false,
	.hasBackground = false,
};

var heartTexture: Texture = undefined;
var halfHeartTexture: Texture = undefined;
var deadHeartTexture: Texture = undefined;

pub fn init() !void {
	heartTexture = try Texture.initFromFile("assets/cubyz/ui/hud/heart.png");
	halfHeartTexture = try Texture.initFromFile("assets/cubyz/ui/hud/half_heart.png");
	deadHeartTexture = try Texture.initFromFile("assets/cubyz/ui/hud/dead_heart.png");
}

pub fn deinit() void {
	heartTexture.deinit();
	halfHeartTexture.deinit();
	deadHeartTexture.deinit();
}

pub fn render() Allocator.Error!void {
	draw.setColor(0xffffffff);
	var y: f32 = 0;
	var x: f32 = 0;
	for(0..@floatToInt(usize, main.game.Player.maxHealth)) |health| {
		if(x >= window.size[0]) {
			x = 0;
			y += 16;
		}
		if(@intToFloat(f32, health) + 1 <= main.game.Player.health) {
			heartTexture.bindTo(0);
		} else if(@intToFloat(f32, health) + 0.5 <= main.game.Player.health) {
			halfHeartTexture.bindTo(0);
		} else {
			deadHeartTexture.bindTo(0);
		}
		draw.boundImage(Vec2f{x, window.contentSize[1] - y - 16}, .{16, 16});
		x += 16;
	}
	y += 16;
	if(y != window.contentSize[1]) {
		window.contentSize[1] = y;
		gui.updateWindowPositions();
	}
}