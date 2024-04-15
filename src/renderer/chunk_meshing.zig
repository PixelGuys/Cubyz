const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("root");
const blocks = main.blocks;
const Block = blocks.Block;
const chunk = main.chunk;
const game = main.game;
const models = main.models;
const renderer = main.renderer;
const graphics = main.graphics;
const c = graphics.c;
const Shader = graphics.Shader;
const SSBO = graphics.SSBO;
const lighting = @import("lighting.zig");
const settings = main.settings;
const vec = main.vec;
const Vec2f = vec.Vec2f;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const Mat4f = vec.Mat4f;

const mesh_storage = @import("mesh_storage.zig");

var shader: Shader = undefined;
var transparentShader: Shader = undefined;
const UniformStruct = struct {
	projectionMatrix: c_int,
	viewMatrix: c_int,
	modelPosition: c_int,
	screenSize: c_int,
	ambientLight: c_int,
	@"fog.color": c_int,
	@"fog.density": c_int,
	texture_sampler: c_int,
	emissionSampler: c_int,
	reflectivityAndAbsorptionSampler: c_int,
	reflectionMap: c_int,
	reflectionMapSize: c_int,
	visibilityMask: c_int,
	voxelSize: c_int,
	zNear: c_int,
	zFar: c_int,
};
pub var uniforms: UniformStruct = undefined;
pub var transparentUniforms: UniformStruct = undefined;
var vao: c_uint = undefined;
var vbo: c_uint = undefined;
var faces: main.List(u32) = undefined;
pub var faceBuffer: graphics.LargeBuffer(FaceData) = undefined;
pub var quadsDrawn: usize = 0;
pub var transparentQuadsDrawn: usize = 0;

pub fn init() void {
	lighting.init();
	shader = Shader.initAndGetUniforms("assets/cubyz/shaders/chunks/chunk_vertex.vs", "assets/cubyz/shaders/chunks/chunk_fragment.fs", &uniforms);
	transparentShader = Shader.initAndGetUniforms("assets/cubyz/shaders/chunks/chunk_vertex.vs", "assets/cubyz/shaders/chunks/transparent_fragment.fs", &transparentUniforms);

	var rawData: [6*3 << (3*chunk.chunkShift)]u32 = undefined; // 6 vertices per face, maximum 3 faces/block
	const lut = [_]u32{0, 2, 1, 1, 2, 3};
	for(0..rawData.len) |i| {
		rawData[i] = @as(u32, @intCast(i))/6*4 + lut[i%6];
	}

	c.glGenVertexArrays(1, &vao);
	c.glBindVertexArray(vao);
	c.glGenBuffers(1, &vbo);
	c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, vbo);
	c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, rawData.len*@sizeOf(u32), &rawData, c.GL_STATIC_DRAW);
	c.glBindVertexArray(0);

	faces = main.List(u32).initCapacity(main.globalAllocator, 65536); // TODO: What is this used for?
	faceBuffer.init(main.globalAllocator, 1 << 20, 3);
}

pub fn deinit() void {
	lighting.deinit();
	shader.deinit();
	transparentShader.deinit();
	c.glDeleteVertexArrays(1, &vao);
	c.glDeleteBuffers(1, &vbo);
	faces.deinit();
	faceBuffer.deinit();
}

pub fn beginRender() void {
	faceBuffer.beginRender();
}

pub fn endRender() void {
	faceBuffer.endRender();
}

fn bindCommonUniforms(locations: *UniformStruct, projMatrix: Mat4f, ambient: Vec3f) void {
	c.glUniformMatrix4fv(locations.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&projMatrix));

	c.glUniform1i(locations.texture_sampler, 0);
	c.glUniform1i(locations.emissionSampler, 1);
	c.glUniform1i(locations.reflectivityAndAbsorptionSampler, 2);
	c.glUniform1i(locations.reflectionMap, 4);
	c.glUniform1f(locations.reflectionMapSize, renderer.reflectionCubeMapSize);

	c.glUniformMatrix4fv(locations.viewMatrix, 1, c.GL_TRUE, @ptrCast(&game.camera.viewMatrix));

	c.glUniform3f(locations.ambientLight, ambient[0], ambient[1], ambient[2]);

	c.glUniform1f(locations.zNear, renderer.zNear);
	c.glUniform1f(locations.zFar, renderer.zFar);
}

pub fn bindShaderAndUniforms(projMatrix: Mat4f, ambient: Vec3f) void {
	shader.bind();

	bindCommonUniforms(&uniforms, projMatrix, ambient);

	c.glBindVertexArray(vao);
}

pub fn bindTransparentShaderAndUniforms(projMatrix: Mat4f, ambient: Vec3f) void {
	transparentShader.bind();

	c.glUniform3fv(transparentUniforms.@"fog.color", 1, @ptrCast(&game.fog.color));
	c.glUniform1f(transparentUniforms.@"fog.density", game.fog.density);

	bindCommonUniforms(&transparentUniforms, projMatrix, ambient);

	c.glBindVertexArray(vao);
}

pub const FaceData = extern struct {
	position: packed struct(u32) {
		x: u5,
		y: u5,
		z: u5,
		padding: u4 = 0,
		isBackFace: bool,
		padding2: u12 = 0,
	},
	blockAndQuad: packed struct(u32) {
		texture: u16,
		quadIndex: u16,
	},
	light: [4]u32 = .{0, 0, 0, 0},

	pub inline fn init(texture: u16, quadIndex: u16, x: i32, y: i32, z: i32, comptime backFace: bool) FaceData {
		return FaceData {
			.position = .{.x = @intCast(x), .y = @intCast(y), .z = @intCast(z), .isBackFace = backFace},
			.blockAndQuad = .{.texture = texture, .quadIndex = quadIndex},
		};
	}
};

const PrimitiveMesh = struct {
	coreFaces: main.ListUnmanaged(FaceData) = .{},
	neighborFacesSameLod: [6]main.ListUnmanaged(FaceData) = [_]main.ListUnmanaged(FaceData){.{}} ** 6,
	neighborFacesHigherLod: [6]main.ListUnmanaged(FaceData) = [_]main.ListUnmanaged(FaceData){.{}} ** 6,
	completeList: []FaceData = &.{},
	coreLen: u32 = 0,
	sameLodLens: [6]u32 = .{0} ** 6,
	higherLodLens: [6]u32 = .{0} ** 6,
	mutex: std.Thread.Mutex = .{},
	bufferAllocation: graphics.SubAllocation = .{.start = 0, .len = 0},
	vertexCount: u31 = 0,
	wasChanged: bool = false,

	fn deinit(self: *PrimitiveMesh) void {
		faceBuffer.free(self.bufferAllocation);
		self.coreFaces.deinit(main.globalAllocator);
		for(&self.neighborFacesSameLod) |*neighborFaces| {
			neighborFaces.deinit(main.globalAllocator);
		}
		for(&self.neighborFacesHigherLod) |*neighborFaces| {
			neighborFaces.deinit(main.globalAllocator);
		}
		main.globalAllocator.free(self.completeList);
	}

	fn reset(self: *PrimitiveMesh) void {
		self.coreFaces.clearRetainingCapacity();
		for(&self.neighborFacesSameLod) |*neighborFaces| {
			neighborFaces.clearRetainingCapacity();
		}
		for(&self.neighborFacesHigherLod) |*neighborFaces| {
			neighborFaces.clearRetainingCapacity();
		}
	}

	fn appendInternalQuadsToCore(self: *PrimitiveMesh, block: Block, x: i32, y: i32, z: i32, comptime backFace: bool) void {
		const model = blocks.meshes.model(block);
		models.models.items[model].appendInternalQuadsToList(&self.coreFaces, main.globalAllocator, block, x, y, z, backFace);
	}

	fn appendNeighborFacingQuadsToCore(self: *PrimitiveMesh, block: Block, neighbor: u3, x: i32, y: i32, z: i32, comptime backFace: bool) void {
		const model = blocks.meshes.model(block);
		models.models.items[model].appendNeighborFacingQuadsToList(&self.coreFaces, main.globalAllocator, block, neighbor, x, y, z, backFace);
	}

	fn appendNeighborFacingQuadsToNeighbor(self: *PrimitiveMesh, block: Block, neighbor: u3, x: i32, y: i32, z: i32, comptime backFace: bool, comptime isLod: bool) void {
		const model = blocks.meshes.model(block);
		if(isLod) {
			models.models.items[model].appendNeighborFacingQuadsToList(&self.neighborFacesHigherLod[neighbor ^ 1], main.globalAllocator, block, neighbor, x, y, z, backFace);
		} else {
			models.models.items[model].appendNeighborFacingQuadsToList(&self.neighborFacesSameLod[neighbor ^ 1], main.globalAllocator, block, neighbor, x, y, z, backFace);
		}
	}

	fn clearNeighbor(self: *PrimitiveMesh, neighbor: u3, comptime isLod: bool) void {
		if(isLod) {
			self.neighborFacesHigherLod[neighbor].clearRetainingCapacity();
		} else {
			self.neighborFacesSameLod[neighbor].clearRetainingCapacity();
		}
	}

	fn finish(self: *PrimitiveMesh, parent: *ChunkMesh) void {
		var len: usize = self.coreFaces.items.len;
		for(self.neighborFacesSameLod) |neighborFaces| {
			len += neighborFaces.items.len;
		}
		for(self.neighborFacesHigherLod) |neighborFaces| {
			len += neighborFaces.items.len;
		}
		const completeList = main.globalAllocator.alloc(FaceData, len);
		var i: usize = 0;
		@memcpy(completeList[i..][0..self.coreFaces.items.len], self.coreFaces.items);
		i += self.coreFaces.items.len;
		for(self.neighborFacesSameLod) |neighborFaces| {
			@memcpy(completeList[i..][0..neighborFaces.items.len], neighborFaces.items);
			i += neighborFaces.items.len;
		}
		for(self.neighborFacesHigherLod) |neighborFaces| {
			@memcpy(completeList[i..][0..neighborFaces.items.len], neighborFaces.items);
			i += neighborFaces.items.len;
		}

		parent.lightingData[0].lock.lockShared();
		parent.lightingData[1].lock.lockShared();
		for(completeList) |*face| {
			face.light = getLight(parent, .{face.position.x, face.position.y, face.position.z}, face.blockAndQuad.quadIndex);
		}
		parent.lightingData[1].lock.unlockShared();
		parent.lightingData[0].lock.unlockShared();

		self.mutex.lock();
		const oldList = self.completeList;
		self.completeList = completeList;
		self.coreLen = @intCast(self.coreFaces.items.len);
		for(self.neighborFacesSameLod, 0..) |neighborFaces, j| {
			self.sameLodLens[j] = @intCast(neighborFaces.items.len);
		}
		for(self.neighborFacesHigherLod, 0..) |neighborFaces, j| {
			self.higherLodLens[j] = @intCast(neighborFaces.items.len);
		}
		self.mutex.unlock();
		main.globalAllocator.free(oldList);
	}

	fn getValues(mesh: *ChunkMesh, wx: i32, wy: i32, wz: i32) [6]u8 {
		const x = (wx >> mesh.chunk.voxelSizeShift) & chunk.chunkMask;
		const y = (wy >> mesh.chunk.voxelSizeShift) & chunk.chunkMask;
		const z = (wz >> mesh.chunk.voxelSizeShift) & chunk.chunkMask;
		return mesh.lightingData[1].getValueHoldingTheLock(x, y, z) ++ mesh.lightingData[0].getValueHoldingTheLock(x, y, z);
	}

	fn getLightAt(parent: *ChunkMesh, x: i32, y: i32, z: i32) [6]u8 {
		const wx = parent.pos.wx +% x*parent.pos.voxelSize;
		const wy = parent.pos.wy +% y*parent.pos.voxelSize;
		const wz = parent.pos.wz +% z*parent.pos.voxelSize;
		if(x == x & chunk.chunkMask and y == y & chunk.chunkMask and z == z & chunk.chunkMask) {
			return getValues(parent, wx, wy, wz);
		}
		const neighborMesh = mesh_storage.getMeshAndIncreaseRefCount(.{.wx = wx, .wy = wy, .wz = wz, .voxelSize = parent.pos.voxelSize}) orelse return .{0, 0, 0, 0, 0, 0};
		defer neighborMesh.decreaseRefCount();
		neighborMesh.lightingData[0].lock.lockShared();
		defer neighborMesh.lightingData[0].lock.unlockShared();
		neighborMesh.lightingData[1].lock.lockShared();
		defer neighborMesh.lightingData[1].lock.unlockShared();
		return getValues(neighborMesh, wx, wy, wz);
	}

	fn getCornerLight(parent: *ChunkMesh, pos: Vec3i, normal: Vec3f) [6]u8 {
		const lightPos = @as(Vec3f, @floatFromInt(pos)) + normal*@as(Vec3f, @splat(0.5)) - @as(Vec3f, @splat(0.5));
		const startPos: Vec3i = @intFromFloat(@floor(lightPos));
		const interp = lightPos - @floor(lightPos);
		var val: [6]f32 = .{0, 0, 0, 0, 0, 0};
		var dx: i32 = 0;
		while(dx <= 1) : (dx += 1) {
			var dy: i32 = 0;
			while(dy <= 1) : (dy += 1) {
				var dz: i32 = 0;
				while(dz <= 1) : (dz += 1) {
					var weight: f32 = 0;
					if(dx == 0) weight = 1 - interp[0]
					else weight = interp[0];
					if(dy == 0) weight *= 1 - interp[1]
					else weight *= interp[1];
					if(dz == 0) weight *= 1 - interp[2]
					else weight *= interp[2];
					const lightVal: [6]u8 = getLightAt(parent, startPos[0] +% dx, startPos[1] +% dy, startPos[2] +% dz);
					for(0..6) |i| {
						val[i] += @as(f32, @floatFromInt(lightVal[i]))*weight;
					}
				}
			}
		}
		var result: [6]u8 = undefined;
		for(0..6) |i| {
			result[i] = std.math.lossyCast(u8, val[i]);
		}
		return result;
	}

	fn getLight(parent: *ChunkMesh, blockPos: Vec3i, quadIndex: u16) [4]u32 {
		// TODO: This is doing 12 interpolations of 8 values each. For full cube models only 4 interpolations or 4 values each would be needed.
		const normal = models.quads.items[quadIndex].normal;
		var cornerVals: [2][2][2][6]u8 = undefined;
		{
			var dx: u31 = 0;
			while(dx <= 1) : (dx += 1) {
				var dy: u31 = 0;
				while(dy <= 1) : (dy += 1) {
					var dz: u31 = 0;
					while(dz <= 1) : (dz += 1) {
						cornerVals[dx][dy][dz] = getCornerLight(parent, blockPos +% Vec3i{dx, dy, dz}, normal);
					}
				}
			}
		}
		var rawVals: [4][6]u5 = undefined;
		for(0..4) |i| {
			const vertexPos = models.quads.items[quadIndex].corners[i];
			const lightPos = vertexPos + @as(Vec3f, @floatFromInt(blockPos));
			const interp = lightPos - @as(Vec3f, @floatFromInt(blockPos));
			var val: [6]f32 = .{0, 0, 0, 0, 0, 0};
			for(0..2) |dx| {
				for(0..2) |dy| {
					for(0..2) |dz| {
						var weight: f32 = 0;
						if(dx == 0) weight = 1 - interp[0]
						else weight = interp[0];
						if(dy == 0) weight *= 1 - interp[1]
						else weight *= interp[1];
						if(dz == 0) weight *= 1 - interp[2]
						else weight *= interp[2];
						const lightVal: [6]u8 = cornerVals[dx][dy][dz];
						for(0..6) |j| {
							val[j] += @as(f32, @floatFromInt(lightVal[j]))*weight;
						}
					}
				}
			}
			for(0..6) |j| {
				rawVals[i][j] = std.math.lossyCast(u5, val[j]/8);
			}
		}
		var result: [4]u32 = undefined;
		for(0..4) |i| {
			result[i] = (
				@as(u32, rawVals[i][0]) << 25 |
				@as(u32, rawVals[i][1]) << 20 |
				@as(u32, rawVals[i][2]) << 15 |
				@as(u32, rawVals[i][3]) << 10 |
				@as(u32, rawVals[i][4]) << 5 |
				@as(u32, rawVals[i][5]) << 0
			);
		}
		return result;
	}

	fn uploadData(self: *PrimitiveMesh, isNeighborLod: [6]bool) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		var len: u32 = self.coreLen;
		var offset: u32 = self.coreLen;
		var list: [6][]FaceData = undefined;
		for(0..6) |i| {
			const neighborLen = self.sameLodLens[i];
			if(!isNeighborLod[i]) {
				list[i] = self.completeList[offset..][0..neighborLen];
				len += neighborLen;
			}
			offset += neighborLen;
		}
		for(0..6) |i| {
			const neighborLen = self.higherLodLens[i];
			if(isNeighborLod[i]) {
				list[i] = self.completeList[offset..][0..neighborLen];
				len += neighborLen;
			}
			offset += neighborLen;
		}
		const fullBuffer = faceBuffer.allocateAndMapRange(len, &self.bufferAllocation);
		defer faceBuffer.unmapRange(fullBuffer);
		@memcpy(fullBuffer[0..self.coreLen], self.completeList[0..self.coreLen]);
		var i: usize = self.coreLen;
		for(0..6) |n| {
			@memcpy(fullBuffer[i..][0..list[n].len], list[n]);
			i += list[n].len;
		}
		self.vertexCount = @intCast(6*fullBuffer.len);
		self.wasChanged = true;
	}
};

pub const ChunkMesh = struct {
	const SortingData = struct {
		face: FaceData,
		distance: u32,
		isBackFace: bool,
		shouldBeCulled: bool,

		pub fn update(self: *SortingData, chunkDx: i32, chunkDy: i32, chunkDz: i32) void {
			const x: i32 = self.face.position.x;
			const y: i32 = self.face.position.y;
			const z: i32 = self.face.position.z;
			const dx = x + chunkDx;
			const dy = y + chunkDy;
			const dz = z + chunkDz;
			self.isBackFace = self.face.position.isBackFace;
			const quadIndex = self.face.blockAndQuad.quadIndex;
			const normalVector = models.quads.items[quadIndex].normal;
			self.shouldBeCulled = vec.dot(normalVector, @floatFromInt(Vec3i{dx, dy, dz})) > 0; // TODO: Adjust for arbitrary voxel models.
			const fullDx = dx - @as(i32, @intFromFloat(normalVector[0])); // TODO: This calculation should only be done for border faces.
			const fullDy = dy - @as(i32, @intFromFloat(normalVector[1]));
			const fullDz = dz - @as(i32, @intFromFloat(normalVector[2]));
			self.distance = @abs(fullDx) + @abs(fullDy) + @abs(fullDz);
		}
	};
	const BoundingRectToNeighborChunk = struct {
		min: Vec3i = @splat(std.math.maxInt(i32)),
		max: Vec3i = @splat(0),

		fn adjustToBlock(self: *BoundingRectToNeighborChunk, block: Block, pos: Vec3i, neighbor: u3) void {
			if(block.viewThrough()) {
				self.min = @min(self.min, pos);
				self.max = @max(self.max, pos + chunk.Neighbors.orthogonalComponents[neighbor]);
			}
		}
	};
	pos: chunk.ChunkPosition,
	size: i32,
	chunk: *chunk.Chunk,
	lightingData: [2]*lighting.ChannelChunk,
	opaqueMesh: PrimitiveMesh,
	transparentMesh: PrimitiveMesh,
	lastNeighborsSameLod: [6]?*const ChunkMesh = [_]?*const ChunkMesh{null} ** 6,
	lastNeighborsHigherLod: [6]?*const ChunkMesh = [_]?*const ChunkMesh{null} ** 6,
	isNeighborLod: [6]bool = .{false} ** 6,
	visibilityMask: u8 = 0xff,
	currentSorting: []SortingData = &.{},
	sortingOutputBuffer: []FaceData = &.{},
	culledSortingCount: u31 = 0,
	lastTransparentUpdatePos: Vec3i = Vec3i{0, 0, 0},
	refCount: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),
	needsLightRefresh: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
	needsMeshUpdate: bool = false,
	finishedMeshing: bool = false,
	finishedLighting: bool = false,
	litNeighbors: Atomic(u32) = Atomic(u32).init(0),
	mutex: std.Thread.Mutex = .{},

	chunkBorders: [6]BoundingRectToNeighborChunk = [1]BoundingRectToNeighborChunk{.{}} ** 6,

	pub fn init(self: *ChunkMesh, pos: chunk.ChunkPosition, ch: *chunk.Chunk) void {
		self.* = ChunkMesh{
			.pos = pos,
			.size = chunk.chunkSize*pos.voxelSize,
			.opaqueMesh = .{},
			.transparentMesh = .{},
			.chunk = ch,
			.lightingData = .{
				lighting.ChannelChunk.init(ch, false),
				lighting.ChannelChunk.init(ch, true),
			},
		};
	}

	pub fn deinit(self: *ChunkMesh) void {
		std.debug.assert(self.refCount.load(.monotonic) == 0);
		self.opaqueMesh.deinit();
		self.transparentMesh.deinit();
		self.chunk.deinit();
		main.globalAllocator.free(self.currentSorting);
		main.globalAllocator.free(self.sortingOutputBuffer);
		for(self.lightingData) |lightingChunk| {
			lightingChunk.deinit();
		}
	}

	pub fn increaseRefCount(self: *ChunkMesh) void {
		const prevVal = self.refCount.fetchAdd(1, .monotonic);
		std.debug.assert(prevVal != 0);
	}

	/// In cases where it's not certain whether the thing was cleared already.
	pub fn tryIncreaseRefCount(self: *ChunkMesh) bool {
		var prevVal = self.refCount.load(.monotonic);
		while(prevVal != 0) {
			prevVal = self.refCount.cmpxchgWeak(prevVal, prevVal + 1, .monotonic, .monotonic) orelse return true;
		}
		return false;
	}

	pub fn decreaseRefCount(self: *ChunkMesh) void {
		const prevVal = self.refCount.fetchSub(1, .monotonic);
		std.debug.assert(prevVal != 0);
		if(prevVal == 1) {
			mesh_storage.addMeshToClearListAndDecreaseRefCount(self);
		}
	}

	pub fn scheduleLightRefreshAndDecreaseRefCount(self: *ChunkMesh) void {
		if(!self.needsLightRefresh.swap(true, .acq_rel)) {
			LightRefreshTask.scheduleAndDecreaseRefCount(self);
		} else {
			self.decreaseRefCount();
		}
	}
	const LightRefreshTask = struct {
		mesh: *ChunkMesh,

		pub const vtable = main.utils.ThreadPool.VTable{
			.getPriority = @ptrCast(&getPriority),
			.isStillNeeded = @ptrCast(&isStillNeeded),
			.run = @ptrCast(&run),
			.clean = @ptrCast(&clean),
		};

		pub fn scheduleAndDecreaseRefCount(mesh: *ChunkMesh) void {
			const task = main.globalAllocator.create(LightRefreshTask);
			task.* = .{
				.mesh = mesh,
			};
			main.threadPool.addTask(task, &vtable);
		}

		pub fn getPriority(_: *LightRefreshTask) f32 {
			return 1000000;
		}

		pub fn isStillNeeded(_: *LightRefreshTask) bool {
			return true; // TODO: Is it worth checking for this?
		}

		pub fn run(self: *LightRefreshTask) void {
			if(self.mesh.needsLightRefresh.swap(false, .acq_rel)) {
				self.mesh.mutex.lock();
				self.mesh.finishData();
				self.mesh.mutex.unlock();
				mesh_storage.addToUpdateListAndDecreaseRefCount(self.mesh);
			} else {
				self.mesh.decreaseRefCount();
			}
			main.globalAllocator.destroy(self);
		}

		pub fn clean(self: *LightRefreshTask) void {
			self.mesh.decreaseRefCount();
			main.globalAllocator.destroy(self);
		}
	};

	pub fn isEmpty(self: *const ChunkMesh) bool {
		return self.opaqueMesh.vertexCount == 0 and self.transparentMesh.vertexCount == 0;
	}

	fn canBeSeenThroughOtherBlock(block: Block, other: Block, neighbor: u3) bool {
		const rotatedModel = blocks.meshes.model(block);
		const model = &models.models.items[rotatedModel];
		_ = model; // TODO: Check if the neighbor model occludes this one. (maybe not that relevant)
		return block.typ != 0 and (
			other.typ == 0
			or (!std.meta.eql(block, other) and other.viewThrough())
			or !models.models.items[blocks.meshes.model(other)].isNeighborOccluded[neighbor ^ 1]
		);
	}

	fn initLight(self: *ChunkMesh) void {
		self.mutex.lock();
		var lightEmittingBlocks = main.List([3]u8).init(main.stackAllocator);
		defer lightEmittingBlocks.deinit();
		var x: u8 = 0;
		while(x < chunk.chunkSize): (x += 1) {
			var y: u8 = 0;
			while(y < chunk.chunkSize): (y += 1) {
				var z: u8 = 0;
				while(z < chunk.chunkSize): (z += 1) {
					const block = (&self.chunk.blocks)[chunk.getIndex(x, y, z)]; // ← a temporary fix to a compiler performance bug. TODO: check if this was fixed.
					if(block.light() != 0) lightEmittingBlocks.append(.{x, y, z});
				}
			}
		}
		self.mutex.unlock();
		self.lightingData[0].propagateLights(lightEmittingBlocks.items, true);
		sunLight: {
			var sunStarters: [chunk.chunkSize*chunk.chunkSize][3]u8 = undefined;
			var index: usize = 0;
			const lightStartMap = mesh_storage.getLightMapPieceAndIncreaseRefCount(self.pos.wx, self.pos.wy, self.pos.voxelSize) orelse break :sunLight;
			defer lightStartMap.decreaseRefCount();
			x = 0;
			while(x < chunk.chunkSize): (x += 1) {
				var y: u8 = 0;
				while(y < chunk.chunkSize): (y += 1) {
					const startHeight: i32 = lightStartMap.getHeight(self.pos.wx + x*self.pos.voxelSize, self.pos.wy + y*self.pos.voxelSize);
					const relHeight = startHeight -% self.pos.wz;
					if(relHeight < chunk.chunkSize*self.pos.voxelSize) {
						sunStarters[index] = .{x, y, chunk.chunkSize-1};
						index += 1;
					}
				}
			}
			self.lightingData[1].propagateLights(sunStarters[0..index], true);
		}
	}

	pub fn generateLightingData(self: *ChunkMesh) error{AlreadyStored}!void {
		self.mutex.lock();
		self.opaqueMesh.reset();
		self.transparentMesh.reset();
		self.mutex.unlock();
		try mesh_storage.addMeshToStorage(self);

		self.initLight();

		self.mutex.lock();
		self.finishedLighting = true;
		self.mutex.unlock();

		// Only generate a mesh if the surrounding 27 chunks finished the light generation steps.
		var dx: i32 = -1;
		while(dx <= 1): (dx += 1) {
			var dy: i32 = -1;
			while(dy <= 1): (dy += 1) {
				var dz: i32 = -1;
				while(dz <= 1): (dz += 1) {
					var pos = self.pos;
					pos.wx +%= pos.voxelSize*chunk.chunkSize*dx;
					pos.wy +%= pos.voxelSize*chunk.chunkSize*dy;
					pos.wz +%= pos.voxelSize*chunk.chunkSize*dz;
					const neighborMesh = mesh_storage.getMeshAndIncreaseRefCount(pos) orelse continue;
					defer neighborMesh.decreaseRefCount();

					const shiftSelf: u5 = @intCast(((dx + 1)*3 + dy + 1)*3 + dz + 1);
					const shiftOther: u5 = @intCast(((-dx + 1)*3 + -dy + 1)*3 + -dz + 1);
					if(neighborMesh.litNeighbors.fetchOr(@as(u27, 1) << shiftOther, .monotonic) ^ @as(u27, 1) << shiftOther == ~@as(u27, 0)) { // Trigger mesh creation for neighbor
						neighborMesh.generateMesh();
					}
					neighborMesh.mutex.lock();
					const neighborFinishedLighting = neighborMesh.finishedLighting;
					neighborMesh.mutex.unlock();
					if(neighborFinishedLighting and self.litNeighbors.fetchOr(@as(u27, 1) << shiftSelf, .monotonic) ^ @as(u27, 1) << shiftSelf == ~@as(u27, 0)) {
						self.generateMesh();
					}
				}
			}
		}
	}

	pub fn generateMesh(self: *ChunkMesh) void {
		self.mutex.lock();
		var n: u32 = 0;
		var x: u8 = 0;
		while(x < chunk.chunkSize): (x += 1) {
			var y: u8 = 0;
			while(y < chunk.chunkSize): (y += 1) {
				var z: u8 = 0;
				while(z < chunk.chunkSize): (z += 1) {
					const block = (&self.chunk.blocks)[chunk.getIndex(x, y, z)]; // ← a temporary fix to a compiler performance bug. TODO: check if this was fixed.
					if(block.typ == 0) continue;
					// Check all neighbors:
					for(chunk.Neighbors.iterable) |i| {
						n += 1;
						const x2 = x + chunk.Neighbors.relX[i];
						const y2 = y + chunk.Neighbors.relY[i];
						const z2 = z + chunk.Neighbors.relZ[i];
						if(x2&chunk.chunkMask != x2 or y2&chunk.chunkMask != y2 or z2&chunk.chunkMask != z2) continue; // Neighbor is outside the chunk.
						const neighborBlock = (&self.chunk.blocks)[chunk.getIndex(x2, y2, z2)]; // ← a temporary fix to a compiler performance bug. TODO: check if this was fixed.
						if(canBeSeenThroughOtherBlock(block, neighborBlock, i)) {
							if(block.transparent()) {
								if(block.hasBackFace()) {
									self.transparentMesh.appendNeighborFacingQuadsToCore(block, i ^ 1, x, y, z, true);
								}
								self.transparentMesh.appendNeighborFacingQuadsToCore(block, i, x2, y2, z2, false);
							} else {
								self.opaqueMesh.appendNeighborFacingQuadsToCore(block, i, x2, y2, z2, false);
							}
						}
					}
					if(block.transparent()) {
						self.transparentMesh.appendInternalQuadsToCore(block, x, y, z, false);
					} else {
						self.opaqueMesh.appendInternalQuadsToCore(block, x, y, z, false);
					}
				}
			}
		}
		// Check out the borders:
		x = 0;
		while(x < chunk.chunkSize): (x += 1) {
			var y: u8 = 0;
			while(y < chunk.chunkSize): (y += 1) {
				self.chunkBorders[chunk.Neighbors.dirNegX].adjustToBlock((&self.chunk.blocks)[chunk.getIndex(0, x, y)], .{0, x, y}, chunk.Neighbors.dirNegX); // TODO: Wait for the compiler bug to get fixed.
				self.chunkBorders[chunk.Neighbors.dirPosX].adjustToBlock((&self.chunk.blocks)[chunk.getIndex(chunk.chunkSize-1, x, y)], .{chunk.chunkSize, x, y}, chunk.Neighbors.dirPosX); // TODO: Wait for the compiler bug to get fixed.
				self.chunkBorders[chunk.Neighbors.dirNegY].adjustToBlock((&self.chunk.blocks)[chunk.getIndex(x, 0, y)], .{x, 0, y}, chunk.Neighbors.dirNegY); // TODO: Wait for the compiler bug to get fixed.
				self.chunkBorders[chunk.Neighbors.dirPosY].adjustToBlock((&self.chunk.blocks)[chunk.getIndex(x, chunk.chunkSize-1, y)], .{x, chunk.chunkSize, y}, chunk.Neighbors.dirPosY); // TODO: Wait for the compiler bug to get fixed.
				self.chunkBorders[chunk.Neighbors.dirDown].adjustToBlock((&self.chunk.blocks)[chunk.getIndex(x, y, 0)], .{x, y, 0}, chunk.Neighbors.dirDown); // TODO: Wait for the compiler bug to get fixed.
				self.chunkBorders[chunk.Neighbors.dirUp].adjustToBlock((&self.chunk.blocks)[chunk.getIndex(x, y, chunk.chunkSize-1)], .{x, y, chunk.chunkSize}, chunk.Neighbors.dirUp); // TODO: Wait for the compiler bug to get fixed.
			}
		}
		self.mutex.unlock();

		self.finishNeighbors();
	}

	pub fn updateBlock(self: *ChunkMesh, _x: i32, _y: i32, _z: i32, _newBlock: Block) void {
		const x = _x & chunk.chunkMask;
		const y = _y & chunk.chunkMask;
		const z = _z & chunk.chunkMask;
		var newBlock = _newBlock;
		var neighborBlocks: [6]Block = undefined;
		@memset(&neighborBlocks, .{.typ = 0, .data = 0});
		for(chunk.Neighbors.iterable) |neighbor| {
			const nx = x + chunk.Neighbors.relX[neighbor];
			const ny = y + chunk.Neighbors.relY[neighbor];
			const nz = z + chunk.Neighbors.relZ[neighbor];
			if(nx & chunk.chunkMask != nx or ny & chunk.chunkMask != ny or nz & chunk.chunkMask != nz) {
				const neighborChunkMesh = mesh_storage.getNeighborAndIncreaseRefCount(self.pos, self.pos.voxelSize, neighbor) orelse continue;
				defer neighborChunkMesh.decreaseRefCount();
				const index = chunk.getIndex(nx & chunk.chunkMask, ny & chunk.chunkMask, nz & chunk.chunkMask);
				neighborChunkMesh.mutex.lock();
				var neighborBlock = neighborChunkMesh.chunk.blocks[index];
				if(neighborBlock.mode().dependsOnNeighbors) {
					if(neighborBlock.mode().updateData(&neighborBlock, neighbor ^ 1, newBlock)) {
						neighborChunkMesh.chunk.blocks[index] = neighborBlock;
						neighborChunkMesh.opaqueMesh.coreFaces.clearRetainingCapacity();
						neighborChunkMesh.transparentMesh.coreFaces.clearRetainingCapacity();
						neighborChunkMesh.mutex.unlock();
						neighborChunkMesh.generateMesh();
						neighborChunkMesh.mutex.lock();
					}
				}
				neighborChunkMesh.mutex.unlock();
				neighborBlocks[neighbor] = neighborBlock;
			} else {
				const index = chunk.getIndex(nx, ny, nz);
				self.mutex.lock();
				var neighborBlock = self.chunk.blocks[index];
				if(neighborBlock.mode().dependsOnNeighbors) {
					if(neighborBlock.mode().updateData(&neighborBlock, neighbor ^ 1, newBlock)) {
						self.chunk.blocks[index] = neighborBlock;
					}
				}
				self.mutex.unlock();
				neighborBlocks[neighbor] = neighborBlock;
			}
		}
		if(newBlock.mode().dependsOnNeighbors) {
			for(chunk.Neighbors.iterable) |neighbor| {
				_ = newBlock.mode().updateData(&newBlock, neighbor, neighborBlocks[neighbor]);
			}
		}
		self.mutex.lock();
		self.chunk.blocks[chunk.getIndex(x, y, z)] = newBlock;
		self.mutex.unlock();
		for(self.lightingData[0..]) |lightingData| {
			lightingData.propagateLightsDestructive(&.{.{@intCast(x), @intCast(y), @intCast(z)}});
		}
		if(newBlock.light() != 0) {
			self.lightingData[0].propagateLights(&.{.{@intCast(x), @intCast(y), @intCast(z)}}, false);
		}
		self.mutex.lock();
		defer self.mutex.unlock();
		// Update neighbor chunks:
		if(x == 0) {
			self.lastNeighborsHigherLod[chunk.Neighbors.dirNegX] = null;
			self.lastNeighborsSameLod[chunk.Neighbors.dirNegX] = null;
		} else if(x == 31) {
			self.lastNeighborsHigherLod[chunk.Neighbors.dirPosX] = null;
			self.lastNeighborsSameLod[chunk.Neighbors.dirPosX] = null;
		}
		if(y == 0) {
			self.lastNeighborsHigherLod[chunk.Neighbors.dirNegY] = null;
			self.lastNeighborsSameLod[chunk.Neighbors.dirNegY] = null;
		} else if(y == 31) {
			self.lastNeighborsHigherLod[chunk.Neighbors.dirPosY] = null;
			self.lastNeighborsSameLod[chunk.Neighbors.dirPosY] = null;
		}
		if(z == 0) {
			self.lastNeighborsHigherLod[chunk.Neighbors.dirDown] = null;
			self.lastNeighborsSameLod[chunk.Neighbors.dirDown] = null;
		} else if(z == 31) {
			self.lastNeighborsHigherLod[chunk.Neighbors.dirUp] = null;
			self.lastNeighborsSameLod[chunk.Neighbors.dirUp] = null;
		}
		self.opaqueMesh.coreFaces.clearRetainingCapacity();
		self.transparentMesh.coreFaces.clearRetainingCapacity();
		self.mutex.unlock();
		self.generateMesh(); // TODO: Batch mesh updates instead of applying them for each block changes.
		self.mutex.lock();
		self.uploadData();
	}

	fn clearNeighbor(self: *ChunkMesh, neighbor: u3, comptime isLod: bool) void {
		self.opaqueMesh.clearNeighbor(neighbor, isLod);
		self.transparentMesh.clearNeighbor(neighbor, isLod);
	}

	pub fn finishData(self: *ChunkMesh) void {
		std.debug.assert(!self.mutex.tryLock());
		self.opaqueMesh.finish(self);
		self.transparentMesh.finish(self);
	}

	pub fn uploadData(self: *ChunkMesh) void {
		self.opaqueMesh.uploadData(self.isNeighborLod);
		self.transparentMesh.uploadData(self.isNeighborLod);
	}

	pub fn changeLodBorders(self: *ChunkMesh, isNeighborLod: [6]bool) void {
		if(!std.meta.eql(isNeighborLod, self.isNeighborLod)) {
			self.isNeighborLod = isNeighborLod;
			self.uploadData();
		}
	}

	fn deadlockFreeDoubleLock(m1: *std.Thread.Mutex, m2: *std.Thread.Mutex) void {
		if(@intFromPtr(m1) < @intFromPtr(m2)) {
			m1.lock();
			m2.lock();
		} else {
			m2.lock();
			m1.lock();
		}
	}

	fn finishNeighbors(self: *ChunkMesh) void {
		for(chunk.Neighbors.iterable) |neighbor| {
			const nullNeighborMesh = mesh_storage.getNeighborAndIncreaseRefCount(self.pos, self.pos.voxelSize, neighbor);
			if(nullNeighborMesh) |neighborMesh| sameLodBlock: {
				defer neighborMesh.decreaseRefCount();
				std.debug.assert(neighborMesh != self);
				deadlockFreeDoubleLock(&self.mutex, &neighborMesh.mutex);
				defer self.mutex.unlock();
				defer neighborMesh.mutex.unlock();
				if(self.lastNeighborsSameLod[neighbor] == neighborMesh) break :sameLodBlock;
				self.lastNeighborsSameLod[neighbor] = neighborMesh;
				neighborMesh.lastNeighborsSameLod[neighbor ^ 1] = self;
				self.clearNeighbor(neighbor, false);
				neighborMesh.clearNeighbor(neighbor ^ 1, false);
				const x3: i32 = if(neighbor & 1 == 0) chunk.chunkMask else 0;
				var x1: i32 = 0;
				while(x1 < chunk.chunkSize): (x1 += 1) {
					var x2: i32 = 0;
					while(x2 < chunk.chunkSize): (x2 += 1) {
						var x: i32 = undefined;
						var y: i32 = undefined;
						var z: i32 = undefined;
						if(chunk.Neighbors.relX[neighbor] != 0) {
							x = x3;
							y = x1;
							z = x2;
						} else if(chunk.Neighbors.relY[neighbor] != 0) {
							x = x1;
							y = x3;
							z = x2;
						} else {
							x = x2;
							y = x1;
							z = x3;
						}
						const otherX = x+%chunk.Neighbors.relX[neighbor] & chunk.chunkMask;
						const otherY = y+%chunk.Neighbors.relY[neighbor] & chunk.chunkMask;
						const otherZ = z+%chunk.Neighbors.relZ[neighbor] & chunk.chunkMask;
						const block = (&self.chunk.blocks)[chunk.getIndex(x, y, z)]; // ← a temporary fix to a compiler performance bug. TODO: check if this was fixed.
						const otherBlock = (&neighborMesh.chunk.blocks)[chunk.getIndex(otherX, otherY, otherZ)]; // ← a temporary fix to a compiler performance bug. TODO: check if this was fixed.
						if(canBeSeenThroughOtherBlock(block, otherBlock, neighbor)) {
							if(block.transparent()) {
								if(block.hasBackFace()) {
									self.transparentMesh.appendNeighborFacingQuadsToNeighbor(block, neighbor ^ 1, x, y, z, true, false);
								}
								neighborMesh.transparentMesh.appendNeighborFacingQuadsToNeighbor(block, neighbor, otherX, otherY, otherZ, false, false);
							} else {
								neighborMesh.opaqueMesh.appendNeighborFacingQuadsToNeighbor(block, neighbor, otherX, otherY, otherZ, false, false);
							}
						}
						if(canBeSeenThroughOtherBlock(otherBlock, block, neighbor ^ 1)) {
							if(otherBlock.transparent()) {
								if(otherBlock.hasBackFace()) {
									neighborMesh.transparentMesh.appendNeighborFacingQuadsToNeighbor(otherBlock, neighbor, otherX, otherY, otherZ, true, false);
								}
								self.transparentMesh.appendNeighborFacingQuadsToNeighbor(otherBlock, neighbor ^ 1, x, y, z, false, false);
							} else {
								self.opaqueMesh.appendNeighborFacingQuadsToNeighbor(otherBlock, neighbor ^ 1, x, y, z, false, false);
							}
						}
					}
				}
				_ = neighborMesh.needsLightRefresh.swap(false, .acq_rel);
				neighborMesh.finishData();
				neighborMesh.increaseRefCount();
				mesh_storage.addToUpdateListAndDecreaseRefCount(neighborMesh);
			} else {
				self.mutex.lock();
				defer self.mutex.unlock();
				if(self.lastNeighborsSameLod[neighbor] != null) {
					self.clearNeighbor(neighbor, false);
					self.lastNeighborsSameLod[neighbor] = null;
				}
			}
			// lod border:
			if(self.pos.voxelSize == 1 << settings.highestLOD) continue;
			const neighborMesh = mesh_storage.getNeighborAndIncreaseRefCount(self.pos, 2*self.pos.voxelSize, neighbor) orelse {
				self.mutex.lock();
				defer self.mutex.unlock();
				if(self.lastNeighborsHigherLod[neighbor] != null) {
					self.clearNeighbor(neighbor, true);
					self.lastNeighborsHigherLod[neighbor] = null;
				}
				continue;
			};
			defer neighborMesh.decreaseRefCount();
			deadlockFreeDoubleLock(&self.mutex, &neighborMesh.mutex);
			defer self.mutex.unlock();
			defer neighborMesh.mutex.unlock();
			if(self.lastNeighborsHigherLod[neighbor] == neighborMesh) continue;
			self.lastNeighborsHigherLod[neighbor] = neighborMesh;
			self.clearNeighbor(neighbor, true);
			const x3: i32 = if(neighbor & 1 == 0) chunk.chunkMask else 0;
			const offsetX = @divExact(self.pos.wx, self.pos.voxelSize) & chunk.chunkSize;
			const offsetY = @divExact(self.pos.wy, self.pos.voxelSize) & chunk.chunkSize;
			const offsetZ = @divExact(self.pos.wz, self.pos.voxelSize) & chunk.chunkSize;
			var x1: i32 = 0;
			while(x1 < chunk.chunkSize): (x1 += 1) {
				var x2: i32 = 0;
				while(x2 < chunk.chunkSize): (x2 += 1) {
					var x: i32 = undefined;
					var y: i32 = undefined;
					var z: i32 = undefined;
					if(chunk.Neighbors.relX[neighbor] != 0) {
						x = x3;
						y = x1;
						z = x2;
					} else if(chunk.Neighbors.relY[neighbor] != 0) {
						x = x1;
						y = x3;
						z = x2;
					} else {
						x = x2;
						y = x1;
						z = x3;
					}
					const otherX = (x+%chunk.Neighbors.relX[neighbor]+%offsetX >> 1) & chunk.chunkMask;
					const otherY = (y+%chunk.Neighbors.relY[neighbor]+%offsetY >> 1) & chunk.chunkMask;
					const otherZ = (z+%chunk.Neighbors.relZ[neighbor]+%offsetZ >> 1) & chunk.chunkMask;
					const block = (&self.chunk.blocks)[chunk.getIndex(x, y, z)]; // ← a temporary fix to a compiler performance bug. TODO: check if this was fixed.
					const otherBlock = (&neighborMesh.chunk.blocks)[chunk.getIndex(otherX, otherY, otherZ)]; // ← a temporary fix to a compiler performance bug. TODO: check if this was fixed.
					if(canBeSeenThroughOtherBlock(otherBlock, block, neighbor ^ 1)) {
						if(otherBlock.transparent()) {
							self.transparentMesh.appendNeighborFacingQuadsToNeighbor(otherBlock, neighbor ^ 1, x, y, z, false, true);
						} else {
							self.opaqueMesh.appendNeighborFacingQuadsToNeighbor(otherBlock, neighbor ^ 1, x, y, z, false, true);
						}
					}
					if(block.hasBackFace()) {
						if(canBeSeenThroughOtherBlock(block, otherBlock, neighbor)) {
							self.transparentMesh.appendNeighborFacingQuadsToNeighbor(block, neighbor ^ 1, x, y, z, true, true);
						}
					}
				}
			}
		}
		self.mutex.lock();
		defer self.mutex.unlock();
		_ = self.needsLightRefresh.swap(false, .acq_rel);
		self.finishData();
		mesh_storage.finishMesh(self);
	}

	pub fn render(self: *ChunkMesh, playerPosition: Vec3d) void {
		if(self.opaqueMesh.vertexCount == 0) return;
		c.glUniform3f(
			uniforms.modelPosition,
			@floatCast(@as(f64, @floatFromInt(self.pos.wx)) - playerPosition[0]),
			@floatCast(@as(f64, @floatFromInt(self.pos.wy)) - playerPosition[1]),
			@floatCast(@as(f64, @floatFromInt(self.pos.wz)) - playerPosition[2])
		);
		c.glUniform1i(uniforms.visibilityMask, self.visibilityMask);
		c.glUniform1i(uniforms.voxelSize, self.pos.voxelSize);
		quadsDrawn += self.opaqueMesh.vertexCount/6;
		c.glDrawElementsBaseVertex(c.GL_TRIANGLES, self.opaqueMesh.vertexCount, c.GL_UNSIGNED_INT, null, self.opaqueMesh.bufferAllocation.start*4);
	}

	pub fn renderTransparent(self: *ChunkMesh, playerPosition: Vec3d) void {
		if(self.transparentMesh.vertexCount == 0) return;

		var needsUpdate: bool = false;
		if(self.transparentMesh.wasChanged) {
			self.transparentMesh.wasChanged = false;
			self.transparentMesh.mutex.lock();
			defer self.transparentMesh.mutex.unlock();
			var len: usize = self.transparentMesh.coreLen;
			var offset: usize = self.transparentMesh.coreLen;
			var list: [6][]FaceData = undefined;
			for(0..6) |i| {
				const neighborLen = self.transparentMesh.sameLodLens[i];
				if(!self.isNeighborLod[i]) {
					list[i] = self.transparentMesh.completeList[offset..][0..neighborLen];
					len += neighborLen;
				}
				offset += neighborLen;
			}
			for(0..6) |i| {
				const neighborLen = self.transparentMesh.higherLodLens[i];
				if(self.isNeighborLod[i]) {
					list[i] = self.transparentMesh.completeList[offset..][0..neighborLen];
					len += neighborLen;
				}
				offset += neighborLen;
			}
			self.sortingOutputBuffer = main.globalAllocator.realloc(self.sortingOutputBuffer, len);
			self.currentSorting = main.globalAllocator.realloc(self.currentSorting, len);
			for(0..self.transparentMesh.coreLen) |i| {
				self.currentSorting[i].face = self.transparentMesh.completeList[i];
			}
			offset = self.transparentMesh.coreLen;
			for(0..6) |n| {
				for(0..list[n].len) |i| {
					self.currentSorting[offset + i].face = list[n][i];
				}
				offset += list[n].len;
			}

			needsUpdate = true;
		}

		var relativePos = Vec3d {
			@as(f64, @floatFromInt(self.pos.wx)) - playerPosition[0],
			@as(f64, @floatFromInt(self.pos.wy)) - playerPosition[1],
			@as(f64, @floatFromInt(self.pos.wz)) - playerPosition[2]
		}/@as(Vec3d, @splat(@as(f64, @floatFromInt(self.pos.voxelSize))));
		relativePos = @min(relativePos, @as(Vec3d, @splat(0)));
		relativePos = @max(relativePos, @as(Vec3d, @splat(-32)));
		const updatePos: Vec3i = @intFromFloat(relativePos);
		if(@reduce(.Or, updatePos != self.lastTransparentUpdatePos)) {
			self.lastTransparentUpdatePos = updatePos;
			needsUpdate = true;
		}
		if(needsUpdate) {
			for(self.currentSorting) |*val| {
				val.update(
					updatePos[0],
					updatePos[1],
					updatePos[2],
				);
			}

			// Sort by back vs front face:
			{
				var backFaceStart: usize = 0;
				var i: usize = 0;
				var culledStart: usize = self.currentSorting.len;
				while(culledStart > 0) {
					if(!self.currentSorting[culledStart-1].shouldBeCulled) {
						break;
					}
					culledStart -= 1;
				}
				while(i < culledStart): (i += 1) {
					if(self.currentSorting[i].shouldBeCulled) {
						culledStart -= 1;
						std.mem.swap(SortingData, &self.currentSorting[i], &self.currentSorting[culledStart]);
						while(culledStart > 0) {
							if(!self.currentSorting[culledStart-1].shouldBeCulled) {
								break;
							}
							culledStart -= 1;
						}
					}
					if(!self.currentSorting[i].isBackFace) {
						std.mem.swap(SortingData, &self.currentSorting[i], &self.currentSorting[backFaceStart]);
						backFaceStart += 1;
					}
				}
				self.culledSortingCount = @intCast(culledStart);
			}

			// Sort it using bucket sort:
			var buckets: [34*3]u32 = undefined;
			@memset(&buckets, 0);
			for(self.currentSorting[0..self.culledSortingCount]) |val| {
				buckets[34*3 - 1 - val.distance] += 1;
			}
			var prefixSum: u32 = 0;
			for(&buckets) |*val| {
				const copy = val.*;
				val.* = prefixSum;
				prefixSum += copy;
			}
			// Move it over into a new buffer:
			for(0..self.culledSortingCount) |i| {
				const bucket = 34*3 - 1 - self.currentSorting[i].distance;
				self.sortingOutputBuffer[buckets[bucket]] = self.currentSorting[i].face;
				buckets[bucket] += 1;
			}

			// Upload:
			faceBuffer.uploadData(self.sortingOutputBuffer[0..self.culledSortingCount], &self.transparentMesh.bufferAllocation);
		}

		c.glUniform3f(
			transparentUniforms.modelPosition,
			@floatCast(@as(f64, @floatFromInt(self.pos.wx)) - playerPosition[0]),
			@floatCast(@as(f64, @floatFromInt(self.pos.wy)) - playerPosition[1]),
			@floatCast(@as(f64, @floatFromInt(self.pos.wz)) - playerPosition[2])
		);
		c.glUniform1i(transparentUniforms.visibilityMask, self.visibilityMask);
		c.glUniform1i(transparentUniforms.voxelSize, self.pos.voxelSize);
		transparentQuadsDrawn += self.culledSortingCount;
		c.glDrawElementsBaseVertex(c.GL_TRIANGLES, self.culledSortingCount*6, c.GL_UNSIGNED_INT, null, self.transparentMesh.bufferAllocation.start*4);
	}
};