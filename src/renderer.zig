const std = @import("std");
const Atomic = std.atomic.Value;

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
const vec = @import("vec.zig");
const gpu_performance_measuring = main.gui.windowlist.gpu_performance_measuring;
const crosshair = main.gui.windowlist.crosshair;
const Vec2f = vec.Vec2f;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const Vec4f = vec.Vec4f;
const Mat4f = vec.Mat4f;

pub const chunk_meshing = @import("renderer/chunk_meshing.zig");
pub const mesh_storage = @import("renderer/mesh_storage.zig");

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

pub fn init() void {
	deferredRenderPassShader = Shader.initAndGetUniforms("assets/cubyz/shaders/deferred_render_pass.vs", "assets/cubyz/shaders/deferred_render_pass.fs", "", &deferredUniforms);
	fakeReflectionShader = Shader.initAndGetUniforms("assets/cubyz/shaders/fake_reflection.vs", "assets/cubyz/shaders/fake_reflection.fs", "", &fakeReflectionUniforms);
	worldFrameBuffer.init(true, c.GL_NEAREST, c.GL_CLAMP_TO_EDGE);
	worldFrameBuffer.updateSize(Window.width, Window.height, c.GL_RGB16F);
	Bloom.init();
	MeshSelection.init();
	MenuBackGround.init() catch |err| {
		std.log.err("Failed to initialize the Menu Background: {s}", .{@errorName(err)});
	};
	chunk_meshing.init();
	mesh_storage.init();
	reflectionCubeMap = .init();
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
	mesh_storage.deinit();
	chunk_meshing.deinit();
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
	lastWidth = @intFromFloat(@as(f32, @floatFromInt(width))*main.settings.resolutionScale);
	lastHeight = @intFromFloat(@as(f32, @floatFromInt(height))*main.settings.resolutionScale);
	lastFov = fov;
	game.projectionMatrix = Mat4f.perspective(std.math.degreesToRadians(fov), @as(f32, @floatFromInt(lastWidth))/@as(f32, @floatFromInt(lastHeight)), zNear, zFar);
	worldFrameBuffer.updateSize(lastWidth, lastHeight, c.GL_RGB16F);
	worldFrameBuffer.unbind();
}

pub fn render(playerPosition: Vec3d) void {
	// TODO: player bobbing
	if(game.world) |world| {
		// TODO: Handle colors and sun position in the world.
		var ambient: Vec3f = undefined;
		ambient[0] = @max(0.1, world.ambientLight);
		ambient[1] = @max(0.1, world.ambientLight);
		ambient[2] = @max(0.1, world.ambientLight);
		const skyColor = vec.xyz(world.clearColor);
		game.fog.skyColor = skyColor;

		renderWorld(world, ambient, skyColor, playerPosition);
		const startTime = std.time.milliTimestamp();
		mesh_storage.updateMeshes(startTime + maximumMeshTime);
	} else {
		c.glViewport(0, 0, main.Window.width, main.Window.height);
		MenuBackGround.render();
	}
}

pub fn crosshairDirection(rotationMatrix: Mat4f, fovY: f32, width: u31, height: u31) Vec3f {
	// stolen code from Frustum.init
	const invRotationMatrix = rotationMatrix.transpose();
	const cameraDir = vec.xyz(invRotationMatrix.mulVec(Vec4f{0, 1, 0, 1}));
	const cameraUp = vec.xyz(invRotationMatrix.mulVec(Vec4f{0, 0, 1, 1}));
	const cameraRight = vec.xyz(invRotationMatrix.mulVec(Vec4f{1, 0, 0, 1}));

	const screenSize = Vec2f{@floatFromInt(width), @floatFromInt(height)};
	const screenCoord = (crosshair.window.pos + crosshair.window.contentSize*Vec2f{0.5, 0.5}*@as(Vec2f, @splat(crosshair.window.scale)))*@as(Vec2f, @splat(main.gui.scale*main.settings.resolutionScale));

	const halfVSide = std.math.tan(std.math.degreesToRadians(fovY)*0.5);
	const halfHSide = halfVSide*screenSize[0]/screenSize[1];
	const sides = Vec2f{halfHSide, halfVSide};

	const scale = (Vec2f{-1, 1} + Vec2f{2, -2} * screenCoord / screenSize) * sides;
	const forwards = cameraDir;
	const horizontal = cameraRight * @as(Vec3f, @splat(scale[0]));
	const vertical = cameraUp * @as(Vec3f, @splat(scale[1])); // adjust for y coordinate

	const adjusted = forwards + horizontal + vertical;
	return adjusted;
}

pub fn renderWorld(world: *World, ambientLight: Vec3f, skyColor: Vec3f, playerPos: Vec3d) void { // MARK: renderWorld()
	worldFrameBuffer.bind();
	c.glViewport(0, 0, lastWidth, lastHeight);
	gpu_performance_measuring.startQuery(.clear);
	worldFrameBuffer.clear(Vec4f{skyColor[0], skyColor[1], skyColor[2], 1});
	gpu_performance_measuring.stopQuery();
	game.camera.updateViewMatrix();

	// Uses FrustumCulling on the chunks.
	const frustum = Frustum.init(Vec3f{0, 0, 0}, game.camera.viewMatrix, lastFov, lastWidth, lastHeight);

	const time: u32 = @intCast(std.time.milliTimestamp() & std.math.maxInt(u32));

	gpu_performance_measuring.startQuery(.animation);
	blocks.meshes.preProcessAnimationData(time);
	gpu_performance_measuring.stopQuery();
	

	// Update the uniforms. The uniforms are needed to render the replacement meshes.
	chunk_meshing.bindShaderAndUniforms(game.projectionMatrix, ambientLight, playerPos);

	c.glActiveTexture(c.GL_TEXTURE0);
	blocks.meshes.blockTextureArray.bind();
	c.glActiveTexture(c.GL_TEXTURE1);
	blocks.meshes.emissionTextureArray.bind();
	c.glActiveTexture(c.GL_TEXTURE2);
	blocks.meshes.reflectivityAndAbsorptionTextureArray.bind();
	reflectionCubeMap.bindTo(4);

	chunk_meshing.quadsDrawn = 0;
	chunk_meshing.transparentQuadsDrawn = 0;
	const meshes = mesh_storage.updateAndGetRenderChunks(world.conn, &frustum, playerPos, settings.renderDistance);

	gpu_performance_measuring.startQuery(.chunk_rendering_preparation);
	const direction = crosshairDirection(game.camera.viewMatrix, lastFov, lastWidth, lastHeight);
	MeshSelection.select(playerPos, direction, game.Player.inventory.getItem(game.Player.selectedSlot));
	MeshSelection.render(game.projectionMatrix, game.camera.viewMatrix, playerPos);

	chunk_meshing.beginRender();

	var chunkList = main.List(u32).init(main.stackAllocator);
	defer chunkList.deinit();
	for(meshes) |mesh| {
		mesh.prepareRendering(&chunkList);
	}
	gpu_performance_measuring.stopQuery();
	if(chunkList.items.len != 0) {
		chunk_meshing.drawChunksIndirect(chunkList.items, game.projectionMatrix, ambientLight, playerPos, false);
	}

	gpu_performance_measuring.startQuery(.entity_rendering);
	entity.ClientEntityManager.render(game.projectionMatrix, ambientLight, .{1, 0.5, 0.25}, playerPos);

	itemdrop.ItemDropRenderer.renderItemDrops(game.projectionMatrix, ambientLight, playerPos, time);
	gpu_performance_measuring.stopQuery();

	// Render transparent chunk meshes:
	worldFrameBuffer.bindDepthTexture(c.GL_TEXTURE5);

	gpu_performance_measuring.startQuery(.transparent_rendering_preparation);
	c.glTextureBarrier();

	c.glBlendEquation(c.GL_FUNC_ADD);
	c.glBlendFunc(c.GL_ONE, c.GL_SRC1_COLOR);
	c.glDepthFunc(c.GL_LEQUAL);
	c.glDepthMask(c.GL_FALSE);
	{
		chunkList.clearRetainingCapacity();
		var i: usize = meshes.len;
		while(true) {
			if(i == 0) break;
			i -= 1;
			meshes[i].prepareTransparentRendering(playerPos, &chunkList);
		}
		gpu_performance_measuring.stopQuery();
		if(chunkList.items.len != 0) {
			chunk_meshing.drawChunksIndirect(chunkList.items, game.projectionMatrix, ambientLight, playerPos, true);
		}
	}
	c.glDepthMask(c.GL_TRUE);
	c.glDepthFunc(c.GL_LESS);
	c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
	chunk_meshing.endRender();

	worldFrameBuffer.bindTexture(c.GL_TEXTURE3);

	const playerBlock = mesh_storage.getBlockFromAnyLod(@intFromFloat(@floor(playerPos[0])), @intFromFloat(@floor(playerPos[1])), @intFromFloat(@floor(playerPos[2])));
	
	if(settings.bloom) {
		Bloom.render(lastWidth, lastHeight, playerBlock);
	} else {
		Bloom.bindReplacementImage();
	}
	gpu_performance_measuring.startQuery(.final_copy);
	if(activeFrameBuffer == 0) c.glViewport(0, 0, main.Window.width, main.Window.height);
	worldFrameBuffer.bindTexture(c.GL_TEXTURE3);
	worldFrameBuffer.bindDepthTexture(c.GL_TEXTURE4);
	worldFrameBuffer.unbind();
	deferredRenderPassShader.bind();
	c.glUniform1i(deferredUniforms.color, 3);
	c.glUniform1i(deferredUniforms.depthTexture, 4);
	if(!blocks.meshes.hasFog(playerBlock)) {
		c.glUniform3fv(deferredUniforms.@"fog.color", 1, @ptrCast(&game.fog.skyColor));
		c.glUniform1f(deferredUniforms.@"fog.density", game.fog.density);
	} else {
		const fogColor = blocks.meshes.fogColor(playerBlock);
		c.glUniform3f(deferredUniforms.@"fog.color", @as(f32, @floatFromInt(fogColor >> 16 & 255))/255.0, @as(f32, @floatFromInt(fogColor >> 8 & 255))/255.0, @as(f32, @floatFromInt(fogColor >> 0 & 255))/255.0);
		c.glUniform1f(deferredUniforms.@"fog.density", blocks.meshes.fogDensity(playerBlock));
	}
	c.glUniform1f(deferredUniforms.zNear, zNear);
	c.glUniform1f(deferredUniforms.zFar, zFar);
	c.glUniform2f(deferredUniforms.tanXY, 1.0/game.projectionMatrix.rows[0][0], 1.0/game.projectionMatrix.rows[1][2]);

	c.glBindFramebuffer(c.GL_FRAMEBUFFER, activeFrameBuffer);

	c.glBindVertexArray(graphics.draw.rectVAO);
	c.glDisable(c.GL_DEPTH_TEST);
	c.glDisable(c.GL_CULL_FACE);
	c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);

	c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

	entity.ClientEntityManager.renderNames(game.projectionMatrix, playerPos);
	gpu_performance_measuring.stopQuery();
}

const Bloom = struct { // MARK: Bloom
	var buffer1: graphics.FrameBuffer = undefined;
	var buffer2: graphics.FrameBuffer = undefined;
	var emptyBuffer: graphics.Texture = undefined;
	var width: u31 = std.math.maxInt(u31);
	var height: u31 = std.math.maxInt(u31);
	var firstPassShader: graphics.Shader = undefined;
	var secondPassShader: graphics.Shader = undefined;
	var colorExtractAndDownsampleShader: graphics.Shader = undefined;
	var colorExtractUniforms: struct {
		depthTexture: c_int,
		zNear: c_int,
		zFar: c_int,
		tanXY: c_int,
		@"fog.color": c_int,
		@"fog.density": c_int,
	} = undefined;

	pub fn init() void {
		buffer1.init(false, c.GL_LINEAR, c.GL_CLAMP_TO_EDGE);
		buffer2.init(false, c.GL_LINEAR, c.GL_CLAMP_TO_EDGE);
		emptyBuffer = .init();
		emptyBuffer.generate(graphics.Image.emptyImage);
		firstPassShader = graphics.Shader.init("assets/cubyz/shaders/bloom/first_pass.vs", "assets/cubyz/shaders/bloom/first_pass.fs", "");
		secondPassShader = graphics.Shader.init("assets/cubyz/shaders/bloom/second_pass.vs", "assets/cubyz/shaders/bloom/second_pass.fs", "");
		colorExtractAndDownsampleShader = graphics.Shader.initAndGetUniforms("assets/cubyz/shaders/bloom/color_extractor_downsample.vs", "assets/cubyz/shaders/bloom/color_extractor_downsample.fs", "", &colorExtractUniforms);
	}

	pub fn deinit() void {
		buffer1.deinit();
		buffer2.deinit();
		firstPassShader.deinit();
		secondPassShader.deinit();
	}

	fn extractImageDataAndDownsample(playerBlock: blocks.Block) void {
		colorExtractAndDownsampleShader.bind();
		worldFrameBuffer.bindTexture(c.GL_TEXTURE3);
		worldFrameBuffer.bindDepthTexture(c.GL_TEXTURE4);
		buffer1.bind();
		c.glUniform1i(colorExtractUniforms.depthTexture, 4);
		if(!blocks.meshes.hasFog(playerBlock)) {
			c.glUniform3fv(colorExtractUniforms.@"fog.color", 1, @ptrCast(&game.fog.skyColor));
			c.glUniform1f(colorExtractUniforms.@"fog.density", game.fog.density);
		} else {
			const fogColor = blocks.meshes.fogColor(playerBlock);
			c.glUniform3f(colorExtractUniforms.@"fog.color", @as(f32, @floatFromInt(fogColor >> 16 & 255))/255.0, @as(f32, @floatFromInt(fogColor >> 8 & 255))/255.0, @as(f32, @floatFromInt(fogColor >> 0 & 255))/255.0);
			c.glUniform1f(colorExtractUniforms.@"fog.density", blocks.meshes.fogDensity(playerBlock));
		}
		c.glUniform1f(colorExtractUniforms.zNear, zNear);
		c.glUniform1f(colorExtractUniforms.zFar, zFar);
		c.glUniform2f(colorExtractUniforms.tanXY, 1.0/game.projectionMatrix.rows[0][0], 1.0/game.projectionMatrix.rows[1][2]);
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

	fn render(currentWidth: u31, currentHeight: u31, playerBlock: blocks.Block) void {
		if(width != currentWidth or height != currentHeight) {
			width = currentWidth;
			height = currentHeight;
			buffer1.updateSize(width/4, height/4, c.GL_R11F_G11F_B10F);
			std.debug.assert(buffer1.validate());
			buffer2.updateSize(width/4, height/4, c.GL_R11F_G11F_B10F);
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

		c.glViewport(0, 0, width, height);
		buffer1.bindTexture(c.GL_TEXTURE5);

		c.glDepthMask(c.GL_TRUE);
		c.glEnable(c.GL_DEPTH_TEST);
		c.glEnable(c.GL_CULL_FACE);
		c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
		gpu_performance_measuring.stopQuery();
	}

	fn bindReplacementImage() void {
		emptyBuffer.bindTo(5);
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
		shader = Shader.initAndGetUniforms("assets/cubyz/shaders/background/vertex.vs", "assets/cubyz/shaders/background/fragment.fs", "", &uniforms);
		shader.bind();
		c.glUniform1i(uniforms.image, 0);
		// 4 sides of a simple cube with some panorama texture on it.
		const rawData = [_]f32 {
			-1, 1, -1, 1, 1,
			-1, 1, 1, 1, 0,
			-1, -1, -1, 0.75, 1,
			-1, -1, 1, 0.75, 0,
			1, -1, -1, 0.5, 1,
			1, -1, 1, 0.5, 0,
			1, 1, -1, 0.25, 1,
			1, 1, 1, 0.25, 0,
			-1, 1, -1, 0, 1,
			-1, 1, 1, 0, 0,
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
		texture = .{.textureID = 0};
		var dir = try std.fs.cwd().makeOpenPath("assets/backgrounds", .{.iterate = true});
		defer dir.close();

		var walker = try dir.walk(main.stackAllocator.allocator);
		defer walker.deinit();
		var fileList = main.List([]const u8).init(main.stackAllocator);
		defer {
			for(fileList.items) |fileName| {
				main.stackAllocator.free(fileName);
			}
			fileList.deinit();
		}

		while(try walker.next()) |entry| {
			if(entry.kind == .file and std.ascii.endsWithIgnoreCase(entry.basename, ".png")) {
				fileList.append(main.stackAllocator.dupe(u8, entry.path));
			}
		}
		if(fileList.items.len == 0) {
			std.log.warn("Couldn't find any background scene images in \"assets/backgrounds\".", .{});
			return;
		}
		const theChosenOne = main.random.nextIntBounded(u32, &main.seed, @as(u32, @intCast(fileList.items.len)));
		const theChosenPath = std.fmt.allocPrint(main.stackAllocator.allocator, "assets/backgrounds/{s}", .{fileList.items[theChosenOne]}) catch unreachable;
		defer main.stackAllocator.free(theChosenPath);
		texture = graphics.Texture.initFromFile(theChosenPath);
	}

	pub fn deinit() void {
		shader.deinit();
		c.glDeleteVertexArrays(1, &vao);
		c.glDeleteBuffers(2, &vbos);
	}

	pub fn hasImage() bool {
		return texture.textureID != 0;
	}

	pub fn render() void {
		if(texture.textureID == 0) return;
		c.glDisable(c.GL_CULL_FACE); // I'm not sure if my triangles are rotated correctly, and there are no triangles facing away from the player anyways.

		// Use a simple rotation around the z axis, with a steadily increasing angle.
		const newTime = std.time.nanoTimestamp();
		angle += @as(f32, @floatFromInt(newTime - lastTime))/2e10;
		lastTime = newTime;
		const viewMatrix = Mat4f.rotationZ(angle);
		shader.bind();
		updateViewport(main.Window.width, main.Window.height, 70.0);

		c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_TRUE, @ptrCast(&viewMatrix));
		c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&game.projectionMatrix));

		texture.bindTo(0);

		c.glBindVertexArray(vao);
		c.glDrawElements(c.GL_TRIANGLES, 24, c.GL_UNSIGNED_INT, null);
	}

	pub fn takeBackgroundImage() void {
		const size: usize = 1024; // Use a power of 2 here, to reduce video memory waste.
		const pixels: []u32 = main.stackAllocator.alloc(u32, size*size);
		defer main.stackAllocator.free(pixels);

		// Change the viewport and the matrices to render 4 cube faces:

		const oldResolutionScale = main.settings.resolutionScale;
		main.settings.resolutionScale = 1;
		updateViewport(size, size, 90.0);
		main.settings.resolutionScale = oldResolutionScale;
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
		const image = graphics.Image.init(main.stackAllocator, 4*size, size);
		defer image.deinit(main.stackAllocator);

		for(0..4) |i| {
			c.glEnable(c.GL_CULL_FACE);
			c.glEnable(c.GL_DEPTH_TEST);
			game.camera.rotation = .{0, 0, angles[i]};
			// Draw to frame buffer.
			buffer.bind();
			c.glClear(c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT | c.GL_COLOR_BUFFER_BIT);
			main.renderer.render(game.Player.getEyePosBlocking());
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

		const fileName = std.fmt.allocPrint(main.stackAllocator.allocator, "assets/backgrounds/{s}_{}.png", .{game.world.?.name, game.world.?.gameTime.load(.monotonic)}) catch unreachable;
		defer main.stackAllocator.free(fileName);
		image.exportToFile(fileName) catch |err| {
			std.log.err("Cannot write file {s} due to {s}", .{fileName, @errorName(err)});
		};
		// TODO: Performance is terrible even with -O3. Consider using qoi instead.
	}
};

pub const Frustum = struct { // MARK: Frustum
	const Plane = struct {
		pos: Vec3f,
		norm: Vec3f,
	};
	planes: [4]Plane, // Who cares about the near/far plane anyways?

	pub fn init(cameraPos: Vec3f, rotationMatrix: Mat4f, fovY: f32, width: u31, height: u31) Frustum {
		const invRotationMatrix = rotationMatrix.transpose();
		const cameraDir = vec.xyz(invRotationMatrix.mulVec(Vec4f{0, 1, 0, 1}));
		const cameraUp = vec.xyz(invRotationMatrix.mulVec(Vec4f{0, 0, 1, 1}));
		const cameraRight = vec.xyz(invRotationMatrix.mulVec(Vec4f{1, 0, 0, 1}));

		const halfVSide = std.math.tan(std.math.degreesToRadians(fovY)*0.5);
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
			dist += @reduce(.Add, @max(Vec3f{0, 0, 0}, dim*plane.norm));
			if(dist < 0) return false;
		}
		return true;
	}
};

pub const MeshSelection = struct { // MARK: MeshSelection
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

	pub fn init() void {
		shader = Shader.initAndGetUniforms("assets/cubyz/shaders/block_selection_vertex.vs", "assets/cubyz/shaders/block_selection_fragment.fs", "", &uniforms);

		const rawData = [_]f32 {
			0, 0, 0,
			0, 0, 1,
			0, 1, 0,
			0, 1, 1,
			1, 0, 0,
			1, 0, 1,
			1, 1, 0,
			1, 1, 1,
		};
		const indices = [_]u8 {
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
	pub var selectedBlockPos: ?Vec3i = null;
	var selectionMin: Vec3f = undefined;
	var selectionMax: Vec3f = undefined;
	var lastPos: Vec3d = undefined;
	var lastDir: Vec3f = undefined;
	pub fn select(pos: Vec3d, _dir: Vec3f, item: ?main.items.Item) void {
		lastPos = pos;
		const dir: Vec3d = @floatCast(_dir);
		lastDir = _dir;

		// Test blocks:
		const closestDistance: f64 = 6.0; // selection now limited
		// Implementation of "A Fast Voxel Traversal Algorithm for Ray Tracing"  http://www.cse.yorku.ca/~amana/research/grid.pdf
		const step: Vec3i = @intFromFloat(std.math.sign(dir));
		const invDir = @as(Vec3d, @splat(1))/dir;
		const tDelta = @abs(invDir);
		var tMax = (@floor(pos) - pos)*invDir;
		tMax = @max(tMax, tMax + tDelta*@as(Vec3f, @floatFromInt(step)));
		tMax = @select(f64, dir == @as(Vec3d, @splat(0)), @as(Vec3d, @splat(std.math.inf(f64))), tMax);
		var voxelPos: Vec3i = @intFromFloat(@floor(pos));

		var total_tMax: f64 = 0;

		selectedBlockPos = null;

		while(total_tMax < closestDistance) {
			const block = mesh_storage.getBlock(voxelPos[0], voxelPos[1], voxelPos[2]) orelse break;
			if(block.typ != 0) {
				if(block.blockClass() != .fluid and block.blockClass() != .air) { // TODO: Buckets could select fluids
					const relativePlayerPos: Vec3f = @floatCast(pos - @as(Vec3d, @floatFromInt(voxelPos)));
					if(block.mode().rayIntersection(block, item, relativePlayerPos, _dir)) |intersection| {
						if(intersection.distance <= closestDistance) {
							selectedBlockPos = voxelPos;
							selectionMin = intersection.min;
							selectionMax = intersection.max;
							break;
						}
					}
				}
			}
			posBeforeBlock = voxelPos;
			if(tMax[0] < tMax[1]) {
				if(tMax[0] < tMax[2]) {
					voxelPos[0] +%= step[0];
					total_tMax = tMax[0];
					tMax[0] += tDelta[0];
				} else {
					voxelPos[2] +%= step[2];
					total_tMax = tMax[2];
					tMax[2] += tDelta[2];
				}
			} else {
				if(tMax[1] < tMax[2]) {
					voxelPos[1] +%= step[1];
					total_tMax = tMax[1];
					tMax[1] += tDelta[1];
				} else {
					voxelPos[2] +%= step[2];
					total_tMax = tMax[2];
					tMax[2] += tDelta[2];
				}
			}
		}
		// TODO: Test entities
	}

	fn canPlaceBlock(pos: Vec3i, block: main.blocks.Block) bool {
		if(main.game.collision.collideWithBlock(block, pos[0], pos[1], pos[2], main.game.Player.getPosBlocking() + main.game.Player.outerBoundingBox.center(), main.game.Player.outerBoundingBox.extent() - @as(Vec3d, @splat(0.00005)), .{0, 0, 0}) != null) {
			return false;
		}
		return true; // TODO: Check other entities
	}

	pub fn placeBlock(inventory: main.items.Inventory, slot: u32) void {
		if(selectedBlockPos) |selectedPos| {
			var oldBlock = mesh_storage.getBlock(selectedPos[0], selectedPos[1], selectedPos[2]) orelse return;
			var block = oldBlock;
			if(inventory.getItem(slot)) |item| {
				switch(item) {
					.baseItem => |baseItem| {
						if(baseItem.block) |itemBlock| {
							const rotationMode = blocks.Block.mode(.{.typ = itemBlock, .data = 0});
							var neighborDir = Vec3i{0, 0, 0};
							// Check if stuff can be added to the block itself:
							if(itemBlock == block.typ) {
								const relPos: Vec3f = @floatCast(lastPos - @as(Vec3d, @floatFromInt(selectedPos)));
								if(rotationMode.generateData(main.game.world.?, selectedPos, relPos, lastDir, neighborDir, &block, .{.typ = 0, .data = 0}, false)) {
									if(!canPlaceBlock(selectedPos, block)) return;
									updateBlockAndSendUpdate(inventory, slot, selectedPos[0], selectedPos[1], selectedPos[2], oldBlock, block);
									return;
								}
							}
							// Check the block in front of it:
							const neighborPos = posBeforeBlock;
							neighborDir = selectedPos - posBeforeBlock;
							const relPos: Vec3f = @floatCast(lastPos - @as(Vec3d, @floatFromInt(neighborPos)));
							const neighborBlock = block;
							oldBlock = mesh_storage.getBlock(neighborPos[0], neighborPos[1], neighborPos[2]) orelse return;
							block = oldBlock;
							if(block.typ == itemBlock) {
								if(rotationMode.generateData(main.game.world.?, neighborPos, relPos, lastDir, neighborDir, &block, neighborBlock, false)) {
									if(!canPlaceBlock(neighborPos, block)) return;
									updateBlockAndSendUpdate(inventory, slot, neighborPos[0], neighborPos[1], neighborPos[2], oldBlock, block);
									return;
								}
							} else {
								if(block.solid()) return;
								block.typ = itemBlock;
								block.data = 0;
								if(rotationMode.generateData(main.game.world.?, neighborPos, relPos, lastDir, neighborDir, &block, neighborBlock, true)) {
									if(!canPlaceBlock(neighborPos, block)) return;
									updateBlockAndSendUpdate(inventory, slot, neighborPos[0], neighborPos[1], neighborPos[2], oldBlock, block);
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

	pub fn breakBlock(inventory: main.items.Inventory, slot: u32) void {
		if(selectedBlockPos) |selectedPos| {
			const block = mesh_storage.getBlock(selectedPos[0], selectedPos[1], selectedPos[2]) orelse return;
			var newBlock = block;
			// TODO: Breaking animation and tools.
			const relPos: Vec3f = @floatCast(lastPos - @as(Vec3d, @floatFromInt(selectedPos)));
			main.items.Inventory.Sync.ClientSide.mutex.lock();
			block.mode().onBlockBreaking(inventory.getStack(slot).item, relPos, lastDir, &newBlock);
			main.items.Inventory.Sync.ClientSide.mutex.unlock();
			if(!std.meta.eql(newBlock, block)) {
				updateBlockAndSendUpdate(inventory, slot, selectedPos[0], selectedPos[1], selectedPos[2], block, newBlock);
			}
		}
	}

	fn updateBlockAndSendUpdate(source: main.items.Inventory, slot: u32, x: i32, y: i32, z: i32, oldBlock: blocks.Block, newBlock: blocks.Block) void {
		main.items.Inventory.Sync.ClientSide.executeCommand(.{.updateBlock = .{.source = .{.inv = source, .slot = slot}, .pos = .{x, y, z}, .oldBlock = oldBlock, .newBlock = newBlock}});
		mesh_storage.updateBlock(x, y, z, newBlock);
	}

	pub fn drawCube(projectionMatrix: Mat4f, viewMatrix: Mat4f, relativePositionToPlayer: Vec3d, min: Vec3f, max: Vec3f) void {
		shader.bind();

		c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&projectionMatrix));
		c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_TRUE, @ptrCast(&viewMatrix));

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
		if(main.gui.hideGui) return;
		if(selectedBlockPos) |_selectedBlockPos| {
			c.glEnable(c.GL_POLYGON_OFFSET_LINE);
			defer c.glDisable(c.GL_POLYGON_OFFSET_LINE);
			c.glPolygonOffset(-2, 0);
			drawCube(projectionMatrix, viewMatrix, @as(Vec3d, @floatFromInt(_selectedBlockPos)) - playerPos, selectionMin, selectionMax);
		}
	}
};
