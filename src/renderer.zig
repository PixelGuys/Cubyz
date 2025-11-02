const std = @import("std");
const Atomic = std.atomic.Value;

const blocks = @import("blocks.zig");
const chunk = @import("chunk.zig");
const entity = @import("entity.zig");
const graphics = @import("graphics.zig");
const particles = @import("particles.zig");
const c = graphics.c;
const game = @import("game.zig");
const World = game.World;
const itemdrop = @import("itemdrop.zig");
const main = @import("main");
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

var deferredRenderPassPipeline: graphics.Pipeline = undefined;
var deferredUniforms: struct {
	@"fog.color": c_int,
	@"fog.density": c_int,
	@"fog.fogLower": c_int,
	@"fog.fogHigher": c_int,
	tanXY: c_int,
	zNear: c_int,
	zFar: c_int,
	invViewMatrix: c_int,
	playerPositionInteger: c_int,
	playerPositionFraction: c_int,
} = undefined;
var fakeReflectionPipeline: graphics.Pipeline = undefined;
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
	deferredRenderPassPipeline = graphics.Pipeline.init(
		"assets/cubyz/shaders/deferred_render_pass.vert",
		"assets/cubyz/shaders/deferred_render_pass.frag",
		"",
		&deferredUniforms,
		.{.cullMode = .none},
		.{.depthTest = false, .depthWrite = false},
		.{.attachments = &.{.noBlending}},
	);
	fakeReflectionPipeline = graphics.Pipeline.init(
		"assets/cubyz/shaders/fake_reflection.vert",
		"assets/cubyz/shaders/fake_reflection.frag",
		"",
		&fakeReflectionUniforms,
		.{.cullMode = .none},
		.{.depthTest = false, .depthWrite = false},
		.{.attachments = &.{.noBlending}},
	);
	worldFrameBuffer.init(true, c.GL_NEAREST, c.GL_CLAMP_TO_EDGE);
	worldFrameBuffer.updateSize(Window.width, Window.height, c.GL_RGB16F);
	Bloom.init();
	MeshSelection.init();
	MenuBackGround.init();
	Skybox.init();
	chunk_meshing.init();
	mesh_storage.init();
	reflectionCubeMap = .init();
	reflectionCubeMap.generate(reflectionCubeMapSize, reflectionCubeMapSize);
	initReflectionCubeMap();
}

pub fn deinit() void {
	deferredRenderPassPipeline.deinit();
	fakeReflectionPipeline.deinit();
	worldFrameBuffer.deinit();
	Bloom.deinit();
	MeshSelection.deinit();
	MenuBackGround.deinit();
	Skybox.deinit();
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
	fakeReflectionPipeline.bind(null);
	c.glUniform1f(fakeReflectionUniforms.frequency, 1);
	c.glUniform1f(fakeReflectionUniforms.reflectionMapSize, reflectionCubeMapSize);
	for(0..6) |face| {
		c.glUniform3fv(fakeReflectionUniforms.normalVector, 1, @ptrCast(&graphics.CubeMapTexture.faceNormal(face)));
		c.glUniform3fv(fakeReflectionUniforms.upVector, 1, @ptrCast(&graphics.CubeMapTexture.faceUp(face)));
		c.glUniform3fv(fakeReflectionUniforms.rightVector, 1, @ptrCast(&graphics.CubeMapTexture.faceRight(face)));
		reflectionCubeMap.bindToFramebuffer(framebuffer, @intCast(face));
		c.glBindVertexArray(graphics.draw.rectVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}
}

var worldFrameBuffer: graphics.FrameBuffer = undefined;

pub var lastWidth: u31 = 0;
pub var lastHeight: u31 = 0;
var lastFov: f32 = 0;
pub fn updateFov(fov: f32) void {
	if(lastFov != fov) {
		lastFov = fov;
		game.projectionMatrix = Mat4f.perspective(std.math.degreesToRadians(fov), @as(f32, @floatFromInt(lastWidth))/@as(f32, @floatFromInt(lastHeight)), zNear, zFar);
	}
}
pub fn updateViewport(width: u31, height: u31) void {
	lastWidth = @intFromFloat(@as(f32, @floatFromInt(width))*main.settings.resolutionScale);
	lastHeight = @intFromFloat(@as(f32, @floatFromInt(height))*main.settings.resolutionScale);
	worldFrameBuffer.updateSize(lastWidth, lastHeight, c.GL_RGB16F);
	worldFrameBuffer.unbind();
}

pub fn render(playerPosition: Vec3d, deltaTime: f64) void {
	// TODO: player bobbing
	// TODO: Handle colors and sun position in the world.
	std.debug.assert(game.world != null);
	var ambient: Vec3f = undefined;
	ambient[0] = @max(0.1, game.world.?.ambientLight);
	ambient[1] = @max(0.1, game.world.?.ambientLight);
	ambient[2] = @max(0.1, game.world.?.ambientLight);

	itemdrop.ItemDisplayManager.update(deltaTime);
	renderWorld(game.world.?, ambient, game.fog.skyColor, playerPosition);
	const startTime = std.time.milliTimestamp();
	mesh_storage.updateMeshes(startTime + maximumMeshTime);
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

	const scale = (Vec2f{-1, 1} + Vec2f{2, -2}*screenCoord/screenSize)*sides;
	const forwards = cameraDir;
	const horizontal = cameraRight*@as(Vec3f, @splat(scale[0]));
	const vertical = cameraUp*@as(Vec3f, @splat(scale[1])); // adjust for y coordinate

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

	gpu_performance_measuring.startQuery(.skybox);
	Skybox.render();
	gpu_performance_measuring.stopQuery();

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
	c.glActiveTexture(c.GL_TEXTURE5);
	blocks.meshes.ditherTexture.bind();
	reflectionCubeMap.bindTo(4);

	chunk_meshing.quadsDrawn = 0;
	chunk_meshing.transparentQuadsDrawn = 0;
	const meshes = mesh_storage.updateAndGetRenderChunks(world.conn, &frustum, playerPos, settings.renderDistance);

	gpu_performance_measuring.startQuery(.chunk_rendering_preparation);
	const direction = crosshairDirection(game.camera.viewMatrix, lastFov, lastWidth, lastHeight);
	MeshSelection.select(playerPos, direction, game.Player.inventory.getItem(game.Player.selectedSlot));

	chunk_meshing.beginRender();

	var chunkLists: [main.settings.highestSupportedLod + 1]main.List(u32) = @splat(main.List(u32).init(main.stackAllocator));
	defer for(chunkLists) |list| list.deinit();
	for(meshes) |mesh| {
		mesh.prepareRendering(&chunkLists);
	}
	gpu_performance_measuring.stopQuery();
	gpu_performance_measuring.startQuery(.chunk_rendering);
	chunk_meshing.drawChunksIndirect(&chunkLists, game.projectionMatrix, ambientLight, playerPos, false);
	gpu_performance_measuring.stopQuery();

	gpu_performance_measuring.startQuery(.entity_rendering);
	entity.ClientEntityManager.render(game.projectionMatrix, ambientLight, playerPos);

	itemdrop.ItemDropRenderer.renderItemDrops(game.projectionMatrix, ambientLight, playerPos);
	gpu_performance_measuring.stopQuery();

	gpu_performance_measuring.startQuery(.block_entity_rendering);
	main.block_entity.renderAll(game.projectionMatrix, ambientLight, playerPos);
	gpu_performance_measuring.stopQuery();

	gpu_performance_measuring.startQuery(.particle_rendering);
	particles.ParticleSystem.render(game.projectionMatrix, game.camera.viewMatrix, ambientLight);
	gpu_performance_measuring.stopQuery();

	// Rebind block textures back to their original slots
	c.glActiveTexture(c.GL_TEXTURE0);
	blocks.meshes.blockTextureArray.bind();
	c.glActiveTexture(c.GL_TEXTURE1);
	blocks.meshes.emissionTextureArray.bind();

	MeshSelection.render(game.projectionMatrix, game.camera.viewMatrix, playerPos);

	// Render transparent chunk meshes:
	worldFrameBuffer.bindDepthTexture(c.GL_TEXTURE5);

	gpu_performance_measuring.startQuery(.transparent_rendering_preparation);
	c.glTextureBarrier();

	{
		for(&chunkLists) |*list| list.clearRetainingCapacity();
		var i: usize = meshes.len;
		while(true) {
			if(i == 0) break;
			i -= 1;
			meshes[i].prepareTransparentRendering(playerPos, &chunkLists);
		}
		gpu_performance_measuring.stopQuery();
		gpu_performance_measuring.startQuery(.transparent_rendering);
		chunk_meshing.drawChunksIndirect(&chunkLists, game.projectionMatrix, ambientLight, playerPos, true);
		gpu_performance_measuring.stopQuery();
	}

	c.glDepthRange(0, 0.001);
	itemdrop.ItemDropRenderer.renderDisplayItems(ambientLight, playerPos);
	c.glDepthRange(0.001, 1);

	chunk_meshing.endRender();

	worldFrameBuffer.bindTexture(c.GL_TEXTURE3);

	const playerBlock = mesh_storage.getBlockFromAnyLodFromRenderThread(@intFromFloat(@floor(playerPos[0])), @intFromFloat(@floor(playerPos[1])), @intFromFloat(@floor(playerPos[2])));

	if(settings.bloom) {
		Bloom.render(lastWidth, lastHeight, playerBlock, playerPos, game.camera.viewMatrix);
	} else {
		Bloom.bindReplacementImage();
	}
	gpu_performance_measuring.startQuery(.final_copy);
	if(activeFrameBuffer == 0) c.glViewport(0, 0, main.Window.width, main.Window.height);
	worldFrameBuffer.bindTexture(c.GL_TEXTURE3);
	worldFrameBuffer.bindDepthTexture(c.GL_TEXTURE4);
	worldFrameBuffer.unbind();
	deferredRenderPassPipeline.bind(null);
	if(!blocks.meshes.hasFog(playerBlock)) {
		c.glUniform3fv(deferredUniforms.@"fog.color", 1, @ptrCast(&game.fog.fogColor));
		c.glUniform1f(deferredUniforms.@"fog.density", game.fog.density);
		c.glUniform1f(deferredUniforms.@"fog.fogLower", game.fog.fogLower);
		c.glUniform1f(deferredUniforms.@"fog.fogHigher", game.fog.fogHigher);
	} else {
		const fogColor = blocks.meshes.fogColor(playerBlock);
		c.glUniform3f(deferredUniforms.@"fog.color", @as(f32, @floatFromInt(fogColor >> 16 & 255))/255.0, @as(f32, @floatFromInt(fogColor >> 8 & 255))/255.0, @as(f32, @floatFromInt(fogColor >> 0 & 255))/255.0);
		c.glUniform1f(deferredUniforms.@"fog.density", blocks.meshes.fogDensity(playerBlock));
		c.glUniform1f(deferredUniforms.@"fog.fogLower", 1e10);
		c.glUniform1f(deferredUniforms.@"fog.fogHigher", 1e10);
	}
	c.glUniformMatrix4fv(deferredUniforms.invViewMatrix, 1, c.GL_TRUE, @ptrCast(&game.camera.viewMatrix.transpose()));
	c.glUniform3i(deferredUniforms.playerPositionInteger, @intFromFloat(@floor(playerPos[0])), @intFromFloat(@floor(playerPos[1])), @intFromFloat(@floor(playerPos[2])));
	c.glUniform3f(deferredUniforms.playerPositionFraction, @floatCast(@mod(playerPos[0], 1)), @floatCast(@mod(playerPos[1], 1)), @floatCast(@mod(playerPos[2], 1)));
	c.glUniform1f(deferredUniforms.zNear, zNear);
	c.glUniform1f(deferredUniforms.zFar, zFar);
	c.glUniform2f(deferredUniforms.tanXY, 1.0/game.projectionMatrix.rows[0][0], 1.0/game.projectionMatrix.rows[1][2]);

	c.glBindFramebuffer(c.GL_FRAMEBUFFER, activeFrameBuffer);

	c.glBindVertexArray(graphics.draw.rectVAO);
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
	var firstPassPipeline: graphics.Pipeline = undefined;
	var secondPassPipeline: graphics.Pipeline = undefined;
	var colorExtractAndDownsamplePipeline: graphics.Pipeline = undefined;
	var colorExtractUniforms: struct {
		zNear: c_int,
		zFar: c_int,
		tanXY: c_int,
		@"fog.color": c_int,
		@"fog.density": c_int,
		@"fog.fogLower": c_int,
		@"fog.fogHigher": c_int,
		invViewMatrix: c_int,
		playerPositionInteger: c_int,
		playerPositionFraction: c_int,
	} = undefined;

	pub fn init() void {
		buffer1.init(false, c.GL_LINEAR, c.GL_CLAMP_TO_EDGE);
		buffer2.init(false, c.GL_LINEAR, c.GL_CLAMP_TO_EDGE);
		emptyBuffer = .init();
		emptyBuffer.generate(graphics.Image.emptyImage);
		firstPassPipeline = graphics.Pipeline.init(
			"assets/cubyz/shaders/bloom/first_pass.vert",
			"assets/cubyz/shaders/bloom/first_pass.frag",
			"",
			null,
			.{.cullMode = .none},
			.{.depthTest = false, .depthWrite = false},
			.{.attachments = &.{.noBlending}},
		);
		secondPassPipeline = graphics.Pipeline.init(
			"assets/cubyz/shaders/bloom/second_pass.vert",
			"assets/cubyz/shaders/bloom/second_pass.frag",
			"",
			null,
			.{.cullMode = .none},
			.{.depthTest = false, .depthWrite = false},
			.{.attachments = &.{.noBlending}},
		);
		colorExtractAndDownsamplePipeline = graphics.Pipeline.init(
			"assets/cubyz/shaders/bloom/color_extractor_downsample.vert",
			"assets/cubyz/shaders/bloom/color_extractor_downsample.frag",
			"",
			&colorExtractUniforms,
			.{.cullMode = .none},
			.{.depthTest = false, .depthWrite = false},
			.{.attachments = &.{.noBlending}},
		);
	}

	pub fn deinit() void {
		buffer1.deinit();
		buffer2.deinit();
		firstPassPipeline.deinit();
		secondPassPipeline.deinit();
		colorExtractAndDownsamplePipeline.deinit();
	}

	fn extractImageDataAndDownsample(playerBlock: blocks.Block, playerPos: Vec3d, viewMatrix: Mat4f) void {
		colorExtractAndDownsamplePipeline.bind(null);
		worldFrameBuffer.bindTexture(c.GL_TEXTURE3);
		worldFrameBuffer.bindDepthTexture(c.GL_TEXTURE4);
		buffer1.bind();
		if(!blocks.meshes.hasFog(playerBlock)) {
			c.glUniform3fv(colorExtractUniforms.@"fog.color", 1, @ptrCast(&game.fog.fogColor));
			c.glUniform1f(colorExtractUniforms.@"fog.density", game.fog.density);
			c.glUniform1f(colorExtractUniforms.@"fog.fogLower", game.fog.fogLower);
			c.glUniform1f(colorExtractUniforms.@"fog.fogHigher", game.fog.fogHigher);
		} else {
			const fogColor = blocks.meshes.fogColor(playerBlock);
			c.glUniform3f(colorExtractUniforms.@"fog.color", @as(f32, @floatFromInt(fogColor >> 16 & 255))/255.0, @as(f32, @floatFromInt(fogColor >> 8 & 255))/255.0, @as(f32, @floatFromInt(fogColor >> 0 & 255))/255.0);
			c.glUniform1f(colorExtractUniforms.@"fog.density", blocks.meshes.fogDensity(playerBlock));
			c.glUniform1f(colorExtractUniforms.@"fog.fogLower", 1e10);
			c.glUniform1f(colorExtractUniforms.@"fog.fogHigher", 1e10);
		}

		c.glUniformMatrix4fv(colorExtractUniforms.invViewMatrix, 1, c.GL_TRUE, @ptrCast(&viewMatrix.transpose()));
		c.glUniform3i(colorExtractUniforms.playerPositionInteger, @intFromFloat(@floor(playerPos[0])), @intFromFloat(@floor(playerPos[1])), @intFromFloat(@floor(playerPos[2])));
		c.glUniform3f(colorExtractUniforms.playerPositionFraction, @floatCast(@mod(playerPos[0], 1)), @floatCast(@mod(playerPos[1], 1)), @floatCast(@mod(playerPos[2], 1)));
		c.glUniform1f(colorExtractUniforms.zNear, zNear);
		c.glUniform1f(colorExtractUniforms.zFar, zFar);
		c.glUniform2f(colorExtractUniforms.tanXY, 1.0/game.projectionMatrix.rows[0][0], 1.0/game.projectionMatrix.rows[1][2]);
		c.glBindVertexArray(graphics.draw.rectVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	fn firstPass() void {
		firstPassPipeline.bind(null);
		buffer1.bindTexture(c.GL_TEXTURE3);
		buffer2.bind();
		c.glBindVertexArray(graphics.draw.rectVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	fn secondPass() void {
		secondPassPipeline.bind(null);
		buffer2.bindTexture(c.GL_TEXTURE3);
		buffer1.bind();
		c.glBindVertexArray(graphics.draw.rectVAO);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
	}

	fn render(currentWidth: u31, currentHeight: u31, playerBlock: blocks.Block, playerPos: Vec3d, viewMatrix: Mat4f) void {
		if(width != currentWidth or height != currentHeight) {
			width = currentWidth;
			height = currentHeight;
			buffer1.updateSize(width/4, height/4, c.GL_R11F_G11F_B10F);
			std.debug.assert(buffer1.validate());
			buffer2.updateSize(width/4, height/4, c.GL_R11F_G11F_B10F);
			std.debug.assert(buffer2.validate());
		}
		gpu_performance_measuring.startQuery(.bloom_extract_downsample);

		c.glViewport(0, 0, width/4, height/4);
		extractImageDataAndDownsample(playerBlock, playerPos, viewMatrix);
		gpu_performance_measuring.stopQuery();
		gpu_performance_measuring.startQuery(.bloom_first_pass);
		firstPass();
		gpu_performance_measuring.stopQuery();
		gpu_performance_measuring.startQuery(.bloom_second_pass);
		secondPass();

		c.glViewport(0, 0, width, height);
		buffer1.bindTexture(c.GL_TEXTURE5);

		gpu_performance_measuring.stopQuery();
	}

	fn bindReplacementImage() void {
		emptyBuffer.bindTo(5);
	}
};

pub const MenuBackGround = struct {
	var pipeline: graphics.Pipeline = undefined;
	var uniforms: struct {
		viewMatrix: c_int,
		projectionMatrix: c_int,
	} = undefined;

	var vao: c_uint = undefined;
	var vbos: [2]c_uint = undefined;
	var texture: graphics.Texture = undefined;

	var angle: f32 = 0;
	var lastTime: i128 = undefined;

	fn init() void {
		lastTime = std.time.nanoTimestamp();
		pipeline = graphics.Pipeline.init(
			"assets/cubyz/shaders/background/vertex.vert",
			"assets/cubyz/shaders/background/fragment.frag",
			"",
			&uniforms,
			.{.cullMode = .none},
			.{.depthTest = false, .depthWrite = false},
			.{.attachments = &.{.noBlending}},
		);
		// 4 sides of a simple cube with some panorama texture on it.
		const rawData = [_]f32{
			-1, 1,  -1, 1,    1,
			-1, 1,  1,  1,    0,
			-1, -1, -1, 0.75, 1,
			-1, -1, 1,  0.75, 0,
			1,  -1, -1, 0.5,  1,
			1,  -1, 1,  0.5,  0,
			1,  1,  -1, 0.25, 1,
			1,  1,  1,  0.25, 0,
			-1, 1,  -1, 0,    1,
			-1, 1,  1,  0,    0,
		};

		const indices = [_]c_int{
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

		const backgroundPath = chooseBackgroundImagePath(main.stackAllocator) catch |err| {
			std.log.err("Couldn't open background path: {s}", .{@errorName(err)});
			texture = .{.textureID = 0};
			return;
		};
		defer main.stackAllocator.free(backgroundPath);
		texture = graphics.Texture.initFromFile(backgroundPath);
	}

	fn chooseBackgroundImagePath(allocator: main.heap.NeverFailingAllocator) ![]const u8 {
		var dir = try main.files.cubyzDir().openIterableDir("backgrounds");
		defer dir.close();

		// Whenever the version changes copy over the new background image and display it.
		if(!std.mem.eql(u8, settings.lastVersionString, settings.version.version)) {
			const defaultImageData = try main.files.cwd().read(main.stackAllocator, "assets/cubyz/default_background.png");
			defer main.stackAllocator.free(defaultImageData);
			try dir.write("default_background.png", defaultImageData);

			return std.fmt.allocPrint(allocator.allocator, "{s}/backgrounds/default_background.png", .{main.files.cubyzDirStr()}) catch unreachable;
		}

		// Otherwise load a random texture from the backgrounds folder. The player may make their own pictures which can be chosen as well.
		var walker = dir.walk(main.stackAllocator);
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
			return error.NoBackgroundImagesFound;
		}
		const theChosenOne = main.random.nextIntBounded(u32, &main.seed, @as(u32, @intCast(fileList.items.len)));
		return std.fmt.allocPrint(allocator.allocator, "{s}/backgrounds/{s}", .{main.files.cubyzDirStr(), fileList.items[theChosenOne]}) catch unreachable;
	}

	pub fn deinit() void {
		pipeline.deinit();
		c.glDeleteVertexArrays(1, &vao);
		c.glDeleteBuffers(2, &vbos);
	}

	pub fn hasImage() bool {
		return texture.textureID != 0;
	}

	pub fn render() void {
		c.glViewport(0, 0, main.Window.width, main.Window.height);
		if(texture.textureID == 0) return;

		// Use a simple rotation around the z axis, with a steadily increasing angle.
		const newTime = std.time.nanoTimestamp();
		angle += @as(f32, @floatFromInt(newTime - lastTime))/2e10;
		lastTime = newTime;
		const viewMatrix = Mat4f.rotationZ(angle);
		pipeline.bind(null);
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
		updateViewport(size, size);
		updateFov(90.0);
		defer updateFov(main.settings.fov);
		main.settings.resolutionScale = oldResolutionScale;
		defer updateViewport(Window.width, Window.height);

		var buffer: graphics.FrameBuffer = undefined;
		buffer.init(true, c.GL_NEAREST, c.GL_REPEAT);
		defer buffer.deinit();
		buffer.updateSize(size, size, c.GL_RGBA8);

		activeFrameBuffer = buffer.frameBuffer;
		defer activeFrameBuffer = 0;

		const oldRotation = game.camera.rotation;
		defer game.camera.rotation = oldRotation;

		const angles = [_]f32{std.math.pi/2.0, std.math.pi, std.math.pi*3/2.0, std.math.pi*2};

		// All 4 sides are stored in a single image.
		const image = graphics.Image.init(main.stackAllocator, 4*size, size);
		defer image.deinit(main.stackAllocator);

		for(0..4) |i| {
			c.glDepthFunc(c.GL_LESS);
			c.glDepthMask(c.GL_TRUE);
			c.glDisable(c.GL_SCISSOR_TEST);
			game.camera.rotation = .{0, 0, angles[i]};
			// Draw to frame buffer.
			buffer.bind();
			c.glClear(c.GL_DEPTH_BUFFER_BIT | c.GL_STENCIL_BUFFER_BIT | c.GL_COLOR_BUFFER_BIT);
			main.renderer.render(game.Player.getEyePosBlocking(), 0);
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
		c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

		const fileName = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/backgrounds/{s}_{}.png", .{main.files.cubyzDirStr(), game.world.?.name, game.world.?.gameTime.load(.monotonic)}) catch unreachable;
		defer main.stackAllocator.free(fileName);
		image.exportToFile(fileName) catch |err| {
			std.log.err("Cannot write file {s} due to {s}", .{fileName, @errorName(err)});
		};
		// TODO: Performance is terrible even with -O3. Consider using qoi instead.
	}
};

pub const Skybox = struct {
	var starPipeline: graphics.Pipeline = undefined;
	var starUniforms: struct {
		mvp: c_int,
		starOpacity: c_int,
	} = undefined;

	var starVao: c_uint = undefined;

	var starSsbo: graphics.SSBO = undefined;

	const numStars = 10000;

	fn getStarPos(seed: *u64) Vec3f {
		const x: f32 = @floatCast(main.random.nextFloatGauss(seed));
		const y: f32 = @floatCast(main.random.nextFloatGauss(seed));
		const z: f32 = @floatCast(main.random.nextFloatGauss(seed));

		const r = std.math.cbrt(main.random.nextFloat(seed))*5000.0;

		return vec.normalize(Vec3f{x, y, z})*@as(Vec3f, @splat(r));
	}

	fn getStarColor(temperature: f32, light: f32, image: graphics.Image) Vec3f {
		const rgbCol = image.getRGB(@intFromFloat(std.math.clamp(temperature/15000.0*@as(f32, @floatFromInt(image.width)), 0.0, @as(f32, @floatFromInt(image.width - 1)))), 0);
		var rgb: Vec3f = @floatFromInt(Vec3i{rgbCol.r, rgbCol.g, rgbCol.b});
		rgb /= @splat(255.0);

		rgb *= @as(Vec3f, @splat(light));

		const m = @reduce(.Max, rgb);
		if(m > 1.0) {
			rgb /= @as(Vec3f, @splat(m));
		}

		return rgb;
	}

	fn init() void {
		const starColorImage = graphics.Image.readFromFile(main.stackAllocator, "assets/cubyz/star.png") catch |err| {
			std.log.err("Failed to load star image: {s}", .{@errorName(err)});
			return;
		};
		defer starColorImage.deinit(main.stackAllocator);

		starPipeline = graphics.Pipeline.init(
			"assets/cubyz/shaders/skybox/star.vert",
			"assets/cubyz/shaders/skybox/star.frag",
			"",
			&starUniforms,
			.{.cullMode = .none},
			.{.depthTest = false, .depthWrite = false},
			.{.attachments = &.{.{
				.srcColorBlendFactor = .one,
				.dstColorBlendFactor = .one,
				.colorBlendOp = .add,
				.srcAlphaBlendFactor = .one,
				.dstAlphaBlendFactor = .one,
				.alphaBlendOp = .add,
			}}},
		);

		var starData: [numStars*20]f32 = undefined;

		const starDist = 200.0;

		const off: f32 = @sqrt(3.0)/6.0;

		const triVertA = Vec3f{0.5, starDist, -off};
		const triVertB = Vec3f{-0.5, starDist, -off};
		const triVertC = Vec3f{0.0, starDist, @sqrt(3.0)/2.0 - off};

		var seed: u64 = 0;

		for(0..numStars) |i| {
			var pos: Vec3f = undefined;

			var radius: f32 = undefined;

			var temperature: f32 = undefined;

			var light: f32 = 0;

			while(light < 0.1) {
				pos = getStarPos(&seed);

				radius = @floatCast(main.random.nextFloatExp(&seed)*4 + 0.2);

				temperature = @floatCast(@abs(main.random.nextFloatGauss(&seed)*3000.0 + 5000.0) + 1000.0);

				// 3.6e-12 can be modified to change the brightness of the stars
				light = (3.6e-12*radius*radius*temperature*temperature*temperature*temperature)/(vec.dot(pos, pos));
			}

			pos = vec.normalize(pos)*@as(Vec3f, @splat(starDist));

			const normPos = vec.normalize(pos);

			const color = getStarColor(temperature, light, starColorImage);

			const latitude: f32 = @floatCast(std.math.asin(normPos[2]));
			const longitude: f32 = @floatCast(std.math.atan2(-normPos[0], normPos[1]));

			const mat = Mat4f.rotationZ(longitude).mul(Mat4f.rotationX(latitude));

			const posA = vec.xyz(mat.mulVec(.{triVertA[0], triVertA[1], triVertA[2], 1.0}));
			const posB = vec.xyz(mat.mulVec(.{triVertB[0], triVertB[1], triVertB[2], 1.0}));
			const posC = vec.xyz(mat.mulVec(.{triVertC[0], triVertC[1], triVertC[2], 1.0}));

			starData[i*20 ..][0..3].* = posA;
			starData[i*20 + 4 ..][0..3].* = posB;
			starData[i*20 + 8 ..][0..3].* = posC;

			starData[i*20 + 12 ..][0..3].* = pos;
			starData[i*20 + 16 ..][0..3].* = color;
		}

		starSsbo = graphics.SSBO.initStatic(f32, &starData);

		c.glGenVertexArrays(1, &starVao);
		c.glBindVertexArray(starVao);
		c.glEnableVertexAttribArray(0);
	}

	pub fn deinit() void {
		starPipeline.deinit();
		starSsbo.deinit();
		c.glDeleteVertexArrays(1, &starVao);
	}

	pub fn render() void {
		const viewMatrix = game.camera.viewMatrix;

		const time = game.world.?.gameTime.load(.monotonic);

		var starOpacity: f32 = 0;
		const dayTime = @abs(@mod(time, game.World.dayCycle) -% game.World.dayCycle/2);
		if(dayTime < game.World.dayCycle/4 - game.World.dayCycle/16) {
			starOpacity = 1;
		} else if(dayTime > game.World.dayCycle/4 + game.World.dayCycle/16) {
			starOpacity = 0;
		} else {
			starOpacity = 1 - @as(f32, @floatFromInt(dayTime - (game.World.dayCycle/4 - game.World.dayCycle/16)))/@as(f32, @floatFromInt(game.World.dayCycle/8));
		}

		if(starOpacity != 0) {
			starPipeline.bind(null);

			const starMatrix = game.projectionMatrix.mul(viewMatrix.mul(Mat4f.rotationX(@as(f32, @floatFromInt(time))/@as(f32, @floatFromInt(main.game.World.dayCycle)))));

			starSsbo.bind(12);

			c.glUniform1f(starUniforms.starOpacity, starOpacity);
			c.glUniformMatrix4fv(starUniforms.mvp, 1, c.GL_TRUE, @ptrCast(&starMatrix));

			c.glBindVertexArray(starVao);
			c.glDrawArrays(c.GL_TRIANGLES, 0, numStars*3);

			c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, 0);
		}
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
		self.planes[0] = Plane{.pos = cameraPos, .norm = vec.cross(cameraUp, cameraDir + cameraRight*@as(Vec3f, @splat(halfHSide)))}; // right
		self.planes[1] = Plane{.pos = cameraPos, .norm = vec.cross(cameraDir - cameraRight*@as(Vec3f, @splat(halfHSide)), cameraUp)}; // left
		self.planes[2] = Plane{.pos = cameraPos, .norm = vec.cross(cameraRight, cameraDir - cameraUp*@as(Vec3f, @splat(halfVSide)))}; // top
		self.planes[3] = Plane{.pos = cameraPos, .norm = vec.cross(cameraDir + cameraUp*@as(Vec3f, @splat(halfVSide)), cameraRight)}; // bottom
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
	var pipeline: graphics.Pipeline = undefined;
	var uniforms: struct {
		projectionMatrix: c_int,
		viewMatrix: c_int,
		modelPosition: c_int,
		lowerBounds: c_int,
		upperBounds: c_int,
		lineSize: c_int,
	} = undefined;

	pub fn init() void {
		pipeline = graphics.Pipeline.init(
			"assets/cubyz/shaders/block_selection_vertex.vert",
			"assets/cubyz/shaders/block_selection_fragment.frag",
			"",
			&uniforms,
			.{.cullMode = .none},
			.{.depthTest = true, .depthWrite = true},
			.{.attachments = &.{.alphaBlending}},
		);
	}

	pub fn deinit() void {
		pipeline.deinit();
	}

	var posBeforeBlock: Vec3i = undefined;
	var neighborOfSelection: chunk.Neighbor = undefined;
	pub var selectedBlockPos: ?Vec3i = null;
	var lastSelectedBlockPos: Vec3i = undefined;
	var currentBlockProgress: f32 = 0;
	var currentSwingProgress: f32 = 0;
	var currentSwingTime: f32 = 0;
	var selectionMin: Vec3f = undefined;
	var selectionMax: Vec3f = undefined;
	var selectionFace: chunk.Neighbor = undefined;
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
			const block = mesh_storage.getBlockFromRenderThread(voxelPos[0], voxelPos[1], voxelPos[2]) orelse break;
			if(block.typ != 0) blk: {
				const fluidPlaceable = item != null and item.? == .baseItem and item.?.baseItem.hasTag(.fluidPlaceable);
				const holdingTargetedBlock = item != null and item.? == .baseItem and item.?.baseItem.block() == block.typ;
				if(block.hasTag(.air) and !holdingTargetedBlock) break :blk;
				if(block.hasTag(.fluid) and !fluidPlaceable and !holdingTargetedBlock) break :blk; // TODO: Buckets could select fluids
				const relativePlayerPos: Vec3f = @floatCast(pos - @as(Vec3d, @floatFromInt(voxelPos)));
				if(block.mode().rayIntersection(block, item, relativePlayerPos, _dir)) |intersection| {
					if(intersection.distance <= closestDistance) {
						selectedBlockPos = voxelPos;
						selectionMin = intersection.min;
						selectionMax = intersection.max;
						selectionFace = intersection.face;
						break;
					}
				}
			}
			posBeforeBlock = voxelPos;
			if(tMax[0] < tMax[1]) {
				if(tMax[0] < tMax[2]) {
					voxelPos[0] +%= step[0];
					total_tMax = tMax[0];
					tMax[0] += tDelta[0];
					neighborOfSelection = if(step[0] == 1) .dirPosX else .dirNegX;
				} else {
					voxelPos[2] +%= step[2];
					total_tMax = tMax[2];
					tMax[2] += tDelta[2];
					neighborOfSelection = if(step[2] == 1) .dirUp else .dirDown;
				}
			} else {
				if(tMax[1] < tMax[2]) {
					voxelPos[1] +%= step[1];
					total_tMax = tMax[1];
					tMax[1] += tDelta[1];
					neighborOfSelection = if(step[1] == 1) .dirPosY else .dirNegY;
				} else {
					voxelPos[2] +%= step[2];
					total_tMax = tMax[2];
					tMax[2] += tDelta[2];
					neighborOfSelection = if(step[2] == 1) .dirUp else .dirDown;
				}
			}
		}
		// TODO: Test entities
	}

	fn canPlaceBlock(pos: Vec3i, block: main.blocks.Block) bool {
		if(main.game.collision.collideWithBlock(block, pos[0], pos[1], pos[2], main.game.Player.getPosBlocking() + main.game.Player.outerBoundingBox.center(), main.game.Player.outerBoundingBox.extent(), .{0, 0, 0}) != null) {
			return false;
		}
		return true; // TODO: Check other entities
	}

	pub fn placeBlock(inventory: main.items.Inventory, slot: u32) void {
		if(selectedBlockPos) |selectedPos| {
			var oldBlock = mesh_storage.getBlockFromRenderThread(selectedPos[0], selectedPos[1], selectedPos[2]) orelse return;
			var block = oldBlock;
			if(inventory.getItem(slot)) |item| {
				switch(item) {
					.baseItem => |baseItem| {
						if(baseItem.block()) |itemBlock| {
							const rotationMode = blocks.Block.mode(.{.typ = itemBlock, .data = 0});
							var neighborDir = Vec3i{0, 0, 0};
							// Check if stuff can be added to the block itself:
							if(itemBlock == block.typ) {
								const relPos: Vec3f = @floatCast(lastPos - @as(Vec3d, @floatFromInt(selectedPos)));
								if(rotationMode.generateData(main.game.world.?, selectedPos, relPos, lastDir, neighborDir, null, &block, .{.typ = 0, .data = 0}, false)) {
									if(!canPlaceBlock(selectedPos, block)) return;
									updateBlockAndSendUpdate(inventory, slot, selectedPos[0], selectedPos[1], selectedPos[2], oldBlock, block);
									return;
								}
							} else {
								if(rotationMode.modifyBlock(&block, itemBlock)) {
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
							oldBlock = mesh_storage.getBlockFromRenderThread(neighborPos[0], neighborPos[1], neighborPos[2]) orelse return;
							block = oldBlock;
							if(block.typ == itemBlock) {
								if(rotationMode.generateData(main.game.world.?, neighborPos, relPos, lastDir, neighborDir, neighborOfSelection, &block, neighborBlock, false)) {
									if(!canPlaceBlock(neighborPos, block)) return;
									updateBlockAndSendUpdate(inventory, slot, neighborPos[0], neighborPos[1], neighborPos[2], oldBlock, block);
									return;
								}
							} else {
								if(!block.replacable()) return;
								block.typ = itemBlock;
								block.data = 0;
								if(rotationMode.generateData(main.game.world.?, neighborPos, relPos, lastDir, neighborDir, neighborOfSelection, &block, neighborBlock, true)) {
									if(!canPlaceBlock(neighborPos, block)) return;
									updateBlockAndSendUpdate(inventory, slot, neighborPos[0], neighborPos[1], neighborPos[2], oldBlock, block);
									return;
								}
							}
						}
						if(std.mem.eql(u8, baseItem.id(), "cubyz:selection_wand")) {
							game.Player.selectionPosition2 = selectedPos;
							main.network.Protocols.genericUpdate.sendWorldEditPos(main.game.world.?.conn, .selectedPos2, selectedPos);
							return;
						}
					},
					.tool => |tool| {
						_ = tool; // TODO: Tools might change existing blocks.
					},
				}
			}
		}
	}

	pub fn breakBlock(inventory: main.items.Inventory, slot: u32, deltaTime: f64) void {
		if(selectedBlockPos) |selectedPos| {
			const stack = inventory.getStack(slot);
			const isSelectionWand = stack.item != null and stack.item.? == .baseItem and std.mem.eql(u8, stack.item.?.baseItem.id(), "cubyz:selection_wand");
			if(isSelectionWand) {
				game.Player.selectionPosition1 = selectedPos;
				main.network.Protocols.genericUpdate.sendWorldEditPos(main.game.world.?.conn, .selectedPos1, selectedPos);
				return;
			}

			if(@reduce(.Or, lastSelectedBlockPos != selectedPos)) {
				mesh_storage.removeBreakingAnimation(lastSelectedBlockPos);
				lastSelectedBlockPos = selectedPos;
				currentBlockProgress = 0;
			}
			const block = mesh_storage.getBlockFromRenderThread(selectedPos[0], selectedPos[1], selectedPos[2]) orelse return;
			const holdingTargetedBlock = stack.item != null and stack.item.? == .baseItem and stack.item.?.baseItem.block() == block.typ;
			if((block.hasTag(.fluid) or block.hasTag(.air)) and !holdingTargetedBlock) return;

			const relPos: Vec3f = @floatCast(lastPos - @as(Vec3d, @floatFromInt(selectedPos)));

			main.items.Inventory.Sync.ClientSide.mutex.lock();
			if(!game.Player.isCreative()) {
				var damage: f32 = main.game.Player.defaultBlockDamage;
				const isTool = stack.item != null and stack.item.? == .tool;
				if(isTool) {
					damage = stack.item.?.tool.getBlockDamage(block);
				}
				damage -= block.blockResistance();
				if(damage > 0) {
					const swingTime = if(isTool and stack.item.?.tool.isEffectiveOn(block)) 1.0/stack.item.?.tool.swingSpeed else 0.5;
					if(currentSwingTime != swingTime) {
						currentSwingProgress = 0;
						currentSwingTime = swingTime;
					}
					currentSwingProgress += @floatCast(deltaTime);
					while(currentSwingProgress > currentSwingTime) {
						currentSwingProgress -= currentSwingTime;
						currentBlockProgress += damage/block.blockHealth();
						if(currentBlockProgress > 1) break;
					}
					if(currentBlockProgress < 1) {
						mesh_storage.removeBreakingAnimation(lastSelectedBlockPos);
						if(currentBlockProgress != 0) {
							mesh_storage.addBreakingAnimation(lastSelectedBlockPos, currentBlockProgress);
						}
						main.items.Inventory.Sync.ClientSide.mutex.unlock();

						return;
					} else {
						currentSwingProgress += (currentBlockProgress - 1)*block.blockHealth()/damage*currentSwingTime;
						mesh_storage.removeBreakingAnimation(lastSelectedBlockPos);
						currentBlockProgress = 0;
					}
				} else {
					main.items.Inventory.Sync.ClientSide.mutex.unlock();
					return;
				}
			}

			var newBlock = block;
			block.mode().onBlockBreaking(inventory.getStack(slot).item, relPos, lastDir, &newBlock);
			main.items.Inventory.Sync.ClientSide.mutex.unlock();

			if(newBlock != block) {
				updateBlockAndSendUpdate(inventory, slot, selectedPos[0], selectedPos[1], selectedPos[2], block, newBlock);
			}
		}
	}

	fn updateBlockAndSendUpdate(source: main.items.Inventory, slot: u32, x: i32, y: i32, z: i32, oldBlock: blocks.Block, newBlock: blocks.Block) void {
		main.items.Inventory.Sync.ClientSide.executeCommand(.{
			.updateBlock = .{
				.source = .{.inv = source, .slot = slot},
				.pos = .{x, y, z},
				.dropLocation = .{
					.dir = selectionFace,
					.min = selectionMin,
					.max = selectionMax,
				},
				.oldBlock = oldBlock,
				.newBlock = newBlock,
			},
		});
		mesh_storage.updateBlock(.{.x = x, .y = y, .z = z, .newBlock = newBlock, .blockEntityData = &.{}});
	}

	pub fn drawCube(projectionMatrix: Mat4f, viewMatrix: Mat4f, relativePositionToPlayer: Vec3d, min: Vec3f, max: Vec3f) void {
		pipeline.bind(null);

		c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&projectionMatrix));
		c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_TRUE, @ptrCast(&viewMatrix));

		c.glUniform3f(
			uniforms.modelPosition,
			@floatCast(relativePositionToPlayer[0]),
			@floatCast(relativePositionToPlayer[1]),
			@floatCast(relativePositionToPlayer[2]),
		);
		c.glUniform3f(uniforms.lowerBounds, min[0], min[1], min[2]);
		c.glUniform3f(uniforms.upperBounds, max[0], max[1], max[2]);
		c.glUniform1f(uniforms.lineSize, 1.0/128.0);

		c.glBindVertexArray(main.renderer.chunk_meshing.vao);
		c.glDrawElements(c.GL_TRIANGLES, 12*6*6, c.GL_UNSIGNED_INT, null);
	}

	pub fn render(projectionMatrix: Mat4f, viewMatrix: Mat4f, playerPos: Vec3d) void {
		if(main.gui.hideGui) return;
		if(selectedBlockPos) |_selectedBlockPos| {
			drawCube(projectionMatrix, viewMatrix, @as(Vec3d, @floatFromInt(_selectedBlockPos)) - playerPos, selectionMin, selectionMax);
		}
		if(game.Player.selectionPosition1) |pos1| {
			if(game.Player.selectionPosition2) |pos2| {
				const bottomLeft: Vec3i = @min(pos1, pos2);
				const topRight: Vec3i = @max(pos1, pos2);
				drawCube(projectionMatrix, viewMatrix, @as(Vec3d, @floatFromInt(bottomLeft)) - playerPos, .{0, 0, 0}, @floatFromInt(topRight - bottomLeft + Vec3i{1, 1, 1}));
			}
		}
	}
};
