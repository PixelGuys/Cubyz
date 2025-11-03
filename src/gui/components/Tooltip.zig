const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const TextBuffer = graphics.TextBuffer;
const Texture = graphics.Texture;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const VerticalList = GuiComponent.VerticalList;

const Tooltip = @This();

// pre-Set SLICE values
pub const cornerVec2Size = Vec2f{4, 4};

var tooltipTexture : Texture = undefined;

pos : Vec2f,
size : Vec2f,
components : *VerticalList,

pub fn __init() void {
	tooltipTexture = Texture.initFromFile("assets/cubyz/ui/tooltip_frame.png");
}

pub fn __deinit() void {
	tooltipTexture.deinit();
}

pub fn init() *Tooltip {
	const self = main.globalAllocator.create(Tooltip);
	self.* = Tooltip{.components = VerticalList.init(Vec2f{0, 0}, 360, cornerVec2Size[1]), .pos = Vec2f{0, 0}, .size = undefined};
	return self;
}

pub fn deinit(self: *const Tooltip) void {
	self.components.deinit();
	main.globalAllocator.destroy(self);
}

pub fn render(self: *Tooltip, mousePosition: ?Vec2f) void {
	const size = self.components.size + Vec2f{cornerVec2Size[0], self.components.padding};
	self.size = size;

	var pos = self.pos;
	if(mousePosition != null) {
		pos = mousePosition.?;
	}

	tooltipTexture.bindTo(0);

	// Draw the Frame
	{
		const cornerSizeUV = (cornerVec2Size - Vec2f{1, 1})/Vec2f{2, 2}/cornerVec2Size;
		const lowerTexture = (cornerVec2Size - Vec2f{1, 1})/Vec2f{2, 2}/cornerVec2Size;
		const upperTexture = (cornerVec2Size + Vec2f{1, 1})/Vec2f{2, 2}/cornerVec2Size;

		draw.setColor(0xffffffff);

		// Corners
		draw.boundSubImage(pos, cornerVec2Size, .{0, 0}, cornerSizeUV);
		draw.boundSubImage(pos + Vec2f{size[0], 0} - Vec2f{cornerVec2Size[0], 0}, cornerVec2Size, .{upperTexture[0], 0}, cornerSizeUV);
		draw.boundSubImage(pos + Vec2f{0, size[1]} - Vec2f{0, cornerVec2Size[1]}, cornerVec2Size, .{0, upperTexture[1]}, cornerSizeUV);
		draw.boundSubImage(pos + size - cornerVec2Size, cornerVec2Size, upperTexture, cornerSizeUV);

		// Edges
		draw.boundSubImage(pos + Vec2f{cornerVec2Size[0], 0}, Vec2f{size[0] - 2*cornerVec2Size[0], cornerVec2Size[1]}, .{lowerTexture[0], 0}, .{upperTexture[0] - lowerTexture[0], cornerSizeUV[1]});
		draw.boundSubImage(pos + Vec2f{cornerVec2Size[0], size[1] - cornerVec2Size[1]}, Vec2f{size[0] - 2*cornerVec2Size[0], cornerVec2Size[1]}, .{lowerTexture[0], upperTexture[1]}, .{upperTexture[0] - lowerTexture[0], cornerSizeUV[1]});
		draw.boundSubImage(pos + Vec2f{0, cornerVec2Size[1]}, Vec2f{cornerVec2Size[0], size[1] - 2*cornerVec2Size[1]}, .{0, lowerTexture[1]}, .{cornerSizeUV[0], upperTexture[1] - lowerTexture[1]});
		draw.boundSubImage(pos + Vec2f{size[0] - cornerVec2Size[0], cornerVec2Size[1]}, Vec2f{cornerVec2Size[0], size[1] - 2*cornerVec2Size[1]}, .{upperTexture[0], lowerTexture[1]}, .{cornerSizeUV[0], upperTexture[1] - lowerTexture[1]});

		// Paste in the center
		draw.boundSubImage(pos + Vec2f{cornerVec2Size[0], cornerVec2Size[1]}, Vec2f{size[0] - 2*cornerVec2Size[0], size[1] - 2*cornerVec2Size[1]}, .{upperTexture[0], lowerTexture[0]}, .{upperTexture[0] - lowerTexture[0], cornerSizeUV[1]});
	}

	self.components.pos = pos + Vec2f{cornerVec2Size[0]/2, self.components.padding/2};
	self.components.render(pos);
}
