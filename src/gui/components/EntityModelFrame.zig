const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;

const c = @import("c");

const EntityModelFrame = @This();

const fontSize: f32 = 16;

pos: Vec2f,
size: Vec2f,
texture: Texture,
index: main.entityModel.EntityModelIndex,
rotation: f64,
fovY: f32 = std.math.degreesToRadians(20),

pub fn init(pos: Vec2f, size: Vec2f, index: main.entityModel.EntityModelIndex) *EntityModelFrame {
	const self = main.globalAllocator.create(EntityModelFrame);
	self.* = EntityModelFrame{
		.texture = Texture.initFromFile("assets/cubyz/characterBackground.png"),
		.pos = pos,
		.size = size,
		.index = index,
		.rotation = 0,
	};
	return self;
}

pub fn deinit(self: *const EntityModelFrame) void {
	main.globalAllocator.destroy(self);
	self.texture.deinit();
}

pub fn toComponent(self: *EntityModelFrame) GuiComponent {
	return .{.entityModelFrame = self};
}

pub fn render(self: *EntityModelFrame, _: Vec2f) void {
	// reset color
	const oldColor = draw.setColor(0xffffffff);
	defer draw.restoreColor(oldColor);

	// reset viewport
	var oldViewport: [4]c_int = undefined;
	c.glGetIntegerv(c.GL_VIEWPORT, &oldViewport);
	defer c.glViewport(oldViewport[0], oldViewport[1], oldViewport[2], oldViewport[3]);

	self.texture.render(self.pos, self.size);

	var pos = self.pos;
	pos *= @splat(main.graphics.draw.getScale());
	pos += main.graphics.draw.getTranslation();
	pos = @floor(pos);

	var _size = self.size;
	_size *= @splat(main.graphics.draw.getScale());

	c.glViewport(@intFromFloat(pos[0]), oldViewport[3] + @as(c_int, @intFromFloat(-pos[1] - _size[1])), @intFromFloat(_size[0]), @intFromFloat(_size[1]));
	const proj = main.vec.Mat4f.perspective(self.fovY, _size[0]/_size[1], main.renderer.zNear, main.renderer.zFar);
	self.rotation += main.lastDeltaTime.raw;
	main.entity.systems.modelRenderer.client.drawModelInGui(proj, .{1, 0, 0}, self.fovY, self.index.get(), draw.getScissor(), self.rotation) catch {};
}
