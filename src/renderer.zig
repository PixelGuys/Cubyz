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
const main = @import("main.zig");
const network = @import("network.zig");
const settings = @import("settings.zig");
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
		try RenderOctree.updateMeshes(startTime + maximumMeshTime);
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
	buffers.bind();
	buffers.clearAndBind(Vec4f{.x=skyColor.x, .y=skyColor.y, .z=skyColor.z, .w=1});
//	TODO:// Clean up old chunk meshes:
//	Meshes.cleanUp();
	game.camera.updateViewMatrix();

	// Uses FrustumCulling on the chunks.
	var frustum = Frustum.init(Vec3f{.x=0, .y=0, .z=0}, game.camera.viewMatrix, settings.fov, zFarLOD, main.Window.width, main.Window.height);

	const time = @intCast(u32, std.time.milliTimestamp() & std.math.maxInt(u32));
	const waterFog = Fog{.active=true, .color=.{.x=0.0, .y=0.1, .z=0.2}, .density=0.1};

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
	try RenderOctree.getRenderChunks(playerPos, frustum, &meshes);
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

pub const RenderOctree = struct {
	pub var allocator: std.mem.Allocator = undefined;
	var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
	pub const Node = struct {
		shouldBeRemoved: bool = false,
		children: ?[]*Node = null,
		size: chunk.ChunkCoordinate,
		mesh: chunk.meshing.ChunkMesh,
		mutex: std.Thread.Mutex = std.Thread.Mutex{},

		fn init(replacement: ?*chunk.meshing.ChunkMesh, pos: chunk.ChunkPosition, size: chunk.ChunkCoordinate, meshRequests: *std.ArrayList(chunk.ChunkPosition)) !*Node {
			var self = try allocator.create(Node);
			self.* = Node {
				.size = size,
				.mesh = chunk.meshing.ChunkMesh.init(pos, replacement),
			};
			try meshRequests.append(pos);
			std.debug.assert(pos.voxelSize & pos.voxelSize-1 == 0);
			return self;
		}

		fn deinit(self: *Node) void {
			if(self.children) |children| {
				for(children) |child| {
					child.deinit();
				}
				allocator.free(children);
			}
			self.mesh.deinit();
			allocator.destroy(self);
		}

		fn update(self: *Node, playerPos: Vec3d, renderDistance: i32, maxRD: i32, minHeight: i32, maxHeight: i32, nearRenderDistance: i32,  meshRequests: *std.ArrayList(chunk.ChunkPosition)) !void {
			self.mutex.lock();
			defer self.mutex.unlock();
			// Calculate the minimum distance between this chunk and the player:
			var minDist = self.mesh.pos.getMinDistanceSquared(playerPos);
			// Check if this chunk is outside the nearRenderDistance or outside the height limits:
			// if (wy + size <= Cubyz.world.chunkManager.getOrGenerateMapFragment(x, z, 32).getMinHeight() || wy > Cubyz.world.chunkManager.getOrGenerateMapFragment(x, z, 32).getMaxHeight()) {
			if(self.mesh.pos.wy + self.size <= 0 or self.mesh.pos.wy > 1024) {
				if(minDist > @intToFloat(f64, nearRenderDistance*nearRenderDistance)) {
					if(self.children) |children| {
						for(children) |child| {
							child.deinit();
						}
						allocator.free(children);
						self.children = null;
					}
					return;
				}
			}
			// Check if parts of this OctTree require using normal chunks:
			if(self.size == chunk.chunkSize*2 and minDist < @intToFloat(f64, renderDistance*renderDistance)) {
				if(self.children == null) {
					self.children = try allocator.alloc(*Node, 8);
					for(self.children.?) |*child, i| {
						child.* = try Node.init(&self.mesh, chunk.ChunkPosition{
							.wx = self.mesh.pos.wx + (if(i & 1 == 0) 0 else @divFloor(self.size, 2)),
							.wy = self.mesh.pos.wy + (if(i & 2 == 0) 0 else @divFloor(self.size, 2)),
							.wz = self.mesh.pos.wz + (if(i & 4 == 0) 0 else @divFloor(self.size, 2)),
							.voxelSize = @divFloor(self.mesh.pos.voxelSize, 2),
						}, @divFloor(self.size, 2), meshRequests);
					}
				}
				for(self.children.?) |child| {
					try child.update(playerPos, renderDistance, @divFloor(maxRD, 2), minHeight, maxHeight, nearRenderDistance, meshRequests);
				}
			// Check if parts of this OctTree require a higher resolution:
			} else if(minDist < @intToFloat(f64, maxRD*maxRD)/4 and self.size > chunk.chunkSize*2) {
				if(self.children == null) {
					self.children = try allocator.alloc(*Node, 8);
					for(self.children.?) |*child, i| {
						child.* = try Node.init(&self.mesh, chunk.ChunkPosition{
							.wx = self.mesh.pos.wx + (if(i & 1 == 0) 0 else @divFloor(self.size, 2)),
							.wy = self.mesh.pos.wy + (if(i & 2 == 0) 0 else @divFloor(self.size, 2)),
							.wz = self.mesh.pos.wz + (if(i & 4 == 0) 0 else @divFloor(self.size, 2)),
							.voxelSize = @divFloor(self.mesh.pos.voxelSize, 2),
						}, @divFloor(self.size, 2), meshRequests);
					}
				}
				for(self.children.?) |child| {
					try child.update(playerPos, renderDistance, @divFloor(maxRD, 2), minHeight, maxHeight, nearRenderDistance, meshRequests);
				}
			// This OctTree doesn't require higher resolution:
			} else {
				if(self.children) |children| {
					for(children) |child| {
						child.deinit();
					}
					allocator.free(children);
					self.children = null;
				}
			}
		}

		fn getChunks(self: *Node, playerPos: Vec3d, frustum: Frustum, meshes: *std.ArrayList(*chunk.meshing.ChunkMesh)) !void {
			self.mutex.lock();
			defer self.mutex.unlock();
			if(self.children) |children| {
				for(children) |child| {
					try child.getChunks(playerPos, frustum, meshes);
				}
			} else {
				if(frustum.testAAB(Vec3f{
					.x = @floatCast(f32, @intToFloat(f64, self.mesh.pos.wx) - playerPos.x),
					.y = @floatCast(f32, @intToFloat(f64, self.mesh.pos.wy) - playerPos.y),
					.z = @floatCast(f32, @intToFloat(f64, self.mesh.pos.wz) - playerPos.z),
				}, Vec3f{
					.x = @intToFloat(f32, self.size),
					.y = @intToFloat(f32, self.size),
					.z = @intToFloat(f32, self.size),
				})) {
					try meshes.append(&self.mesh);
				}
			}
		}
		// TODO:
//		public boolean testFrustum(FrustumIntersection frustumInt, double x0, double y0, double z0) {
//			return frustumInt.testAab((float)(wx - x0), (float)(wy - y0), (float)(wz - z0), (float)(wx + size - x0), (float)(wy + size - y0), (float)(wz + size - z0));
//		}
	};

	const HashMapKey3D = struct {
		x: chunk.ChunkCoordinate,
		y: chunk.ChunkCoordinate,
		z: chunk.ChunkCoordinate,

		pub fn hash(_: anytype, key: HashMapKey3D) u64 {
			return @bitCast(u32, ((key.x << 13) | (key.x >> 19)) ^ ((key.y << 7) | (key.y >> 25)) ^ ((key.z << 23) | (key.z >> 9))); // This should be a good hash for now. TODO: Test how good it really is and find a better one.
		}

		pub fn eql(_: anytype, key: HashMapKey3D, other: HashMapKey3D) bool {
			return key.x == other.x and key.y == other.y and key.z == other.z;
		}
	};

	var roots: std.HashMap(HashMapKey3D, *Node, HashMapKey3D, 80) = undefined;
	var updatableList: std.ArrayList(*chunk.ChunkVisibilityData) = undefined;
	var lastRD: i32 = 0;
	var lastFactor: f32 = 0;
	var mutex = std.Thread.Mutex{};

	pub fn init() !void {
		lastRD = 0;
		lastFactor = 0;
		gpa = std.heap.GeneralPurposeAllocator(.{}){};
		allocator = gpa.allocator();
		roots = std.HashMap(HashMapKey3D, *Node, HashMapKey3D, 80).initContext(allocator, undefined);
		updatableList = std.ArrayList(*chunk.ChunkVisibilityData).init(allocator);
	}

	pub fn deinit() void {
		var iterator = roots.valueIterator();
		while(iterator.next()) |value| {
			value.*.deinit();
		}
		roots.deinit();
		for(updatableList.items) |updatable| {
			updatable.visibles.deinit();
			allocator.destroy(updatable);
		}
		updatableList.deinit();
		game.world.?.blockPalette.deinit();
		if(gpa.deinit()) {
			@panic("Memory leak");
		}
	}

	pub fn update(conn: *network.Connection, playerPos: Vec3d, renderDistance: i32, LODFactor: f32) !void {
		if(lastRD != renderDistance and lastFactor != LODFactor) {
			// TODO:
//			Protocols.GENERIC_UPDATE.sendRenderDistance(Cubyz.world.serverConnection, renderDistance, LODFactor);
		}
		var px = @floatToInt(chunk.ChunkCoordinate, playerPos.x);
		var py = @floatToInt(chunk.ChunkCoordinate, playerPos.y);
		var pz = @floatToInt(chunk.ChunkCoordinate, playerPos.z);
		var maxRenderDistance = @floatToInt(i32, @ceil(@intToFloat(f32, renderDistance*chunk.chunkSize << settings.highestLOD)*LODFactor));
		var nearRenderDistance = renderDistance*chunk.chunkSize;
		var LODShift = settings.highestLOD + chunk.chunkShift;
		var LODSize = chunk.chunkSize << settings.highestLOD;
		var LODMask = LODSize - 1;
		var minX = (px - maxRenderDistance - LODMask) & ~LODMask;
		var maxX = (px + maxRenderDistance + LODMask) & ~LODMask;
		// The LOD chunks are offset from grid to make generation easier.
		minX += @divExact(LODSize, 2) - chunk.chunkSize;
		maxX += @divExact(LODSize, 2) - chunk.chunkSize;
		var newMap = std.HashMap(HashMapKey3D, *Node, HashMapKey3D, 80).initContext(allocator, undefined);
		var meshRequests = std.ArrayList(chunk.ChunkPosition).init(main.threadAllocator);
		defer meshRequests.deinit();
		var x = minX;
		while(x <= maxX): (x += LODSize) {
			var maxYRenderDistanceSquare = @intToFloat(f32, maxRenderDistance)*@intToFloat(f32, maxRenderDistance) - @intToFloat(f32, (x - px))*@intToFloat(f32, (x - px));
			if(maxYRenderDistanceSquare < 0) continue;
			var maxYRenderDistance = @floatToInt(i32, @ceil(@sqrt(maxYRenderDistanceSquare)));
			var minY = (py - maxYRenderDistance - LODMask) & ~LODMask;
			var maxY = (py + maxYRenderDistance + LODMask) & ~LODMask;
			// The LOD chunks are offset from grid to make generation easier.
			minY += @divFloor(LODSize, 2) - chunk.chunkSize;
			maxY += @divFloor(LODSize, 2) - chunk.chunkSize;
			var y = minY;
			while(y <= maxY): (y += LODSize) {
				var maxZRenderDistanceSquare = @intToFloat(f32, maxYRenderDistance)*@intToFloat(f32, maxYRenderDistance) - @intToFloat(f32, (y - py))*@intToFloat(f32, (y - py));
				if(maxZRenderDistanceSquare < 0) continue;
				var maxZRenderDistance = @floatToInt(i32, @ceil(@sqrt(maxZRenderDistanceSquare)));
				var minZ = (pz - maxZRenderDistance - LODMask) & ~LODMask;
				var maxZ = (pz + maxZRenderDistance + LODMask) & ~LODMask;
				// The LOD chunks are offset from grid to make generation easier.
				minZ += @divFloor(LODSize, 2) - chunk.chunkSize;
				maxZ += @divFloor(LODSize, 2) - chunk.chunkSize;
				var z = minZ;
				while(z <= maxZ): (z += LODSize) {
					if(y + LODSize <= 0 or y > 1024) {
						var dx = @maximum(0, try std.math.absInt(x + @divFloor(LODSize, 2) - px) - @divFloor(LODSize, 2));
						var dy = @maximum(0, try std.math.absInt(y + @divFloor(LODSize, 2) - py) - @divFloor(LODSize, 2));
						var dz = @maximum(0, try std.math.absInt(z + @divFloor(LODSize, 2) - pz) - @divFloor(LODSize, 2));
						if(dx*dx + dy*dy + dz*dz > nearRenderDistance*nearRenderDistance) continue;
					}
					var rootX = x >> LODShift;
					var rootY = y >> LODShift;
					var rootZ = z >> LODShift;

					var key = HashMapKey3D{.x = rootX, .y = rootY, .z = rootZ};
					var node = roots.get(key);
					if(node) |_node| {
						// Mark that this node should not be removed.
						_node.shouldBeRemoved = false;
					} else {
						node = try Node.init(null, .{.wx=x, .wy=y, .wz=z, .voxelSize=@intCast(chunk.UChunkCoordinate, LODSize>>chunk.chunkShift)}, LODSize, &meshRequests);
						// Mark this node to be potentially removed in the next update:
						node.?.shouldBeRemoved = true;
					}
					try newMap.put(key, node.?);
					try node.?.update(playerPos, renderDistance*chunk.chunkSize, maxRenderDistance, 0, 1024, nearRenderDistance, &meshRequests);
				}
			}
		}
		// Clean memory for unused nodes:
		mutex.lock();
		defer mutex.unlock();
		var iterator = roots.valueIterator();
		while(iterator.next()) |node| {
			if(node.*.shouldBeRemoved) {
				node.*.deinit();
			} else {
				node.*.shouldBeRemoved = true;
			}
		}
		roots.deinit();
		roots = newMap;
		lastRD = renderDistance;
		lastFactor = LODFactor;
		// Make requests after updating the, to avoid concurrency issues and reduce the number of requests:
		try network.Protocols.chunkRequest.sendRequest(conn, meshRequests.items);
	}

	fn findNode(pos: chunk.ChunkPosition) ?*Node {
		var LODShift = settings.highestLOD + chunk.chunkShift;
		var LODSize = @as(chunk.UChunkCoordinate, 1) << LODShift;
		var key = HashMapKey3D{
			.x = (pos.wx - LODSize/2 + chunk.chunkSize) >> LODShift,
			.y = (pos.wy - LODSize/2 + chunk.chunkSize) >> LODShift,
			.z = (pos.wz - LODSize/2 + chunk.chunkSize) >> LODShift,
		};
		const rootNode: *Node = roots.get(key) orelse return null;
		rootNode.mutex.lock();
		defer rootNode.mutex.unlock();

		var node = rootNode;

		while(node.mesh.pos.voxelSize != pos.voxelSize) {
			var children = node.children orelse return null;
			var i: u3 = 0;
			if(pos.wx >= node.mesh.pos.wx + @divFloor(node.size, 2)) i += 1;
			if(pos.wy >= node.mesh.pos.wy + @divFloor(node.size, 2)) i += 2;
			if(pos.wz >= node.mesh.pos.wz + @divFloor(node.size, 2)) i += 4;
			node = children[i];
		}

		return node;
	}

	pub fn updateMeshes(targetTime: i64) !void {
		mutex.lock();
		defer mutex.unlock();
		while(updatableList.items.len != 0) {
			const mesh = updatableList.pop();
			const nullNode = findNode(mesh.pos);
			if(nullNode) |node| {
				node.mutex.lock();
				defer node.mutex.unlock();
				try node.mesh.regenerateMesh(mesh);
			}
			mesh.visibles.deinit();
			allocator.destroy(mesh);
			if(std.time.milliTimestamp() >= targetTime) break; // Update at least one mesh.
		}
	}

	pub fn updateChunkMesh(mesh: *chunk.ChunkVisibilityData) !void {
		mutex.lock();
		defer mutex.unlock();
		try updatableList.append(mesh);
	}

	pub fn getRenderChunks(playerPos: Vec3d, frustum: Frustum, meshes: *std.ArrayList(*chunk.meshing.ChunkMesh)) !void {
		mutex.lock();
		defer mutex.unlock();
		var iterator = roots.valueIterator();
		while(iterator.next()) |node| {
			try node.*.getChunks(playerPos, frustum, meshes);
		}
	}
	// TODO:
//	public void updateChunkMesh(VisibleChunk mesh) {
//		OctTreeNode node = findNode(mesh);
//		if (node != null) {
//			((NormalChunkMesh)node.mesh).updateChunk(mesh);
//		}
//	}
};
