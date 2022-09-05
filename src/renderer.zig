const std = @import("std");

const blocks = @import("blocks.zig");
const graphics = @import("graphics.zig");
const c = graphics.c;
const Fog = graphics.Fog;
const Shader = graphics.Shader;
const vec = @import("vec.zig");
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const Vec4f = vec.Vec4f;
const Mat4f = vec.Mat4f;
const game = @import("game.zig");
const World = game.World;
const chunk = @import("chunk.zig");
const Window = @import("main.zig").Window;

/// The number of milliseconds after which no more chunk meshes are created. This allows the game to run smoother on movement.
const maximumMeshTime = 12;
const zNear = 0.1;
const zFar = 10000.0;
const zNearLOD = 2.0;
const zFarLOD = 65536.0;

var fogShader: graphics.Shader = undefined;
var fogUniforms: struct {
	fog_activ: c_int,
	fog_color: c_int,
	fog_density: c_int,
	position: c_int,
	color: c_int,
} = undefined;
var deferredRenderPassShader: graphics.Shader = undefined;
var deferredUniforms: struct {
	position: c_int,
	color: c_int,
} = undefined;

pub fn init() !void {
	fogShader = try Shader.create("assets/cubyz/shaders/fog_vertex.vs", "assets/cubyz/shaders/fog_fragment.fs");
	fogUniforms = fogShader.bulkGetUniformLocation(@TypeOf(fogUniforms));
	deferredRenderPassShader = try Shader.create("assets/cubyz/shaders/deferred_render_pass.vs", "assets/cubyz/shaders/deferred_render_pass.fs");
	deferredUniforms = deferredRenderPassShader.bulkGetUniformLocation(@TypeOf(deferredUniforms));
	buffers.init();
}

pub fn deinit() void {
	fogShader.delete();
	deferredRenderPassShader.delete();
	buffers.deinit();
}

const buffers = struct {
	var buffer: c_uint = undefined;
	var colorTexture: c_uint = undefined;
	var positionTexture: c_uint = undefined;
	var depthBuffer: c_uint = undefined;
	fn init() void {
		c.glGenFramebuffers(1, &buffer);
		c.glGenRenderbuffers(1, &depthBuffer);
		c.glGenTextures(1, &colorTexture);
		c.glGenTextures(1, &positionTexture);

		updateBufferSize(Window.width, Window.height);

		c.glBindFramebuffer(c.GL_FRAMEBUFFER, buffer);

		c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, colorTexture, 0);
		c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT1, c.GL_TEXTURE_2D, positionTexture, 0);
		
		c.glFramebufferRenderbuffer(c.GL_FRAMEBUFFER, c.GL_DEPTH_STENCIL_ATTACHMENT, c.GL_RENDERBUFFER, depthBuffer);

		c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
	}

	fn deinit() void {
		c.glDeleteFramebuffers(1, &buffer);
		c.glDeleteRenderbuffers(1, &depthBuffer);
		c.glDeleteTextures(1, &colorTexture);
		c.glDeleteTextures(1, &positionTexture);
	}

	fn regenTexture(texture: c_uint, internalFormat: c_int, format: c_uint, width: u31, height: u31) void {
		c.glBindTexture(c.GL_TEXTURE_2D, texture);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
		c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
		c.glTexImage2D(c.GL_TEXTURE_2D, 0, internalFormat, width, height, 0, format, c.GL_UNSIGNED_BYTE, null);
		c.glBindTexture(c.GL_TEXTURE_2D, 0);
	}

	fn updateBufferSize(width: u31, height: u31) void {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, buffer);

		regenTexture(colorTexture, c.GL_RGB10_A2, c.GL_RGB, width, height);
		regenTexture(positionTexture, c.GL_RGB16F, c.GL_RGB, width, height);

		c.glBindRenderbuffer(c.GL_RENDERBUFFER, depthBuffer);
		c.glRenderbufferStorage(c.GL_RENDERBUFFER, c.GL_DEPTH24_STENCIL8, width, height);
		c.glBindRenderbuffer(c.GL_RENDERBUFFER, 0);

		const attachments = [_]c_uint{c.GL_COLOR_ATTACHMENT0, c.GL_COLOR_ATTACHMENT1};
		c.glDrawBuffers(attachments.len, &attachments);

		c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
	}

	fn bindTextures() void {
		c.glActiveTexture(c.GL_TEXTURE3);
		c.glBindTexture(c.GL_TEXTURE_2D, colorTexture);
		c.glActiveTexture(c.GL_TEXTURE4);
		c.glBindTexture(c.GL_TEXTURE_2D, positionTexture);
	}

	fn bind() void {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, buffer);
	}

	fn unbind() void {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
	}

	fn clearAndBind(clearColor: Vec4f) void {
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, buffer);
		c.glClearColor(clearColor.x, clearColor.y, clearColor.z, 1);
		c.glClear(c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT | c.GL_COLOR_BUFFER_BIT);
		// Clears the position separately to prevent issues with default value.
		const positionClearColor = [_]f32 {0, 0, 6.55e4, 1}; // z value corresponds to the highest 16-bit float value.
		c.glClearBufferfv(c.GL_COLOR, 1, &positionClearColor);

		c.glBindFramebuffer(c.GL_FRAMEBUFFER, buffer);
	}
};

pub fn updateViewport(width: u31, height: u31, fov: f32) void {
	c.glViewport(0, 0, width, height);
	game.projectionMatrix = Mat4f.perspective(std.math.degreesToRadians(f32, fov), @intToFloat(f32, width)/@intToFloat(f32, height), zNear, zFar);
	game.lodProjectionMatrix = Mat4f.perspective(std.math.degreesToRadians(f32, fov), @intToFloat(f32, width)/@intToFloat(f32, height), zNearLOD, zFarLOD);
//	TODO: Transformation.updateProjectionMatrix(frustumProjectionMatrix, (float)Math.toRadians(fov), width, height, Z_NEAR, Z_FAR_LOD); // Need to combine both for frustum intersection
	buffers.updateBufferSize(width, height);
}

pub fn render(playerPosition: Vec3d) void {
	var startTime = std.time.milliTimestamp();
//	TODO:	BlockMeshes.loadMeshes(); // Loads all meshes that weren't loaded yet
//		if (Cubyz.player != null) {
//			if (Cubyz.playerInc.x != 0 || Cubyz.playerInc.z != 0) { // while walking
//				if (bobbingUp) {
//					playerBobbing += 0.005f;
//					if (playerBobbing >= 0.05f) {
//						bobbingUp = false;
//					}
//				} else {
//					playerBobbing -= 0.005f;
//					if (playerBobbing <= -0.05f) {
//						bobbingUp = true;
//					}
//				}
//			}
//			if (Cubyz.playerInc.y != 0) {
//				Cubyz.player.vy = Cubyz.playerInc.y;
//			}
//			if (Cubyz.playerInc.x != 0) {
//				Cubyz.player.vx = Cubyz.playerInc.x;
//			}
//			playerPosition.y += Player.cameraHeight + playerBobbing;
//		}
//		
//		while (!Cubyz.renderDeque.isEmpty()) {
//			Cubyz.renderDeque.pop().run();
//		}
	if(game.world) |world| {
//		// TODO: Handle colors and sun position in the world.
//		ambient.x = ambient.y = ambient.z = Cubyz.world.getGlobalLighting();
//		if (ambient.x < 0.1f) ambient.x = 0.1f;
//		if (ambient.y < 0.1f) ambient.y = 0.1f;
//		if (ambient.z < 0.1f) ambient.z = 0.1f;
//		clearColor = Cubyz.world.getClearColor();
//		Cubyz.fog.setColor(clearColor);
//		Cubyz.fog.setActive(ClientSettings.FOG_COEFFICIENT != 0);
//		Cubyz.fog.setDensity(1 / (ClientSettings.EFFECTIVE_RENDER_DISTANCE*ClientSettings.FOG_COEFFICIENT));
//		clearColor = clearColor.mul(0.25f, new Vector4f());
//		
//		light.setColor(clearColor);
//		
//		float lightY = ((float)Cubyz.world.gameTime % World.DAY_CYCLE) / (float) (World.DAY_CYCLE/2) - 1f;
//		float lightX = ((float)Cubyz.world.gameTime % World.DAY_CYCLE) / (float) (World.DAY_CYCLE/2) - 1f;
//		light.getDirection().set(lightY, 0, lightX);
//		// Set intensity:
//		light.setDirection(light.getDirection().mul(0.1f*Cubyz.world.getGlobalLighting()/light.getDirection().length()));
//		Window.setClearColor(clearColor);
		renderWorld(world, Vec3f{.x=0, .y=0, .z=0}, Vec3f{.x=0, .y=1, .z=0.5}, playerPosition);
//		TODO:
		_ = startTime;
//		// Update meshes:
//		do { // A do while loop is used so even when the framerate is low at least one mesh gets updated per frame.
//			ChunkMesh mesh = Meshes.getNextQueuedMesh();
//			if (mesh == null) break;
//			mesh.regenerateMesh();
//		} while (System.currentTimeMillis() - startTime <= maximumMeshTime);
	} else {
//		clearColor.y = clearColor.z = 0.7f;
//		clearColor.x = 0.1f;
//		
//		Window.setClearColor(clearColor);
//
//		BackgroundScene.renderBackground();
	}
//	Cubyz.gameUI.render();
//	Keyboard.release(); // TODO: Why is this called in the render thread???
}

pub fn renderWorld(world: *World, ambientLight: Vec3f, directionalLight: Vec3f, playerPosition: Vec3d) void {
	_ = world;
	_ = playerPosition; // TODO
	buffers.bind();
	buffers.clearAndBind(Vec4f{.x=0, .y=1, .z=0.5, .w=1});
//	TODO:// Clean up old chunk meshes:
//	Meshes.cleanUp();
	game.camera.updateViewMatrix();

//TODO:	// Uses FrustumCulling on the chunks.
//	Matrix4f frustumMatrix = new Matrix4f();
//	frustumMatrix.set(frustumProjectionMatrix);
//	frustumMatrix.mul(Camera.getViewMatrix());
//	frustumInt.set(frustumMatrix);

	const time = @intCast(u32, std.time.milliTimestamp() & std.math.maxInt(u32));
	const waterFog = Fog{.active=true, .color=.{.x=0.0, .y=0.1, .z=0.2}, .density=0.1};

	// Update the uniforms. The uniforms are needed to render the replacement meshes.
	chunk.meshing.bindShaderAndUniforms(game.projectionMatrix, ambientLight, directionalLight, time);

//TODO:	NormalChunkMesh.bindShader(ambientLight, directionalLight.getDirection(), time);

	c.glActiveTexture(c.GL_TEXTURE0);
	blocks.meshes.blockTextureArray.bind();
	c.glActiveTexture(c.GL_TEXTURE1);
	blocks.meshes.emissionTextureArray.bind();

//TODO:	BlockInstance selected = null;
//	if (Cubyz.msd.getSelected() instanceof BlockInstance) {
//		selected = (BlockInstance)Cubyz.msd.getSelected();
//	}

	c.glDepthRange(0, 0.05);

//	SimpleList<NormalChunkMesh> visibleChunks = new SimpleList<NormalChunkMesh>(new NormalChunkMesh[64]);
//	SimpleList<ReducedChunkMesh> visibleReduced = new SimpleList<ReducedChunkMesh>(new ReducedChunkMesh[64]);
//	for (ChunkMesh mesh : Cubyz.chunkTree.getRenderChunks(frustumInt, x0, y0, z0)) {
//		if (mesh instanceof NormalChunkMesh) {
//			visibleChunks.add((NormalChunkMesh)mesh);
//			
//			mesh.render(playerPosition);
//		} else if (mesh instanceof ReducedChunkMesh) {
//			visibleReduced.add((ReducedChunkMesh)mesh);
//		}
//	}
//	if(selected != null && !Blocks.transparent(selected.getBlock())) {
//		BlockBreakingRenderer.render(selected, playerPosition);
		c.glActiveTexture(c.GL_TEXTURE0);
		blocks.meshes.blockTextureArray.bind();
		c.glActiveTexture(c.GL_TEXTURE1);
		blocks.meshes.emissionTextureArray.bind();
//	}

	// Render the far away ReducedChunks:
	c.glDepthRangef(0.05, 1.0); // ← Used to fix z-fighting.
	chunk.meshing.bindShaderAndUniforms(game.projectionMatrix, ambientLight, directionalLight, time);
	c.glUniform1i(chunk.meshing.uniforms.waterFog_activ, if(waterFog.active) 1 else 0);
	c.glUniform3fv(chunk.meshing.uniforms.waterFog_color, 1, @ptrCast([*c]f32, &waterFog.color));
	c.glUniform1f(chunk.meshing.uniforms.waterFog_density, waterFog.density);

//		for(int i = 0; i < visibleReduced.size; i++) {
//			ReducedChunkMesh mesh = visibleReduced.array[i];
//			mesh.render(playerPosition);
//		}
	c.glDepthRangef(0, 0.05);

//		EntityRenderer.render(ambientLight, directionalLight, playerPosition);

//		BlockDropRenderer.render(frustumInt, ambientLight, directionalLight, playerPosition);

//		// Render transparent chunk meshes:
//		NormalChunkMesh.bindTransparentShader(ambientLight, directionalLight.getDirection(), time);

	buffers.bindTextures();

//		NormalChunkMesh.transparentShader.setUniform(NormalChunkMesh.TransparentUniforms.loc_waterFog_activ, waterFog.isActive());
//		NormalChunkMesh.transparentShader.setUniform(NormalChunkMesh.TransparentUniforms.loc_waterFog_color, waterFog.getColor());
//		NormalChunkMesh.transparentShader.setUniform(NormalChunkMesh.TransparentUniforms.loc_waterFog_density, waterFog.getDensity());

//		NormalChunkMesh[] meshes = sortChunks(visibleChunks.toArray(), x0/Chunk.chunkSize - 0.5f, y0/Chunk.chunkSize - 0.5f, z0/Chunk.chunkSize - 0.5f);
//		for (NormalChunkMesh mesh : meshes) {
//			NormalChunkMesh.transparentShader.setUniform(NormalChunkMesh.TransparentUniforms.loc_drawFrontFace, false);
//			glCullFace(GL_FRONT);
//			mesh.renderTransparent(playerPosition);

//			NormalChunkMesh.transparentShader.setUniform(NormalChunkMesh.TransparentUniforms.loc_drawFrontFace, true);
//			glCullFace(GL_BACK);
//			mesh.renderTransparent(playerPosition);
//		}

//		if(selected != null && Blocks.transparent(selected.getBlock())) {
//			BlockBreakingRenderer.render(selected, playerPosition);
//			glActiveTexture(GL_TEXTURE0);
//			Meshes.blockTextureArray.bind();
//			glActiveTexture(GL_TEXTURE1);
//			Meshes.emissionTextureArray.bind();
//		}

	fogShader.bind();
	// Draw the water fog if the player is underwater:
//		Player player = Cubyz.player;
//		int block = Cubyz.world.getBlock((int)Math.round(player.getPosition().x), (int)(player.getPosition().y + player.height), (int)Math.round(player.getPosition().z));
//		if (block != 0 && !Blocks.solid(block)) {
//			if (Blocks.id(block).toString().equals("cubyz:water")) {
//				fogShader.setUniform(FogUniforms.loc_fog_activ, waterFog.isActive());
//				fogShader.setUniform(FogUniforms.loc_fog_color, waterFog.getColor());
//				fogShader.setUniform(FogUniforms.loc_fog_density, waterFog.getDensity());
//				glUniform1i(FogUniforms.loc_color, 3);
//				glUniform1i(FogUniforms.loc_position, 4);

//				glBindVertexArray(Graphics.rectVAO);
//				glDisable(GL_DEPTH_TEST);
//				glDisable(GL_CULL_FACE);
//				glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
//			}
//		}
//		if(ClientSettings.BLOOM) {
//			BloomRenderer.render(buffers, Window.getWidth(), Window.getHeight()); // TODO: Use true width/height
//		}
	buffers.unbind();
	buffers.bindTextures();
	deferredRenderPassShader.bind();
	c.glUniform1i(deferredUniforms.color, 3);
	c.glUniform1i(deferredUniforms.position, 4);

//	if(Window.getRenderTarget() != null)
//		Window.getRenderTarget().bind();

	c.glBindVertexArray(graphics.Draw.rectVAO);
	c.glDisable(c.GL_DEPTH_TEST);
	c.glDisable(c.GL_CULL_FACE);
	c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);

//	if(Window.getRenderTarget() != null)
//		Window.getRenderTarget().unbind();

//TODO	EntityRenderer.renderNames(playerPosition);
}

//	private final Matrix4f frustumProjectionMatrix = new Matrix4f();
//	private final FrustumIntersection frustumInt = new FrustumIntersection();
//	
//	private float playerBobbing;
//	private boolean bobbingUp;
//	
//	private Vector3f ambient = new Vector3f();
//	private Vector4f clearColor = new Vector4f(0.1f, 0.7f, 0.7f, 1f);
//	private DirectionalLight light = new DirectionalLight(new Vector3f(1.0f, 1.0f, 1.0f), new Vector3f(0.0f, 1.0f, 0.0f).mul(0.1f));
//	
//	/**
//	 * Sorts the chunks based on their distance from the player to reduce complexity when sorting the transparent blocks.
//	 * @param toSort
//	 * @param playerX
//	 * @param playerZ
//	 * @return sorted chunk array
//	 */
//	public NormalChunkMesh[] sortChunks(NormalChunkMesh[] toSort, double playerX, double playerY, double playerZ) {
//		NormalChunkMesh[] output = new NormalChunkMesh[toSort.length];
//		double[] distances = new double[toSort.length];
//		System.arraycopy(toSort, 0, output, 0, toSort.length);
//		for(int i = 0; i < output.length; i++) {
//			distances[i] = (playerX - output[i].wx)*(playerX - output[i].wx) + (playerY - output[i].wy)*(playerY - output[i].wy) + (playerZ - output[i].wz)*(playerZ - output[i].wz);
//		}
//		// Insert sort them:
//		for(int i = 1; i < output.length; i++) {
//			for(int j = i-1; j >= 0; j--) {
//				if (distances[j] < distances[j+1]) {
//					// Swap them:
//					distances[j] += distances[j+1];
//					distances[j+1] = distances[j] - distances[j+1];
//					distances[j] -= distances[j+1];
//					NormalChunkMesh local = output[j+1];
//					output[j+1] = output[j];
//					output[j] = local;
//				} else {
//					break;
//				}
//			}
//		}
//		return output;
//	}
//}