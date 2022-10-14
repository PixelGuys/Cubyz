const std = @import("std");

const blocks = @import("blocks.zig");
const entity = @import("entity.zig");
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
const main = @import("main.zig");
const network = @import("network.zig");
const settings = @import("settings.zig");
const utils = @import("utils.zig");
const Window = main.Window;

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
		ambient.x = @maximum(0.1, world.ambientLight);
		ambient.y = @maximum(0.1, world.ambientLight);
		ambient.z = @maximum(0.1, world.ambientLight);
		var skyColor = Vec3f.xyz(world.clearColor);
		game.fog.color = skyColor;
		// TODO:
//		Cubyz.fog.setActive(ClientSettings.FOG_COEFFICIENT != 0);
//		Cubyz.fog.setDensity(1 / (ClientSettings.EFFECTIVE_RENDER_DISTANCE*ClientSettings.FOG_COEFFICIENT));
		skyColor.mulEqualScalar(0.25);

		try renderWorld(world, ambient, skyColor, playerPosition);
		try RenderStructure.updateMeshes(startTime + maximumMeshTime);
	} else {
		// TODO:
//		clearColor.y = clearColor.z = 0.7f;
//		clearColor.x = 0.1f;@import("main.zig")
//		
//		Window.setClearColor(clearColor);
//
//		BackgroundScene.renderBackground();
	}
//	Cubyz.gameUI.render();
//	Keyboard.release(); // TODO: Why is this called in the render thread???
}

pub fn renderWorld(world: *World, ambientLight: Vec3f, skyColor: Vec3f, playerPos: Vec3d) !void {
	_ = world;
	buffers.clearAndBind(Vec4f{.x=skyColor.x, .y=skyColor.y, .z=skyColor.z, .w=1});
//	TODO:// Clean up old chunk meshes:
//	Meshes.cleanUp();
	game.camera.updateViewMatrix();

	// Uses FrustumCulling on the chunks.
	var frustum = Frustum.init(Vec3f{.x=0, .y=0, .z=0}, game.camera.viewMatrix, settings.fov, zFarLOD, main.Window.width, main.Window.height);

	const time = @intCast(u32, std.time.milliTimestamp() & std.math.maxInt(u32));
	var waterFog = Fog{.active=true, .color=.{.x=0.0, .y=0.1, .z=0.2}, .density=0.1};

	// Update the uniforms. The uniforms are needed to render the replacement meshes.
	chunk.meshing.bindShaderAndUniforms(game.lodProjectionMatrix, ambientLight, time);

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
	var meshes = std.ArrayList(*chunk.meshing.ChunkMesh).init(main.threadAllocator);
	defer meshes.deinit();

	try RenderStructure.updateAndGetRenderChunks(game.world.?.conn, playerPos, settings.renderDistance, settings.LODFactor, frustum, &meshes);
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
	c.glDepthRangef(0, 0.05);

	entity.ClientEntityManager.render(game.projectionMatrix, ambientLight, .{.x=1, .y=0.5, .z=0.25}, playerPos);

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

pub const Frustum = struct {
	const Plane = struct {
		pos: Vec3f,
		norm: Vec3f,
	};
	planes: [5]Plane, // Who cares about the near plane anyways?

	pub fn init(cameraPos: Vec3f, rotationMatrix: Mat4f, fovY: f32, _zFar: f32, width: u31, height: u31) Frustum {
		var invRotationMatrix = rotationMatrix.transpose();
		var cameraDir = Vec3f.xyz(invRotationMatrix.mulVec(Vec4f{.x=0, .y=0, .z=1, .w=1}));
		var cameraUp = Vec3f.xyz(invRotationMatrix.mulVec(Vec4f{.x=0, .y=1, .z=0, .w=1}));
		var cameraRight = Vec3f.xyz(invRotationMatrix.mulVec(Vec4f{.x=1, .y=0, .z=0, .w=1}));

		const halfVSide = _zFar*std.math.tan(std.math.degreesToRadians(f32, fovY)*0.5);
		const halfHSide = halfVSide*@intToFloat(f32, width)/@intToFloat(f32, height);
		const frontMultFar = cameraDir.mulScalar(_zFar);

		var self: Frustum = undefined;
		self.planes[0] = Plane{.pos = cameraPos.add(frontMultFar), .norm=cameraDir.mulScalar(-1)}; // far
		self.planes[1] = Plane{.pos = cameraPos, .norm=cameraUp.cross(frontMultFar.add(cameraRight.mulScalar(halfHSide)))}; // right
		self.planes[2] = Plane{.pos = cameraPos, .norm=frontMultFar.sub(cameraRight.mulScalar(halfHSide)).cross(cameraUp)}; // left
		self.planes[3] = Plane{.pos = cameraPos, .norm=cameraRight.cross(frontMultFar.sub(cameraUp.mulScalar(halfVSide)))}; // top
		self.planes[4] = Plane{.pos = cameraPos, .norm=frontMultFar.add(cameraUp.mulScalar(halfVSide)).cross(cameraRight)}; // bottom
		return self;
	}

	pub fn testAAB(self: Frustum, pos: Vec3f, dim: Vec3f) bool {
		inline for(self.planes) |plane| {
			var dist: f32 = pos.sub(plane.pos).dot(plane.norm);
			// Find the most positive corner:
			dist += @maximum(0, dim.x*plane.norm.x);
			dist += @maximum(0, dim.y*plane.norm.y);
			dist += @maximum(0, dim.z*plane.norm.z);
			if(dist < 128) return false;
		}
		return true;
	}
};

pub const RenderStructure = struct {
	pub var allocator: std.mem.Allocator = undefined;
	var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

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
	var lastX: [settings.highestLOD + 1]chunk.ChunkCoordinate = [_]chunk.ChunkCoordinate{0} ** (settings.highestLOD + 1);
	var lastY: [settings.highestLOD + 1]chunk.ChunkCoordinate = [_]chunk.ChunkCoordinate{0} ** (settings.highestLOD + 1);
	var lastZ: [settings.highestLOD + 1]chunk.ChunkCoordinate = [_]chunk.ChunkCoordinate{0} ** (settings.highestLOD + 1);
	var lastSize: [settings.highestLOD + 1]chunk.ChunkCoordinate = [_]chunk.ChunkCoordinate{0} ** (settings.highestLOD + 1);
	var lodMutex: [settings.highestLOD + 1]std.Thread.Mutex = [_]std.Thread.Mutex{std.Thread.Mutex{}} ** (settings.highestLOD + 1);
	var mutex = std.Thread.Mutex{};

	pub fn init() !void {
		lastRD = 0;
		lastFactor = 0;
		gpa = std.heap.GeneralPurposeAllocator(.{}){};
		allocator = gpa.allocator();
		updatableList = std.ArrayList(chunk.ChunkPosition).init(allocator);
		clearList = std.ArrayList(*ChunkMeshNode).init(allocator);
		for(storageLists) |*storageList| {
			storageList.* = try allocator.alloc(?*ChunkMeshNode, 0);
		}
	}

	pub fn deinit() void {
		for(storageLists) |storageList| {
			for(storageList) |nullChunkMesh| {
				if(nullChunkMesh) |chunkMesh| {
					chunkMesh.mesh.deinit();
					allocator.destroy(chunkMesh);
				}
			}
			allocator.free(storageList);
		}
		updatableList.deinit();
		for(clearList.items) |chunkMesh| {
			chunkMesh.mesh.deinit();
			allocator.destroy(chunkMesh);
		}
		clearList.deinit();
		game.world.?.blockPalette.deinit();
		if(gpa.deinit()) {
			@panic("Memory leak");
		}
	}

	fn _getNode(pos: chunk.ChunkPosition) ?*ChunkMeshNode {
		var lod = std.math.log2_int(chunk.UChunkCoordinate, pos.voxelSize);
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

	pub fn getNeighbor(_pos: chunk.ChunkPosition, resolution: chunk.UChunkCoordinate, neighbor: u3) ?*chunk.meshing.ChunkMesh {
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
		const px = @floatToInt(chunk.ChunkCoordinate, playerPos.x);
		const py = @floatToInt(chunk.ChunkCoordinate, playerPos.y);
		const pz = @floatToInt(chunk.ChunkCoordinate, playerPos.z);

		var meshRequests = std.ArrayList(chunk.ChunkPosition).init(main.threadAllocator);
		defer meshRequests.deinit();

		for(storageLists) |_, _lod| {
			const lod = @intCast(u5, _lod);
			var maxRenderDistance = renderDistance*chunk.chunkSize << lod;
			if(lod != 0) maxRenderDistance = @floatToInt(i32, @ceil(@intToFloat(f32, maxRenderDistance)*LODFactor));
			var sizeShift = chunk.chunkShift + lod;
			const size = @intCast(chunk.UChunkCoordinate, chunk.chunkSize << lod);
			const mask: chunk.ChunkCoordinate = size - 1;
			const invMask: chunk.ChunkCoordinate = ~mask;

			const maxSideLength = @intCast(chunk.UChunkCoordinate, @divFloor(2*maxRenderDistance + size-1, size) + 2);
			var newList = try allocator.alloc(?*ChunkMeshNode, maxSideLength*maxSideLength*maxSideLength);
			std.mem.set(?*ChunkMeshNode, newList, null);

			const startX = size*(@divFloor(px, size) -% maxSideLength/2);
			const startY = size*(@divFloor(py, size) -% maxSideLength/2);
			const startZ = size*(@divFloor(pz, size) -% maxSideLength/2);

			const minX = px-%maxRenderDistance-%1 & invMask;
			const maxX = px+%maxRenderDistance+%size & invMask;
			var x = minX;
			while(x != maxX): (x +%= size) {
				const xIndex = @divExact(x -% startX, size);
				var deltaX: i64 = std.math.absInt(@as(i64, x +% size/2 -% px)) catch unreachable;
				deltaX = @maximum(0, deltaX - size/2);
				const maxYRenderDistanceSquare = @as(i64, maxRenderDistance)*@as(i64, maxRenderDistance) - deltaX*deltaX;
				const maxYRenderDistance = @floatToInt(i32, @ceil(@sqrt(@intToFloat(f64, maxYRenderDistanceSquare))));

				const minY = py-%maxYRenderDistance-%1 & invMask;
				const maxY = py+%maxYRenderDistance+%size & invMask;
				var y = minY;
				while(y != maxY): (y +%= size) {
					const yIndex = @divExact(y -% startY, size);
					var deltaY: i64 = std.math.absInt(@as(i64, y +% size/2 -% py)) catch unreachable;
					deltaY = @maximum(0, deltaY - size/2);
					const maxZRenderDistanceSquare = @as(i64, maxYRenderDistance)*@as(i64, maxYRenderDistance) - deltaY*deltaY;
					const maxZRenderDistance = @floatToInt(i32, @ceil(@sqrt(@intToFloat(f64, maxZRenderDistanceSquare))));

					const minZ = pz-%maxZRenderDistance-%1 & invMask;
					const maxZ = pz+%maxZRenderDistance+%size & invMask;
					var z = minZ;
					while(z != maxZ): (z +%= size) {
						const zIndex = @divExact(z -% startZ, size);
						const index = (xIndex*maxSideLength + yIndex)*maxSideLength + zIndex;
						const pos = chunk.ChunkPosition{.wx=x, .wy=y, .wz=z, .voxelSize=@as(chunk.UChunkCoordinate, 1)<<lod};
						var node = _getNode(pos);
						if(node) |_node| {
							_node.shouldBeRemoved = false;
						} else {
							node = try allocator.create(ChunkMeshNode);
							node.?.mesh = chunk.meshing.ChunkMesh.init(allocator, pos);
							node.?.shouldBeRemoved = true; // Might be removed in the next iteration.
							try meshRequests.append(pos);
						}
						if(frustum.testAAB(Vec3f{
							.x = @floatCast(f32, @intToFloat(f64, x) - playerPos.x),
							.y = @floatCast(f32, @intToFloat(f64, y) - playerPos.y),
							.z = @floatCast(f32, @intToFloat(f64, z) - playerPos.z),
						}, Vec3f{
							.x = @intToFloat(f32, size),
							.y = @intToFloat(f32, size),
							.z = @intToFloat(f32, size),
						}) and node.?.mesh.visibilityMask != 0) {
							try meshes.append(&node.?.mesh);
						}
						if(lod+1 != storageLists.len and node.?.mesh.generated) {
							if(_getNode(.{.wx=x, .wy=y, .wz=z, .voxelSize=@as(chunk.UChunkCoordinate, 1)<<(lod+1)})) |parent| {
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
							allocator.destroy(mesh);
						} else {
							try clearList.append(mesh);
						}
					} else {
						mesh.shouldBeRemoved = true;
					}
				}
			}
			allocator.free(oldList);
		}

		var i: usize = 0;
		while(i < clearList.items.len) {
			const mesh = clearList.items[i];
			if(mesh.mesh.mutex.tryLock()) { // Make sure there is no task currently running on the thing.
				mesh.mesh.mutex.unlock();
				mesh.mesh.deinit();
				allocator.destroy(mesh);
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
		mutex.lock();
		defer mutex.unlock();
		while(updatableList.items.len != 0) {
			// TODO: Find a faster solution than going through the entire list.
			var closestPriority: f32 = -std.math.floatMax(f32);
			var closestIndex: usize = 0;
			const playerPos = game.Player.getPosBlocking();
			for(updatableList.items) |pos, i| {
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
			.run = @ptrCast(*const fn(*anyopaque) void, &run),
			.clean = @ptrCast(*const fn(*anyopaque) void, &clean),
		};

		pub fn schedule(mesh: *chunk.Chunk) !void {
			var task = try allocator.create(MeshGenerationTask);
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
			if(self.mesh.pos.voxelSize != 1) maxRenderDistance = @floatToInt(i32, @ceil(@intToFloat(f32, maxRenderDistance)*settings.LODFactor));
			maxRenderDistance += 2*self.mesh.pos.voxelSize*chunk.chunkSize;
			return distanceSqr < @intToFloat(f64, maxRenderDistance*maxRenderDistance);
		}

		pub fn run(self: *MeshGenerationTask) void {
			const pos = self.mesh.pos;
			const nullNode = _getNode(pos);
			if(nullNode) |node| {
				{
					node.mesh.mutex.lock();
					defer node.mesh.mutex.unlock();
					node.mesh.regenerateMainMesh(self.mesh) catch |err| {
						std.log.err("Error while regenerating mesh: {s}", .{@errorName(err)});
						if(@errorReturnTrace()) |trace| {
							std.log.err("Trace: {}", .{trace});
						}
						allocator.destroy(self.mesh);
						allocator.destroy(self);
						return;
					};
				}
				mutex.lock();
				defer mutex.unlock();
				updatableList.append(pos) catch |err| {
					std.log.err("Error while regenerating mesh: {s}", .{@errorName(err)});
					if(@errorReturnTrace()) |trace| {
						std.log.err("Trace: {}", .{trace});
					}
					allocator.destroy(self.mesh);
				};
			} else {
				allocator.destroy(self.mesh);
			}
			allocator.destroy(self);
		}

		pub fn clean(self: *MeshGenerationTask) void {
			allocator.destroy(self.mesh);
			allocator.destroy(self);
		}
	};

	pub fn updateChunkMesh(mesh: *chunk.Chunk) !void {
		try MeshGenerationTask.schedule(mesh);
	}
};
