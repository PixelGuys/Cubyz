const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const vec = main.vec;
const Vec2f = vec.Vec2f;
const Vec4f = vec.Vec4f;
const gui = @import("gui.zig");
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

fn posFromAlignment(pos: Vec2f, size: Vec2f, alignment: graphics.TextBuffer.Alignment) Vec2f {
	return switch (alignment) {
		.right => pos + Vec2f{offsetFromMouse, 0},
		.left => pos - Vec2f{size[0] + cornerSize[0]*2, 0},
		.center => pos - Vec2f{size[0]/2, 0},
	};
}

pub fn render(guicomponent: *GuiComponent, pos: Vec2f, alignment: graphics.TextBuffer.Alignment) void {
	const size = guicomponent.size() + Vec2f{cornerSize[0]*2, cornerSize[1]*2};
	tooltipTexture.bindTo(0);

	const windowSize = main.Window.getWindowSize()/@as(Vec2f, @splat(gui.scale));
	var renderpos = posFromAlignment(pos, size, alignment);
	if ((alignment == .center and renderpos[0] + size[0]/2 > windowSize[0]) or renderpos[0] + size[0] > windowSize[0]) {
		renderpos = posFromAlignment(pos, size, .left);
	} else if (renderpos[0] < 0) {
		renderpos = posFromAlignment(pos, size, .right);
	}
	if (renderpos[1] + size[1] > windowSize[1]) {
		renderpos[1] += windowSize[1] - (renderpos[1] + size[1]);
	}

	draw.bound9SliceImage(renderpos, size, @floatFromInt(tooltipTexture.size()), cornerSize, 1);

	guicomponent.mutPos().* = renderpos + Vec2f{cornerSize[0], cornerSize[1]};
	guicomponent.render(pos);
}

pub fn renderFromText(text: []const u8, pos: Vec2f, alignment: graphics.TextBuffer.Alignment) void {
	var label = GuiComponent.Label.init(Vec2f{0, 0}, 300, text, .left);
	var size = label.text.calculateLineBreaks(fontSize, 300);
	size[0] = 0;
	for (label.text.lineBreaks.items) |lineBreak| {
		size[0] = @max(size[0], lineBreak.width);
	}
	label.size = size;

	var component = GuiComponent{.label = label};
	defer component.deinit();
	render(&component, pos, alignment);
}
