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
pub const tooltipSliceCenter: Vec4f = .{4, 4, 4, 4};

pub fn globalInit() void {
	tooltipTexture = Texture.initFromFile("assets/cubyz/ui/tooltip_background.png");
}

pub fn globalDeinit() void {
	tooltipTexture.deinit();
}

pub fn render(guicomponent: *GuiComponent, pos: Vec2f, alignment: graphics.TextBuffer.Alignment) void {
	const size = guicomponent.size();
	tooltipTexture.bindTo(0);

	var renderpos = pos;
	switch (alignment) {
		.right => {
			renderpos = pos + Vec2f{tooltipSliceCenter[0], 0};
		},
		.left => {
			renderpos = pos - Vec2f{size[0] + tooltipSliceCenter[0]*2 + tooltipSliceCenter[1], 0};
		},
		.center => {
			renderpos = pos - Vec2f{size[0]/2, 0};
		},
	}

	draw.bound9SliceImage(renderpos, size + Vec2f{tooltipSliceCenter[0] + tooltipSliceCenter[1], tooltipSliceCenter[2] + tooltipSliceCenter[3]}, @floatFromInt(tooltipTexture.size()), tooltipSliceCenter, 1);

	guicomponent.mutPos().* = renderpos + Vec2f{tooltipSliceCenter[0], tooltipSliceCenter[2]};
	guicomponent.render(pos);
}
