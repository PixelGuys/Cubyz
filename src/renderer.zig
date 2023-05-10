const std = @import("std");
const Allocator = std.mem.Allocator;

const blocks = @import("blocks.zig");
const chunk = @import("chunk.zig");
const entity = @import("entity.zig");
const graphics = @import("graphics.zig");
const c = graphics.c;
const Fog = graphics.Fog;
const Shader = graphics.Shader;
const game = @import("game.zig");
const World = game.World;
const itemdrop = @import("itemdrop.zig");
const main = @import("main.zig");
const Window = main.Window;
const models = @import("models.zig");
const network = @import("network.zig");
const settings = @import("settings.zig");
const utils = @import("utils.zig");
const vec = @import("vec.zig");
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const Vec4f = vec.Vec4f;
const Mat4f = vec.Mat4f;

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

pub var activeFrameBuffer: c_uint = 0;

pub fn init() !void {
	fogShader = try Shader.initAndGetUniforms("assets/cubyz/shaders/fog_vertex.vs", "assets/cubyz/shaders/fog_fragment.fs", &fogUniforms);
	deferredRenderPassShader = try Shader.initAndGetUniforms("assets/cubyz/shaders/deferred_render_pass.vs", "assets/cubyz/shaders/deferred_render_pass.fs", &deferredUniforms);
	buffers.init();
	try Bloom.init();
	try MeshSelection.init();
	try MenuBackGround.init();
}

pub fn deinit() void {
	fogShader.deinit();
	deferredRenderPassShader.deinit();
	buffers.deinit();
	Bloom.deinit();
	MeshSelection.deinit();
	MenuBackGround.deinit();
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
		c.glClearColor(clearColor[0], clearColor[1], clearColor[2], 1);
		c.glClear(c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT | c.GL_COLOR_BUFFER_BIT);
		// Clears the position separately to prevent issues with default value.
		const positionClearColor = [_]f32 {0, 0, 6.55e4, 1}; // z value corresponds to the highest 16-bit float value.
		c.glClearBufferfv(c.GL_COLOR, 1, &positionClearColor);
	}
};

var lastWidth: u31 = 0;
var lastHeight: u31 = 0;
var lastFov: f32 = 0;
pub fn updateViewport(width: u31, height: u31, fov: f32) void {
	lastWidth = width;
	lastHeight = height;
	lastFov = fov;
	c.glViewport(0, 0, width, height);
	game.projectionMatrix = Mat4f.perspective(std.math.degreesToRadians(f32, fov), @intToFloat(f32, width)/@intToFloat(f32, height), zNear, zFar);
	game.lodProjectionMatrix = Mat4f.perspective(std.math.degreesToRadians(f32, fov), @intToFloat(f32, width)/@intToFloat(f32, height), zNearLOD, zFarLOD);
//	TODO: Transformation.updateProjectionMatrix(frustumProjectionMatrix, (float)Math.toRadians(fov), width, height, Z_NEAR, Z_FAR_LOD); // Need to combine both for frustum intersection
	buffers.updateBufferSize(width, height);
}

pub fn render(playerPosition: Vec3d) !void {
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
		var ambient: Vec3f = undefined;
		ambient[0] = @max(0.1, world.ambientLight);
		ambient[1] = @max(0.1, world.ambientLight);
		ambient[2] = @max(0.1, world.ambientLight);
		var skyColor = vec.xyz(world.clearColor);
		game.fog.color = skyColor;
		// TODO:
//		Cubyz.fog.setActive(ClientSettings.FOG_COEFFICIENT != 0);
//		Cubyz.fog.setDensity(1 / (ClientSettings.EFFECTIVE_RENDER_DISTANCE*ClientSettings.FOG_COEFFICIENT));
		skyColor *= @splat(3, @as(f32, 0.25));

		try renderWorld(world, ambient, skyColor, playerPosition);
		try RenderStructure.updateMeshes(startTime + maximumMeshTime);
	} else {
		// TODO:
//		clearColor.y = clearColor.z = 0.7f;
//		clearColor.x = 0.1f;@import("main.zig")
//		
//		Window.setClearColor(clearColor);
		MenuBackGround.render();
	}
//	Cubyz.gameUI.render();
//	Keyboard.release(); // TODO: Why is this called in the render thread???
}

pub fn renderWorld(world: *World, ambientLight: Vec3f, skyColor: Vec3f, playerPos: Vec3d) !void {
	_ = world;
	buffers.clearAndBind(Vec4f{skyColor[0], skyColor[1], skyColor[2], 1});
//	TODO:// Clean up old chunk meshes:
//	Meshes.cleanUp();
	game.camera.updateViewMatrix();

	// Uses FrustumCulling on the chunks.
	var frustum = Frustum.init(Vec3f{0, 0, 0}, game.camera.viewMatrix, lastFov, zFarLOD, lastWidth, lastHeight);

	const time = @intCast(u32, std.time.milliTimestamp() & std.math.maxInt(u32));
	var waterFog = Fog{.active=true, .color=.{0.0, 0.1, 0.2}, .density=0.1};

	// Update the uniforms. The uniforms are needed to render the replacement meshes.
	chunk.meshing.bindShaderAndUniforms(game.lodProjectionMatrix, ambientLight, time);

//TODO:	NormalChunkMesh.bindShader(ambientLight, directionalLight.getDirection(), time);

	c.glActiveTexture(c.GL_TEXTURE0);
	blocks.meshes.blockTextureArray.bind();
	c.glActiveTexture(c.GL_TEXTURE1);
	blocks.meshes.emissionTextureArray.bind();

//	SimpleList<NormalChunkMesh> visibleChunks = new SimpleList<NormalChunkMesh>(new NormalChunkMesh[64]);
//	SimpleList<ReducedChunkMesh> visibleReduced = new SimpleList<ReducedChunkMesh>(new ReducedChunkMesh[64]);
	var meshes = std.ArrayList(*chunk.meshing.ChunkMesh).init(main.threadAllocator);
	defer meshes.deinit();

	try RenderStructure.updateAndGetRenderChunks(game.world.?.conn, playerPos, settings.renderDistance, settings.LODFactor, frustum, &meshes);

	try sortChunks(meshes.items, playerPos);

//	for (ChunkMesh mesh : Cubyz.chunkTree.getRenderChunks(frustumInt, x0, y0, z0)) {
//		if (mesh instanceof NormalChunkMesh) {
//			visibleChunks.add((NormalChunkMesh)mesh);
//			
//			mesh.render(playerPosition);
//		} else if (mesh instanceof ReducedChunkMesh) {
//			visibleReduced.add((ReducedChunkMesh)mesh);
//		}
//	}
	MeshSelection.select(playerPos, game.camera.direction);
	MeshSelection.render(game.projectionMatrix, game.camera.viewMatrix, playerPos);

	// Render the far away ReducedChunks:
	chunk.meshing.bindShaderAndUniforms(game.projectionMatrix, ambientLight, time);
	c.glUniform1i(chunk.meshing.uniforms.@"waterFog.activ", if(waterFog.active) 1 else 0);
	c.glUniform3fv(chunk.meshing.uniforms.@"waterFog.color", 1, @ptrCast([*c]f32, &waterFog.color));
	c.glUniform1f(chunk.meshing.uniforms.@"waterFog.density", waterFog.density);

	for(meshes.items) |mesh| {
		mesh.render(playerPos);
	}

//		for(int i = 0; i < visibleReduced.size; i++) {
//			ReducedChunkMesh mesh = visibleReduced.array[i];
//			mesh.render(playerPosition);
//		}

	entity.ClientEntityManager.render(game.projectionMatrix, ambientLight, .{1, 0.5, 0.25}, playerPos);

	try itemdrop.ItemDropRenderer.renderItemDrops(game.projectionMatrix, ambientLight, playerPos, time);

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
	if(settings.bloom) {
		Bloom.render(lastWidth, lastHeight);
	}
	buffers.unbind();
	buffers.bindTextures();
	deferredRenderPassShader.bind();
	c.glUniform1i(deferredUniforms.color, 3);
	c.glUniform1i(deferredUniforms.position, 4);

	c.glBindFramebuffer(c.GL_FRAMEBUFFER, activeFrameBuffer);

	c.glBindVertexArray(graphics.draw.rectVAO);
	c.glDisable(c.GL_DEPTH_TEST);
	c.glDisable(c.GL_CULL_FACE);
	c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);

	c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

	try entity.ClientEntityManager.renderNames(game.projectionMatrix, playerPos);
}

/// Sorts the chunks based on their distance from the player to reduce overdraw.
fn sortChunks(toSort: []*chunk.meshing.ChunkMesh, playerPos: Vec3d) !void {
	const distances = try main.threadAllocator.alloc(f64, toSort.len);
	defer main.threadAllocator.free(distances);

	for(distances, 0..) |*dist, i| {
		dist.* = vec.length(playerPos - Vec3d{
			@intToFloat(f64, toSort[i].pos.wx),
			@intToFloat(f64, toSort[i].pos.wy),
			@intToFloat(f64, toSort[i].pos.wz)
		});
	}
	// Insert sort them:
	var i: u32 = 1;
	while(i < toSort.len) : (i += 1) {
		var j: u32 = i - 1;
		while(true) {
			@setRuntimeSafety(false);
			if(distances[j] > distances[j+1]) {
				// Swap them:
				{
					const swap = distances[j];
					distances[j] = distances[j+1];
					distances[j+1] = swap;
				} {
					const swap = toSort[j];
					toSort[j] = toSort[j+1];
					toSort[j+1] = swap;
				}
			} else {
				break;
			}

			if(j == 0) break;
			j -= 1;
		}
	}
}

//	private float playerBobbing;
//	private boolean bobbingUp;
//	
//	private Vector3f ambient = new Vector3f();
//	private Vector4f clearColor = new Vector4f(0.1f, 0.7f, 0.7f, 1f);
//	private DirectionalLight light = new DirectionalLight(new Vector3f(1.0f, 1.0f, 1.0f), new Vector3f(0.0f, 1.0f, 0.0f).mul(0.1f));

const Bloom = struct {
	var buffer1: graphics.FrameBuffer = undefined;
	var buffer2: graphics.FrameBuffer = undefined;
	var width: u31 = std.math.maxInt(u31);
	var height: u31 = std.math.maxInt(u31);
	var firstPassShader: graphics.Shader = undefined;
	var secondPassShader: graphics.Shader = undefined;
	var colorExtractAndDownsampleShader: graphics.Shader = undefined;
	var upscaleShader: graphics.Shader = undefined;

	pub fn init() !void {
		buffer1.init(false);
		buffer2.init(false);
		firstPassShader = try graphics.Shader.init("assets/cubyz/shaders/bloom/first_pass.vs", "assets/cubyz/shaders/bloom/first_pass.fs");
		secondPassShader = try graphics.Shader.init("assets/cubyz/shaders/bloom/second_pass.vs", "assets/cubyz/shaders/bloom/second_pass.fs");
		colorExtractAndDownsampleShader = try graphics.Shader.init("assets/cubyz/shaders/bloom/color_extractor_downsample.vs", "assets/cubyz/shaders/bloom/color_extractor_downsample.fs");
		upscaleShader = try graphics.Shader.init("assets/cubyz/shaders/bloom/upscale.vs", "assets/cubyz/shaders/bloom/upscale.fs");
	}

	pub fn deinit() void {
		buffer1.deinit();
		buffer2.deinit();
		firstPassShader.deinit();
		secondPassShader.deinit();
		upscaleShader.deinit();
	}

	fn extractImageDataAndDownsample() void {
		colorExtractAndDownsampleShader.bind();
		buffers.bindTextures();
		buffer1.bind();
		c.glBindVertexArray(graphics.draw.rectVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	fn firstPass() void {
		firstPassShader.bind();
		c.glActiveTexture(c.GL_TEXTURE3);
		c.glBindTexture(c.GL_TEXTURE_2D, buffer1.texture);
		buffer2.bind();
		c.glBindVertexArray(graphics.draw.rectVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	fn secondPass() void {
		secondPassShader.bind();
		c.glActiveTexture(c.GL_TEXTURE3);
		c.glBindTexture(c.GL_TEXTURE_2D, buffer2.texture);
		buffer1.bind();
		c.glBindVertexArray(graphics.draw.rectVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	fn upscale() void {
		upscaleShader.bind();
		c.glActiveTexture(c.GL_TEXTURE3);
		c.glBindTexture(c.GL_TEXTURE_2D, buffer1.texture);
		buffers.bind();
		c.glBindVertexArray(graphics.draw.rectVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	pub fn render(currentWidth: u31, currentHeight: u31) void {
		if(width != currentWidth or height != currentHeight) {
			width = currentWidth;
			height = currentHeight;
			buffer1.updateSize(width/2, height/2, c.GL_NEAREST, c.GL_CLAMP_TO_EDGE);
			std.debug.assert(buffer1.validate());
			buffer2.updateSize(width/2, height/2, c.GL_NEAREST, c.GL_CLAMP_TO_EDGE);
			std.debug.assert(buffer2.validate());
		}
		c.glDisable(c.GL_DEPTH_TEST);
		c.glDisable(c.GL_CULL_FACE);

		c.glViewport(0, 0, width/2, height/2);
		extractImageDataAndDownsample();
		firstPass();
		secondPass();
		c.glViewport(0, 0, width, height);
		c.glBlendFunc(c.GL_ONE, c.GL_ONE);
		upscale();

		c.glEnable(c.GL_DEPTH_TEST);
		c.glEnable(c.GL_CULL_FACE);
		c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
	}
};

pub const MenuBackGround = struct {
	var shader: Shader = undefined;
	var uniforms: struct {
		image: c_int,
		viewMatrix: c_int,
		projectionMatrix: c_int,
	} = undefined;

	var vao: c_uint = undefined;
	var vbos: [2]c_uint = undefined;
	var texture: graphics.Texture = undefined;

	var angle: f32 = 0;
	var lastTime: i128 = undefined;

	fn init() !void {
		lastTime = std.time.nanoTimestamp();
		shader = try Shader.initAndGetUniforms("assets/cubyz/shaders/background/vertex.vs", "assets/cubyz/shaders/background/fragment.fs", &uniforms);
		shader.bind();
		c.glUniform1i(uniforms.image, 0);
		// 4 sides of a simple cube with some panorama texture on it.
		const rawData = [_]f32 {
			-1, -1, -1, 1, 1,
			-1, 1, -1, 1, 0,
			-1, -1, 1, 0.75, 1,
			-1, 1, 1, 0.75, 0,
			1, -1, 1, 0.5, 1,
			1, 1, 1, 0.5, 0,
			1, -1, -1, 0.25, 1,
			1, 1, -1, 0.25, 0,
			-1, -1, -1, 0, 1,
			-1, 1, -1, 0, 0,
		};

		const indices = [_]c_int {
			0, 1, 2,
			2, 3, 1,
			2, 3, 4,
			4, 5, 3,
			4, 5, 6,
			6, 7, 5,
			6, 7, 8,
			8, 9, 7,
		};

		c.glGenVertexArrays(1, &vao);
		c.glBindVertexArray(vao);
		c.glGenBuffers(2, &vbos);
		c.glBindBuffer(c.GL_ARRAY_BUFFER, vbos[0]);
		c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(isize, rawData.len*@sizeOf(f32)), &rawData, c.GL_STATIC_DRAW);
		c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 5*@sizeOf(f32), null);
		c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, 5*@sizeOf(f32), @intToPtr(?*const anyopaque, 3*@sizeOf(f32)));
		c.glEnableVertexAttribArray(0);
		c.glEnableVertexAttribArray(1);
		c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, vbos[1]);
		c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @intCast(isize, indices.len*@sizeOf(c_int)), &indices, c.GL_STATIC_DRAW);

		// Load a random texture from the backgrounds folder. The player may make their own pictures which can be chosen as well.
		var dir: std.fs.IterableDir = try std.fs.cwd().makeOpenPathIterable("assets/backgrounds", .{});
		defer dir.close();

		var walker = try dir.walk(main.threadAllocator);
		defer walker.deinit();
		var fileList = std.ArrayList([]const u8).init(main.threadAllocator);
		defer {
			for(fileList.items) |fileName| {
				main.threadAllocator.free(fileName);
			}
			fileList.deinit();
		}

		while(try walker.next()) |entry| {
			if(entry.kind == .File and std.ascii.endsWithIgnoreCase(entry.basename, ".png")) {
				try fileList.append(try main.threadAllocator.dupe(u8, entry.path));
			}
		}
		if(fileList.items.len == 0) {
			std.log.warn("Couldn't find any background scene images in \"assets/backgrounds\".", .{});
			texture = .{.textureID = 0};
			return;
		}
		const theChosenOne = main.random.nextIntBounded(u32, &main.seed, @intCast(u32, fileList.items.len));
		const theChosenPath = try std.fmt.allocPrint(main.threadAllocator, "assets/backgrounds/{s}", .{fileList.items[theChosenOne]});
		defer main.threadAllocator.free(theChosenPath);
		texture = try graphics.Texture.initFromFile(theChosenPath);
	}

	pub fn deinit() void {
		shader.deinit();
		c.glDeleteVertexArrays(1, &vao);
		c.glDeleteBuffers(2, &vbos);
	}

	pub fn render() void {
		if(texture.textureID == 0) return;
		c.glDisable(c.GL_CULL_FACE); // I'm not sure if my triangles are rotated correctly, and there are no triangles facing away from the player anyways.

		// Use a simple rotation around the y axis, with a steadily increasing angle.
		const newTime = std.time.nanoTimestamp();
		angle += @intToFloat(f32, newTime - lastTime)/2e10;
		lastTime = newTime;
		var viewMatrix = Mat4f.rotationY(angle);
		shader.bind();

		c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_FALSE, @ptrCast([*c]const f32, &viewMatrix));
		c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_FALSE, @ptrCast([*c]const f32, &game.projectionMatrix));

		texture.bindTo(0);

		c.glBindVertexArray(vao);
		c.glDrawElements(c.GL_TRIANGLES, 24, c.GL_UNSIGNED_INT, null);
	}

	pub fn takeBackgroundImage() !void {
		const size: usize = 1024; // Use a power of 2 here, to reduce video memory waste.
		var pixels: []u32 = try main.threadAllocator.alloc(u32, size*size);
		defer main.threadAllocator.free(pixels);

		// Change the viewport and the matrices to render 4 cube faces:

		updateViewport(size, size, 90.0);
		defer updateViewport(Window.width, Window.height, settings.fov);
		
		var buffer: graphics.FrameBuffer = undefined;
		buffer.init(true);
		defer buffer.deinit();
		buffer.updateSize(size, size, c.GL_NEAREST, c.GL_REPEAT);

		activeFrameBuffer = buffer.frameBuffer;
		defer activeFrameBuffer = 0;

		const oldRotation = game.camera.rotation;
		defer game.camera.rotation = oldRotation;

		const angles = [_]f32 {std.math.pi/2.0, std.math.pi, std.math.pi*3/2.0, std.math.pi*2};

		// All 4 sides are stored in a single image.
		var image = try graphics.Image.init(main.threadAllocator, 4*size, size);
		defer image.deinit(main.threadAllocator);

		for(0..4) |i| {
			c.glEnable(c.GL_CULL_FACE);
			c.glEnable(c.GL_DEPTH_TEST);
			game.camera.rotation = .{0, angles[i], 0};
			// Draw to frame buffer.
			buffer.bind();
			c.glClear(c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT | c.GL_COLOR_BUFFER_BIT);
			try main.renderer.render(game.Player.getPosBlocking());
			// Copy the pixels directly from OpenGL
			buffer.bind();
			c.glReadPixels(0, 0, size, size, c.GL_RGBA, c.GL_UNSIGNED_BYTE, pixels.ptr);

			for(0..size) |y| {
				for(0..size) |x| {
					const index = x + y*size;
					// Needs to flip the image in y-direction.
					image.setRGB(x + size*i, size - 1 - y, @bitCast(graphics.Color, pixels[index]));
				}
			}
		}
		c.glDisable(c.GL_CULL_FACE);
		c.glDisable(c.GL_DEPTH_TEST);
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

		const fileName = try std.fmt.allocPrint(main.threadAllocator, "assets/backgrounds/{s}_{}.png", .{game.world.?.name, game.world.?.gameTime.load(.Monotonic)});
		defer main.threadAllocator.free(fileName);
		try image.exportToFile(fileName);
		// TODO: Performance is terrible even with -O3. Consider using qoi instead.
	}
};

pub const Frustum = struct {
	const Plane = struct {
		pos: Vec3f,
		norm: Vec3f,
	};
	planes: [5]Plane, // Who cares about the near plane anyways?

	pub fn init(cameraPos: Vec3f, rotationMatrix: Mat4f, fovY: f32, _zFar: f32, width: u31, height: u31) Frustum {
		var invRotationMatrix = rotationMatrix.transpose();
		var cameraDir = vec.xyz(invRotationMatrix.mulVec(Vec4f{0, 0, 1, 1}));
		var cameraUp = vec.xyz(invRotationMatrix.mulVec(Vec4f{0, 1, 0, 1}));
		var cameraRight = vec.xyz(invRotationMatrix.mulVec(Vec4f{1, 0, 0, 1}));

		const halfVSide = _zFar*std.math.tan(std.math.degreesToRadians(f32, fovY)*0.5);
		const halfHSide = halfVSide*@intToFloat(f32, width)/@intToFloat(f32, height);
		const frontMultFar = cameraDir*@splat(3, _zFar);

		var self: Frustum = undefined;
		self.planes[0] = Plane{.pos = cameraPos + frontMultFar, .norm=-cameraDir}; // far
		self.planes[1] = Plane{.pos = cameraPos, .norm=vec.cross(cameraUp, frontMultFar + cameraRight*@splat(3, halfHSide))}; // right
		self.planes[2] = Plane{.pos = cameraPos, .norm=vec.cross(frontMultFar - cameraRight*@splat(3, halfHSide), cameraUp)}; // left
		self.planes[3] = Plane{.pos = cameraPos, .norm=vec.cross(cameraRight, frontMultFar - cameraUp*@splat(3, halfVSide))}; // top
		self.planes[4] = Plane{.pos = cameraPos, .norm=vec.cross(frontMultFar + cameraUp*@splat(3, halfVSide), cameraRight)}; // bottom
		return self;
	}

	pub fn testAAB(self: Frustum, pos: Vec3f, dim: Vec3f) bool {
		inline for(self.planes) |plane| {
			var dist: f32 = vec.dot(pos - plane.pos, plane.norm);
			// Find the most positive corner:
			dist += @max(0.0, dim[0]*plane.norm[0]); // TODO: #15644
			dist += @max(0.0, dim[1]*plane.norm[1]); // TODO: #15644
			dist += @max(0.0, dim[2]*plane.norm[2]); // TODO: #15644
			if(dist < 128) return false;
		}
		return true;
	}
};

pub const MeshSelection = struct {
	var shader: Shader = undefined;
	var uniforms: struct {
		projectionMatrix: c_int,
		viewMatrix: c_int,
		modelPosition: c_int,
		lowerBounds: c_int,
		upperBounds: c_int,
	} = undefined;

	var cubeVAO: c_uint = undefined;
	var cubeVBO: c_uint = undefined;
	var cubeIBO: c_uint = undefined;

	pub fn init() !void {
		shader = try Shader.initAndGetUniforms("assets/cubyz/shaders/block_selection_vertex.vs", "assets/cubyz/shaders/block_selection_fragment.fs", &uniforms);

		var rawData = [_]f32 {
			0, 0, 0,
			0, 0, 1,
			0, 1, 0,
			0, 1, 1,
			1, 0, 0,
			1, 0, 1,
			1, 1, 0,
			1, 1, 1,
		};
		var indices = [_]u8 {
			0, 1,
			0, 2,
			0, 4,
			1, 3,
			1, 5,
			2, 3,
			2, 6,
			3, 7,
			4, 5,
			4, 6,
			5, 7,
			6, 7,
		};

		c.glGenVertexArrays(1, &cubeVAO);
		c.glBindVertexArray(cubeVAO);
		c.glGenBuffers(1, &cubeVBO);
		c.glBindBuffer(c.GL_ARRAY_BUFFER, cubeVBO);
		c.glBufferData(c.GL_ARRAY_BUFFER, rawData.len*@sizeOf(f32), &rawData, c.GL_STATIC_DRAW);
		c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 3*@sizeOf(f32), null);
		c.glEnableVertexAttribArray(0);
		c.glGenBuffers(1, &cubeIBO);
		c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, cubeIBO);
		c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, indices.len*@sizeOf(u8), &indices, c.GL_STATIC_DRAW);

	}

	pub fn deinit() void {
		shader.deinit();
		c.glDeleteBuffers(1, &cubeIBO);
		c.glDeleteBuffers(1, &cubeVBO);
		c.glDeleteVertexArrays(1, &cubeVAO);
	}

	var selectedBlockPos: ?Vec3i = null;
	pub fn select(_pos: Vec3d, _dir: Vec3f) void {
		var pos = _pos;
		// TODO: pos.y += Player.cameraHeight;
		var dir = vec.floatCast(f64, _dir);
//TODO:
//		intersection.set(0, 0, 0, dir.x, dir.y, dir.z);

		// Test blocks:
		const closestDistance: f64 = 6.0; // selection now limited
		// Implementation of "A Fast Voxel Traversal Algorithm for Ray Tracing"  http://www.cse.yorku.ca/~amana/research/grid.pdf
		const step = vec.floatToInt(i32, std.math.sign(dir));
		const invDir = @splat(3, @as(f64, 1))/dir;
		const tDelta = @fabs(invDir);
		var tMax = (@floor(pos) - pos)*invDir;
		tMax = @max(tMax, tMax + tDelta*vec.intToFloat(f64, step));
		tMax = @select(f64, dir == @splat(3, @as(f64, 0)), @splat(3, std.math.inf(f64)), tMax);
		var voxelPos = vec.floatToInt(i32, @floor(pos));

		var total_tMax: f64 = 0;

		selectedBlockPos = null;

		while(total_tMax < closestDistance) {
			const block = RenderStructure.getBlock(voxelPos[0], voxelPos[1], voxelPos[2]) orelse break;
			if(block.typ != 0) {
				// Check the true bounding box (using this algorithm here: https://tavianator.com/2011/ray_box.html):
				const model = blocks.meshes.model(block);
				const voxelModel = &models.voxelModels.items[model.modelIndex];
				var transformedMin = model.permutation.transform(voxelModel.min - @splat(3, @as(i32, 8))) + @splat(3, @as(i32, 8));
				var transformedMax = model.permutation.transform(voxelModel.max - @splat(3, @as(i32, 8))) + @splat(3, @as(i32, 8));
				const min = @min(transformedMin, transformedMax);
				const max = @max(transformedMin ,transformedMax);
				const t1 = (vec.intToFloat(f64, voxelPos) + vec.intToFloat(f64, min)/@splat(3, @as(f64, 16.0)) - pos)*invDir;
				const t2 = (vec.intToFloat(f64, voxelPos) + vec.intToFloat(f64, max)/@splat(3, @as(f64, 16.0)) - pos)*invDir;
				const boxTMin = @reduce(.Max, @min(t1, t2));
				const boxTMax = @reduce(.Min, @max(t1, t2));
				if(boxTMin <= boxTMax and boxTMin <= closestDistance and boxTMax > 0) {
					selectedBlockPos = voxelPos;
					break;
				}
			}
			if(tMax[0] < tMax[1]) {
				if(tMax[0] < tMax[2]) {
					voxelPos[0] += step[0];
					total_tMax = tMax[0];
					tMax[0] += tDelta[0];
				} else {
					voxelPos[2] += step[2];
					total_tMax = tMax[2];
					tMax[2] += tDelta[2];
				}
			} else {
				if(tMax[1] < tMax[2]) {
					voxelPos[1] += step[1];
					total_tMax = tMax[1];
					tMax[1] += tDelta[1];
				} else {
					voxelPos[2] += step[2];
					total_tMax = tMax[2];
					tMax[2] += tDelta[2];
				}
			}
		}
		// TODO: Test entities
	}
//	TODO(requires inventory):
//	/**
//	 * Places a block in the world.
//	 * @param stack
//	 * @param world
//	 */
//	public void placeBlock(ItemStack stack, World world) {
//		if (selectedSpatial != null && selectedSpatial instanceof BlockInstance) {
//			BlockInstance bi = (BlockInstance)selectedSpatial;
//			IntWrapper block = new IntWrapper(bi.getBlock());
//			Vector3d relativePos = new Vector3d(pos);
//			relativePos.sub(bi.x, bi.y, bi.z);
//			int b = stack.getBlock();
//			if (b != 0) {
//				Vector3i neighborDir = new Vector3i();
//				// Check if stuff can be added to the block itself:
//				if (b == bi.getBlock()) {
//					if (Blocks.mode(b).generateData(Cubyz.world, bi.x, bi.y, bi.z, relativePos, dir, neighborDir, block, false)) {
//						world.updateBlock(bi.x, bi.y, bi.z, block.data);
//						stack.add(-1);
//						return;
//					}
//				}
//				// Get the next neighbor:
//				Vector3i neighbor = new Vector3i();
//				getEmptyPlace(neighbor, neighborDir);
//				relativePos.set(pos);
//				relativePos.sub(neighbor.x, neighbor.y, neighbor.z);
//				boolean dataOnlyUpdate = world.getBlock(neighbor.x, neighbor.y, neighbor.z) == b;
//				if (dataOnlyUpdate) {
//					block.data = world.getBlock(neighbor.x, neighbor.y, neighbor.z);
//					if (Blocks.mode(b).generateData(Cubyz.world, neighbor.x, neighbor.y, neighbor.z, relativePos, dir, neighborDir, block, false)) {
//						world.updateBlock(neighbor.x, neighbor.y, neighbor.z, block.data);
//						stack.add(-1);
//					}
//				} else {
//					// Check if the block can actually be placed at that point. There might be entities or other blocks in the way.
//					if (Blocks.solid(world.getBlock(neighbor.x, neighbor.y, neighbor.z)))
//						return;
//					for(ClientEntity ent : ClientEntityManager.getEntities()) {
//						Vector3d pos = ent.position;
//						// Check if the block is inside:
//						if (neighbor.x < pos.x + ent.width && neighbor.x + 1 > pos.x - ent.width
//						        && neighbor.z < pos.z + ent.width && neighbor.z + 1 > pos.z - ent.width
//						        && neighbor.y < pos.y + ent.height && neighbor.y + 1 > pos.y)
//							return;
//					}
//					block.data = b;
//					if (Blocks.mode(b).generateData(Cubyz.world, neighbor.x, neighbor.y, neighbor.z, relativePos, dir, neighborDir, block, true)) {
//						world.updateBlock(neighbor.x, neighbor.y, neighbor.z, block.data);
//						stack.add(-1);
//					}
//				}
//			}
//		}
//	}
//	TODO: Check how this is needed.
//	/**
//	 * Returns the free block right next to the currently selected block.
//	 * @param pos selected block position
//	 * @param dir camera direction
//	 */
//	private void getEmptyPlace(Vector3i pos, Vector3i dir) {
//		int dirX = CubyzMath.nonZeroSign(this.dir.x);
//		int dirY = CubyzMath.nonZeroSign(this.dir.y);
//		int dirZ = CubyzMath.nonZeroSign(this.dir.z);
//		pos.set(((BlockInstance)selectedSpatial).x, ((BlockInstance)selectedSpatial).y, ((BlockInstance)selectedSpatial).z);
//		pos.add(-dirX, 0, 0);
//		dir.add(dirX, 0, 0);
//		min.set(pos.x, pos.y, pos.z).sub(this.pos);
//		max.set(min);
//		max.add(1, 1, 1); // scale, scale, scale
//		if (!intersection.test((float)min.x, (float)min.y, (float)min.z, (float)max.x, (float)max.y, (float)max.z)) {
//			pos.add(dirX, -dirY, 0);
//			dir.add(-dirX, dirY, 0);
//			min.set(pos.x, pos.y, pos.z).sub(this.pos);
//			max.set(min);
//			max.add(1, 1, 1); // scale, scale, scale
//			if (!intersection.test((float)min.x, (float)min.y, (float)min.z, (float)max.x, (float)max.y, (float)max.z)) {
//				pos.add(0, dirY, -dirZ);
//				dir.add(0, -dirY, dirZ);
//			}
//		}
//	}
	pub fn render(projectionMatrix: Mat4f, viewMatrix: Mat4f, playerPos: Vec3d) void {
		if(selectedBlockPos) |_selectedBlockPos| {
			var block = RenderStructure.getBlock(_selectedBlockPos[0], _selectedBlockPos[1], _selectedBlockPos[2]) orelse return;
			const model = blocks.meshes.model(block);
			const voxelModel = &models.voxelModels.items[model.modelIndex];
			var transformedMin = model.permutation.transform(voxelModel.min - @splat(3, @as(i32, 8))) + @splat(3, @as(i32, 8));
			var transformedMax = model.permutation.transform(voxelModel.max - @splat(3, @as(i32, 8))) + @splat(3, @as(i32, 8));
			const min = @min(transformedMin, transformedMax);
			const max = @max(transformedMin ,transformedMax);
			shader.bind();

			c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_FALSE, @ptrCast([*c]const f32, &projectionMatrix));
			c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_FALSE, @ptrCast([*c]const f32, &viewMatrix));
			c.glUniform3f(uniforms.modelPosition,
				@floatCast(f32, @intToFloat(f64, _selectedBlockPos[0]) - playerPos[0]),
				@floatCast(f32, @intToFloat(f64, _selectedBlockPos[1]) - playerPos[1]),
				@floatCast(f32, @intToFloat(f64, _selectedBlockPos[2]) - playerPos[2])
			);
			c.glUniform3f(uniforms.lowerBounds,
				@intToFloat(f32, min[0])/16.0,
				@intToFloat(f32, min[1])/16.0,
				@intToFloat(f32, min[2])/16.0
			);
			c.glUniform3f(uniforms.upperBounds,
				@intToFloat(f32, max[0])/16.0,
				@intToFloat(f32, max[1])/16.0,
				@intToFloat(f32, max[2])/16.0
			);

			c.glBindVertexArray(cubeVAO);
			c.glDrawElements(c.GL_LINES, 12*2, c.GL_UNSIGNED_BYTE, null); // TODO: Draw thicker lines so they are more visible. Maybe a simple shader + cube mesh is enough.
		}
	}
};

pub const RenderStructure = struct {
	const ChunkMeshNode = struct {
		mesh: chunk.meshing.ChunkMesh,
		shouldBeRemoved: bool, // Internal use.
		drawableChildren: u32, // How many children can be renderer. If this is 8 then there is no need to render this mesh.
	};
	var storageLists: [settings.highestLOD + 1][]?*ChunkMeshNode = undefined;
	var updatableList: std.ArrayList(chunk.ChunkPosition) = undefined;
	var clearList: std.ArrayList(*ChunkMeshNode) = undefined;
	var lastRD: i32 = 0;
	var lastFactor: f32 = 0;
	var lastX: [settings.highestLOD + 1]i32 = [_]i32{0} ** (settings.highestLOD + 1);
	var lastY: [settings.highestLOD + 1]i32 = [_]i32{0} ** (settings.highestLOD + 1);
	var lastZ: [settings.highestLOD + 1]i32 = [_]i32{0} ** (settings.highestLOD + 1);
	var lastSize: [settings.highestLOD + 1]i32 = [_]i32{0} ** (settings.highestLOD + 1);
	var lodMutex: [settings.highestLOD + 1]std.Thread.Mutex = [_]std.Thread.Mutex{std.Thread.Mutex{}} ** (settings.highestLOD + 1);
	var mutex = std.Thread.Mutex{};
	var blockUpdateMutex = std.Thread.Mutex{};
	const BlockUpdate = struct {
		x: i32,
		y: i32,
		z: i32,
		newBlock: blocks.Block,
	};
	var blockUpdateList: std.ArrayList(BlockUpdate) = undefined;

	pub fn init() !void {
		lastRD = 0;
		lastFactor = 0;
		updatableList = std.ArrayList(chunk.ChunkPosition).init(main.globalAllocator);
		blockUpdateList = std.ArrayList(BlockUpdate).init(main.globalAllocator);
		clearList = std.ArrayList(*ChunkMeshNode).init(main.globalAllocator);
		for(&storageLists) |*storageList| {
			storageList.* = try main.globalAllocator.alloc(?*ChunkMeshNode, 0);
		}
	}

	pub fn deinit() void {
		for(storageLists) |storageList| {
			for(storageList) |nullChunkMesh| {
				if(nullChunkMesh) |chunkMesh| {
					chunkMesh.mesh.deinit();
					main.globalAllocator.destroy(chunkMesh);
				}
			}
			main.globalAllocator.free(storageList);
		}
		updatableList.deinit();
		for(clearList.items) |chunkMesh| {
			chunkMesh.mesh.deinit();
			main.globalAllocator.destroy(chunkMesh);
		}
		blockUpdateList.deinit();
		clearList.deinit();
	}

	fn _getNode(pos: chunk.ChunkPosition) ?*ChunkMeshNode {
		var lod = std.math.log2_int(u31, pos.voxelSize);
		lodMutex[lod].lock();
		defer lodMutex[lod].unlock();
		var xIndex = pos.wx-%(&lastX[lod]).* >> lod+chunk.chunkShift;
		var yIndex = pos.wy-%(&lastY[lod]).* >> lod+chunk.chunkShift;
		var zIndex = pos.wz-%(&lastZ[lod]).* >> lod+chunk.chunkShift;
		if(xIndex < 0 or xIndex >= (&lastSize[lod]).*) return null;
		if(yIndex < 0 or yIndex >= (&lastSize[lod]).*) return null;
		if(zIndex < 0 or zIndex >= (&lastSize[lod]).*) return null;
		var index = (xIndex*(&lastSize[lod]).* + yIndex)*(&lastSize[lod]).* + zIndex;
		return (&storageLists[lod]).*[@intCast(usize, index)]; // TODO: Wait for #12205 to be fixed and remove the weird (&...).* workaround.
	}

	pub fn getChunk(x: i32, y: i32, z: i32) ?*chunk.Chunk {
		const node = RenderStructure._getNode(.{.wx = x, .wy = y, .wz = z, .voxelSize=1}) orelse return null;
		return node.mesh.chunk.load(.Monotonic);
	}

	pub fn getBlock(x: i32, y: i32, z: i32) ?blocks.Block {
		const node = RenderStructure._getNode(.{.wx = x, .wy = y, .wz = z, .voxelSize=1}) orelse return null;
		const block = (node.mesh.chunk.load(.Monotonic) orelse return null).getBlock(x & chunk.chunkMask, y & chunk.chunkMask, z & chunk.chunkMask);
		return block;
	}

	pub fn getNeighbor(_pos: chunk.ChunkPosition, resolution: u31, neighbor: u3) ?*chunk.meshing.ChunkMesh {
		var pos = _pos;
		pos.wx += pos.voxelSize*chunk.chunkSize*chunk.Neighbors.relX[neighbor];
		pos.wy += pos.voxelSize*chunk.chunkSize*chunk.Neighbors.relY[neighbor];
		pos.wz += pos.voxelSize*chunk.chunkSize*chunk.Neighbors.relZ[neighbor];
		pos.voxelSize = resolution;
		var node = _getNode(pos) orelse return null;
		return &node.mesh;
	}

	pub fn updateAndGetRenderChunks(conn: *network.Connection, playerPos: Vec3d, renderDistance: i32, LODFactor: f32, frustum: Frustum, meshes: *std.ArrayList(*chunk.meshing.ChunkMesh)) !void {
		if(lastRD != renderDistance and lastFactor != LODFactor) {
			try network.Protocols.genericUpdate.sendRenderDistance(conn, renderDistance, LODFactor);
		}
		const px = @floatToInt(i32, playerPos[0]);
		const py = @floatToInt(i32, playerPos[1]);
		const pz = @floatToInt(i32, playerPos[2]);

		var meshRequests = std.ArrayList(chunk.ChunkPosition).init(main.threadAllocator);
		defer meshRequests.deinit();

		for(0..storageLists.len) |_lod| {
			const lod = @intCast(u5, _lod);
			var maxRenderDistance = renderDistance*chunk.chunkSize << lod;
			if(lod != 0) maxRenderDistance = @floatToInt(i32, @ceil(@intToFloat(f32, maxRenderDistance)*LODFactor));
			var sizeShift = chunk.chunkShift + lod;
			const size = @intCast(u31, chunk.chunkSize << lod);
			const mask: i32 = size - 1;
			const invMask: i32 = ~mask;

			const maxSideLength = @intCast(u31, @divFloor(2*maxRenderDistance + size-1, size) + 2);
			var newList = try main.globalAllocator.alloc(?*ChunkMeshNode, maxSideLength*maxSideLength*maxSideLength);
			@memset(newList, null);

			const startX = size*(@divFloor(px, size) -% maxSideLength/2);
			const startY = size*(@divFloor(py, size) -% maxSideLength/2);
			const startZ = size*(@divFloor(pz, size) -% maxSideLength/2);

			const minX = px-%maxRenderDistance-%1 & invMask;
			const maxX = px+%maxRenderDistance+%size & invMask;
			var x = minX;
			while(x != maxX): (x +%= size) {
				const xIndex = @divExact(x -% startX, size);
				var deltaX: i64 = std.math.absInt(@as(i64, x +% size/2 -% px)) catch unreachable;
				deltaX = @max(0, deltaX - size/2);
				const maxYRenderDistanceSquare = @as(i64, maxRenderDistance)*@as(i64, maxRenderDistance) - deltaX*deltaX;
				const maxYRenderDistance = @floatToInt(i32, @ceil(@sqrt(@intToFloat(f64, maxYRenderDistanceSquare))));

				const minY = py-%maxYRenderDistance-%1 & invMask;
				const maxY = py+%maxYRenderDistance+%size & invMask;
				var y = minY;
				while(y != maxY): (y +%= size) {
					const yIndex = @divExact(y -% startY, size);
					var deltaY: i64 = std.math.absInt(@as(i64, y +% size/2 -% py)) catch unreachable;
					deltaY = @max(0, deltaY - size/2);
					const maxZRenderDistanceSquare = @as(i64, maxYRenderDistance)*@as(i64, maxYRenderDistance) - deltaY*deltaY;
					const maxZRenderDistance = @floatToInt(i32, @ceil(@sqrt(@intToFloat(f64, maxZRenderDistanceSquare))));

					const minZ = pz-%maxZRenderDistance-%1 & invMask;
					const maxZ = pz+%maxZRenderDistance+%size & invMask;
					var z = minZ;
					while(z != maxZ): (z +%= size) {
						const zIndex = @divExact(z -% startZ, size);
						const index = (xIndex*maxSideLength + yIndex)*maxSideLength + zIndex;
						const pos = chunk.ChunkPosition{.wx=x, .wy=y, .wz=z, .voxelSize=@as(u31, 1)<<lod};
						var node = _getNode(pos);
						if(node) |_node| {
							_node.shouldBeRemoved = false;
						} else {
							node = try main.globalAllocator.create(ChunkMeshNode);
							node.?.mesh = chunk.meshing.ChunkMesh.init(main.globalAllocator, pos);
							node.?.shouldBeRemoved = true; // Might be removed in the next iteration.
							try meshRequests.append(pos);
						}
						if(frustum.testAAB(Vec3f{
							@floatCast(f32, @intToFloat(f64, x) - playerPos[0]),
							@floatCast(f32, @intToFloat(f64, y) - playerPos[1]),
							@floatCast(f32, @intToFloat(f64, z) - playerPos[2]),
						}, Vec3f{
							@intToFloat(f32, size),
							@intToFloat(f32, size),
							@intToFloat(f32, size),
						}) and node.?.mesh.visibilityMask != 0 and node.?.mesh.vertexCount != 0) {
							try meshes.append(&node.?.mesh);
						}
						if(lod+1 != storageLists.len and node.?.mesh.generated) {
							if(_getNode(.{.wx=x, .wy=y, .wz=z, .voxelSize=@as(u31, 1)<<(lod+1)})) |parent| {
								const octantIndex = @intCast(u3, (x>>sizeShift & 1) | (y>>sizeShift & 1)<<1 | (z>>sizeShift & 1)<<2);
								parent.mesh.visibilityMask &= ~(@as(u8, 1) << octantIndex);
							}
						}
						node.?.drawableChildren = 0;
						newList[@intCast(usize, index)] = node;
					}
				}
			}

			var oldList = storageLists[lod];
			{
				lodMutex[lod].lock();
				defer lodMutex[lod].unlock();
				lastX[lod] = startX;
				lastY[lod] = startY;
				lastZ[lod] = startZ;
				lastSize[lod] = maxSideLength;
				storageLists[lod] = newList;
			}
			for(oldList) |nullMesh| {
				if(nullMesh) |mesh| {
					if(mesh.shouldBeRemoved) {
						if(mesh.mesh.pos.voxelSize != 1 << settings.highestLOD) {
							if(_getNode(.{.wx=mesh.mesh.pos.wx, .wy=mesh.mesh.pos.wy, .wz=mesh.mesh.pos.wz, .voxelSize=2*mesh.mesh.pos.voxelSize})) |parent| {
								const octantIndex = @intCast(u3, (mesh.mesh.pos.wx>>sizeShift & 1) | (mesh.mesh.pos.wy>>sizeShift & 1)<<1 | (mesh.mesh.pos.wz>>sizeShift & 1)<<2);
								parent.mesh.visibilityMask |= @as(u8, 1) << octantIndex;
							}
						}
						// Update the neighbors, so we don't get cracks when we look back:
						for(chunk.Neighbors.iterable) |neighbor| {
							if(getNeighbor(mesh.mesh.pos, mesh.mesh.pos.voxelSize, neighbor)) |neighborMesh| {
								if(neighborMesh.generated) {
									neighborMesh.mutex.lock();
									defer neighborMesh.mutex.unlock();
									try neighborMesh.uploadDataAndFinishNeighbors();
								}
							}
						}
						if(mesh.mesh.mutex.tryLock()) { // Make sure there is no task currently running on the thing.
							mesh.mesh.mutex.unlock();
							mesh.mesh.deinit();
							main.globalAllocator.destroy(mesh);
						} else {
							try clearList.append(mesh);
						}
					} else {
						mesh.shouldBeRemoved = true;
					}
				}
			}
			main.globalAllocator.free(oldList);
		}

		var i: usize = 0;
		while(i < clearList.items.len) {
			const mesh = clearList.items[i];
			if(mesh.mesh.mutex.tryLock()) { // Make sure there is no task currently running on the thing.
				mesh.mesh.mutex.unlock();
				mesh.mesh.deinit();
				main.globalAllocator.destroy(mesh);
				_ = clearList.swapRemove(i);
			} else {
				i += 1;
			}
		}

		lastRD = renderDistance;
		lastFactor = LODFactor;
		// Make requests after updating the, to avoid concurrency issues and reduce the number of requests:
		try network.Protocols.chunkRequest.sendRequest(conn, meshRequests.items);
	}

	pub fn updateMeshes(targetTime: i64) !void {
		{ // First of all process all the block updates:
			blockUpdateMutex.lock();
			defer blockUpdateMutex.unlock();
			for(blockUpdateList.items) |blockUpdate| {
				const pos = chunk.ChunkPosition{.wx=blockUpdate.x, .wy=blockUpdate.y, .wz=blockUpdate.z, .voxelSize=1};
				if(_getNode(pos)) |node| {
					try node.mesh.updateBlock(blockUpdate.x, blockUpdate.y, blockUpdate.z, blockUpdate.newBlock);
				}
			}
			blockUpdateList.clearRetainingCapacity();
		}
		mutex.lock();
		defer mutex.unlock();
		while(updatableList.items.len != 0) {
			// TODO: Find a faster solution than going through the entire list.
			var closestPriority: f32 = -std.math.floatMax(f32);
			var closestIndex: usize = 0;
			const playerPos = game.Player.getPosBlocking();
			for(updatableList.items, 0..) |pos, i| {
				const priority = pos.getPriority(playerPos);
				if(priority > closestPriority) {
					closestPriority = priority;
					closestIndex = i;
				}
			}
			const pos = updatableList.orderedRemove(closestIndex);
			mutex.unlock();
			defer mutex.lock();
			const nullNode = _getNode(pos);
			if(nullNode) |node| {
				node.mesh.mutex.lock();
				defer node.mesh.mutex.unlock();
				node.mesh.uploadDataAndFinishNeighbors() catch |err| {
					if(err == error.LODMissing) {
						mutex.lock();
						defer mutex.unlock();
						try updatableList.append(pos);
					} else {
						return err;
					}
				};
			}
			if(std.time.milliTimestamp() >= targetTime) break; // Update at least one mesh.
		}
	}

	pub const MeshGenerationTask = struct {
		mesh: *chunk.Chunk,

		pub const vtable = utils.ThreadPool.VTable{
			.getPriority = @ptrCast(*const fn(*anyopaque) f32, &getPriority),
			.isStillNeeded = @ptrCast(*const fn(*anyopaque) bool, &isStillNeeded),
			.run = @ptrCast(*const fn(*anyopaque) Allocator.Error!void, &run),
			.clean = @ptrCast(*const fn(*anyopaque) void, &clean),
		};

		pub fn schedule(mesh: *chunk.Chunk) !void {
			var task = try main.globalAllocator.create(MeshGenerationTask);
			task.* = MeshGenerationTask {
				.mesh = mesh,
			};
			try main.threadPool.addTask(task, &vtable);
		}

		pub fn getPriority(self: *MeshGenerationTask) f32 {
			return self.mesh.pos.getPriority(game.Player.getPosBlocking()); // TODO: This is called in loop, find a way to do this without calling the mutex every time.
		}

		pub fn isStillNeeded(self: *MeshGenerationTask) bool {
			var distanceSqr = self.mesh.pos.getMinDistanceSquared(game.Player.getPosBlocking()); // TODO: This is called in loop, find a way to do this without calling the mutex every time.
			var maxRenderDistance = settings.renderDistance*chunk.chunkSize*self.mesh.pos.voxelSize;
			if(self.mesh.pos.voxelSize != 1) maxRenderDistance = @floatToInt(u31, @ceil(@intToFloat(f32, maxRenderDistance)*settings.LODFactor));
			maxRenderDistance += 2*self.mesh.pos.voxelSize*chunk.chunkSize;
			return distanceSqr < @intToFloat(f64, maxRenderDistance*maxRenderDistance);
		}

		pub fn run(self: *MeshGenerationTask) Allocator.Error!void {
			const pos = self.mesh.pos;
			const nullNode = _getNode(pos);
			if(nullNode) |node| {
				{
					node.mesh.mutex.lock();
					defer node.mesh.mutex.unlock();
					try node.mesh.regenerateMainMesh(self.mesh);
				}
				mutex.lock();
				defer mutex.unlock();
				updatableList.append(pos) catch |err| {
					std.log.err("Error while regenerating mesh: {s}", .{@errorName(err)});
					if(@errorReturnTrace()) |trace| {
						std.log.err("Trace: {}", .{trace});
					}
					main.globalAllocator.destroy(self.mesh);
				};
			} else {
				main.globalAllocator.destroy(self.mesh);
			}
			main.globalAllocator.destroy(self);
		}

		pub fn clean(self: *MeshGenerationTask) void {
			main.globalAllocator.destroy(self.mesh);
			main.globalAllocator.destroy(self);
		}
	};

	pub fn updateBlock(x: i32, y: i32, z: i32, newBlock: blocks.Block) !void {
		blockUpdateMutex.lock();
		try blockUpdateList.append(BlockUpdate{.x=x, .y=y, .z=z, .newBlock=newBlock});
		defer blockUpdateMutex.unlock();
	}

	pub fn updateChunkMesh(mesh: *chunk.Chunk) !void {
		try MeshGenerationTask.schedule(mesh);
	}
};
