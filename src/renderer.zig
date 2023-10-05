const std = @import("std");
const Allocator = std.mem.Allocator;

const blocks = @import("blocks.zig");
const chunk = @import("chunk.zig");
const entity = @import("entity.zig");
const graphics = @import("graphics.zig");
const c = graphics.c;
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
const gpu_performance_measuring = main.gui.windowlist.gpu_performance_measuring;
const Vec2f = vec.Vec2f;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const Vec4f = vec.Vec4f;
const Mat4f = vec.Mat4f;

/// The number of milliseconds after which no more chunk meshes are created. This allows the game to run smoother on movement.
const maximumMeshTime = 12;
pub const zNear = 0.1;
pub const zFar = 65536.0; // TODO: Fix z-fighting problems.

var deferredRenderPassShader: graphics.Shader = undefined;
var deferredUniforms: struct {
	color: c_int,
	depthTexture: c_int,
	@"fog.color": c_int,
	@"fog.density": c_int,
	tanXY: c_int,
	zNear: c_int,
	zFar: c_int,
} = undefined;
var fakeReflectionShader: graphics.Shader = undefined;
var fakeReflectionUniforms: struct {
	normalVector: c_int,
	upVector: c_int,
	rightVector: c_int,
	frequency: c_int,
	reflectionMapSize: c_int,
} = undefined;

pub var activeFrameBuffer: c_uint = 0;

pub const reflectionCubeMapSize = 64;
var reflectionCubeMap: graphics.CubeMapTexture = undefined;

pub fn init() !void {
	deferredRenderPassShader = try Shader.initAndGetUniforms("assets/cubyz/shaders/deferred_render_pass.vs", "assets/cubyz/shaders/deferred_render_pass.fs", &deferredUniforms);
	fakeReflectionShader = try Shader.initAndGetUniforms("assets/cubyz/shaders/fake_reflection.vs", "assets/cubyz/shaders/fake_reflection.fs", &fakeReflectionUniforms);
	worldFrameBuffer.init(true, c.GL_NEAREST, c.GL_CLAMP_TO_EDGE);
	worldFrameBuffer.updateSize(Window.width, Window.height, c.GL_RGB16F);
	try Bloom.init();
	try MeshSelection.init();
	try MenuBackGround.init();
	reflectionCubeMap = graphics.CubeMapTexture.init();
	reflectionCubeMap.generate(reflectionCubeMapSize, reflectionCubeMapSize);
	initReflectionCubeMap();
}

pub fn deinit() void {
	deferredRenderPassShader.deinit();
	fakeReflectionShader.deinit();
	worldFrameBuffer.deinit();
	Bloom.deinit();
	MeshSelection.deinit();
	MenuBackGround.deinit();
	reflectionCubeMap.deinit();
}

fn initReflectionCubeMap() void {
	c.glViewport(0, 0, reflectionCubeMapSize, reflectionCubeMapSize);
	var framebuffer: graphics.FrameBuffer = undefined;
	framebuffer.init(false, c.GL_LINEAR, c.GL_CLAMP_TO_EDGE);
	defer framebuffer.deinit();
	framebuffer.bind();
	fakeReflectionShader.bind();
	c.glUniform1f(fakeReflectionUniforms.frequency, 1);
	c.glUniform1f(fakeReflectionUniforms.reflectionMapSize, reflectionCubeMapSize);
	for(0..6) |face| {
		c.glUniform3fv(fakeReflectionUniforms.normalVector, 1, @ptrCast(&graphics.CubeMapTexture.faceNormal(face)));
		c.glUniform3fv(fakeReflectionUniforms.upVector, 1, @ptrCast(&graphics.CubeMapTexture.faceUp(face)));
		c.glUniform3fv(fakeReflectionUniforms.rightVector, 1, @ptrCast(&graphics.CubeMapTexture.faceRight(face)));
		reflectionCubeMap.bindToFramebuffer(framebuffer, @intCast(face));
		c.glBindVertexArray(graphics.draw.rectVAO);
		c.glDisable(c.GL_DEPTH_TEST);
		c.glDisable(c.GL_CULL_FACE);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}
}

var worldFrameBuffer: graphics.FrameBuffer = undefined;

var lastWidth: u31 = 0;
var lastHeight: u31 = 0;
var lastFov: f32 = 0;
pub fn updateViewport(width: u31, height: u31, fov: f32) void {
	lastWidth = width;
	lastHeight = height;
	lastFov = fov;
	c.glViewport(0, 0, width, height);
	game.projectionMatrix = Mat4f.perspective(std.math.degreesToRadians(f32, fov), @as(f32, @floatFromInt(width))/@as(f32, @floatFromInt(height)), zNear, zFar);
	worldFrameBuffer.updateSize(width, height, c.GL_RGB16F);
	worldFrameBuffer.unbind();
}

pub fn render(playerPosition: Vec3d) !void {
	var startTime = std.time.milliTimestamp();
//	TODO:
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
	if(game.world) |world| {
//		// TODO: Handle colors and sun position in the world.
		var ambient: Vec3f = undefined;
		ambient[0] = @max(0.1, world.ambientLight);
		ambient[1] = @max(0.1, world.ambientLight);
		ambient[2] = @max(0.1, world.ambientLight);
		var skyColor = vec.xyz(world.clearColor);
		game.fog.color = skyColor;

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
}

pub fn renderWorld(world: *World, ambientLight: Vec3f, skyColor: Vec3f, playerPos: Vec3d) !void {
	_ = world;
	worldFrameBuffer.bind();
	gpu_performance_measuring.startQuery(.clear);
	worldFrameBuffer.clear(Vec4f{skyColor[0], skyColor[1], skyColor[2], 1});
	gpu_performance_measuring.stopQuery();
	game.camera.updateViewMatrix();

	// Uses FrustumCulling on the chunks.
	var frustum = Frustum.init(Vec3f{0, 0, 0}, game.camera.viewMatrix, lastFov, lastWidth, lastHeight);
	_ = frustum;

	const time: u32 = @intCast(std.time.milliTimestamp() & std.math.maxInt(u32));

	gpu_performance_measuring.startQuery(.animation);
	blocks.meshes.preProcessAnimationData(time);
	gpu_performance_measuring.stopQuery();
	

	// Update the uniforms. The uniforms are needed to render the replacement meshes.
	chunk.meshing.bindShaderAndUniforms(game.projectionMatrix, ambientLight);

	reflectionCubeMap.bindTo(2);
	c.glActiveTexture(c.GL_TEXTURE0);
	blocks.meshes.blockTextureArray.bind();
	c.glActiveTexture(c.GL_TEXTURE1);
	blocks.meshes.emissionTextureArray.bind();

//	SimpleList<NormalChunkMesh> visibleChunks = new SimpleList<NormalChunkMesh>(new NormalChunkMesh[64]);
//	SimpleList<ReducedChunkMesh> visibleReduced = new SimpleList<ReducedChunkMesh>(new ReducedChunkMesh[64]);

	chunk.meshing.quadsDrawn = 0;
	chunk.meshing.transparentQuadsDrawn = 0;
	const meshes = try RenderStructure.updateAndGetRenderChunks(game.world.?.conn, playerPos, settings.renderDistance, settings.LODFactor);

//	for (ChunkMesh mesh : Cubyz.chunkTree.getRenderChunks(frustumInt, x0, y0, z0)) {
//		if (mesh instanceof NormalChunkMesh) {
//			visibleChunks.add((NormalChunkMesh)mesh);
//			
//			mesh.render(playerPosition);
//		} else if (mesh instanceof ReducedChunkMesh) {
//			visibleReduced.add((ReducedChunkMesh)mesh);
//		}
//	}
	gpu_performance_measuring.startQuery(.chunk_rendering);
	MeshSelection.select(playerPos, game.camera.direction);
	MeshSelection.render(game.projectionMatrix, game.camera.viewMatrix, playerPos);

	chunk.meshing.bindShaderAndUniforms(game.projectionMatrix, ambientLight);

	for(meshes) |mesh| {
		mesh.render(playerPos);
	}
	gpu_performance_measuring.stopQuery();

//		for(int i = 0; i < visibleReduced.size; i++) {
//			ReducedChunkMesh mesh = visibleReduced.array[i];
//			mesh.render(playerPosition);
//		}

	gpu_performance_measuring.startQuery(.entity_rendering);
	entity.ClientEntityManager.render(game.projectionMatrix, ambientLight, .{1, 0.5, 0.25}, playerPos);

	try itemdrop.ItemDropRenderer.renderItemDrops(game.projectionMatrix, ambientLight, playerPos, time);
	gpu_performance_measuring.stopQuery();

	// Render transparent chunk meshes:
	worldFrameBuffer.bindDepthTexture(c.GL_TEXTURE3);

	gpu_performance_measuring.startQuery(.transparent_rendering);
	c.glTextureBarrier();
	chunk.meshing.bindTransparentShaderAndUniforms(game.projectionMatrix, ambientLight);

	c.glBlendEquation(c.GL_FUNC_ADD);
	c.glBlendFunc(c.GL_ONE, c.GL_SRC1_COLOR);
	c.glDepthFunc(c.GL_LEQUAL);
	c.glDepthMask(c.GL_FALSE);
	{
		var i: usize = meshes.len;
		while(true) {
			if(i == 0) break;
			i -= 1;
			try meshes[i].renderTransparent(playerPos);
		}
	}
	c.glDepthMask(c.GL_TRUE);
	c.glDepthFunc(c.GL_LESS);
	c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
	gpu_performance_measuring.stopQuery();
//		NormalChunkMesh.bindTransparentShader(ambientLight, directionalLight.getDirection(), time);

	worldFrameBuffer.bindTexture(c.GL_TEXTURE3);

//		if(selected != null && Blocks.transparent(selected.getBlock())) {
//			BlockBreakingRenderer.render(selected, playerPosition);
//			glActiveTexture(GL_TEXTURE0);
//			Meshes.blockTextureArray.bind();
//			glActiveTexture(GL_TEXTURE1);
//			Meshes.emissionTextureArray.bind();
//		}

	const playerBlock = RenderStructure.getBlockFromAnyLod(@intFromFloat(@floor(playerPos[0])), @intFromFloat(@floor(playerPos[1])), @intFromFloat(@floor(playerPos[2])));
	
	if(settings.bloom) {
		Bloom.render(lastWidth, lastHeight, playerBlock);
	}
	gpu_performance_measuring.startQuery(.final_copy);
	worldFrameBuffer.bindTexture(c.GL_TEXTURE3);
	worldFrameBuffer.bindDepthTexture(c.GL_TEXTURE4);
	worldFrameBuffer.unbind();
	deferredRenderPassShader.bind();
	c.glUniform1i(deferredUniforms.color, 3);
	c.glUniform1i(deferredUniforms.depthTexture, 4);
	if(playerBlock.typ == 0) {
		c.glUniform3fv(deferredUniforms.@"fog.color", 1, @ptrCast(&game.fog.color));
		c.glUniform1f(deferredUniforms.@"fog.density", game.fog.density);
	} else {
		const fogColor = blocks.meshes.fogColor(playerBlock);
		c.glUniform3f(deferredUniforms.@"fog.color", @as(f32, @floatFromInt(fogColor >> 16 & 255))/255.0, @as(f32, @floatFromInt(fogColor >> 8 & 255))/255.0, @as(f32, @floatFromInt(fogColor >> 0 & 255))/255.0);
		c.glUniform1f(deferredUniforms.@"fog.density", blocks.meshes.fogDensity(playerBlock));
	}
	c.glUniform1f(deferredUniforms.zNear, zNear);
	c.glUniform1f(deferredUniforms.zFar, zFar);
	c.glUniform2f(deferredUniforms.tanXY, 1.0/game.projectionMatrix.columns[0][0], 1.0/game.projectionMatrix.columns[1][1]);

	c.glBindFramebuffer(c.GL_FRAMEBUFFER, activeFrameBuffer);

	c.glBindVertexArray(graphics.draw.rectVAO);
	c.glDisable(c.GL_DEPTH_TEST);
	c.glDisable(c.GL_CULL_FACE);
	c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);

	c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

	try entity.ClientEntityManager.renderNames(game.projectionMatrix, playerPos);
	gpu_performance_measuring.stopQuery();
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
	var colorExtractUniforms: struct {
		depthTexture: c_int,
		zNear: c_int,
		zFar: c_int,
		tanXY: c_int,
		@"fog.color": c_int,
		@"fog.density": c_int,
	} = undefined;

	pub fn init() !void {
		buffer1.init(false, c.GL_LINEAR, c.GL_CLAMP_TO_EDGE);
		buffer2.init(false, c.GL_LINEAR, c.GL_CLAMP_TO_EDGE);
		firstPassShader = try graphics.Shader.init("assets/cubyz/shaders/bloom/first_pass.vs", "assets/cubyz/shaders/bloom/first_pass.fs");
		secondPassShader = try graphics.Shader.init("assets/cubyz/shaders/bloom/second_pass.vs", "assets/cubyz/shaders/bloom/second_pass.fs");
		colorExtractAndDownsampleShader = try graphics.Shader.initAndGetUniforms("assets/cubyz/shaders/bloom/color_extractor_downsample.vs", "assets/cubyz/shaders/bloom/color_extractor_downsample.fs", &colorExtractUniforms);
		upscaleShader = try graphics.Shader.init("assets/cubyz/shaders/bloom/upscale.vs", "assets/cubyz/shaders/bloom/upscale.fs");
	}

	pub fn deinit() void {
		buffer1.deinit();
		buffer2.deinit();
		firstPassShader.deinit();
		secondPassShader.deinit();
		upscaleShader.deinit();
	}

	fn extractImageDataAndDownsample(playerBlock: blocks.Block) void {
		colorExtractAndDownsampleShader.bind();
		worldFrameBuffer.bindTexture(c.GL_TEXTURE3);
		worldFrameBuffer.bindDepthTexture(c.GL_TEXTURE4);
		buffer1.bind();
		c.glUniform1i(colorExtractUniforms.depthTexture, 4);
		if(playerBlock.typ == 0) {
			c.glUniform3fv(colorExtractUniforms.@"fog.color", 1, @ptrCast(&game.fog.color));
			c.glUniform1f(colorExtractUniforms.@"fog.density", game.fog.density);
		} else {
			const fogColor = blocks.meshes.fogColor(playerBlock);
			c.glUniform3f(colorExtractUniforms.@"fog.color", @as(f32, @floatFromInt(fogColor >> 16 & 255))/255.0, @as(f32, @floatFromInt(fogColor >> 8 & 255))/255.0, @as(f32, @floatFromInt(fogColor >> 0 & 255))/255.0);
			c.glUniform1f(colorExtractUniforms.@"fog.density", blocks.meshes.fogDensity(playerBlock));
		}
		c.glUniform1f(colorExtractUniforms.zNear, zNear);
		c.glUniform1f(colorExtractUniforms.zFar, zFar);
		c.glUniform2f(colorExtractUniforms.tanXY, 1.0/game.projectionMatrix.columns[0][0], 1.0/game.projectionMatrix.columns[1][1]);
		c.glBindVertexArray(graphics.draw.rectVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	fn firstPass() void {
		firstPassShader.bind();
		buffer1.bindTexture(c.GL_TEXTURE3);
		buffer2.bind();
		c.glBindVertexArray(graphics.draw.rectVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	fn secondPass() void {
		secondPassShader.bind();
		buffer2.bindTexture(c.GL_TEXTURE3);
		buffer1.bind();
		c.glBindVertexArray(graphics.draw.rectVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	fn upscale() void {
		upscaleShader.bind();
		buffer1.bindTexture(c.GL_TEXTURE3);
		worldFrameBuffer.bind();
		c.glBindVertexArray(graphics.draw.rectVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	pub fn render(currentWidth: u31, currentHeight: u31, playerBlock: blocks.Block) void {
		if(width != currentWidth or height != currentHeight) {
			width = currentWidth;
			height = currentHeight;
			buffer1.updateSize(width/4, height/4, c.GL_RGB16F);
			std.debug.assert(buffer1.validate());
			buffer2.updateSize(width/4, height/4, c.GL_RGB16F);
			std.debug.assert(buffer2.validate());
		}
		gpu_performance_measuring.startQuery(.bloom_extract_downsample);
		c.glDisable(c.GL_DEPTH_TEST);
		c.glDisable(c.GL_CULL_FACE);
		c.glDepthMask(c.GL_FALSE);

		c.glViewport(0, 0, width/4, height/4);
		extractImageDataAndDownsample(playerBlock);
		gpu_performance_measuring.stopQuery();
		gpu_performance_measuring.startQuery(.bloom_first_pass);
		firstPass();
		gpu_performance_measuring.stopQuery();
		gpu_performance_measuring.startQuery(.bloom_second_pass);
		secondPass();
		gpu_performance_measuring.stopQuery();
		gpu_performance_measuring.startQuery(.bloom_upscale);
		c.glViewport(0, 0, width, height);
		c.glBlendFunc(c.GL_ONE, c.GL_ONE);
		upscale();

		c.glDepthMask(c.GL_TRUE);
		c.glEnable(c.GL_DEPTH_TEST);
		c.glEnable(c.GL_CULL_FACE);
		c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
		gpu_performance_measuring.stopQuery();
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
		c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(rawData.len*@sizeOf(f32)), &rawData, c.GL_STATIC_DRAW);
		c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 5*@sizeOf(f32), null);
		c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, 5*@sizeOf(f32), @ptrFromInt(3*@sizeOf(f32)));
		c.glEnableVertexAttribArray(0);
		c.glEnableVertexAttribArray(1);
		c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, vbos[1]);
		c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @intCast(indices.len*@sizeOf(c_int)), &indices, c.GL_STATIC_DRAW);

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
			if(entry.kind == .file and std.ascii.endsWithIgnoreCase(entry.basename, ".png")) {
				try fileList.append(try main.threadAllocator.dupe(u8, entry.path));
			}
		}
		if(fileList.items.len == 0) {
			std.log.warn("Couldn't find any background scene images in \"assets/backgrounds\".", .{});
			texture = .{.textureID = 0};
			return;
		}
		const theChosenOne = main.random.nextIntBounded(u32, &main.seed, @as(u32, @intCast(fileList.items.len)));
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
		angle += @as(f32, @floatFromInt(newTime - lastTime))/2e10;
		lastTime = newTime;
		var viewMatrix = Mat4f.rotationY(angle);
		shader.bind();

		c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_FALSE, @ptrCast(&viewMatrix));
		c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_FALSE, @ptrCast(&game.projectionMatrix));

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
		buffer.init(true, c.GL_NEAREST, c.GL_REPEAT);
		defer buffer.deinit();
		buffer.updateSize(size, size, c.GL_RGBA8);

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
					image.setRGB(x + size*i, size - 1 - y, @bitCast(pixels[index]));
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
	planes: [4]Plane, // Who cares about the near/far plane anyways?

	pub fn init(cameraPos: Vec3f, rotationMatrix: Mat4f, fovY: f32, width: u31, height: u31) Frustum {
		var invRotationMatrix = rotationMatrix.transpose();
		var cameraDir = vec.xyz(invRotationMatrix.mulVec(Vec4f{0, 0, 1, 1}));
		var cameraUp = vec.xyz(invRotationMatrix.mulVec(Vec4f{0, 1, 0, 1}));
		var cameraRight = vec.xyz(invRotationMatrix.mulVec(Vec4f{1, 0, 0, 1}));

		const halfVSide = std.math.tan(std.math.degreesToRadians(f32, fovY)*0.5);
		const halfHSide = halfVSide*@as(f32, @floatFromInt(width))/@as(f32, @floatFromInt(height));

		var self: Frustum = undefined;
		self.planes[0] = Plane{.pos = cameraPos, .norm=vec.cross(cameraUp, cameraDir + cameraRight*@as(Vec3f, @splat(halfHSide)))}; // right
		self.planes[1] = Plane{.pos = cameraPos, .norm=vec.cross(cameraDir - cameraRight*@as(Vec3f, @splat(halfHSide)), cameraUp)}; // left
		self.planes[2] = Plane{.pos = cameraPos, .norm=vec.cross(cameraRight, cameraDir - cameraUp*@as(Vec3f, @splat(halfVSide)))}; // top
		self.planes[3] = Plane{.pos = cameraPos, .norm=vec.cross(cameraDir + cameraUp*@as(Vec3f, @splat(halfVSide)), cameraRight)}; // bottom
		return self;
	}

	pub fn testAAB(self: Frustum, pos: Vec3f, dim: Vec3f) bool {
		inline for(self.planes) |plane| {
			var dist: f32 = vec.dot(pos - plane.pos, plane.norm);
			// Find the most positive corner:
			dist += @max(0, dim[0]*plane.norm[0]);
			dist += @max(0, dim[1]*plane.norm[1]);
			dist += @max(0, dim[2]*plane.norm[2]);
			if(dist < 0) return false;
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

	var posBeforeBlock: Vec3i = undefined;
	var selectedBlockPos: ?Vec3i = null;
	var lastPos: Vec3d = undefined;
	var lastDir: Vec3f = undefined;
	pub fn select(_pos: Vec3d, _dir: Vec3f) void {
		var pos = _pos;
		// TODO: pos.y += Player.cameraHeight;
		lastPos = pos;
		var dir = vec.floatCast(f64, _dir);
		lastDir = _dir;

		// Test blocks:
		const closestDistance: f64 = 6.0; // selection now limited
		// Implementation of "A Fast Voxel Traversal Algorithm for Ray Tracing"  http://www.cse.yorku.ca/~amana/research/grid.pdf
		const step = vec.intFromFloat(i32, std.math.sign(dir));
		const invDir = @as(Vec3d, @splat(1))/dir;
		const tDelta = @abs(invDir);
		var tMax = (@floor(pos) - pos)*invDir;
		tMax = @max(tMax, tMax + tDelta*vec.floatFromInt(f64, step));
		tMax = @select(f64, dir == @as(Vec3d, @splat(0)), @as(Vec3d, @splat(std.math.inf(f64))), tMax);
		var voxelPos = vec.intFromFloat(i32, @floor(pos));

		var total_tMax: f64 = 0;

		selectedBlockPos = null;

		while(total_tMax < closestDistance) {
			const block = RenderStructure.getBlock(voxelPos[0], voxelPos[1], voxelPos[2]) orelse break;
			if(block.typ != 0) {
				// Check the true bounding box (using this algorithm here: https://tavianator.com/2011/ray_box.html):
				const model = blocks.meshes.model(block);
				const voxelModel = &models.voxelModels.items[model.modelIndex];
				var transformedMin = model.permutation.transform(voxelModel.min - @as(Vec3i, @splat(8))) + @as(Vec3i, @splat(8));
				var transformedMax = model.permutation.transform(voxelModel.max - @as(Vec3i, @splat(8))) + @as(Vec3i, @splat(8));
				const min = @min(transformedMin, transformedMax);
				const max = @max(transformedMin ,transformedMax);
				const t1 = (vec.floatFromInt(f64, voxelPos) + vec.floatFromInt(f64, min)/@as(Vec3d, @splat(16.0)) - pos)*invDir;
				const t2 = (vec.floatFromInt(f64, voxelPos) + vec.floatFromInt(f64, max)/@as(Vec3d, @splat(16.0)) - pos)*invDir;
				const boxTMin = @reduce(.Max, @min(t1, t2));
				const boxTMax = @reduce(.Min, @max(t1, t2));
				if(boxTMin <= boxTMax and boxTMin <= closestDistance and boxTMax > 0) {
					selectedBlockPos = voxelPos;
					break;
				}
			}
			posBeforeBlock = voxelPos;
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

	pub fn placeBlock(inventoryStack: *main.items.ItemStack) !void {
		if(selectedBlockPos) |selectedPos| {
			var block = RenderStructure.getBlock(selectedPos[0], selectedPos[1], selectedPos[2]) orelse return;
			if(inventoryStack.item) |item| {
				switch(item) {
					.baseItem => |baseItem| {
						if(baseItem.block) |itemBlock| {
							const rotationMode = blocks.Block.mode(.{.typ = itemBlock, .data = 0});
							var neighborDir = Vec3i{0, 0, 0};
							// Check if stuff can be added to the block itself:
							if(itemBlock == block.typ) {
								const relPos = lastPos - vec.floatFromInt(f64, selectedPos);
								if(rotationMode.generateData(main.game.world.?, selectedPos, relPos, lastDir, neighborDir, &block, false)) {
									// TODO: world.updateBlock(bi.x, bi.y, bi.z, block.data); (→ Sending it over the network)
									try RenderStructure.updateBlock(selectedPos[0], selectedPos[1], selectedPos[2], block);
									_ = inventoryStack.add(@as(i32, -1));
									return;
								}
							}
							// Check the block in front of it:
							const neighborPos = posBeforeBlock;
							neighborDir = selectedPos - posBeforeBlock;
							const relPos = lastPos - vec.floatFromInt(f64, neighborPos);
							block = RenderStructure.getBlock(neighborPos[0], neighborPos[1], neighborPos[2]) orelse return;
							if(block.typ == itemBlock) {
								if(rotationMode.generateData(main.game.world.?, neighborPos, relPos, lastDir, neighborDir, &block, false)) {
									// TODO: world.updateBlock(bi.x, bi.y, bi.z, block.data); (→ Sending it over the network)
									try RenderStructure.updateBlock(neighborPos[0], neighborPos[1], neighborPos[2], block);
									_ = inventoryStack.add(@as(i32, -1));
									return;
								}
							} else {
								// Check if the block can actually be placed at that point. There might be entities or other blocks in the way.
								if(block.solid()) return;
								// TODO:
//								for(ClientEntity ent : ClientEntityManager.getEntities()) {
//									Vector3d pos = ent.position;
//									// Check if the block is inside:
//									if (neighbor.x < pos.x + ent.width && neighbor.x + 1 > pos.x - ent.width
//									        && neighbor.z < pos.z + ent.width && neighbor.z + 1 > pos.z - ent.width
//									        && neighbor.y < pos.y + ent.height && neighbor.y + 1 > pos.y)
//										return;
//								}
								block.typ = itemBlock;
								block.data = 0;
								if(rotationMode.generateData(main.game.world.?, neighborPos, relPos, lastDir, neighborDir, &block, true)) {
									// TODO: world.updateBlock(bi.x, bi.y, bi.z, block.data); (→ Sending it over the network)
									try RenderStructure.updateBlock(neighborPos[0], neighborPos[1], neighborPos[2], block);
									_ = inventoryStack.add(@as(i32, -1));
									return;
								}
							}
						}
					},
					.tool => |tool| {
						_ = tool; // TODO: Tools might change existing blocks.
					}
				}
			}
		}
	}

	pub fn drawCube(projectionMatrix: Mat4f, viewMatrix: Mat4f, relativePositionToPlayer: Vec3d, min: Vec3f, max: Vec3f) void {
		shader.bind();

		c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_FALSE, @ptrCast(&projectionMatrix));
		c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_FALSE, @ptrCast(&viewMatrix));

		c.glUniform3f(uniforms.modelPosition,
			@floatCast(relativePositionToPlayer[0]),
			@floatCast(relativePositionToPlayer[1]),
			@floatCast(relativePositionToPlayer[2]),
		);
		c.glUniform3f(uniforms.lowerBounds, min[0], min[1], min[2]);
		c.glUniform3f(uniforms.upperBounds, max[0], max[1], max[2]);

		c.glBindVertexArray(cubeVAO);
		// c.glLineWidth(2); // TODO: Draw thicker lines so they are more visible. Maybe a simple shader + cube mesh is enough.
		c.glDrawElements(c.GL_LINES, 12*2, c.GL_UNSIGNED_BYTE, null);
	}

	pub fn render(projectionMatrix: Mat4f, viewMatrix: Mat4f, playerPos: Vec3d) void {
		if(selectedBlockPos) |_selectedBlockPos| {
			c.glEnable(c.GL_POLYGON_OFFSET_LINE);
			defer c.glDisable(c.GL_POLYGON_OFFSET_LINE);
			c.glPolygonOffset(-2, 0);
			var block = RenderStructure.getBlock(_selectedBlockPos[0], _selectedBlockPos[1], _selectedBlockPos[2]) orelse return;
			const model = blocks.meshes.model(block);
			const voxelModel = &models.voxelModels.items[model.modelIndex];
			var transformedMin = model.permutation.transform(voxelModel.min - @as(Vec3i, @splat(8))) + @as(Vec3i, @splat(8));
			var transformedMax = model.permutation.transform(voxelModel.max - @as(Vec3i, @splat(8))) + @as(Vec3i, @splat(8));
			const min = @min(transformedMin, transformedMax);
			const max = @max(transformedMin ,transformedMax);
			drawCube(projectionMatrix, viewMatrix, vec.floatFromInt(f64, _selectedBlockPos) - playerPos, vec.floatFromInt(f32, min)/@as(Vec3f, @splat(16.0)), vec.floatFromInt(f32, max)/@as(Vec3f, @splat(16.0)));
		}
	}
};

pub const RenderStructure = struct {
	const ChunkMeshNode = struct {
		mesh: chunk.meshing.ChunkMesh,
		shouldBeRemoved: bool, // Internal use.
		drawableChildren: u32, // How many children can be renderer. If this is 8 then there is no need to render this mesh.
		lod: u3,
		min: Vec2f,
		max: Vec2f,
		active: bool,
	};
	var storageLists: [settings.highestLOD + 1][]?*ChunkMeshNode = [1][]?*ChunkMeshNode{&.{}} ** (settings.highestLOD + 1);
	var storageListsSwap: [settings.highestLOD + 1][]?*ChunkMeshNode = [1][]?*ChunkMeshNode{&.{}} ** (settings.highestLOD + 1);
	var meshList = std.ArrayList(*chunk.meshing.ChunkMesh).init(main.globalAllocator);
	var updatableList: std.ArrayList(chunk.ChunkPosition) = undefined;
	var updatableListSwap: std.ArrayList(chunk.ChunkPosition) = undefined;
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
		for(storageListsSwap) |storageList| {
			main.globalAllocator.free(storageList);
		}
		updatableList.deinit();
		for(clearList.items) |chunkMesh| {
			chunkMesh.mesh.deinit();
			main.globalAllocator.destroy(chunkMesh);
		}
		blockUpdateList.deinit();
		clearList.deinit();
		meshList.deinit();
	}

	fn getNodeFromRenderThread(pos: chunk.ChunkPosition) ?*ChunkMeshNode {
		var lod = std.math.log2_int(u31, pos.voxelSize);
		var xIndex = pos.wx-%(&lastX[lod]).* >> lod+chunk.chunkShift;
		var yIndex = pos.wy-%(&lastY[lod]).* >> lod+chunk.chunkShift;
		var zIndex = pos.wz-%(&lastZ[lod]).* >> lod+chunk.chunkShift;
		if(xIndex < 0 or xIndex >= (&lastSize[lod]).*) return null;
		if(yIndex < 0 or yIndex >= (&lastSize[lod]).*) return null;
		if(zIndex < 0 or zIndex >= (&lastSize[lod]).*) return null;
		var index = (xIndex*(&lastSize[lod]).* + yIndex)*(&lastSize[lod]).* + zIndex;
		return storageLists[lod][@intCast(index)];
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
		return storageLists[lod][@intCast(index)];
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

	pub fn getBlockFromAnyLod(x: i32, y: i32, z: i32) blocks.Block {
		var lod: u5 = 0;
		while(lod < settings.highestLOD) : (lod += 1) {
			const node = RenderStructure._getNode(.{.wx = x, .wy = y, .wz = z, .voxelSize=@as(u31, 1) << lod}) orelse continue;
			const block = (node.mesh.chunk.load(.Monotonic) orelse continue).getBlock(x & chunk.chunkMask<<lod, y & chunk.chunkMask<<lod, z & chunk.chunkMask<<lod);
			return block;
		}
		return blocks.Block{.typ = 0, .data = 0};
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

	pub fn updateAndGetRenderChunks(conn: *network.Connection, playerPos: Vec3d, renderDistance: i32, LODFactor: f32) ![]*chunk.meshing.ChunkMesh {
		meshList.clearRetainingCapacity();
		if(lastRD != renderDistance and lastFactor != LODFactor) {
			try network.Protocols.genericUpdate.sendRenderDistance(conn, renderDistance, LODFactor);
		}
		const px: i32 = @intFromFloat(playerPos[0]);
		const py: i32 = @intFromFloat(playerPos[1]);
		const pz: i32 = @intFromFloat(playerPos[2]);

		var meshRequests = std.ArrayList(chunk.ChunkPosition).init(main.threadAllocator);
		defer meshRequests.deinit();

		for(0..storageLists.len) |_lod| { // TODO: Can this be done in a more intelligent way?
			const lod: u5 = @intCast(_lod);
			var maxRenderDistance = renderDistance*chunk.chunkSize << lod;
			if(lod != 0) maxRenderDistance = @intFromFloat(@ceil(@as(f32, @floatFromInt(maxRenderDistance))*LODFactor));
			const size: u31 = @intCast(chunk.chunkSize << lod);
			const mask: i32 = size - 1;
			const invMask: i32 = ~mask;

			const maxSideLength: u31 = @intCast(@divFloor(2*maxRenderDistance + size-1, size) + 2);
			var newList = storageListsSwap[_lod];
			if(newList.len != maxSideLength*maxSideLength*maxSideLength) {
				main.globalAllocator.free(newList);
				newList = try main.globalAllocator.alloc(?*ChunkMeshNode, maxSideLength*maxSideLength*maxSideLength);
			}
			@memset(newList, null);

			const startX = size*(@divFloor(px, size) -% maxSideLength/2);
			const startY = size*(@divFloor(py, size) -% maxSideLength/2);
			const startZ = size*(@divFloor(pz, size) -% maxSideLength/2);

			const minX = px-%maxRenderDistance-%1 & invMask;
			const maxX = px+%maxRenderDistance+%size & invMask;
			var x = minX;
			while(x != maxX): (x +%= size) {
				const xIndex = @divExact(x -% startX, size);
				var deltaX: i64 = @abs(x +% size/2 -% px);
				deltaX = @max(0, deltaX - size/2);
				const maxYRenderDistanceSquare: f64 = @floatFromInt(@as(i64, maxRenderDistance)*@as(i64, maxRenderDistance) - deltaX*deltaX);
				const maxYRenderDistance: i32 = @intFromFloat(@ceil(@sqrt(maxYRenderDistanceSquare)));

				const minY = py-%maxYRenderDistance-%1 & invMask;
				const maxY = py+%maxYRenderDistance+%size & invMask;
				var y = minY;
				while(y != maxY): (y +%= size) {
					const yIndex = @divExact(y -% startY, size);
					var deltaY: i64 = @abs(y +% size/2 -% py);
					deltaY = @max(0, deltaY - size/2);
					const maxZRenderDistanceSquare: f64 = @floatFromInt(@as(i64, maxYRenderDistance)*@as(i64, maxYRenderDistance) - deltaY*deltaY);
					const maxZRenderDistance: i32 = @intFromFloat(@ceil(@sqrt(maxZRenderDistanceSquare)));

					const minZ = pz-%maxZRenderDistance-%1 & invMask;
					const maxZ = pz+%maxZRenderDistance+%size & invMask;
					var z = minZ;
					while(z != maxZ): (z +%= size) {
						const zIndex = @divExact(z -% startZ, size);
						const index = (xIndex*maxSideLength + yIndex)*maxSideLength + zIndex;
						const pos = chunk.ChunkPosition{.wx=x, .wy=y, .wz=z, .voxelSize=@as(u31, 1)<<lod};
						var node = getNodeFromRenderThread(pos);
						if(node) |_node| {
							if(_node.mesh.generated) {
								_node.mesh.visibilityMask = 0xff;
							}
							_node.shouldBeRemoved = false;
						} else {
							node = try main.globalAllocator.create(ChunkMeshNode);
							node.?.mesh = chunk.meshing.ChunkMesh.init(main.globalAllocator, pos);
							node.?.shouldBeRemoved = true; // Might be removed in the next iteration.
							try meshRequests.append(pos);
						}
						node.?.drawableChildren = 0;
						newList[@intCast(index)] = node;
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
				storageListsSwap[lod] = oldList;
			}
			for(oldList) |nullMesh| {
				if(nullMesh) |mesh| {
					if(mesh.shouldBeRemoved) {
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
		}

		// Does occlusion using a breadth-first search that caches an on-screen visibility rectangle.

		const OcclusionData = struct {
			node: *ChunkMeshNode,
			distance: f64,

			pub fn compare(_: void, a: @This(), b: @This()) std.math.Order {
				if(a.distance < b.distance) return .lt;
				if(a.distance > b.distance) return .gt;
				return .eq;
			}
		};

		// TODO: Is there a way to combine this with minecraft's approach?
		var searchList = std.PriorityQueue(OcclusionData, void, OcclusionData.compare).init(main.threadAllocator, {});
		defer searchList.deinit();
		{
			var firstPos = chunk.ChunkPosition{
				.wx = @intFromFloat(@floor(playerPos[0])),
				.wy = @intFromFloat(@floor(playerPos[1])),
				.wz = @intFromFloat(@floor(playerPos[2])),
				.voxelSize = 1,
			};
			firstPos.wx &= ~@as(i32, chunk.chunkMask);
			firstPos.wy &= ~@as(i32, chunk.chunkMask);
			firstPos.wz &= ~@as(i32, chunk.chunkMask);
			var lod: u3 = 0;
			while(lod <= settings.highestLOD) : (lod += 1) {
				if(getNodeFromRenderThread(firstPos)) |node| if(node.mesh.generated) {
					node.lod = lod;
					node.min = @splat(-1);
					node.max = @splat(1);
					node.active = true;
					try searchList.add(.{
						.node = node,
						.distance = 0,
					});
					break;
				};
				firstPos.wx &= ~@as(i32, firstPos.voxelSize*chunk.chunkSize);
				firstPos.wy &= ~@as(i32, firstPos.voxelSize*chunk.chunkSize);
				firstPos.wz &= ~@as(i32, firstPos.voxelSize*chunk.chunkSize);
				firstPos.voxelSize *= 2;
			}
		}
		const projRotMat = game.projectionMatrix.mul(game.camera.viewMatrix);
		while(searchList.removeOrNull()) |data| {
			data.node.active = false;
			const mesh = &data.node.mesh;
			if(data.node.lod+1 != storageLists.len) {
				if(getNodeFromRenderThread(.{.wx=mesh.pos.wx, .wy=mesh.pos.wy, .wz=mesh.pos.wz, .voxelSize=mesh.pos.voxelSize << 1})) |parent| {
					const sizeShift = chunk.chunkShift + data.node.lod;
					const octantIndex: u3 = @intCast((mesh.pos.wx>>sizeShift & 1) | (mesh.pos.wy>>sizeShift & 1)<<1 | (mesh.pos.wz>>sizeShift & 1)<<2);
					parent.mesh.visibilityMask &= ~(@as(u8, 1) << octantIndex);
				}
			}
			try meshList.append(mesh);
			const relPos: Vec3d = vec.floatFromInt(f64, Vec3i{mesh.pos.wx, mesh.pos.wy, mesh.pos.wz}) - playerPos;
			const relPosFloat: Vec3f = vec.floatCast(f32, relPos);
			for(chunk.Neighbors.iterable) |neighbor| continueNeighborLoop: {
				const component = chunk.Neighbors.extractDirectionComponent(neighbor, relPos);
				if(chunk.Neighbors.isPositive[neighbor] and component + @as(f64, @floatFromInt(chunk.chunkSize*mesh.pos.voxelSize)) <= 0) continue;
				if(!chunk.Neighbors.isPositive[neighbor] and component >= 0) continue;
				if(@reduce(.Or, @min(mesh.chunkBorders[neighbor].min, mesh.chunkBorders[neighbor].max) != mesh.chunkBorders[neighbor].min)) continue; // There was not a single block in the chunk. TODO: Find a better solution.
				const minVec = vec.floatFromInt(f32, mesh.chunkBorders[neighbor].min*@as(Vec3i, @splat(mesh.pos.voxelSize)));
				const maxVec = vec.floatFromInt(f32, mesh.chunkBorders[neighbor].max*@as(Vec3i, @splat(mesh.pos.voxelSize)));
				var xyMin: Vec2f = .{10, 10};
				var xyMax: Vec2f = .{-10, -10};
				var numberOfNegatives: u8 = 0;
				var corners: [5]Vec4f = undefined;
				var curCorner: usize = 0;
				for(0..2) |a| {
					for(0..2) |b| {
						var cornerVector: Vec3f = undefined;
						switch(chunk.Neighbors.vectorComponent[neighbor]) {
							.x => {
								cornerVector[0] = minVec[0];
								cornerVector[1] = if(a == 0) minVec[1] else maxVec[1];
								cornerVector[2] = if(b == 0) minVec[2] else maxVec[2];
							},
							.y => {
								cornerVector[1] = minVec[1];
								cornerVector[0] = if(a == 0) minVec[0] else maxVec[0];
								cornerVector[2] = if(b == 0) minVec[2] else maxVec[2];
							},
							.z => {
								cornerVector[2] = minVec[2];
								cornerVector[0] = if(a == 0) minVec[0] else maxVec[0];
								cornerVector[1] = if(b == 0) minVec[1] else maxVec[1];
							},
						}
						corners[curCorner] = projRotMat.mulVec(vec.combine(relPosFloat + cornerVector, 1));
						if(corners[curCorner][3] < 0) {
							numberOfNegatives += 1;
						}
						curCorner += 1;
					}
				}
				switch(numberOfNegatives) { // Oh, so complicated. But this should only trigger very close to the player.
					4 => continue,
					0 => {},
					1 => {
						// Needs to duplicate the problematic corner and move it onto the projected plane.
						var problematicOne: usize = 0;
						for(0..curCorner) |i| {
							if(corners[i][3] < 0) {
								problematicOne = i;
								break;
							}
						}
						const problematicVector = corners[problematicOne];
						// The two neighbors of the quad:
						const neighborA = corners[problematicOne ^ 1];
						const neighborB = corners[problematicOne ^ 2];
						// Move the problematic point towards the neighbor:
						const one: Vec4f = @splat(1);
						const weightA: Vec4f = @splat(problematicVector[3]/(problematicVector[3] - neighborA[3]));
						var towardsA = neighborA*weightA + problematicVector*(one - weightA);
						towardsA[3] = 0; // Prevent inaccuracies
						const weightB: Vec4f = @splat(problematicVector[3]/(problematicVector[3] - neighborB[3]));
						var towardsB = neighborB*weightB + problematicVector*(one - weightB);
						towardsB[3] = 0; // Prevent inaccuracies
						corners[problematicOne] = towardsA;
						corners[curCorner] = towardsB;
						curCorner += 1;
					},
					2 => {
						// Needs to move the two problematic corners onto the projected plane.
						var problematicOne: usize = undefined;
						for(0..curCorner) |i| {
							if(corners[i][3] < 0) {
								problematicOne = i;
								break;
							}
						}
						const problematicVectorOne = corners[problematicOne];
						var problematicTwo: usize = undefined;
						for(problematicOne+1..curCorner) |i| {
							if(corners[i][3] < 0) {
								problematicTwo = i;
								break;
							}
						}
						const problematicVectorTwo = corners[problematicTwo];

						const commonDirection = problematicOne ^ problematicTwo;
						const projectionDirection = commonDirection ^ 0b11;
						// The respective neighbors:
						const neighborOne = corners[problematicOne ^ projectionDirection];
						const neighborTwo = corners[problematicTwo ^ projectionDirection];
						// Move the problematic points towards the neighbor:
						const one: Vec4f = @splat(1);
						const weightOne: Vec4f = @splat(problematicVectorOne[3]/(problematicVectorOne[3] - neighborOne[3]));
						var towardsOne = neighborOne*weightOne + problematicVectorOne*(one - weightOne);
						towardsOne[3] = 0; // Prevent inaccuracies
						corners[problematicOne] = towardsOne;

						const weightTwo: Vec4f = @splat(problematicVectorTwo[3]/(problematicVectorTwo[3] - neighborTwo[3]));
						var towardsTwo = neighborTwo*weightTwo + problematicVectorTwo*(one - weightTwo);
						towardsTwo[3] = 0; // Prevent inaccuracies
						corners[problematicTwo] = towardsTwo;
					},
					3 => {
						// Throw away the far problematic vector, move the other two onto the projection plane.
						var neighborIndex: usize = undefined;
						for(0..curCorner) |i| {
							if(corners[i][3] >= 0) {
								neighborIndex = i;
								break;
							}
						}
						const neighborVector = corners[neighborIndex];
						const problematicVectorOne = corners[neighborIndex ^ 1];
						const problematicVectorTwo = corners[neighborIndex ^ 2];
						// Move the problematic points towards the neighbor:
						const one: Vec4f = @splat(1);
						const weightOne: Vec4f = @splat(problematicVectorOne[3]/(problematicVectorOne[3] - neighborVector[3]));
						var towardsOne = neighborVector*weightOne + problematicVectorOne*(one - weightOne);
						towardsOne[3] = 0; // Prevent inaccuracies

						const weightTwo: Vec4f = @splat(problematicVectorTwo[3]/(problematicVectorTwo[3] - neighborVector[3]));
						var towardsTwo = neighborVector*weightTwo + problematicVectorTwo*(one - weightTwo);
						towardsTwo[3] = 0; // Prevent inaccuracies

						corners[0] = neighborVector;
						corners[1] = towardsOne;
						corners[2] = towardsTwo;
						curCorner = 3;
					},
					else => unreachable,
				}

				for(0..curCorner) |i| {
					const projected = corners[i];
					const xy = vec.xy(projected)/@as(Vec2f, @splat(@max(0, projected[3])));
					xyMin = @min(xyMin, xy);
					xyMax = @max(xyMax, xy);
				}
				const min = @max(xyMin, data.node.min);
				const max = @min(xyMax, data.node.max);
				if(@reduce(.Or, min >= max)) continue; // Nothing to render.
				var neighborPos = chunk.ChunkPosition{
					.wx = mesh.pos.wx + chunk.Neighbors.relX[neighbor]*chunk.chunkSize*mesh.pos.voxelSize,
					.wy = mesh.pos.wy + chunk.Neighbors.relY[neighbor]*chunk.chunkSize*mesh.pos.voxelSize,
					.wz = mesh.pos.wz + chunk.Neighbors.relZ[neighbor]*chunk.chunkSize*mesh.pos.voxelSize,
					.voxelSize = mesh.pos.voxelSize,
				};
				var lod: u3 = data.node.lod;
				while(lod <= settings.highestLOD) : (lod += 1) {
					if(getNodeFromRenderThread(neighborPos)) |node| if(node.mesh.generated) {
						if(node.active) {
							node.min = @min(node.min, min);
							node.max = @max(node.max, max);
						} else {
							node.lod = lod;
							node.min = min;
							node.max = max;
							node.active = true;
							try searchList.add(.{
								.node = node,
								.distance = node.mesh.pos.getMaxDistanceSquared(playerPos)
							});
						}
						break :continueNeighborLoop;
					};
					neighborPos.wx &= ~@as(i32, neighborPos.voxelSize*chunk.chunkSize);
					neighborPos.wy &= ~@as(i32, neighborPos.voxelSize*chunk.chunkSize);
					neighborPos.wz &= ~@as(i32, neighborPos.voxelSize*chunk.chunkSize);
					neighborPos.voxelSize *= 2;
				}
			}
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
		return meshList.items;
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
			.getPriority = @ptrCast(&getPriority),
			.isStillNeeded = @ptrCast(&isStillNeeded),
			.run = @ptrCast(&run),
			.clean = @ptrCast(&clean),
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
			if(self.mesh.pos.voxelSize != 1) maxRenderDistance = @intFromFloat(@ceil(@as(f32, @floatFromInt(maxRenderDistance))*settings.LODFactor));
			maxRenderDistance += 2*self.mesh.pos.voxelSize*chunk.chunkSize;
			return distanceSqr < @as(f64, @floatFromInt(maxRenderDistance*maxRenderDistance));
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
