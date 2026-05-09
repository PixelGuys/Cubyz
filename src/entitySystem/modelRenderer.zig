const std = @import("std");

const main = @import("main");
const chunk = main.chunk;
const game = main.game;
const graphics = main.graphics;
const ZonElement = main.ZonElement;
const renderer = main.renderer;
const settings = main.settings;
const utils = main.utils;
const BinaryReader = utils.BinaryReader;
const BinaryWriter = utils.BinaryWriter;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const blocks = main.blocks;
const chunk_zig = main.chunk;
const ServerChunk = chunk_zig.ServerChunk;
const World = game.World;
const ServerWorld = main.server.ServerWorld;
const items = main.items;
const ItemStack = items.ItemStack;
const random = main.random;
const entityComponent = main.entity.components;

const c = @import("c");

// ############################# Client only stuff ################################
pub const client = struct {
	var pipeline: graphics.Pipeline = undefined;

	var uniforms: struct {
		projectionMatrix: c_int,
		viewMatrix: c_int,
		light: c_int,
		contrast: c_int,
		ambientLight: c_int,
	} = undefined;

	pub fn init() void {
		pipeline = graphics.Pipeline.init(
			"assets/cubyz/shaders/entity_vertex.vert",
			"assets/cubyz/shaders/entity_fragment.frag",
			"",
			&uniforms,
			main.entityModel.EntityModel.Vertex,
			&.{},
			.{},
			.{.depthTest = true},
			.{.attachments = &.{.alphaBlending}},
		);
	}
	pub fn deinit() void {
		pipeline.deinit();
	}
	pub fn clear() void {}

	pub fn renderHud(projMatrix: Mat4f, _: Vec3f, playerPos: Vec3d) void {
		main.client.entity_manager.mutex.lock();
		defer main.client.entity_manager.mutex.unlock();

		const screenUnits = @as(f32, @floatFromInt(main.Window.height))/1024;
		const fontBaseSize = 128.0;
		const fontMinScreenSize = 16.0;
		const fontScreenSize = fontBaseSize*screenUnits;

		for (main.client.entity_manager.entities.items()) |ent| {
			if (ent.id == game.Player.id) // don't render local player
				continue;
			if (ent.name.len == 0 and !settings.showPlayerIndexWithName) continue;

			var offsetText: f32 = 0;
			if (main.entity.components.@"cubyz:model".client.get(ent.id)) |component| {
				const entModel = component.entityModel.get();
				offsetText = entModel.height/2;
			}

			const pos3d = ent.getRenderPosition() - playerPos;
			const pos4f = Vec4f{
				@floatCast(pos3d[0]),
				@floatCast(pos3d[1]),
				@floatCast(pos3d[2] + offsetText + 0.1),
				1,
			};

			const rotatedPos = game.camera.viewMatrix.mulVec(pos4f);
			const projectedPos = projMatrix.mulVec(rotatedPos);
			if (projectedPos[2] < 0) continue;
			const xCenter = (1 + projectedPos[0]/projectedPos[3])*@as(f32, @floatFromInt(main.Window.width/2));
			const yCenter = (1 - projectedPos[1]/projectedPos[3])*@as(f32, @floatFromInt(main.Window.height/2));

			const transparency = 38.0*std.math.log10(vec.lengthSquare(pos3d) + 1) - 80.0;
			const alpha: u32 = @trunc(std.math.clamp(0xff - transparency, 0, 0xff));
			graphics.draw.setColor(alpha << 24);

			const renderedName = std.fmt.allocPrint(main.stackAllocator.allocator, "{f}", .{ent}) catch unreachable;
			defer main.stackAllocator.free(renderedName);

			var buf = graphics.TextBuffer.init(main.stackAllocator, renderedName, .{.color = 0xffffff}, false, .center);
			defer buf.deinit();
			const fontSize = std.mem.max(f32, &.{fontMinScreenSize, fontScreenSize/projectedPos[3]});
			const size = buf.calculateLineBreaks(fontSize, @floatFromInt(main.Window.width*8));
			buf.render(xCenter - size[0]/2, yCenter - size[1], fontSize);
		}
	}
	pub fn render(projMatrix: Mat4f, ambientLight: Vec3f, playerPos: Vec3d, deltaTime: f64) void {
		_ = deltaTime;
		main.client.entity_manager.mutex.lock();
		defer main.client.entity_manager.mutex.unlock();
		pipeline.bind(null);

		c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&projMatrix));
		c.glUniform3fv(uniforms.ambientLight, 1, @ptrCast(&ambientLight));
		c.glUniform1f(uniforms.contrast, 0.12);

		for (entityComponent.@"cubyz:model".client.components.dense.items, entityComponent.@"cubyz:model".client.components.denseToSparseIndex.items) |component, id| {
			if (@intFromEnum(id) == game.Player.id) // don't render local player
				continue;

			const entModel = component.entityModel.get();
			const ent = main.client.entity_manager.getEntity(@intFromEnum(id)) orelse continue;

			entModel.bind();
			const entTexture = entModel.defaultTexture;

			entTexture.?.bindTo(0);
			const blockPos: vec.Vec3i = @floor(ent.pos);
			const lightVals: [6]u8 = main.renderer.mesh_storage.getLight(blockPos[0], blockPos[1], blockPos[2]) orelse @splat(0);
			const light = (@as(u32, lightVals[0] >> 3) << 25 |
				@as(u32, lightVals[1] >> 3) << 20 |
				@as(u32, lightVals[2] >> 3) << 15 |
				@as(u32, lightVals[3] >> 3) << 10 |
				@as(u32, lightVals[4] >> 3) << 5 |
				@as(u32, lightVals[5] >> 3) << 0);

			c.glUniform1ui(uniforms.light, @bitCast(@as(u32, light)));

			const pos: Vec3d = ent.getRenderPosition() - playerPos;
			const modelMatrix = (Mat4f.identity()
				.mul(Mat4f.translation(Vec3f{
					@floatCast(pos[0]),
					@floatCast(pos[1]),
					@floatCast(pos[2] - entModel.height/2),
				}))
				.mul(Mat4f.rotationZ(-ent.rot[2])));
			const modelViewMatrix = game.camera.viewMatrix.mul(modelMatrix);
			c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_TRUE, @ptrCast(&modelViewMatrix));
			c.glDrawElements(c.GL_TRIANGLES, entModel.indexCount, c.GL_UNSIGNED_INT, null);
		}
	}
};
// ############################# Server only stuff ################################
pub const server = struct {
	pub fn init() void {}
	pub fn deinit() void {}

	pub fn update() void {}
};
