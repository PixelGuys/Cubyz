const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const Texture = graphics.Texture;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

const c = main.graphics.c;

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
var pipeline: graphics.Pipeline = undefined;
var uniforms: struct {
	screen: c_int,
	start: c_int,
	size: c_int,
	color: c_int,
	uvOffset: c_int,
	uvDim: c_int,
} = undefined;

pub fn init() void {
	pipeline = graphics.Pipeline.init(
		"assets/cubyz/shaders/graphics/Image.vert",
		"assets/cubyz/shaders/graphics/Image.frag",
		"",
		&uniforms,
		.{.cullMode = .none},
		.{.depthTest = false, .depthWrite = false},
		.{.attachments = &.{.{
			.srcColorBlendFactor = .one,
			.dstColorBlendFactor = .one,
			.colorBlendOp = .subtract,
			.srcAlphaBlendFactor = .one,
			.dstAlphaBlendFactor = .one,
			.alphaBlendOp = .subtract,
		}}},
	);
	texture = Texture.initFromFile("assets/cubyz/ui/hud/crosshair.png");
}

pub fn deinit() void {
	pipeline.deinit();
	texture.deinit();
}

pub fn render() void {
	texture.bindTo(0);
	graphics.draw.setColor(0xffffffff);
	pipeline.bind(graphics.draw.getScissor());
	graphics.draw.customShadedImage(&uniforms, .{0, 0}, .{size, size});
}
