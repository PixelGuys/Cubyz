const std = @import("std");

const main = @import("root");
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
		.{.attachedToWindow = .{.reference = &hotbar.window, .selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower}},
		.{.attachedToWindow = .{.reference = &hotbar.window, .selfAttachmentPoint = .upper, .otherAttachmentPoint = .lower}},
	},
	.contentSize = Vec2f{160, 20},
	.isHud = true,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
	.closeable = false,
};

var energyTexture: Texture = undefined;
var halfEnergyTexture: Texture = undefined;
var noEnergyTexture: Texture = undefined;

pub fn init() void {
	energyTexture = Texture.initFromFile("assets/cubyz/ui/hud/energy.png");
	halfEnergyTexture = Texture.initFromFile("assets/cubyz/ui/hud/half_energy.png");
	noEnergyTexture = Texture.initFromFile("assets/cubyz/ui/hud/no_energy.png");
}

pub fn deinit() void {
	energyTexture.deinit();
	halfEnergyTexture.deinit();
	noEnergyTexture.deinit();
}

pub fn render() void {
	draw.setColor(0xffffffff);
	var y: f32 = 0;
	var x: f32 = 0;
	var energy: f32 = 0;
	while(energy < main.game.Player.super.maxEnergy) : (energy += 1) {
		if(x >= window.contentSize[0]) {
			x = 0;
			y += 20;
		}
		if(energy + 1 <= main.game.Player.super.energy) {
			energyTexture.bindTo(0);
		} else if(energy + 0.5 <= main.game.Player.super.energy) {
			halfEnergyTexture.bindTo(0);
		} else {
			noEnergyTexture.bindTo(0);
		}
		draw.boundImage(Vec2f{x, window.contentSize[1] - y - 20}, .{20, 20});
		x += 20;
	}
	y += 20;
	if(y != window.contentSize[1]) {
		window.contentSize[1] = y;
		gui.updateWindowPositions();
	}
}
