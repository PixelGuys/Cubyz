const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const vec = main.vec;
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;
const gui = main.gui;
const GuiComponent = gui.GuiComponent;

var tooltipTexture: Texture = undefined;
var cornerSize: Vec2f = undefined;

const fontSize: f32 = 16;
const offsetFromMouse: f32 = 4;

pub fn globalInit() void {
	tooltipTexture = Texture.initFromFile("assets/cubyz/ui/tooltip_background.png");
	cornerSize = (@as(Vec2f, @floatFromInt(tooltipTexture.size())) - Vec2f{1, 1})/Vec2f{2, 2};
}

pub fn globalDeinit() void {
	tooltipTexture.deinit();
}

pub fn render(guiComponent: *GuiComponent, pos: Vec2f) void {
	const size = guiComponent.size() + Vec2f{cornerSize[0]*2, cornerSize[1]*2};
	tooltipTexture.bindTo(0);

	const windowSize = main.Window.getWindowSize()/@as(Vec2f, @splat(gui.scale));
	var renderPos = pos + Vec2f{offsetFromMouse, 0};
	if (renderPos[0] + size[0] > windowSize[0]) {
		renderPos = pos - Vec2f{size[0] + cornerSize[0]*2, 0};
	}
	renderPos = @max(Vec2f{0, 0}, renderPos);
	if (renderPos[1] + size[1] > windowSize[1]) {
		renderPos[1] += windowSize[1] - (renderPos[1] + size[1]);
	}

	draw.bound9SliceImage(renderPos, size, @floatFromInt(tooltipTexture.size()), cornerSize, 1);

	const adjustment = renderPos - guiComponent.pos() + Vec2f{cornerSize[0], cornerSize[1]};
	const oldTranslation = draw.setTranslation(adjustment);
	defer draw.restoreTranslation(oldTranslation);
	const oldClip = draw.setClip(guiComponent.size());
	defer draw.restoreClip(oldClip);
	guiComponent.render(guiComponent.pos());
}

pub fn renderFromText(text: []const u8, pos: Vec2f) void {
	var label = GuiComponent.Label.init(Vec2f{0, 0}, 300, text, .left);
	defer label.deinit();
	var size = label.text.calculateLineBreaks(fontSize, 300);
	size[0] = 0;
	for (label.text.lineBreaks.items) |lineBreak| {
		size[0] = @max(size[0], lineBreak.width);
	}
	label.size = size;

	var component = label.toComponent();
	render(&component, pos);
}
