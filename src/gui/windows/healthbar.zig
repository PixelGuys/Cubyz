const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

const hotbar = @import("hotbar.zig");

pub var window = GuiWindow{
	.scale = 0.5,
	.relativePosition = .{
		.{.attachedToWindow = .{.reference = &hotbar.window, .selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper}},
		.{.attachedToWindow = .{.reference = &hotbar.window, .selfAttachmentPoint = .upper, .otherAttachmentPoint = .lower}},
	},
	.contentSize = Vec2f{160, 20},
	.isHud = true,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
	.closeable = false,
};

var heartTexture: Texture = undefined;
var halfHeartTexture: Texture = undefined;
var deadHeartTexture: Texture = undefined;

pub fn init() void {
	heartTexture = Texture.initFromFile("assets/cubyz/ui/hud/heart.png");
	halfHeartTexture = Texture.initFromFile("assets/cubyz/ui/hud/half_heart.png");
	deadHeartTexture = Texture.initFromFile("assets/cubyz/ui/hud/dead_heart.png");
}

pub fn deinit() void {
	heartTexture.deinit();
	halfHeartTexture.deinit();
	deadHeartTexture.deinit();
}

pub fn render() void {
	if (main.game.Player.isCreative())
		return;

	draw.setColor(0xffffffff);
	const displayHealth = @max(0, main.game.Player.super.health);
	const halfHeartUnits: usize = @intFromFloat(@ceil(displayHealth*2));
	const wholeHearts = halfHeartUnits/2;
	const halfHeart = halfHeartUnits%2;
	const totalHearts: usize = @intFromFloat(@ceil(main.game.Player.super.maxHealth));

	var x: f32 = 0;
	var y: f32 = 0;
	for (0..totalHearts) |i| {
		if (x >= window.contentSize[0]) {
			x = 0;
			y += 20;
		}

		if (i < wholeHearts) {
			heartTexture.bindTo(0);
		} else if (i < wholeHearts + halfHeart) {
			halfHeartTexture.bindTo(0);
		} else {
			deadHeartTexture.bindTo(0);
		}

		draw.boundImage(Vec2f{x, window.contentSize[1] - y - 20}, .{20, 20});
		x += 20;
	}

	y += 20;
	if (y != window.contentSize[1]) {
		window.contentSize[1] = y;
		gui.updateWindowPositions();
	}
}
