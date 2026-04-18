const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;

const c = main.graphics.c;

const EntityModelFrame = @This();

const fontSize: f32 = 16;

pos: Vec2f,
size: Vec2f,
texture: Texture,
index: main.entityModel.EntityModelIndex,
rotation:f64,
pub fn init(pos: Vec2f, size: Vec2f, index:main.entityModel.EntityModelIndex) *EntityModelFrame {
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
	// if (self.hasShadow) {
	// draw.setColor(0xff000000);
	// self.texture.render(self.pos + Vec2f{1, 1}, self.size);
	// }
	draw.setColor(0xffffffff);
	self.texture.render(self.pos, self.size);

	var pos = self.pos;
	pos *= @splat(main.graphics.draw.getScale());
	pos += main.graphics.draw.getTranslation();
	pos = @floor(pos);
	//std.log.err("nr: {}", .{pos[1]});

	
	var oldViewport: [4]c_int = undefined;
	c.glGetIntegerv(c.GL_VIEWPORT, &oldViewport);
	defer c.glViewport(oldViewport[0], oldViewport[1], oldViewport[2], oldViewport[3]);

	c.glViewport(@intFromFloat(pos[0]),oldViewport[3]+@as(c_int,@intFromFloat(-pos[1]-100*main.graphics.draw.getScale())),@intFromFloat(100*main.graphics.draw.getScale()),@intFromFloat(100*main.graphics.draw.getScale()));
	const proj = main.vec.Mat4f.perspective(std.math.degreesToRadians(20), @as(f32, @floatFromInt(100))/@as(f32, @floatFromInt(100)), main.renderer.zNear, main.renderer.zFar);
	self.rotation += main.lastDeltaTime.raw;
	main.client.entity_manager.drawModel(proj, .{1,1,1}, .{0,0,0}, self.index.get(),self.rotation) catch {};

}
