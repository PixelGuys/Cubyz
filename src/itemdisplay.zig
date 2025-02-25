const std = @import("std");

const blocks = @import("blocks.zig");
const chunk_zig = @import("chunk.zig");
const ServerChunk = chunk_zig.ServerChunk;
const game = @import("game.zig");
const Player = game.Player;
const graphics = @import("graphics.zig");
const c = graphics.c;
const main = @import("main.zig");
const utils = @import("utils.zig");
const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;
const ItemModelStore = @import("itemdrop.zig").ItemModelStore;

// will be used for rendering currenly held item of a player (starting from basics)
pub const PlayerItemDisplay = struct { // MARK: PlayerItemDisplay
	// stolen from itemdrop.zig with love!!!
	var itemShader: graphics.Shader = undefined;
	var itemUniforms: struct {
		projectionMatrix: c_int,
		modelMatrix: c_int,
		viewMatrix: c_int,
		modelPosition: c_int,
		ambientLight: c_int,
		modelIndex: c_int,
		block: c_int,
		time: c_int,
		texture_sampler: c_int,
		emissionSampler: c_int,
		reflectivityAndAbsorptionSampler: c_int,
		reflectionMap: c_int,
		reflectionMapSize: c_int,
		contrast: c_int,
	} = undefined;

	pub fn init() void {
		itemShader = graphics.Shader.initAndGetUniforms("assets/cubyz/shaders/item_drop.vs", "assets/cubyz/shaders/item_drop.fs", "", &itemUniforms);
	}

	pub fn deinit() void {
		itemShader.deinit();
	}

	pub fn renderPlayerDisplayItem(projMatrix: Mat4f, ambientLight: Vec3f, playerPos: Vec3d, time: u32) void {
		itemShader.bind();
		c.glUniform1i(itemUniforms.texture_sampler, 0);
		c.glUniform1i(itemUniforms.emissionSampler, 1);
		c.glUniform1i(itemUniforms.reflectivityAndAbsorptionSampler, 2);
		c.glUniform1i(itemUniforms.reflectionMap, 4);
		c.glUniform1f(itemUniforms.reflectionMapSize, main.renderer.reflectionCubeMapSize);
		c.glUniform1i(itemUniforms.time, @as(u31, @truncate(time)));
		c.glUniformMatrix4fv(itemUniforms.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&projMatrix));
		c.glUniform3fv(itemUniforms.ambientLight, 1, @ptrCast(&ambientLight));
		c.glUniformMatrix4fv(itemUniforms.viewMatrix, 1, c.GL_TRUE, @ptrCast(&game.camera.viewMatrix));
		c.glUniform1f(itemUniforms.contrast, 0.12);

		const selectedItem = Player.inventory.getItem(Player.selectedSlot);
		if(selectedItem) |item| {
			var pos: Vec3d = Vec3d{0, 0, 0};
			const rot: Vec3f = Vec3f{game.camera.rotation[0], game.camera.rotation[1], game.camera.rotation[2]};

			_ = playerPos; // going to be used when light value fetching from mesh_storage is implemented.
			const light: u32 = 0xffffffff; // TODO: Get this light value from the mesh_storage.
			c.glUniform3fv(itemUniforms.ambientLight, 1, @ptrCast(&@max(
				ambientLight*@as(Vec3f, @splat(@as(f32, @floatFromInt(light >> 24))/255)),
				Vec3f{light >> 16 & 255, light >> 8 & 255, light & 255}/@as(Vec3f, @splat(255))
			)));

			const model = ItemModelStore.getModel(item);
			c.glUniform1i(itemUniforms.modelIndex, model.index);
			var vertices: u31 = 36;

			var scale: f32 = 0.25;
			var isTool: bool = false;
			if(item == .baseItem and item.baseItem.block != null and item.baseItem.image.imageData.ptr == graphics.Image.defaultImage.imageData.ptr) {
				const blockType = item.baseItem.block.?;
				c.glUniform1i(itemUniforms.block, blockType);
				vertices = model.len/2*6;
				pos = Vec3d{0.4, 0.65, -0.25};
			} else {
				c.glUniform1i(itemUniforms.block, 0);
				isTool = true;
				scale = 0.6;
				pos = Vec3d{0.4, 0.65, -0.25};
			}

			var modelMatrix = Mat4f.rotationZ(-rot[2]);
			modelMatrix = modelMatrix.mul(Mat4f.rotationY(-rot[1]));
			modelMatrix = modelMatrix.mul(Mat4f.rotationX(-rot[0]));
			modelMatrix = modelMatrix.mul(Mat4f.translation(@floatCast(pos)));
			if (isTool) {
				modelMatrix = modelMatrix.mul(Mat4f.rotationZ(-std.math.pi*0.45));
			}
			modelMatrix = modelMatrix.mul(Mat4f.scale(@splat(scale)));
			modelMatrix = modelMatrix.mul(Mat4f.translation(@splat(-0.5)));
			c.glUniformMatrix4fv(itemUniforms.modelMatrix, 1, c.GL_TRUE, @ptrCast(&modelMatrix));

			c.glBindVertexArray(main.renderer.chunk_meshing.vao);
			c.glDrawElements(c.GL_TRIANGLES, vertices, c.GL_UNSIGNED_INT, null);
		}
	}
};
