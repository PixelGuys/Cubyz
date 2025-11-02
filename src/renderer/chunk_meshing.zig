const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("main");
const blocks = main.blocks;
const Block = blocks.Block;
const chunk = main.chunk;
const game = main.game;
const models = main.models;
const QuadIndex = models.QuadIndex;
const renderer = main.renderer;
const graphics = main.graphics;
const c = graphics.c;
const SSBO = graphics.SSBO;
const lighting = @import("lighting.zig");
const settings = main.settings;
const vec = main.vec;
const Vec2f = vec.Vec2f;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const Mat4f = vec.Mat4f;
const gpu_performance_measuring = main.gui.windowlist.gpu_performance_measuring;

const mesh_storage = @import("mesh_storage.zig");

var pipeline: graphics.Pipeline = undefined;
var transparentPipeline: graphics.Pipeline = undefined;
const UniformStruct = struct {
	projectionMatrix: c_int,
	viewMatrix: c_int,
	playerPositionInteger: c_int,
	playerPositionFraction: c_int,
	screenSize: c_int,
	ambientLight: c_int,
	contrast: c_int,
	@"fog.color": c_int,
	@"fog.density": c_int,
	@"fog.fogLower": c_int,
	@"fog.fogHigher": c_int,
	reflectionMapSize: c_int,
	lodDistance: c_int,
	zNear: c_int,
	zFar: c_int,
};
pub var uniforms: UniformStruct = undefined;
pub var transparentUniforms: UniformStruct = undefined;
pub var commandPipeline: graphics.ComputePipeline = undefined;
pub var commandUniforms: struct {
	chunkIDIndex: c_int,
	commandIndexStart: c_int,
	size: c_int,
	isTransparent: c_int,
	playerPositionInteger: c_int,
	onlyDrawPreviouslyInvisible: c_int,
	lodDistance: c_int,
} = undefined;
pub var occlusionTestPipeline: graphics.Pipeline = undefined;
pub var occlusionTestUniforms: struct {
	projectionMatrix: c_int,
	viewMatrix: c_int,
	playerPositionInteger: c_int,
	playerPositionFraction: c_int,
} = undefined;
pub var vao: c_uint = undefined;
var vbo: c_uint = undefined;
pub var faceBuffers: [settings.highestSupportedLod + 1]graphics.LargeBuffer(FaceData) = undefined;
pub var lightBuffers: [settings.highestSupportedLod + 1]graphics.LargeBuffer(u32) = undefined;
pub var chunkBuffer: graphics.LargeBuffer(ChunkData) = undefined;
pub var commandBuffer: graphics.LargeBuffer(IndirectData) = undefined;
pub var chunkIDBuffer: graphics.LargeBuffer(u32) = undefined;
pub var quadsDrawn: usize = 0;
pub var transparentQuadsDrawn: usize = 0;
pub const maxQuadsInIndexBuffer = 3 << (3*chunk.chunkShift); // maximum 3 faces/block

pub fn init() void {
	lighting.init();
	pipeline = graphics.Pipeline.init(
		"assets/cubyz/shaders/chunks/chunk_vertex.vert",
		"assets/cubyz/shaders/chunks/chunk_fragment.frag",
		"",
		&uniforms,
		.{},
		.{.depthTest = true, .depthWrite = true},
		.{.attachments = &.{.noBlending}},
	);
	transparentPipeline = graphics.Pipeline.init(
		"assets/cubyz/shaders/chunks/chunk_vertex.vert",
		"assets/cubyz/shaders/chunks/transparent_fragment.frag",
		"#define transparent\n",
		&transparentUniforms,
		.{},
		.{.depthTest = true, .depthWrite = false, .depthCompare = .lessOrEqual},
		.{.attachments = &.{.{
			.srcColorBlendFactor = .one,
			.dstColorBlendFactor = .src1Color,
			.colorBlendOp = .add,
			.srcAlphaBlendFactor = .one,
			.dstAlphaBlendFactor = .src1Alpha,
			.alphaBlendOp = .add,
		}}},
	);
	commandPipeline = graphics.ComputePipeline.init("assets/cubyz/shaders/chunks/fillIndirectBuffer.comp", "", &commandUniforms);
	occlusionTestPipeline = graphics.Pipeline.init(
		"assets/cubyz/shaders/chunks/occlusionTestVertex.vert",
		"assets/cubyz/shaders/chunks/occlusionTestFragment.frag",
		"",
		&occlusionTestUniforms,
		.{},
		.{.depthTest = true, .depthWrite = false},
		.{.attachments = &.{.{
			.enabled = false,
			.srcColorBlendFactor = undefined,
			.dstColorBlendFactor = undefined,
			.colorBlendOp = undefined,
			.srcAlphaBlendFactor = undefined,
			.dstAlphaBlendFactor = undefined,
			.alphaBlendOp = undefined,
			.colorWriteMask = .none,
		}}},
	);

	var rawData: [6*maxQuadsInIndexBuffer]u32 = undefined;
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

	for(0..settings.highestSupportedLod + 1) |i| {
		faceBuffers[i].init(main.globalAllocator, 1 << 20, 3);
		lightBuffers[i].init(main.globalAllocator, 1 << 20, 10);
	}
	chunkBuffer.init(main.globalAllocator, 1 << 20, 6);
	commandBuffer.init(main.globalAllocator, 1 << 20, 8);
	chunkIDBuffer.init(main.globalAllocator, 1 << 20, 9);
}

pub fn deinit() void {
	lighting.deinit();
	pipeline.deinit();
	transparentPipeline.deinit();
	occlusionTestPipeline.deinit();
	commandPipeline.deinit();
	c.glDeleteVertexArrays(1, &vao);
	c.glDeleteBuffers(1, &vbo);
	for(0..settings.highestSupportedLod + 1) |i| {
		faceBuffers[i].deinit();
		lightBuffers[i].deinit();
	}
	chunkBuffer.deinit();
	commandBuffer.deinit();
	chunkIDBuffer.deinit();
}

pub fn beginRender() void {
	for(0..settings.highestSupportedLod + 1) |i| {
		faceBuffers[i].beginRender();
		lightBuffers[i].beginRender();
	}
	chunkBuffer.beginRender();
	commandBuffer.beginRender();
	chunkIDBuffer.beginRender();
}

pub fn endRender() void {
	for(0..settings.highestSupportedLod + 1) |i| {
		faceBuffers[i].endRender();
		lightBuffers[i].endRender();
	}
	chunkBuffer.endRender();
	commandBuffer.endRender();
	chunkIDBuffer.endRender();
}

fn bindCommonUniforms(locations: *UniformStruct, projMatrix: Mat4f, ambient: Vec3f, playerPos: Vec3d) void {
	c.glUniformMatrix4fv(locations.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&projMatrix));

	c.glUniform1f(locations.reflectionMapSize, renderer.reflectionCubeMapSize);

	c.glUniform1f(locations.contrast, main.settings.blockContrast);

	c.glUniform1f(locations.lodDistance, main.settings.@"lod0.5Distance");

	c.glUniformMatrix4fv(locations.viewMatrix, 1, c.GL_TRUE, @ptrCast(&game.camera.viewMatrix));

	c.glUniform3f(locations.ambientLight, ambient[0], ambient[1], ambient[2]);

	c.glUniform1f(locations.zNear, renderer.zNear);
	c.glUniform1f(locations.zFar, renderer.zFar);

	c.glUniform3i(locations.playerPositionInteger, @intFromFloat(@floor(playerPos[0])), @intFromFloat(@floor(playerPos[1])), @intFromFloat(@floor(playerPos[2])));
	c.glUniform3f(locations.playerPositionFraction, @floatCast(@mod(playerPos[0], 1)), @floatCast(@mod(playerPos[1], 1)), @floatCast(@mod(playerPos[2], 1)));
}

pub fn bindShaderAndUniforms(projMatrix: Mat4f, ambient: Vec3f, playerPos: Vec3d) void {
	pipeline.bind(null);

	bindCommonUniforms(&uniforms, projMatrix, ambient, playerPos);

	c.glBindVertexArray(vao);
}

pub fn bindTransparentShaderAndUniforms(projMatrix: Mat4f, ambient: Vec3f, playerPos: Vec3d) void {
	transparentPipeline.bind(null);

	c.glUniform3fv(transparentUniforms.@"fog.color", 1, @ptrCast(&game.fog.skyColor));
	c.glUniform1f(transparentUniforms.@"fog.density", game.fog.density);
	c.glUniform1f(transparentUniforms.@"fog.fogLower", game.fog.fogLower);
	c.glUniform1f(transparentUniforms.@"fog.fogHigher", game.fog.fogHigher);

	bindCommonUniforms(&transparentUniforms, projMatrix, ambient, playerPos);

	c.glBindVertexArray(vao);
}

fn bindBuffers(lod: usize) void {
	faceBuffers[lod].ssbo.bind(faceBuffers[lod].binding);
	lightBuffers[lod].ssbo.bind(lightBuffers[lod].binding);
}

pub fn drawChunksIndirect(chunkIds: *const [main.settings.highestSupportedLod + 1]main.List(u32), projMatrix: Mat4f, ambient: Vec3f, playerPos: Vec3d, transparent: bool) void {
	for(0..chunkIds.len) |i| {
		const lod = if(transparent) main.settings.highestSupportedLod - i else i;
		bindBuffers(lod);
		drawChunksOfLod(chunkIds[lod].items, projMatrix, ambient, playerPos, transparent);
	}
}

fn drawChunksOfLod(chunkIDs: []const u32, projMatrix: Mat4f, ambient: Vec3f, playerPos: Vec3d, transparent: bool) void {
	if(chunkIDs.len == 0) return;
	const drawCallsEstimate: u31 = @intCast(if(transparent) chunkIDs.len else chunkIDs.len*8);
	var chunkIDAllocation: main.graphics.SubAllocation = .{.start = 0, .len = 0};
	chunkIDBuffer.uploadData(chunkIDs, &chunkIDAllocation);
	defer chunkIDBuffer.free(chunkIDAllocation);
	const allocation = commandBuffer.rawAlloc(drawCallsEstimate);
	defer commandBuffer.free(allocation);
	commandPipeline.bind();
	c.glUniform1f(commandUniforms.lodDistance, main.settings.@"lod0.5Distance");
	c.glUniform1ui(commandUniforms.chunkIDIndex, chunkIDAllocation.start);
	c.glUniform1ui(commandUniforms.commandIndexStart, allocation.start);
	c.glUniform1ui(commandUniforms.size, @intCast(chunkIDs.len));
	c.glUniform1i(commandUniforms.isTransparent, @intFromBool(transparent));
	c.glUniform3i(commandUniforms.playerPositionInteger, @intFromFloat(@floor(playerPos[0])), @intFromFloat(@floor(playerPos[1])), @intFromFloat(@floor(playerPos[2])));
	if(!transparent) {
		c.glUniform1i(commandUniforms.onlyDrawPreviouslyInvisible, 0);
		c.glDispatchCompute(@intCast(@divFloor(chunkIDs.len + 63, 64)), 1, 1); // TODO: Replace with @divCeil once available
		c.glMemoryBarrier(c.GL_SHADER_STORAGE_BARRIER_BIT | c.GL_COMMAND_BARRIER_BIT);

		if(transparent) {
			bindTransparentShaderAndUniforms(projMatrix, ambient, playerPos);
		} else {
			bindShaderAndUniforms(projMatrix, ambient, playerPos);
		}
		c.glBindBuffer(c.GL_DRAW_INDIRECT_BUFFER, commandBuffer.ssbo.bufferID);
		c.glMultiDrawElementsIndirect(c.GL_TRIANGLES, c.GL_UNSIGNED_INT, @ptrFromInt(allocation.start*@sizeOf(IndirectData)), drawCallsEstimate, 0);
	}

	// Occlusion tests:
	occlusionTestPipeline.bind(null);
	c.glUniform3i(occlusionTestUniforms.playerPositionInteger, @intFromFloat(@floor(playerPos[0])), @intFromFloat(@floor(playerPos[1])), @intFromFloat(@floor(playerPos[2])));
	c.glUniform3f(occlusionTestUniforms.playerPositionFraction, @floatCast(@mod(playerPos[0], 1)), @floatCast(@mod(playerPos[1], 1)), @floatCast(@mod(playerPos[2], 1)));
	c.glUniformMatrix4fv(occlusionTestUniforms.projectionMatrix, 1, c.GL_TRUE, @ptrCast(&projMatrix));
	c.glUniformMatrix4fv(occlusionTestUniforms.viewMatrix, 1, c.GL_TRUE, @ptrCast(&game.camera.viewMatrix));
	c.glBindVertexArray(vao);
	c.glDrawElementsBaseVertex(c.GL_TRIANGLES, @intCast(6*6*chunkIDs.len), c.GL_UNSIGNED_INT, null, chunkIDAllocation.start*24);
	c.glMemoryBarrier(c.GL_SHADER_STORAGE_BARRIER_BIT);

	// Draw again:
	commandPipeline.bind();
	c.glUniform1i(commandUniforms.onlyDrawPreviouslyInvisible, 1);
	c.glDispatchCompute(@intCast(@divFloor(chunkIDs.len + 63, 64)), 1, 1); // TODO: Replace with @divCeil once available
	c.glMemoryBarrier(c.GL_SHADER_STORAGE_BARRIER_BIT | c.GL_COMMAND_BARRIER_BIT);

	if(transparent) {
		bindTransparentShaderAndUniforms(projMatrix, ambient, playerPos);
	} else {
		bindShaderAndUniforms(projMatrix, ambient, playerPos);
	}
	c.glBindBuffer(c.GL_DRAW_INDIRECT_BUFFER, commandBuffer.ssbo.bufferID);
	c.glMultiDrawElementsIndirect(c.GL_TRIANGLES, c.GL_UNSIGNED_INT, @ptrFromInt(allocation.start*@sizeOf(IndirectData)), drawCallsEstimate, 0);
}

pub const FaceData = extern struct {
	position: packed struct(u32) {
		x: u5,
		y: u5,
		z: u5,
		isBackFace: bool,
		lightIndex: u16 = 0,
	},
	blockAndQuad: packed struct(u32) {
		texture: u16,
		quadIndex: QuadIndex,
	},

	pub inline fn init(texture: u16, quadIndex: QuadIndex, x: i32, y: i32, z: i32, comptime backFace: bool) FaceData {
		return FaceData{
			.position = .{.x = @intCast(x), .y = @intCast(y), .z = @intCast(z), .isBackFace = backFace},
			.blockAndQuad = .{.texture = texture, .quadIndex = quadIndex},
		};
	}
};

pub const ChunkData = extern struct {
	position: Vec3i align(16),
	min: Vec3f align(16),
	max: Vec3f align(16),
	voxelSize: i32,
	lightStart: u32,
	vertexStartOpaque: u32,
	faceCountsByNormalOpaque: [14]u32,
	vertexStartTransparent: u32,
	vertexCountTransparent: u32,
	visibilityState: u32,
	oldVisibilityState: u32,
};

pub const IndirectData = extern struct {
	count: u32,
	instanceCount: u32,
	firstIndex: u32,
	baseVertex: i32,
	baseInstance: u32,
};

pub const PrimitiveMesh = struct { // MARK: PrimitiveMesh
	const FaceGroups = enum(u32) {
		core,
		neighbor0,
		neighbor1,
		neighbor2,
		neighbor3,
		neighbor4,
		neighbor5,
		neighborLod0,
		neighborLod1,
		neighborLod2,
		neighborLod3,
		neighborLod4,
		neighborLod5,
		optional,

		pub fn neighbor(n: main.chunk.Neighbor) FaceGroups {
			return @enumFromInt(@intFromEnum(FaceGroups.neighbor0) + @intFromEnum(n));
		}

		pub fn neighborLod(n: main.chunk.Neighbor) FaceGroups {
			return @enumFromInt(@intFromEnum(FaceGroups.neighborLod0) + @intFromEnum(n));
		}
	};
	completeList: main.MultiArray(FaceData, FaceGroups) = .{},
	lock: main.utils.ReadWriteLock = .{},
	bufferAllocation: graphics.SubAllocation = .{.start = 0, .len = 0},
	vertexCount: u31 = 0,
	byNormalCount: [14]u32 = @splat(0),
	wasChanged: bool = false,
	min: Vec3f = undefined,
	max: Vec3f = undefined,
	lod: u3,

	fn deinit(self: *PrimitiveMesh) void {
		faceBuffers[self.lod].free(self.bufferAllocation);
		self.completeList.deinit(main.globalAllocator);
	}

	fn replaceRange(self: *PrimitiveMesh, group: FaceGroups, items: []const FaceData) void {
		self.lock.lockWrite();
		self.completeList.replaceRange(main.globalAllocator, group, items);
		self.lock.unlockWrite();
	}

	fn finish(self: *PrimitiveMesh, parent: *ChunkMesh, lightList: *main.List(u32), lightMap: *std.AutoHashMap([4]u32, u16)) void {
		self.min = @splat(std.math.floatMax(f32));
		self.max = @splat(-std.math.floatMax(f32));

		self.lock.lockRead();
		for(self.completeList.getEverything()) |*face| {
			const light = getLight(parent, .{face.position.x, face.position.y, face.position.z}, face.blockAndQuad.texture, face.blockAndQuad.quadIndex);
			const result = lightMap.getOrPut(light) catch unreachable;
			if(!result.found_existing) {
				result.value_ptr.* = @intCast(lightList.items.len/4);
				lightList.appendSlice(&light);
			}
			face.position.lightIndex = result.value_ptr.*;
			const basePos: Vec3f = .{
				@floatFromInt(face.position.x),
				@floatFromInt(face.position.y),
				@floatFromInt(face.position.z),
			};
			for(face.blockAndQuad.quadIndex.quadInfo().corners) |cornerPos| {
				self.min = @min(self.min, basePos + cornerPos);
				self.max = @max(self.max, basePos + cornerPos);
			}
		}
		self.lock.unlockRead();
	}

	fn getValues(mesh: *ChunkMesh, wx: i32, wy: i32, wz: i32) [6]u8 {
		const x = (wx >> mesh.chunk.voxelSizeShift) & chunk.chunkMask;
		const y = (wy >> mesh.chunk.voxelSizeShift) & chunk.chunkMask;
		const z = (wz >> mesh.chunk.voxelSizeShift) & chunk.chunkMask;
		return mesh.lightingData[1].getValue(x, y, z) ++ mesh.lightingData[0].getValue(x, y, z);
	}

	fn getLightAt(parent: *ChunkMesh, x: i32, y: i32, z: i32) [6]u8 {
		const wx = parent.pos.wx +% x*parent.pos.voxelSize;
		const wy = parent.pos.wy +% y*parent.pos.voxelSize;
		const wz = parent.pos.wz +% z*parent.pos.voxelSize;
		if(x == x & chunk.chunkMask and y == y & chunk.chunkMask and z == z & chunk.chunkMask) {
			return getValues(parent, wx, wy, wz);
		}
		const neighborMesh = mesh_storage.getMesh(.{.wx = wx, .wy = wy, .wz = wz, .voxelSize = parent.pos.voxelSize}) orelse return .{0, 0, 0, 0, 0, 0};
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
					if(dx == 0) weight = 1 - interp[0] else weight = interp[0];
					if(dy == 0) weight *= 1 - interp[1] else weight *= interp[1];
					if(dz == 0) weight *= 1 - interp[2] else weight *= interp[2];
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

	fn getCornerLightAligned(parent: *ChunkMesh, pos: Vec3i, direction: chunk.Neighbor) [6]u8 { // Fast path for algined normals, leading to 4 instead of 8 light samples.
		const normal: Vec3f = @floatFromInt(Vec3i{direction.relX(), direction.relY(), direction.relZ()});
		const lightPos = @as(Vec3f, @floatFromInt(pos)) + normal*@as(Vec3f, @splat(0.5)) - @as(Vec3f, @splat(0.5));
		const startPos: Vec3i = @intFromFloat(@floor(lightPos));
		var val: [6]f32 = .{0, 0, 0, 0, 0, 0};
		var dx: i32 = 0;
		while(dx <= 1) : (dx += 1) {
			var dy: i32 = 0;
			while(dy <= 1) : (dy += 1) {
				const weight: f32 = 1.0/4.0;
				const finalPos = startPos +% @as(Vec3i, @intCast(@abs(direction.textureX())))*@as(Vec3i, @splat(dx)) +% @as(Vec3i, @intCast(@abs(direction.textureY()*@as(Vec3i, @splat(dy)))));
				var lightVal: [6]u8 = getLightAt(parent, finalPos[0], finalPos[1], finalPos[2]);
				if(parent.pos.voxelSize == 1) {
					const nextVal = getLightAt(parent, finalPos[0] +% direction.relX(), finalPos[1] +% direction.relY(), finalPos[2] +% direction.relZ());
					for(0..6) |i| {
						const diff: u8 = @min(8, lightVal[i] -| nextVal[i]);
						lightVal[i] = lightVal[i] -| diff*5/2;
					}
				}
				for(0..6) |i| {
					val[i] += @as(f32, @floatFromInt(lightVal[i]))*weight;
				}
			}
		}
		var result: [6]u8 = undefined;
		for(0..6) |i| {
			result[i] = std.math.lossyCast(u8, val[i]);
		}
		return result;
	}

	fn packLightValues(rawVals: [4][6]u5) [4]u32 {
		var result: [4]u32 = undefined;
		for(0..4) |i| {
			result[i] = (@as(u32, rawVals[i][0]) << 25 |
				@as(u32, rawVals[i][1]) << 20 |
				@as(u32, rawVals[i][2]) << 15 |
				@as(u32, rawVals[i][3]) << 10 |
				@as(u32, rawVals[i][4]) << 5 |
				@as(u32, rawVals[i][5]) << 0);
		}
		return result;
	}

	pub fn getLight(parent: *ChunkMesh, blockPos: Vec3i, textureIndex: u16, quadIndex: QuadIndex) [4]u32 {
		const quadInfo = quadIndex.quadInfo();
		const extraQuadInfo = quadIndex.extraQuadInfo();
		const normal = quadInfo.normal;
		if(!blocks.meshes.textureOcclusionData.items[textureIndex]) { // No ambient occlusion (→ no smooth lighting)
			const fullValues = getLightAt(parent, blockPos[0], blockPos[1], blockPos[2]);
			var rawVals: [6]u5 = undefined;
			for(0..6) |i| {
				rawVals[i] = std.math.lossyCast(u5, fullValues[i]/8);
			}
			return packLightValues(@splat(rawVals));
		}
		if(extraQuadInfo.hasOnlyCornerVertices) { // Fast path for simple quads.
			var rawVals: [4][6]u5 = undefined;
			for(0..4) |i| {
				const vertexPos: Vec3f = quadInfo.corners[i];
				const fullPos = blockPos +% @as(Vec3i, @intFromFloat(vertexPos));
				const fullValues = if(extraQuadInfo.alignedNormalDirection) |dir|
					getCornerLightAligned(parent, fullPos, dir)
				else
					getCornerLight(parent, fullPos, normal);
				for(0..6) |j| {
					rawVals[i][j] = std.math.lossyCast(u5, fullValues[j]/8);
				}
			}
			return packLightValues(rawVals);
		}
		var cornerVals: [2][2][2][6]u8 = undefined;
		{
			var dx: u31 = 0;
			while(dx <= 1) : (dx += 1) {
				var dy: u31 = 0;
				while(dy <= 1) : (dy += 1) {
					var dz: u31 = 0;
					while(dz <= 1) : (dz += 1) {
						cornerVals[dx][dy][dz] = if(extraQuadInfo.alignedNormalDirection) |dir|
							getCornerLightAligned(parent, blockPos +% Vec3i{dx, dy, dz}, dir)
						else
							getCornerLight(parent, blockPos +% Vec3i{dx, dy, dz}, normal);
					}
				}
			}
		}
		var rawVals: [4][6]u5 = undefined;
		for(0..4) |i| {
			const vertexPos: Vec3f = quadInfo.corners[i];
			const lightPos = vertexPos + @as(Vec3f, @floatFromInt(blockPos));
			const interp = lightPos - @as(Vec3f, @floatFromInt(blockPos));
			var val: [6]f32 = .{0, 0, 0, 0, 0, 0};
			for(0..2) |dx| {
				for(0..2) |dy| {
					for(0..2) |dz| {
						var weight: f32 = 0;
						if(dx == 0) weight = 1 - interp[0] else weight = interp[0];
						if(dy == 0) weight *= 1 - interp[1] else weight *= interp[1];
						if(dz == 0) weight *= 1 - interp[2] else weight *= interp[2];
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
		return packLightValues(rawVals);
	}

	fn uploadData(self: *PrimitiveMesh, isNeighborLod: [6]bool) void {
		self.lock.lockRead();
		defer self.lock.unlockRead();
		var len: usize = 0;
		const coreList = self.completeList.getRange(.core);
		len += coreList.len;
		const optionalList = self.completeList.getRange(.optional);
		len += optionalList.len;
		var list: [6][]FaceData = undefined;
		for(0..6) |i| {
			if(!isNeighborLod[i]) {
				list[i] = self.completeList.getRange(.neighbor(@enumFromInt(i)));
			} else {
				list[i] = self.completeList.getRange(.neighborLod(@enumFromInt(i)));
			}
			len += list[i].len;
		}

		const fullBuffer = faceBuffers[self.lod].allocateAndMapRange(len, &self.bufferAllocation);
		defer faceBuffers[self.lod].unmapRange(fullBuffer);
		// Sort the faces by normal to allow for backface culling on the GPU:
		var i: u32 = 0;
		var iStart = i;
		for(0..7) |normal| {
			for(coreList) |face| {
				if(face.blockAndQuad.quadIndex.extraQuadInfo().alignedNormalDirection) |normalDir| {
					if(normalDir.toInt() == normal) {
						fullBuffer[i] = face;
						i += 1;
					}
				} else if(normal == 6) {
					fullBuffer[i] = face;
					i += 1;
				}
			}
			if(normal < 6) {
				const normalDir: chunk.Neighbor = @enumFromInt(normal);
				@memcpy(fullBuffer[i..][0..list[normalDir.reverse().toInt()].len], list[normalDir.reverse().toInt()]);
				i += @intCast(list[normalDir.reverse().toInt()].len);
			}
			self.byNormalCount[normal] = i - iStart;
			iStart = i;
		}
		for(0..7) |normal| {
			for(optionalList) |face| {
				if(face.blockAndQuad.quadIndex.extraQuadInfo().alignedNormalDirection) |normalDir| {
					if(normalDir.toInt() == normal) {
						fullBuffer[i] = face;
						i += 1;
					}
				} else if(normal == 6) {
					fullBuffer[i] = face;
					i += 1;
				}
			}
			self.byNormalCount[normal + 7] = i - iStart;
			iStart = i;
		}
		std.debug.assert(i == fullBuffer.len);
		self.vertexCount = @intCast(6*fullBuffer.len);
		self.wasChanged = true;
	}
};

pub const ChunkMesh = struct { // MARK: ChunkMesh
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
			const normalVector: Vec3f = quadIndex.quadInfo().normal;
			self.shouldBeCulled = vec.dot(normalVector, @floatFromInt(Vec3i{dx, dy, dz})) > 0; // TODO: Adjust for arbitrary voxel models.
			const fullDx = dx - @as(i32, @intFromFloat(normalVector[0])); // TODO: This calculation should only be done for border faces.
			const fullDy = dy - @as(i32, @intFromFloat(normalVector[1]));
			const fullDz = dz - @as(i32, @intFromFloat(normalVector[2]));
			self.distance = @abs(fullDx) + @abs(fullDy) + @abs(fullDz);
		}
	};
	pos: chunk.ChunkPosition,
	size: i32,
	chunk: *chunk.Chunk,
	lightingData: [2]*lighting.ChannelChunk,
	opaqueMesh: PrimitiveMesh,
	transparentMesh: PrimitiveMesh,
	lightList: []u32 = &.{},
	lightListNeedsUpload: bool = false,
	lightAllocation: graphics.SubAllocation = .{.start = 0, .len = 0},

	lastNeighborsSameLod: [6]?*const ChunkMesh = @splat(null),
	lastNeighborsHigherLod: [6]?*const ChunkMesh = @splat(null),
	isNeighborLod: [6]bool = @splat(false),
	currentSorting: []SortingData = &.{},
	sortingOutputBuffer: []FaceData = &.{},
	culledSortingCount: u31 = 0,
	lastTransparentUpdatePos: Vec3i = Vec3i{0, 0, 0},
	needsLightRefresh: std.atomic.Value(bool) = .init(false),
	needsMeshUpdate: bool = false,
	finishedMeshing: bool = false, // Must be synced with node.finishedMeshing in mesh_storage.zig
	finishedLighting: bool = false,
	litNeighbors: Atomic(u32) = .init(0),
	mutex: std.Thread.Mutex = .{},
	chunkAllocation: graphics.SubAllocation = .{.start = 0, .len = 0},
	min: Vec3f = undefined,
	max: Vec3f = undefined,

	blockBreakingFaces: main.List(FaceData),
	blockBreakingFacesSortingData: []SortingData = &.{},
	blockBreakingFacesChanged: bool = false,

	pub fn init(pos: chunk.ChunkPosition, ch: *chunk.Chunk) *ChunkMesh {
		const self = mesh_storage.meshMemoryPool.create();
		self.* = ChunkMesh{
			.pos = pos,
			.size = chunk.chunkSize*pos.voxelSize,
			.opaqueMesh = .{
				.lod = @intCast(std.math.log2_int(u32, pos.voxelSize)),
			},
			.transparentMesh = .{
				.lod = @intCast(std.math.log2_int(u32, pos.voxelSize)),
			},
			.chunk = ch,
			.lightingData = .{
				lighting.ChannelChunk.init(ch, false),
				lighting.ChannelChunk.init(ch, true),
			},
			.blockBreakingFaces = .init(main.globalAllocator),
		};
		return self;
	}

	fn privateDeinit(self: *ChunkMesh) void {
		chunkBuffer.free(self.chunkAllocation);
		self.opaqueMesh.deinit();
		self.transparentMesh.deinit();
		self.chunk.unloadBlockEntities(.client);
		self.chunk.deinit();
		main.globalAllocator.free(self.currentSorting);
		main.globalAllocator.free(self.sortingOutputBuffer);
		for(self.lightingData) |lightingChunk| {
			lightingChunk.deinit();
		}
		self.blockBreakingFaces.deinit();
		main.globalAllocator.free(self.blockBreakingFacesSortingData);
		main.globalAllocator.free(self.lightList);
		lightBuffers[std.math.log2_int(u32, self.pos.voxelSize)].free(self.lightAllocation);
		mesh_storage.meshMemoryPool.destroy(self);
	}

	pub fn deferredDeinit(self: *ChunkMesh) void {
		main.heap.GarbageCollection.deferredFree(.{.ptr = self, .freeFunction = main.utils.castFunctionSelfToAnyopaque(privateDeinit)});
	}

	pub fn scheduleLightRefresh(pos: chunk.ChunkPosition) void {
		LightRefreshTask.schedule(pos);
	}
	const LightRefreshTask = struct {
		pos: chunk.ChunkPosition,

		pub const vtable = main.utils.ThreadPool.VTable{
			.getPriority = main.utils.castFunctionSelfToAnyopaque(getPriority),
			.isStillNeeded = main.utils.castFunctionSelfToAnyopaque(isStillNeeded),
			.run = main.utils.castFunctionSelfToAnyopaque(run),
			.clean = main.utils.castFunctionSelfToAnyopaque(clean),
			.taskType = .misc,
		};

		pub fn schedule(pos: chunk.ChunkPosition) void {
			const task = main.globalAllocator.create(LightRefreshTask);
			task.* = .{
				.pos = pos,
			};
			main.threadPool.addTask(task, &vtable);
		}

		pub fn getPriority(_: *LightRefreshTask) f32 {
			return 1000000;
		}

		pub fn isStillNeeded(_: *LightRefreshTask) bool {
			return true;
		}

		pub fn run(self: *LightRefreshTask) void {
			defer main.globalAllocator.destroy(self);
			const mesh = mesh_storage.getMesh(self.pos) orelse return;
			if(mesh.needsLightRefresh.swap(false, .acq_rel)) {
				mesh.mutex.lock();
				mesh.finishData();
				mesh.mutex.unlock();
				mesh_storage.addToUpdateList(mesh);
			}
		}

		pub fn clean(self: *LightRefreshTask) void {
			main.globalAllocator.destroy(self);
		}
	};

	pub fn isEmpty(self: *const ChunkMesh) bool {
		return self.opaqueMesh.vertexCount == 0 and self.transparentMesh.vertexCount == 0;
	}

	fn canBeSeenThroughOtherBlock(block: Block, other: Block, neighbor: chunk.Neighbor) bool {
		const rotatedModel = blocks.meshes.model(block).model();
		_ = rotatedModel; // TODO: Check if the neighbor model occludes this one. (maybe not that relevant)
		return block.typ != 0 and (other.typ == 0 or (block != other and other.viewThrough()) or other.alwaysViewThrough() or !blocks.meshes.model(other).model().isNeighborOccluded[neighbor.reverse().toInt()]);
	}

	fn initLight(self: *ChunkMesh, lightRefreshList: *main.List(chunk.ChunkPosition)) void {
		self.mutex.lock();
		var lightEmittingBlocks = main.List([3]u8).init(main.stackAllocator);
		defer lightEmittingBlocks.deinit();
		var x: u8 = 0;
		while(x < chunk.chunkSize) : (x += 1) {
			var y: u8 = 0;
			while(y < chunk.chunkSize) : (y += 1) {
				var z: u8 = 0;
				while(z < chunk.chunkSize) : (z += 1) {
					const block = self.chunk.data.getValue(chunk.getIndex(x, y, z));
					if(block.light() != 0) lightEmittingBlocks.append(.{x, y, z});
				}
			}
		}
		self.mutex.unlock();
		self.lightingData[0].propagateLights(lightEmittingBlocks.items, true, lightRefreshList);
		sunLight: {
			var allSun: bool = self.chunk.data.palette().len == 1 and self.chunk.data.palette()[0].load(.unordered).typ == 0;
			var sunStarters: [chunk.chunkSize*chunk.chunkSize][3]u8 = undefined;
			var index: usize = 0;
			const lightStartMap = mesh_storage.getLightMapPiece(self.pos.wx, self.pos.wy, self.pos.voxelSize) orelse break :sunLight;
			x = 0;
			while(x < chunk.chunkSize) : (x += 1) {
				var y: u8 = 0;
				while(y < chunk.chunkSize) : (y += 1) {
					const startHeight: i32 = lightStartMap.getHeight(self.pos.wx + x*self.pos.voxelSize, self.pos.wy + y*self.pos.voxelSize);
					const relHeight = startHeight -% self.pos.wz;
					if(relHeight < chunk.chunkSize*self.pos.voxelSize) {
						sunStarters[index] = .{x, y, chunk.chunkSize - 1};
						index += 1;
					} else {
						allSun = false;
					}
				}
			}
			if(allSun) {
				self.lightingData[1].propagateUniformSun(lightRefreshList);
			} else {
				self.lightingData[1].propagateLights(sunStarters[0..index], true, lightRefreshList);
			}
		}
	}

	pub fn generateLightingData(self: *ChunkMesh) error{AlreadyStored, NoLongerNeeded}!void {
		try mesh_storage.addMeshToStorage(self);

		var lightRefreshList = main.List(chunk.ChunkPosition).init(main.stackAllocator);
		defer lightRefreshList.deinit();
		self.initLight(&lightRefreshList);

		self.mutex.lock();
		self.finishedLighting = true;
		self.mutex.unlock();

		// Only generate a mesh if the surrounding 27 chunks finished the light generation steps.
		var dx: i32 = -1;
		while(dx <= 1) : (dx += 1) {
			var dy: i32 = -1;
			while(dy <= 1) : (dy += 1) {
				var dz: i32 = -1;
				while(dz <= 1) : (dz += 1) {
					var pos = self.pos;
					pos.wx +%= pos.voxelSize*chunk.chunkSize*dx;
					pos.wy +%= pos.voxelSize*chunk.chunkSize*dy;
					pos.wz +%= pos.voxelSize*chunk.chunkSize*dz;
					const neighborMesh = mesh_storage.getMesh(pos) orelse continue;

					const shiftSelf: u5 = @intCast(((dx + 1)*3 + dy + 1)*3 + dz + 1);
					const shiftOther: u5 = @intCast(((-dx + 1)*3 + -dy + 1)*3 + -dz + 1);
					if(neighborMesh.litNeighbors.fetchOr(@as(u27, 1) << shiftOther, .monotonic) ^ @as(u27, 1) << shiftOther == ~@as(u27, 0)) { // Trigger mesh creation for neighbor
						neighborMesh.generateMesh(&lightRefreshList);
					}
					neighborMesh.mutex.lock();
					const neighborFinishedLighting = neighborMesh.finishedLighting;
					neighborMesh.mutex.unlock();
					if(neighborFinishedLighting and self.litNeighbors.fetchOr(@as(u27, 1) << shiftSelf, .monotonic) ^ @as(u27, 1) << shiftSelf == ~@as(u27, 0)) {
						self.generateMesh(&lightRefreshList);
					}
				}
			}
		}

		for(lightRefreshList.items) |pos| {
			scheduleLightRefresh(pos);
		}
	}

	fn appendInternalQuads(block: Block, x: i32, y: i32, z: i32, comptime backFace: bool, list: *main.ListUnmanaged(FaceData), allocator: main.heap.NeverFailingAllocator) void {
		const model = blocks.meshes.model(block).model();
		model.appendInternalQuadsToList(list, allocator, block, x, y, z, backFace);
	}

	fn appendNeighborFacingQuads(block: Block, neighbor: chunk.Neighbor, x: i32, y: i32, z: i32, comptime backFace: bool, list: *main.ListUnmanaged(FaceData), allocator: main.heap.NeverFailingAllocator) void {
		const model = blocks.meshes.model(block).model();
		model.appendNeighborFacingQuadsToList(list, allocator, block, neighbor, x, y, z, backFace);
	}

	pub fn generateMesh(self: *ChunkMesh, lightRefreshList: *main.List(chunk.ChunkPosition)) void {
		var alwaysViewThroughMask: [chunk.chunkSize][chunk.chunkSize]u32 = undefined;
		@memset(std.mem.asBytes(&alwaysViewThroughMask), 0);
		var alwaysViewThroughMask2: [chunk.chunkSize][chunk.chunkSize]u32 = undefined;
		var canSeeNeighbor: [6][chunk.chunkSize][chunk.chunkSize]u32 = undefined;
		@memset(std.mem.asBytes(&canSeeNeighbor), 0);
		var canSeeAllNeighbors: [chunk.chunkSize][chunk.chunkSize]u32 = undefined;
		@memset(std.mem.asBytes(&canSeeAllNeighbors), 0);
		var hasFaces: [chunk.chunkSize][chunk.chunkSize]u32 = undefined;
		@memset(std.mem.asBytes(&hasFaces), 0);
		self.mutex.lock();

		var transparentCore: main.ListUnmanaged(FaceData) = .{};
		defer transparentCore.deinit(main.stackAllocator);
		var opaqueCore: main.ListUnmanaged(FaceData) = .{};
		defer opaqueCore.deinit(main.stackAllocator);
		var transparentOptional: main.ListUnmanaged(FaceData) = .{};
		defer transparentOptional.deinit(main.stackAllocator);
		var opaqueOptional: main.ListUnmanaged(FaceData) = .{};
		defer opaqueOptional.deinit(main.stackAllocator);

		const OcclusionInfo = packed struct {
			canSeeNeighbor: u6 = 0,
			canSeeAllNeighbors: bool = false,
			hasExternalQuads: bool = false,
			hasInternalQuads: bool = false,
			alwaysViewThrough: bool = false,
		};
		var paletteCache = main.stackAllocator.alloc(OcclusionInfo, self.chunk.data.palette().len);
		defer main.stackAllocator.free(paletteCache);
		for(0..self.chunk.data.palette().len) |i| {
			const block = self.chunk.data.palette()[i].load(.unordered);
			const model = blocks.meshes.model(block).model();
			var result: OcclusionInfo = .{};
			if(model.noNeighborsOccluded or block.viewThrough()) {
				result.canSeeAllNeighbors = true;
			} else if(!model.allNeighborsOccluded) {
				for(chunk.Neighbor.iterable) |neighbor| {
					if(!model.isNeighborOccluded[neighbor.toInt()]) {
						result.canSeeNeighbor |= neighbor.bitMask();
					}
				}
			}
			if(model.hasNeighborFacingQuads) {
				result.hasExternalQuads = true;
			}
			if(model.internalQuads.len != 0) {
				result.hasInternalQuads = true;
			}
			result.alwaysViewThrough = block.alwaysViewThrough() and block.opaqueVariant() != block.typ;
			paletteCache[i] = result;
		}
		// Generate the bitMasks:
		for(0..chunk.chunkSize) |_x| {
			const x: u5 = @intCast(_x);
			for(0..chunk.chunkSize) |_y| {
				const y: u5 = @intCast(_y);
				for(0..chunk.chunkSize) |_z| {
					const z: u5 = @intCast(_z);
					const paletteId = self.chunk.data.impl.raw.data.getValue(chunk.getIndex(x, y, z));
					const occlusionInfo = paletteCache[paletteId];
					const setBit = @as(u32, 1) << z;
					if(occlusionInfo.alwaysViewThrough or (!occlusionInfo.canSeeAllNeighbors and occlusionInfo.canSeeNeighbor == 0)) {
						alwaysViewThroughMask[x][y] |= setBit;
					}
				}
			}
		}
		const initialAlwaysViewThroughMask = alwaysViewThroughMask;
		const depthFilteredViewThroughMask = blk: {
			var a = &alwaysViewThroughMask;
			var b = &alwaysViewThroughMask2;
			for(0..main.settings.leavesQuality) |_| {
				for(0..chunk.chunkSize) |_x| {
					const x: u5 = @intCast(_x);
					for(0..chunk.chunkSize) |_y| {
						const y: u5 = @intCast(_y);
						var mask = a[x][y];
						mask &= mask << 1;
						mask &= mask >> 1;
						if(x == 0) mask = 0 else mask &= a[x - 1][y];
						if(x == chunk.chunkSize - 1) mask = 0 else mask &= a[x + 1][y];
						if(y == 0) mask = 0 else mask &= a[x][y - 1];
						if(y == chunk.chunkSize - 1) mask = 0 else mask &= a[x][y + 1];
						b[x][y] = mask;
					}
				}
				const swap = a;
				a = b;
				b = swap;
			}
			break :blk a;
		};
		for(0..chunk.chunkSize) |_x| {
			const x: u5 = @intCast(_x);
			for(0..chunk.chunkSize) |_y| {
				const y: u5 = @intCast(_y);
				for(0..chunk.chunkSize) |_z| {
					const z: u5 = @intCast(_z);
					const paletteId = self.chunk.data.impl.raw.data.getValue(chunk.getIndex(x, y, z));
					const occlusionInfo = paletteCache[paletteId];
					const setBit = @as(u32, 1) << z;
					if(depthFilteredViewThroughMask[x][y] & setBit != 0) {} else if(occlusionInfo.canSeeAllNeighbors) {
						canSeeAllNeighbors[x][y] |= setBit;
					} else if(occlusionInfo.canSeeNeighbor != 0) {
						for(chunk.Neighbor.iterable) |neighbor| {
							if(occlusionInfo.canSeeNeighbor & neighbor.bitMask() != 0) {
								canSeeNeighbor[neighbor.toInt()][x][y] |= setBit;
							}
						}
					}
					if(occlusionInfo.hasExternalQuads) {
						hasFaces[x][y] |= setBit;
					}
					if(occlusionInfo.hasInternalQuads) {
						const block = self.chunk.data.palette()[paletteId].load(.unordered);
						if(block.transparent()) {
							appendInternalQuads(block, x, y, z, false, &transparentCore, main.stackAllocator);
						} else {
							appendInternalQuads(block, x, y, z, false, &opaqueCore, main.stackAllocator);
						}
					}
				}
			}
		}
		// Generate the meshes:
		{
			const neighbor = chunk.Neighbor.dirNegX;
			for(1..chunk.chunkSize) |x| {
				for(0..chunk.chunkSize) |y| {
					var bitMask = hasFaces[x][y] & (canSeeNeighbor[comptime neighbor.reverse().toInt()][x - 1][y] | canSeeAllNeighbors[x - 1][y]);
					while(bitMask != 0) {
						const z = @ctz(bitMask);
						const setBit = @as(u32, 1) << @intCast(z);
						bitMask &= ~setBit;
						var block = self.chunk.data.getValue(chunk.getIndex(@intCast(x), @intCast(y), z));
						if(depthFilteredViewThroughMask[x][y] & setBit != 0) block.typ = block.opaqueVariant();
						if(block.viewThrough() and !block.alwaysViewThrough()) { // Needs to check the neighbor block
							const neighborBlock = self.chunk.data.getValue(chunk.getIndex(@intCast(x - 1), @intCast(y), z));
							if(block == neighborBlock) continue;
						}
						if(block.transparent()) {
							if(block.hasBackFace()) {
								appendNeighborFacingQuads(block, neighbor.reverse(), @intCast(x), @intCast(y), z, true, &transparentCore, main.stackAllocator);
							}
							appendNeighborFacingQuads(block, neighbor, @intCast(x - 1), @intCast(y), z, false, &transparentCore, main.stackAllocator);
						} else {
							appendNeighborFacingQuads(block, neighbor, @intCast(x - 1), @intCast(y), z, false, if(initialAlwaysViewThroughMask[x - 1][y] & setBit != 0) &opaqueOptional else &opaqueCore, main.stackAllocator);
						}
					}
				}
			}
		}
		{
			const neighbor = chunk.Neighbor.dirPosX;
			for(0..chunk.chunkSize - 1) |x| {
				for(0..chunk.chunkSize) |y| {
					var bitMask = hasFaces[x][y] & (canSeeNeighbor[comptime neighbor.reverse().toInt()][x + 1][y] | canSeeAllNeighbors[x + 1][y]);
					while(bitMask != 0) {
						const z = @ctz(bitMask);
						const setBit = @as(u32, 1) << @intCast(z);
						bitMask &= ~setBit;
						var block = self.chunk.data.getValue(chunk.getIndex(@intCast(x), @intCast(y), z));
						if(depthFilteredViewThroughMask[x][y] & setBit != 0) block.typ = block.opaqueVariant();
						if(block.viewThrough() and !block.alwaysViewThrough()) { // Needs to check the neighbor block
							const neighborBlock = self.chunk.data.getValue(chunk.getIndex(@intCast(x + 1), @intCast(y), z));
							if(block == neighborBlock) continue;
						}
						if(block.transparent()) {
							if(block.hasBackFace()) {
								appendNeighborFacingQuads(block, neighbor.reverse(), @intCast(x), @intCast(y), z, true, &transparentCore, main.stackAllocator);
							}
							appendNeighborFacingQuads(block, neighbor, @intCast(x + 1), @intCast(y), z, false, &transparentCore, main.stackAllocator);
						} else {
							appendNeighborFacingQuads(block, neighbor, @intCast(x + 1), @intCast(y), z, false, if(initialAlwaysViewThroughMask[x + 1][y] & setBit != 0) &opaqueOptional else &opaqueCore, main.stackAllocator);
						}
					}
				}
			}
		}
		{
			const neighbor = chunk.Neighbor.dirNegY;
			for(0..chunk.chunkSize) |x| {
				for(1..chunk.chunkSize) |y| {
					var bitMask = hasFaces[x][y] & (canSeeNeighbor[comptime neighbor.reverse().toInt()][x][y - 1] | canSeeAllNeighbors[x][y - 1]);
					while(bitMask != 0) {
						const z = @ctz(bitMask);
						const setBit = @as(u32, 1) << @intCast(z);
						bitMask &= ~setBit;
						var block = self.chunk.data.getValue(chunk.getIndex(@intCast(x), @intCast(y), z));
						if(depthFilteredViewThroughMask[x][y] & setBit != 0) block.typ = block.opaqueVariant();
						if(block.viewThrough() and !block.alwaysViewThrough()) { // Needs to check the neighbor block
							const neighborBlock = self.chunk.data.getValue(chunk.getIndex(@intCast(x), @intCast(y - 1), z));
							if(block == neighborBlock) continue;
						}
						if(block.transparent()) {
							if(block.hasBackFace()) {
								appendNeighborFacingQuads(block, neighbor.reverse(), @intCast(x), @intCast(y), z, true, &transparentCore, main.stackAllocator);
							}
							appendNeighborFacingQuads(block, neighbor, @intCast(x), @intCast(y - 1), z, false, &transparentCore, main.stackAllocator);
						} else {
							appendNeighborFacingQuads(block, neighbor, @intCast(x), @intCast(y - 1), z, false, if(initialAlwaysViewThroughMask[x][y - 1] & setBit != 0) &opaqueOptional else &opaqueCore, main.stackAllocator);
						}
					}
				}
			}
		}
		{
			const neighbor = chunk.Neighbor.dirPosY;
			for(0..chunk.chunkSize) |x| {
				for(0..chunk.chunkSize - 1) |y| {
					var bitMask = hasFaces[x][y] & (canSeeNeighbor[comptime neighbor.reverse().toInt()][x][y + 1] | canSeeAllNeighbors[x][y + 1]);
					while(bitMask != 0) {
						const z = @ctz(bitMask);
						const setBit = @as(u32, 1) << @intCast(z);
						bitMask &= ~setBit;
						var block = self.chunk.data.getValue(chunk.getIndex(@intCast(x), @intCast(y), z));
						if(depthFilteredViewThroughMask[x][y] & setBit != 0) block.typ = block.opaqueVariant();
						if(block.viewThrough() and !block.alwaysViewThrough()) { // Needs to check the neighbor block
							const neighborBlock = self.chunk.data.getValue(chunk.getIndex(@intCast(x), @intCast(y + 1), z));
							if(block == neighborBlock) continue;
						}
						if(block.transparent()) {
							if(block.hasBackFace()) {
								appendNeighborFacingQuads(block, neighbor.reverse(), @intCast(x), @intCast(y), z, true, &transparentCore, main.stackAllocator);
							}
							appendNeighborFacingQuads(block, neighbor, @intCast(x), @intCast(y + 1), z, false, &transparentCore, main.stackAllocator);
						} else {
							appendNeighborFacingQuads(block, neighbor, @intCast(x), @intCast(y + 1), z, false, if(initialAlwaysViewThroughMask[x][y + 1] & setBit != 0) &opaqueOptional else &opaqueCore, main.stackAllocator);
						}
					}
				}
			}
		}
		{
			const neighbor = chunk.Neighbor.dirDown;
			for(0..chunk.chunkSize) |x| {
				for(0..chunk.chunkSize) |y| {
					var bitMask = hasFaces[x][y] & (canSeeNeighbor[comptime neighbor.reverse().toInt()][x][y] | canSeeAllNeighbors[x][y]) << 1;
					while(bitMask != 0) {
						const z = @ctz(bitMask);
						const setBit = @as(u32, 1) << @intCast(z);
						bitMask &= ~setBit;
						var block = self.chunk.data.getValue(chunk.getIndex(@intCast(x), @intCast(y), z));
						if(depthFilteredViewThroughMask[x][y] & setBit != 0) block.typ = block.opaqueVariant();
						if(block.viewThrough() and !block.alwaysViewThrough()) { // Needs to check the neighbor block
							const neighborBlock = self.chunk.data.getValue(chunk.getIndex(@intCast(x), @intCast(y), z - 1));
							if(block == neighborBlock) continue;
						}
						if(block.transparent()) {
							if(block.hasBackFace()) {
								appendNeighborFacingQuads(block, neighbor.reverse(), @intCast(x), @intCast(y), z, true, &transparentCore, main.stackAllocator);
							}
							appendNeighborFacingQuads(block, neighbor, @intCast(x), @intCast(y), z - 1, false, &transparentCore, main.stackAllocator);
						} else {
							appendNeighborFacingQuads(block, neighbor, @intCast(x), @intCast(y), z - 1, false, if(initialAlwaysViewThroughMask[x][y] << 1 & setBit != 0) &opaqueOptional else &opaqueCore, main.stackAllocator);
						}
					}
				}
			}
		}
		{
			const neighbor = chunk.Neighbor.dirUp;
			for(0..chunk.chunkSize) |x| {
				for(0..chunk.chunkSize) |y| {
					var bitMask = hasFaces[x][y] & (canSeeNeighbor[comptime neighbor.reverse().toInt()][x][y] | canSeeAllNeighbors[x][y]) >> 1;
					while(bitMask != 0) {
						const z = @ctz(bitMask);
						const setBit = @as(u32, 1) << @intCast(z);
						bitMask &= ~setBit;
						var block = self.chunk.data.getValue(chunk.getIndex(@intCast(x), @intCast(y), z));
						if(depthFilteredViewThroughMask[x][y] & setBit != 0) block.typ = block.opaqueVariant();
						if(block.viewThrough() and !block.alwaysViewThrough()) { // Needs to check the neighbor block
							const neighborBlock = self.chunk.data.getValue(chunk.getIndex(@intCast(x), @intCast(y), z + 1));
							if(block == neighborBlock) continue;
						}
						if(block.transparent()) {
							if(block.hasBackFace()) {
								appendNeighborFacingQuads(block, neighbor.reverse(), @intCast(x), @intCast(y), z, true, &transparentCore, main.stackAllocator);
							}
							appendNeighborFacingQuads(block, neighbor, @intCast(x), @intCast(y), z + 1, false, &transparentCore, main.stackAllocator);
						} else {
							appendNeighborFacingQuads(block, neighbor, @intCast(x), @intCast(y), z + 1, false, if(initialAlwaysViewThroughMask[x][y] >> 1 & setBit != 0) &opaqueOptional else &opaqueCore, main.stackAllocator);
						}
					}
				}
			}
		}

		self.mutex.unlock();

		self.opaqueMesh.replaceRange(.core, opaqueCore.items);
		self.opaqueMesh.replaceRange(.optional, opaqueOptional.items);

		self.transparentMesh.replaceRange(.core, transparentCore.items);
		self.transparentMesh.replaceRange(.optional, transparentOptional.items);

		self.finishNeighbors(lightRefreshList);
	}

	fn updateBlockLight(self: *ChunkMesh, x: u5, y: u5, z: u5, newBlock: Block, lightRefreshList: *main.List(chunk.ChunkPosition)) void {
		for(self.lightingData[0..]) |lightingData| {
			lightingData.propagateLightsDestructive(&.{.{x, y, z}}, lightRefreshList);
		}
		if(newBlock.light() != 0) {
			self.lightingData[0].propagateLights(&.{.{x, y, z}}, false, lightRefreshList);
		}
	}

	pub fn updateBlock(self: *ChunkMesh, _x: i32, _y: i32, _z: i32, _newBlock: Block, blockEntityData: []const u8, lightRefreshList: *main.List(chunk.ChunkPosition), regenerateMeshList: *main.List(*ChunkMesh)) void {
		const x: u5 = @intCast(_x & chunk.chunkMask);
		const y: u5 = @intCast(_y & chunk.chunkMask);
		const z: u5 = @intCast(_z & chunk.chunkMask);
		var newBlock = _newBlock;
		self.mutex.lock();
		const oldBlock = self.chunk.data.getValue(chunk.getIndex(x, y, z));

		if(oldBlock == newBlock) {
			if(newBlock.blockEntity()) |blockEntity| {
				var reader = main.utils.BinaryReader.init(blockEntityData);
				blockEntity.updateClientData(.{_x, _y, _z}, self.chunk, .{.update = &reader}) catch |err| {
					std.log.err("Got error {s} while trying to apply block entity data {any} in position {} for block {s}", .{@errorName(err), blockEntityData, Vec3i{_x, _y, _z}, newBlock.id()});
				};
			}
			self.mutex.unlock();
			return;
		}
		self.mutex.unlock();

		if(oldBlock.blockEntity()) |blockEntity| {
			blockEntity.updateClientData(.{_x, _y, _z}, self.chunk, .remove) catch |err| {
				std.log.err("Got error {s} while trying to remove entity data in position {} for block {s}", .{@errorName(err), Vec3i{_x, _y, _z}, oldBlock.id()});
			};
		}

		var neighborBlocks: [6]Block = undefined;
		@memset(&neighborBlocks, .{.typ = 0, .data = 0});

		for(chunk.Neighbor.iterable) |neighbor| {
			const nx = x + neighbor.relX();
			const ny = y + neighbor.relY();
			const nz = z + neighbor.relZ();

			if(nx & chunk.chunkMask != nx or ny & chunk.chunkMask != ny or nz & chunk.chunkMask != nz) {
				const nnx: u5 = @intCast(nx & chunk.chunkMask);
				const nny: u5 = @intCast(ny & chunk.chunkMask);
				const nnz: u5 = @intCast(nz & chunk.chunkMask);

				const neighborChunkMesh = mesh_storage.getNeighbor(self.pos, self.pos.voxelSize, neighbor) orelse continue;

				const index = chunk.getIndex(nnx, nny, nnz);

				neighborChunkMesh.mutex.lock();
				var neighborBlock = neighborChunkMesh.chunk.data.getValue(index);

				if(neighborBlock.mode().dependsOnNeighbors and neighborBlock.mode().updateData(&neighborBlock, neighbor.reverse(), newBlock)) {
					neighborChunkMesh.chunk.data.setValue(index, neighborBlock);
					neighborChunkMesh.mutex.unlock();
					neighborChunkMesh.updateBlockLight(nnx, nny, nnz, neighborBlock, lightRefreshList);
					appendIfNotContained(regenerateMeshList, neighborChunkMesh);
					neighborChunkMesh.mutex.lock();
				}
				neighborChunkMesh.mutex.unlock();
				neighborBlocks[neighbor.toInt()] = neighborBlock;
			} else {
				const index = chunk.getIndex(nx, ny, nz);
				self.mutex.lock();
				var neighborBlock = self.chunk.data.getValue(index);
				if(neighborBlock.mode().dependsOnNeighbors and neighborBlock.mode().updateData(&neighborBlock, neighbor.reverse(), newBlock)) {
					self.chunk.data.setValue(index, neighborBlock);
					self.updateBlockLight(@intCast(nx), @intCast(ny), @intCast(nz), neighborBlock, lightRefreshList);
				}
				self.mutex.unlock();
				neighborBlocks[neighbor.toInt()] = neighborBlock;
			}
		}
		if(newBlock.mode().dependsOnNeighbors) {
			for(chunk.Neighbor.iterable) |neighbor| {
				_ = newBlock.mode().updateData(&newBlock, neighbor, neighborBlocks[neighbor.toInt()]);
			}
		}
		self.mutex.lock();
		self.chunk.data.setValue(chunk.getIndex(x, y, z), newBlock);
		self.mutex.unlock();

		self.updateBlockLight(x, y, z, newBlock, lightRefreshList);

		self.mutex.lock();
		// Update neighbor chunks:
		if(x == 0) {
			self.lastNeighborsHigherLod[chunk.Neighbor.dirNegX.toInt()] = null;
			self.lastNeighborsSameLod[chunk.Neighbor.dirNegX.toInt()] = null;
		} else if(x == 31) {
			self.lastNeighborsHigherLod[chunk.Neighbor.dirPosX.toInt()] = null;
			self.lastNeighborsSameLod[chunk.Neighbor.dirPosX.toInt()] = null;
		}
		if(y == 0) {
			self.lastNeighborsHigherLod[chunk.Neighbor.dirNegY.toInt()] = null;
			self.lastNeighborsSameLod[chunk.Neighbor.dirNegY.toInt()] = null;
		} else if(y == 31) {
			self.lastNeighborsHigherLod[chunk.Neighbor.dirPosY.toInt()] = null;
			self.lastNeighborsSameLod[chunk.Neighbor.dirPosY.toInt()] = null;
		}
		if(z == 0) {
			self.lastNeighborsHigherLod[chunk.Neighbor.dirDown.toInt()] = null;
			self.lastNeighborsSameLod[chunk.Neighbor.dirDown.toInt()] = null;
		} else if(z == 31) {
			self.lastNeighborsHigherLod[chunk.Neighbor.dirUp.toInt()] = null;
			self.lastNeighborsSameLod[chunk.Neighbor.dirUp.toInt()] = null;
		}
		self.mutex.unlock();

		appendIfNotContained(regenerateMeshList, self);
	}

	fn appendIfNotContained(list: *main.List(*ChunkMesh), mesh: *ChunkMesh) void {
		for(list.items) |other| {
			if(other == mesh) {
				return;
			}
		}
		list.append(mesh);
	}

	fn clearNeighborA(self: *ChunkMesh, neighbor: chunk.Neighbor, comptime isLod: bool) void {
		self.opaqueMesh.clearNeighbor(neighbor, isLod);
		self.transparentMesh.clearNeighbor(neighbor, isLod);
	}

	pub fn finishData(self: *ChunkMesh) void {
		main.utils.assertLocked(&self.mutex);

		var lightList = main.List(u32).init(main.stackAllocator);
		defer lightList.deinit();
		var lightMap = std.AutoHashMap([4]u32, u16).init(main.stackAllocator.allocator);
		defer lightMap.deinit();

		self.opaqueMesh.finish(self, &lightList, &lightMap);
		self.transparentMesh.finish(self, &lightList, &lightMap);

		self.lightList = main.globalAllocator.realloc(self.lightList, lightList.items.len);
		@memcpy(self.lightList, lightList.items);
		self.lightListNeedsUpload = true;

		self.min = @min(self.opaqueMesh.min, self.transparentMesh.min);
		self.max = @max(self.opaqueMesh.max, self.transparentMesh.max);
	}

	pub fn uploadData(self: *ChunkMesh) void {
		self.opaqueMesh.uploadData(self.isNeighborLod);
		self.transparentMesh.uploadData(self.isNeighborLod);

		if(self.lightListNeedsUpload) {
			self.lightListNeedsUpload = false;
			lightBuffers[std.math.log2_int(u32, self.pos.voxelSize)].uploadData(self.lightList, &self.lightAllocation);
		}

		self.uploadChunkPosition();
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

	fn finishNeighbors(self: *ChunkMesh, lightRefreshList: *main.List(chunk.ChunkPosition)) void {
		for(chunk.Neighbor.iterable) |neighbor| {
			const nullNeighborMesh = mesh_storage.getNeighbor(self.pos, self.pos.voxelSize, neighbor);
			if(nullNeighborMesh) |neighborMesh| sameLodBlock: {
				std.debug.assert(neighborMesh != self);
				deadlockFreeDoubleLock(&self.mutex, &neighborMesh.mutex);
				defer self.mutex.unlock();
				defer neighborMesh.mutex.unlock();
				if(self.lastNeighborsSameLod[neighbor.toInt()] == neighborMesh) break :sameLodBlock;
				self.lastNeighborsSameLod[neighbor.toInt()] = neighborMesh;
				neighborMesh.lastNeighborsSameLod[neighbor.reverse().toInt()] = self;

				var transparentSelf: main.ListUnmanaged(FaceData) = .{};
				defer transparentSelf.deinit(main.stackAllocator);
				var opaqueSelf: main.ListUnmanaged(FaceData) = .{};
				defer opaqueSelf.deinit(main.stackAllocator);
				var transparentNeighbor: main.ListUnmanaged(FaceData) = .{};
				defer transparentNeighbor.deinit(main.stackAllocator);
				var opaqueNeighbor: main.ListUnmanaged(FaceData) = .{};
				defer opaqueNeighbor.deinit(main.stackAllocator);

				const x3: i32 = if(neighbor.isPositive()) chunk.chunkMask else 0;
				var x1: i32 = 0;
				while(x1 < chunk.chunkSize) : (x1 += 1) {
					var x2: i32 = 0;
					while(x2 < chunk.chunkSize) : (x2 += 1) {
						var x: i32 = undefined;
						var y: i32 = undefined;
						var z: i32 = undefined;
						if(neighbor.relX() != 0) {
							x = x3;
							y = x1;
							z = x2;
						} else if(neighbor.relY() != 0) {
							x = x1;
							y = x3;
							z = x2;
						} else {
							x = x2;
							y = x1;
							z = x3;
						}
						const otherX = x +% neighbor.relX() & chunk.chunkMask;
						const otherY = y +% neighbor.relY() & chunk.chunkMask;
						const otherZ = z +% neighbor.relZ() & chunk.chunkMask;
						var block = self.chunk.data.getValue(chunk.getIndex(x, y, z));
						if(settings.leavesQuality == 0) block.typ = block.opaqueVariant();
						var otherBlock = neighborMesh.chunk.data.getValue(chunk.getIndex(otherX, otherY, otherZ));
						if(settings.leavesQuality == 0) otherBlock.typ = otherBlock.opaqueVariant();
						if(canBeSeenThroughOtherBlock(block, otherBlock, neighbor)) {
							if(block.transparent()) {
								if(block.hasBackFace()) {
									appendNeighborFacingQuads(block, neighbor.reverse(), x, y, z, true, &transparentSelf, main.stackAllocator);
								}
								appendNeighborFacingQuads(block, neighbor, otherX, otherY, otherZ, false, &transparentNeighbor, main.stackAllocator);
							} else {
								appendNeighborFacingQuads(block, neighbor, otherX, otherY, otherZ, false, &opaqueNeighbor, main.stackAllocator);
							}
						}
						if(canBeSeenThroughOtherBlock(otherBlock, block, neighbor.reverse())) {
							if(otherBlock.transparent()) {
								if(otherBlock.hasBackFace()) {
									appendNeighborFacingQuads(otherBlock, neighbor, otherX, otherY, otherZ, true, &transparentNeighbor, main.stackAllocator);
								}
								appendNeighborFacingQuads(otherBlock, neighbor.reverse(), x, y, z, false, &transparentSelf, main.stackAllocator);
							} else {
								appendNeighborFacingQuads(otherBlock, neighbor.reverse(), x, y, z, false, &opaqueSelf, main.stackAllocator);
							}
						}
					}
				}
				self.opaqueMesh.replaceRange(.neighbor(neighbor), opaqueSelf.items);
				self.transparentMesh.replaceRange(.neighbor(neighbor), transparentSelf.items);
				neighborMesh.opaqueMesh.replaceRange(.neighbor(neighbor.reverse()), opaqueNeighbor.items);
				neighborMesh.transparentMesh.replaceRange(.neighbor(neighbor.reverse()), transparentNeighbor.items);

				_ = neighborMesh.needsLightRefresh.store(true, .release);
				lightRefreshList.append(neighborMesh.pos);
			} else {
				self.mutex.lock();
				defer self.mutex.unlock();
				if(self.lastNeighborsSameLod[neighbor.toInt()] != null) {
					self.opaqueMesh.replaceRange(.neighbor(neighbor), &.{});
					self.transparentMesh.replaceRange(.neighbor(neighbor), &.{});
					self.lastNeighborsSameLod[neighbor.toInt()] = null;
				}
			}
			// lod border:
			if(self.pos.voxelSize == @as(u31, 1) << settings.highestLod) continue;
			const neighborMesh = mesh_storage.getNeighbor(self.pos, 2*self.pos.voxelSize, neighbor) orelse {
				self.mutex.lock();
				defer self.mutex.unlock();
				if(self.lastNeighborsHigherLod[neighbor.toInt()] != null) {
					self.opaqueMesh.replaceRange(.neighborLod(neighbor), &.{});
					self.transparentMesh.replaceRange(.neighborLod(neighbor), &.{});
					self.lastNeighborsHigherLod[neighbor.toInt()] = null;
				}
				continue;
			};
			deadlockFreeDoubleLock(&self.mutex, &neighborMesh.mutex);
			defer self.mutex.unlock();
			defer neighborMesh.mutex.unlock();
			if(self.lastNeighborsHigherLod[neighbor.toInt()] == neighborMesh) continue;
			self.lastNeighborsHigherLod[neighbor.toInt()] = neighborMesh;

			var transparentSelf: main.ListUnmanaged(FaceData) = .{};
			defer transparentSelf.deinit(main.stackAllocator);
			var opaqueSelf: main.ListUnmanaged(FaceData) = .{};
			defer opaqueSelf.deinit(main.stackAllocator);

			const x3: i32 = if(neighbor.isPositive()) chunk.chunkMask else 0;
			const offsetX = @divExact(self.pos.wx, self.pos.voxelSize) & chunk.chunkSize;
			const offsetY = @divExact(self.pos.wy, self.pos.voxelSize) & chunk.chunkSize;
			const offsetZ = @divExact(self.pos.wz, self.pos.voxelSize) & chunk.chunkSize;
			var x1: i32 = 0;
			while(x1 < chunk.chunkSize) : (x1 += 1) {
				var x2: i32 = 0;
				while(x2 < chunk.chunkSize) : (x2 += 1) {
					var x: i32 = undefined;
					var y: i32 = undefined;
					var z: i32 = undefined;
					if(neighbor.relX() != 0) {
						x = x3;
						y = x1;
						z = x2;
					} else if(neighbor.relY() != 0) {
						x = x1;
						y = x3;
						z = x2;
					} else {
						x = x2;
						y = x1;
						z = x3;
					}
					const otherX = (x +% neighbor.relX() +% offsetX >> 1) & chunk.chunkMask;
					const otherY = (y +% neighbor.relY() +% offsetY >> 1) & chunk.chunkMask;
					const otherZ = (z +% neighbor.relZ() +% offsetZ >> 1) & chunk.chunkMask;
					var block = self.chunk.data.getValue(chunk.getIndex(x, y, z));
					if(settings.leavesQuality == 0) block.typ = block.opaqueVariant();
					var otherBlock = neighborMesh.chunk.data.getValue(chunk.getIndex(otherX, otherY, otherZ));
					if(settings.leavesQuality == 0) otherBlock.typ = otherBlock.opaqueVariant();
					if(canBeSeenThroughOtherBlock(otherBlock, block, neighbor.reverse())) {
						if(otherBlock.transparent()) {
							appendNeighborFacingQuads(otherBlock, neighbor.reverse(), x, y, z, false, &transparentSelf, main.stackAllocator);
						} else {
							appendNeighborFacingQuads(otherBlock, neighbor.reverse(), x, y, z, false, &opaqueSelf, main.stackAllocator);
						}
					}
					if(block.hasBackFace()) {
						if(canBeSeenThroughOtherBlock(block, otherBlock, neighbor)) {
							appendNeighborFacingQuads(block, neighbor.reverse(), x, y, z, true, &transparentSelf, main.stackAllocator);
						}
					}
				}
			}
			self.opaqueMesh.replaceRange(.neighborLod(neighbor), opaqueSelf.items);
			self.transparentMesh.replaceRange(.neighborLod(neighbor), transparentSelf.items);
		}
		self.mutex.lock();
		defer self.mutex.unlock();
		_ = self.needsLightRefresh.swap(false, .acq_rel);
		self.finishData();
		mesh_storage.finishMesh(self.pos);
	}

	fn uploadChunkPosition(self: *ChunkMesh) void {
		chunkBuffer.uploadData(&.{ChunkData{
			.position = .{self.pos.wx, self.pos.wy, self.pos.wz},
			.voxelSize = self.pos.voxelSize,
			.lightStart = self.lightAllocation.start,
			.vertexStartOpaque = self.opaqueMesh.bufferAllocation.start*4,
			.faceCountsByNormalOpaque = self.opaqueMesh.byNormalCount,
			.vertexStartTransparent = self.transparentMesh.bufferAllocation.start*4,
			.vertexCountTransparent = self.transparentMesh.bufferAllocation.len*6,
			.min = self.min,
			.max = self.max,
			.visibilityState = 0,
			.oldVisibilityState = 0,
		}}, &self.chunkAllocation);
	}

	pub fn prepareRendering(self: *ChunkMesh, chunkLists: *[main.settings.highestSupportedLod + 1]main.List(u32)) void {
		if(self.opaqueMesh.vertexCount == 0) return;

		chunkLists[std.math.log2_int(u32, self.pos.voxelSize)].append(self.chunkAllocation.start);

		quadsDrawn += self.opaqueMesh.vertexCount/6;
	}

	pub fn prepareTransparentRendering(self: *ChunkMesh, playerPosition: Vec3d, chunkLists: *[main.settings.highestSupportedLod + 1]main.List(u32)) void {
		if(self.transparentMesh.vertexCount == 0 and self.blockBreakingFaces.items.len == 0) return;

		var needsUpdate: bool = false;
		if(self.transparentMesh.wasChanged) {
			self.transparentMesh.wasChanged = false;
			self.transparentMesh.lock.lockRead();
			defer self.transparentMesh.lock.unlockRead();
			var len: usize = 0;
			const coreList = self.transparentMesh.completeList.getRange(.core);
			len += coreList.len;
			var list: [6][]FaceData = undefined;
			for(0..6) |i| {
				if(!self.isNeighborLod[i]) {
					list[i] = self.transparentMesh.completeList.getRange(.neighbor(@enumFromInt(i)));
				} else {
					list[i] = self.transparentMesh.completeList.getRange(.neighborLod(@enumFromInt(i)));
				}
				len += list[i].len;
			}
			self.currentSorting = main.globalAllocator.realloc(self.currentSorting, len);
			self.sortingOutputBuffer = main.globalAllocator.realloc(self.sortingOutputBuffer, len + self.blockBreakingFaces.items.len);
			for(0..coreList.len) |i| {
				self.currentSorting[i].face = coreList[i];
			}
			var offset = coreList.len;
			for(0..6) |n| {
				for(0..list[n].len) |i| {
					self.currentSorting[offset + i].face = list[n][i];
				}
				offset += list[n].len;
			}

			needsUpdate = true;
		}

		var relativePos = Vec3d{
			@as(f64, @floatFromInt(self.pos.wx)) - playerPosition[0],
			@as(f64, @floatFromInt(self.pos.wy)) - playerPosition[1],
			@as(f64, @floatFromInt(self.pos.wz)) - playerPosition[2],
		}/@as(Vec3d, @splat(@as(f64, @floatFromInt(self.pos.voxelSize))));
		relativePos = @min(relativePos, @as(Vec3d, @splat(0)));
		relativePos = @max(relativePos, @as(Vec3d, @splat(-32)));
		const updatePos: Vec3i = @intFromFloat(relativePos);
		if(@reduce(.Or, updatePos != self.lastTransparentUpdatePos)) {
			self.lastTransparentUpdatePos = updatePos;
			needsUpdate = true;
		}
		if(self.blockBreakingFacesChanged) {
			self.blockBreakingFacesChanged = false;
			self.sortingOutputBuffer = main.globalAllocator.realloc(self.sortingOutputBuffer, self.currentSorting.len + self.blockBreakingFaces.items.len);
			self.blockBreakingFacesSortingData = main.globalAllocator.realloc(self.blockBreakingFacesSortingData, self.blockBreakingFaces.items.len);
			for(0..self.blockBreakingFaces.items.len) |i| {
				self.blockBreakingFacesSortingData[i].face = self.blockBreakingFaces.items[i];
			}
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
			for(0..self.blockBreakingFaces.items.len) |i| {
				self.blockBreakingFacesSortingData[i].update(updatePos[0], updatePos[1], updatePos[2]);
			}

			// Sort by back vs front face:
			var backFaceStart: usize = 0;
			{
				var i: usize = 0;
				var culledStart: usize = self.currentSorting.len;
				while(culledStart > 0) {
					if(!self.currentSorting[culledStart - 1].shouldBeCulled) {
						break;
					}
					culledStart -= 1;
				}
				while(i < culledStart) : (i += 1) {
					if(self.currentSorting[i].shouldBeCulled) {
						culledStart -= 1;
						std.mem.swap(SortingData, &self.currentSorting[i], &self.currentSorting[culledStart]);
						while(culledStart > 0) {
							if(!self.currentSorting[culledStart - 1].shouldBeCulled) {
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
			for(self.blockBreakingFacesSortingData) |val| {
				buckets[34*3 - 1 - val.distance] += 1;
			}
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
			for(0..backFaceStart) |i| {
				const bucket = 34*3 - 1 - self.currentSorting[i].distance;
				self.sortingOutputBuffer[buckets[bucket]] = self.currentSorting[i].face;
				buckets[bucket] += 1;
			}
			// Block breaking faces should be drawn after front faces, but before the corresponding backfaces.
			for(self.blockBreakingFacesSortingData) |val| {
				const bucket = 34*3 - 1 - val.distance;
				self.sortingOutputBuffer[buckets[bucket]] = val.face;
				buckets[bucket] += 1;
			}
			for(backFaceStart..self.culledSortingCount) |i| {
				const bucket = 34*3 - 1 - self.currentSorting[i].distance;
				self.sortingOutputBuffer[buckets[bucket]] = self.currentSorting[i].face;
				buckets[bucket] += 1;
			}
			self.culledSortingCount += @intCast(self.blockBreakingFaces.items.len);
			// Upload:
			faceBuffers[self.transparentMesh.lod].uploadData(self.sortingOutputBuffer[0..self.culledSortingCount], &self.transparentMesh.bufferAllocation);
			self.uploadChunkPosition();
		}

		chunkLists[std.math.log2_int(u32, self.pos.voxelSize)].append(self.chunkAllocation.start);
		transparentQuadsDrawn += self.culledSortingCount;
	}
};
