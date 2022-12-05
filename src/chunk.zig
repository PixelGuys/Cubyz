const std = @import("std");
const Allocator = std.mem.Allocator;

const blocks = @import("blocks.zig");
const Block = blocks.Block;
const game = @import("game.zig");
const graphics = @import("graphics.zig");
const c = graphics.c;
const Shader = graphics.Shader;
const SSBO = graphics.SSBO;
const main = @import("main.zig");
const models = @import("models.zig");
const renderer = @import("renderer.zig");
const settings = @import("settings.zig");
const vec = @import("vec.zig");
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const Mat4f = vec.Mat4f;

pub const ChunkCoordinate = i32;
pub const UChunkCoordinate = u31;
pub const chunkShift: u5 = 5;
pub const chunkShift2: u5 = chunkShift*2;
pub const chunkSize: ChunkCoordinate = 1 << chunkShift;
pub const chunkSizeIterator: [chunkSize]u0 = undefined;
pub const chunkVolume: UChunkCoordinate = 1 << 3*chunkShift;
pub const chunkMask: ChunkCoordinate = chunkSize - 1;

/// Contains a bunch of constants used to describe neighboring blocks.
pub const Neighbors = struct {
	/// How many neighbors there are.
	pub const neighbors: u32 = 6;
	/// Directions → Index
	pub const dirUp: u32 = 0;
	/// Directions → Index
	pub const dirDown: u32 = 1;
	/// Directions → Index
	pub const dirPosX: u32 = 2;
	/// Directions → Index
	pub const dirNegX: u32 = 3;
	/// Directions → Index
	pub const dirPosZ: u32 = 4;
	/// Directions → Index
	pub const dirNegZ: u32 = 5;
	/// Index to relative position
	pub const relX = [_]ChunkCoordinate {0, 0, 1, -1, 0, 0};
	/// Index to relative position
	pub const relY = [_]ChunkCoordinate {1, -1, 0, 0, 0, 0};
	/// Index to relative position
	pub const relZ = [_]ChunkCoordinate {0, 0, 0, 0, 1, -1};
	/// Index to bitMask for bitmap direction data
	pub const bitMask = [_]u6 {0x01, 0x02, 0x04, 0x08, 0x10, 0x20};
	/// To iterate over all neighbors easily
	pub const iterable = [_]u3 {0, 1, 2, 3, 4, 5};
};

/// Gets the index of a given position inside this chunk.
fn getIndex(x: ChunkCoordinate, y: ChunkCoordinate, z: ChunkCoordinate) u32 {
	std.debug.assert((x & chunkMask) == x and (y & chunkMask) == y and (z & chunkMask) == z);
	return (@intCast(u32, x) << chunkShift) | (@intCast(u32, y) << chunkShift2) | @intCast(u32, z);
}
/// Gets the x coordinate from a given index inside this chunk.
fn extractXFromIndex(index: usize) ChunkCoordinate {
	return @intCast(ChunkCoordinate, index >> chunkShift & chunkMask);
}
/// Gets the y coordinate from a given index inside this chunk.
fn extractYFromIndex(index: usize) ChunkCoordinate {
	return @intCast(ChunkCoordinate, index >> chunkShift2 & chunkMask);
}
/// Gets the z coordinate from a given index inside this chunk.
fn extractZFromIndex(index: usize) ChunkCoordinate {
	return @intCast(ChunkCoordinate, index & chunkMask);
}

pub const ChunkPosition = struct {
	wx: ChunkCoordinate,
	wy: ChunkCoordinate,
	wz: ChunkCoordinate,
	voxelSize: UChunkCoordinate,
	
//	TODO(mabye?):
//	public int hashCode() {
//		int shift = Math.min(Integer.numberOfTrailingZeros(wx), Math.min(Integer.numberOfTrailingZeros(wy), Integer.numberOfTrailingZeros(wz)));
//		return (((wx >> shift) * 31 + (wy >> shift)) * 31 + (wz >> shift)) * 31 + voxelSize;
//	}

	pub fn getMinDistanceSquared(self: ChunkPosition, playerPosition: Vec3d) f64 {
		var halfWidth = @intToFloat(f64, self.voxelSize*@divExact(chunkSize, 2));
		var dx = @fabs(@intToFloat(f64, self.wx) + halfWidth - playerPosition[0]);
		var dy = @fabs(@intToFloat(f64, self.wy) + halfWidth - playerPosition[1]);
		var dz = @fabs(@intToFloat(f64, self.wz) + halfWidth - playerPosition[2]);
		dx = @max(0, dx - halfWidth);
		dy = @max(0, dy - halfWidth);
		dz = @max(0, dz - halfWidth);
		return dx*dx + dy*dy + dz*dz;
	}

	pub fn getPriority(self: ChunkPosition, playerPos: Vec3d) f32 {
		return -@floatCast(f32, self.getMinDistanceSquared(playerPos))/@intToFloat(f32, self.voxelSize*self.voxelSize) + 2*@intToFloat(f32, std.math.log2_int(UChunkCoordinate, self.voxelSize)*chunkSize*chunkSize);
	}
};

pub const Chunk = struct {
	pos: ChunkPosition,
	blocks: [chunkVolume]Block = undefined,

	wasChanged: bool = false,
	/// When a chunk is cleaned, it won't be saved by the ChunkManager anymore, so following changes need to be saved directly.
	wasCleaned: bool = false,
	generated: bool = false,

	width: ChunkCoordinate,
	voxelSizeShift: u5,
	voxelSizeMask: ChunkCoordinate,
	widthShift: u5,
	mutex: std.Thread.Mutex,

	pub fn init(self: *Chunk, pos: ChunkPosition) void {
		std.debug.assert((pos.voxelSize - 1 & pos.voxelSize) == 0);
		std.debug.assert(@mod(pos.wx, pos.voxelSize) == 0 and @mod(pos.wy, pos.voxelSize) == 0 and @mod(pos.wz, pos.voxelSize) == 0);
		const voxelSizeShift = @intCast(u5, std.math.log2_int(UChunkCoordinate, pos.voxelSize));
		self.* = Chunk {
			.pos = pos,
			.width = pos.voxelSize*chunkSize,
			.voxelSizeShift = voxelSizeShift,
			.voxelSizeMask = pos.voxelSize - 1,
			.widthShift = voxelSizeShift + chunkShift,
			.mutex = std.Thread.Mutex{},
		};
	}

	pub fn setChanged(self: *Chunk) void {
		self.wasChanged = true;
		{
			self.mutex.lock();
			if(self.wasCleaned) {
				self.save();
			}
			self.mutex.unlock();
		}
	}

	pub fn clean(self: *Chunk) void {
		{
			self.mutex.lock();
			self.wasCleaned = true;
			self.save();
			self.mutex.unlock();
		}
	}

	pub fn unclean(self: *Chunk) void {
		{
			self.mutex.lock();
			self.wasCleaned = false;
			self.save();
			self.mutex.unlock();
		}
	}

	/// Checks if the given relative coordinates lie within the bounds of this chunk.
	pub fn liesInChunk(self: *const Chunk, x: ChunkCoordinate, y: ChunkCoordinate, z: ChunkCoordinate) bool {
		return x >= 0 and x < self.width
			and y >= 0 and y < self.width
			and z >= 0 and z < self.width;
	}

	/// This is useful to convert for loops to work for reduced resolution:
	/// Instead of using
	/// for(int x = start; x < end; x++)
	/// for(int x = chunk.startIndex(start); x < end; x += chunk.getVoxelSize())
	/// should be used to only activate those voxels that are used in Cubyz's downscaling technique.
	pub fn startIndex(self: *const Chunk, start: ChunkCoordinate) ChunkCoordinate {
		return start+self.voxelSizeMask & ~self.voxelSizeMask; // Rounds up to the nearest valid voxel coordinate.
	}

	/// Updates a block if current value is air or the current block is degradable.
	/// Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	pub fn updateBlockIfDegradable(self: *Chunk, x: ChunkCoordinate, y: ChunkCoordinate, z: ChunkCoordinate, newBlock: Block) void {
		x >>= self.voxelSizeShift;
		y >>= self.voxelSizeShift;
		z >>= self.voxelSizeShift;
		var index = getIndex(x, y, z);
		if (self.blocks[index] == 0 || self.blocks[index].degradable()) {
			self.blocks[index] = newBlock;
		}
	}

	/// Updates a block if it is inside this chunk.
	/// Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	pub fn updateBlock(self: *Chunk, x: ChunkCoordinate, y: ChunkCoordinate, z: ChunkCoordinate, newBlock: Block) void {
		x >>= self.voxelSizeShift;
		y >>= self.voxelSizeShift;
		z >>= self.voxelSizeShift;
		var index = getIndex(x, y, z);
		self.blocks[index] = newBlock;
	}

	/// Updates a block if it is inside this chunk. Should be used in generation to prevent accidently storing these as changes.
	/// Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	pub fn updateBlockInGeneration(self: *Chunk, x: ChunkCoordinate, y: ChunkCoordinate, z: ChunkCoordinate, newBlock: Block) void {
		x >>= self.voxelSizeShift;
		y >>= self.voxelSizeShift;
		z >>= self.voxelSizeShift;
		var index = getIndex(x, y, z);
		self.blocks[index] = newBlock;
	}

	/// Gets a block if it is inside this chunk.
	/// Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	pub fn getBlock(self: *const Chunk, _x: ChunkCoordinate, _y: ChunkCoordinate, _z: ChunkCoordinate) Block {
		var x = _x >> self.voxelSizeShift;
		var y = _y >> self.voxelSizeShift;
		var z = _z >> self.voxelSizeShift;
		var index = getIndex(x, y, z);
		return self.blocks[index];
	}

	pub fn getNeighbors(self: *const Chunk, x: ChunkCoordinate, y: ChunkCoordinate, z: ChunkCoordinate, neighborsArray: *[6]Block) void {
		std.debug.assert(neighborsArray.length == 6);
		x &= chunkMask;
		y &= chunkMask;
		z &= chunkMask;
		for(Neighbors.relX) |_, i| {
			var xi = x + Neighbors.relX[i];
			var yi = y + Neighbors.relY[i];
			var zi = z + Neighbors.relZ[i];
			if (xi == (xi & chunkMask) and yi == (yi & chunkMask) and zi == (zi & chunkMask)) { // Simple double-bound test for coordinates.
				neighborsArray[i] = self.getBlock(xi, yi, zi);
			} else {
				// TODO: What about other chunks?
//				NormalChunk ch = world.getChunk(xi + wx, yi + wy, zi + wz);
//				if (ch != null) {
//					neighborsArray[i] = ch.getBlock(xi & chunkMask, yi & chunkMask, zi & chunkMask);
//				} else {
//					neighborsArray[i] = 1; // Some solid replacement, in case the chunk isn't loaded. TODO: Properly choose a solid block.
//				}
			}
		}
	}

	pub fn updateFromLowerResolution(self: *Chunk, other: *const Chunk) void {
		const xOffset = if(other.wx != self.wx) chunkSize/2 else 0; // Offsets of the lower resolution chunk in this chunk.
		const yOffset = if(other.wy != self.wy) chunkSize/2 else 0;
		const zOffset = if(other.wz != self.wz) chunkSize/2 else 0;
		
		var x: ChunkCoordinate = 0;
		while(x < chunkSize/2): (x += 1) {
			var y: ChunkCoordinate = 0;
			while(y < chunkSize/2): (y += 1) {
				var z: ChunkCoordinate = 0;
				while(z < chunkSize/2): (z += 1) {
					// Count the neighbors for each subblock. An transparent block counts 5. A chunk border(unknown block) only counts 1.
					var neighborCount: [8]u32 = undefined;
					var octantBlocks: [8]Block = undefined;
					var maxCount: u32 = 0;
					var dx: ChunkCoordinate = 0;
					while(dx <= 1): (dx += 1) {
						var dy: ChunkCoordinate = 0;
						while(dy <= 1): (dy += 1) {
							var dz: ChunkCoordinate = 0;
							while(dz <= 1): (dz += 1) {
								const index = getIndex(x*2 + dx, y*2 + dy, z*2 + dz);
								const i = dx*4 + dz*2 + dy;
								octantBlocks[i] = other.blocks[index];
								if(octantBlocks[i] == 0) continue; // I don't care about air blocks.
								
								var count: u32 = 0;
								for(Neighbors.iterable) |n| {
									const nx = x*2 + dx + Neighbors.relX[n];
									const ny = y*2 + dy + Neighbors.relY[n];
									const nz = z*2 + dz + Neighbors.relZ[n];
									if((nx & chunkMask) == nx and (ny & chunkMask) == ny and (nz & chunkMask) == nz) { // If it's inside the chunk.
										const neighborIndex = getIndex(nx, ny, nz);
										if(other.blocks[neighborIndex].transparent()) {
											count += 5;
										}
									} else {
										count += 1;
									}
								}
								maxCount = @max(maxCount, count);
								neighborCount[i] = count;
							}
						}
					}
					// Uses a specific permutation here that keeps high resolution patterns in lower resolution.
					const permutationStart = (x & 1)*4 + (z & 1)*2 + (y & 1);
					const block = Block{.typ = 0, .data = 0};
					for(neighborCount) |_, i| {
						const appliedPermutation = permutationStart ^ i;
						if(neighborCount[appliedPermutation] >= maxCount - 1) { // Avoid pattern breaks at chunk borders.
							block = blocks[appliedPermutation];
						}
					}
					// Update the block:
					const thisIndex = getIndex(x + xOffset, y + yOffset, z + zOffset);
					self.blocks[thisIndex] = block;
				}
			}
		}
		
		// Create updated meshes and send to client:
		// TODO:
		//for(int x = 0; x <= 2*xOffset; x += chunkSize) {
		//	for(int y = 0; y <= 2*yOffset; y += chunkSize) {
		//		for(int z = 0; z <= 2*zOffset; z += chunkSize) {
		//			int wx = this.wx + x*voxelSize - Chunk.chunkSize;
		//			int wy = this.wy + y*voxelSize - Chunk.chunkSize;
		//			int wz = this.wz + z*voxelSize - Chunk.chunkSize;
		//			if(voxelSize == 32) {
		//				wx -= chunkSize*voxelSize/2;
		//				wy -= chunkSize*voxelSize/2;
		//				wz -= chunkSize*voxelSize/2;
		//			}
		//			world.queueChunks(new ChunkData[] {new ChunkData(wx, wy, wz, voxelSize)});
		//		}
		//	}
		//}
		
		self.setChanged();
	}
// TODO: Move this outside.
//	/**
//	 * Generates this chunk.
//	 * If the chunk was already saved it is loaded from file instead.
//	 * @param seed
//	 * @param terrainGenerationProfile
//	 */
//	public void generate(World world, long seed, TerrainGenerationProfile terrainGenerationProfile) {
//		assert !generated : "Seriously, why would you generate this chunk twice???";
//		if(!ChunkIO.loadChunkFromFile(world, this)) {
//			CaveMap caveMap = new CaveMap(this);
//			CaveBiomeMap biomeMap = new CaveBiomeMap(this);
//			
//			for (Generator g : terrainGenerationProfile.generators) {
//				g.generate(seed ^ g.getGeneratorSeed(), wx, wy, wz, this, caveMap, biomeMap);
//			}
//		}
//		generated = true;
//	}


//	TODO:
	pub fn save(chunk: *const Chunk) void {
		_ = chunk;
//	/**
//	 * Saves this chunk.
//	 */
//	public void save(World world) {
//		if(wasChanged) {
//			ChunkIO.storeChunkToFile(world, this);
//			wasChanged = false;
//			// Update the next lod chunk:
//			if(voxelSize != 1 << Constants.HIGHEST_LOD) {
//				if(world instanceof ServerWorld) {
//					ReducedChunk chunk = ((ServerWorld)world).chunkManager.getOrGenerateReducedChunk(wx, wy, wz, voxelSize*2);
//					chunk.updateFromLowerResolution(this);
//				} else {
//					Logger.error("Not implemented: ");
//					Logger.error(new Exception());
//				}
//			}
//		}
	}

//	TODO: Check if/how they are needed:
//	
//	public Vector3d getMin() {
//		return new Vector3d(wx, wy, wz);
//	}
//	
//	public Vector3d getMax() {
//		return new Vector3d(wx + width, wy + width, wz + width);
//	}
};


pub const meshing = struct {
	var shader: Shader = undefined;
	pub var uniforms: struct {
		projectionMatrix: c_int,
		viewMatrix: c_int,
		modelPosition: c_int,
		ambientLight: c_int,
		@"fog.activ": c_int,
		@"fog.color": c_int,
		@"fog.density": c_int,
		texture_sampler: c_int,
		emissionSampler: c_int,
		@"waterFog.activ": c_int,
		@"waterFog.color": c_int,
		@"waterFog.density": c_int,
		time: c_int,
		visibilityMask: c_int,
		voxelSize: c_int,
		integerPosition: c_int,
	} = undefined;
	var vao: c_uint = undefined;
	var vbo: c_uint = undefined;
	var faces: std.ArrayList(u32) = undefined;
	var faceData: graphics.LargeBuffer = undefined;

	pub fn init() !void {
		shader = try Shader.create("assets/cubyz/shaders/chunks/chunk_vertex.vs", "assets/cubyz/shaders/chunks/chunk_fragment.fs");
		uniforms = shader.bulkGetUniformLocation(@TypeOf(uniforms));

		var rawData: [6*3 << (3*chunkShift)]u32 = undefined; // 6 vertices per face, maximum 3 faces/block
		const lut = [_]u32{0, 1, 2, 2, 1, 3};
		for(rawData) |_, i| {
			rawData[i] = @intCast(u32, i)/6*4 + lut[i%6];
		}

		c.glGenVertexArrays(1, &vao);
		c.glBindVertexArray(vao);
		c.glGenBuffers(1, &vbo);
		c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, vbo);
		c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, rawData.len*@sizeOf(f32), &rawData, c.GL_STATIC_DRAW);
		c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 2*@sizeOf(f32), null);
		c.glBindVertexArray(0);

		faces = try std.ArrayList(u32).initCapacity(std.heap.page_allocator, 65536);
		try faceData.init(main.globalAllocator, 128 << 20, 3);
	}

	pub fn deinit() void {
		shader.delete();
		c.glDeleteVertexArrays(1, &vao);
		c.glDeleteBuffers(1, &vbo);
		faces.deinit();
		faceData.deinit();
	}

	pub fn bindShaderAndUniforms(projMatrix: Mat4f, ambient: Vec3f, time: u32) void {
		shader.bind();

		c.glUniform1i(uniforms.@"fog.activ", if(game.fog.active) 1 else 0);
		c.glUniform3fv(uniforms.@"fog.color", 1, @ptrCast([*c]f32, &game.fog.color));
		c.glUniform1f(uniforms.@"fog.density", game.fog.density);

		c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_FALSE, @ptrCast([*c]const f32, &projMatrix));

		c.glUniform1i(uniforms.texture_sampler, 0);
		c.glUniform1i(uniforms.emissionSampler, 1);

		c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_FALSE, @ptrCast([*c]f32, &game.camera.viewMatrix));

		c.glUniform3f(uniforms.ambientLight, ambient[0], ambient[1], ambient[2]);

		c.glUniform1i(uniforms.time, @bitCast(i32, time));

		c.glBindVertexArray(vao);
	}

	pub const ChunkMesh = struct {
		pos: ChunkPosition,
		size: ChunkCoordinate,
		chunk: std.atomic.Atomic(?*Chunk),
		faces: std.ArrayList(u32),
		bufferAllocation: graphics.LargeBuffer.Allocation = .{.start = 0, .len = 0},
		coreCount: u31 = 0,
		neighborStart: [7]u31 = [_]u31{0} ** 7,
		vertexCount: u31 = 0,
		generated: bool = false,
		mutex: std.Thread.Mutex = std.Thread.Mutex{},
		visibilityMask: u8 = 0xff,

		pub fn init(allocator: Allocator, pos: ChunkPosition) ChunkMesh {
			return ChunkMesh{
				.pos = pos,
				.size = chunkSize*pos.voxelSize,
				.faces = std.ArrayList(u32).init(allocator),
				.chunk = std.atomic.Atomic(?*Chunk).init(null),
			};
		}

		pub fn deinit(self: *ChunkMesh) void {
			faceData.free(self.bufferAllocation) catch unreachable;
			self.faces.deinit();
			if(self.chunk.load(.Monotonic)) |ch| {
				renderer.RenderStructure.allocator.destroy(ch);
			}
		}

		fn canBeSeenThroughOtherBlock(block: Block, other: Block, neighbor: u3) bool {
			const model = &models.voxelModels.items[blocks.meshes.modelIndices(block)];
			const freestandingModel = blk:{
				switch(neighbor) {
					Neighbors.dirNegX => {
						break :blk model.minX != 0;
					},
					Neighbors.dirPosX => {
						break :blk model.maxX != 16;
					},
					Neighbors.dirDown => {
						break :blk model.minY != 0;
					},
					Neighbors.dirUp => {
						break :blk model.maxY != 16;
					},
					Neighbors.dirNegZ => {
						break :blk model.minZ != 0;
					},
					Neighbors.dirPosZ => {
						break :blk model.maxZ != 16;
					},
					else => unreachable,
				}
			};
			return block.typ != 0 and (
				freestandingModel
				or other.typ == 0
				or false  // TODO: Blocks.mode(other).checkTransparency(other, neighbor) // TODO: make blocks.meshes.modelIndices(other) != 0 more strict to avoid overdraw.
				or (!std.meta.eql(block, other) and other.viewThrough())
				or blocks.meshes.modelIndices(other) != 0
			);
		}

		pub fn regenerateMainMesh(self: *ChunkMesh, chunk: *Chunk) !void {
			std.debug.assert(!self.mutex.tryLock()); // The mutex should be locked when calling this function.
			self.faces.clearRetainingCapacity();
			var n: u32 = 0;
			var x: u8 = 0;
			while(x < chunkSize): (x += 1) {
				var y: u8 = 0;
				while(y < chunkSize): (y += 1) {
					var z: u8 = 0;
					while(z < chunkSize): (z += 1) {
						const block = (&chunk.blocks)[getIndex(x, y, z)]; // ← a temporary fix to a compiler performance bug. TODO: check if this was fixed.
						if(block.typ == 0) continue;
						// Check all neighbors:
						for(Neighbors.iterable) |i| {
							n += 1;
							const x2 = x + Neighbors.relX[i];
							const y2 = y + Neighbors.relY[i];
							const z2 = z + Neighbors.relZ[i];
							if(x2&chunkMask != x2 or y2&chunkMask != y2 or z2&chunkMask != z2) continue; // Neighbor is outside the chunk.
							const neighborBlock = (&chunk.blocks)[getIndex(x2, y2, z2)]; // ← a temporary fix to a compiler performance bug. TODO: check if this was fixed.
							if(canBeSeenThroughOtherBlock(block, neighborBlock, i)) {
								const normal: u32 = i;
								const positionNormal: u32 = @intCast(u32, x2) | @intCast(u32, y2)<<5 | @intCast(u32, z2)<<10 | normal<<24;
								const textureModel = block.typ | @as(u32, blocks.meshes.modelIndices(block))<<16;
								try self.faces.append(positionNormal);
								try self.faces.append(textureModel);
							}
						}
					}
				}
			}

			if(self.chunk.load(.Monotonic)) |oldChunk| {
				renderer.RenderStructure.allocator.destroy(oldChunk);
			}
			self.chunk.store(chunk, .Monotonic);
			self.coreCount = @intCast(u31, self.faces.items.len);
			self.neighborStart = [_]u31{self.coreCount} ** 7;
		}

		fn addFace(self: *ChunkMesh, position: u32, textureNormal: u32, fromNeighborChunk: ?u3) !void {
			std.debug.assert(!self.mutex.tryLock()); // The mutex should be locked when calling this function.
			var insertionIndex: u31 = undefined;
			if(fromNeighborChunk) |neighbor| {
				insertionIndex = self.neighborStart[neighbor];
				for(self.neighborStart[neighbor+1..]) |*start| {
					start.* += 2;
				}
			} else {
				insertionIndex = self.coreCount;
				self.coreCount += 2;
				for(self.neighborStart) |*start| {
					start.* += 2;
				}
			}
			try self.faces.insert(insertionIndex, position);
			try self.faces.insert(insertionIndex+1, textureNormal);
		}

		fn removeFace(self: *ChunkMesh, position: u32, textureNormal: u32, fromNeighborChunk: ?u3) void {
			std.debug.assert(!self.mutex.tryLock()); // The mutex should be locked when calling this function.
			var searchStart: u32 = undefined;
			var searchEnd: u32 = undefined;
			if(fromNeighborChunk) |neighbor| {
				searchStart = self.neighborStart[neighbor];
				searchEnd = self.neighborStart[neighbor+1];
				for(self.neighborStart[neighbor+1..]) |*start| {
					start.* -= 2;
				}
			} else {
				searchStart = 0;
				searchEnd = self.coreCount;
				self.coreCount -= 2;
				for(self.neighborStart) |*start| {
					start.* -= 2;
				}
			}
			var i: u32 = searchStart;
			while(i < searchEnd): (i += 2) {
				if(self.faces.items[i] == position and self.faces.items[i+1] == textureNormal) {
					_ = self.faces.orderedRemove(i+1);
					_ = self.faces.orderedRemove(i);
					return;
				}
			}
			@panic("Couldn't find the face to remove. This case is not handled.");
		}

		fn changeFace(self: *ChunkMesh, position: u32, oldTextureNormal: u32, newTextureNormal: u32, fromNeighborChunk: ?u3) void {
			std.debug.assert(!self.mutex.tryLock()); // The mutex should be locked when calling this function.
			var searchRange: []u32 = undefined;
			if(fromNeighborChunk) |neighbor| {
				searchRange = self.faces.items[self.neighborStart[neighbor]..self.neighborStart[neighbor+1]];
			} else {
				searchRange = self.faces.items[0..self.coreCount];
			}
			var i: u32 = 0;
			while(i < searchRange.len): (i += 2) {
				if(searchRange[i] == position and searchRange[i+1] == oldTextureNormal) {
					searchRange[i+1] = newTextureNormal;
					return;
				}
			}
			std.log.err("Couldn't find the face to replace.", .{});
		}

		pub fn updateBlock(self: *ChunkMesh, _x: ChunkCoordinate, _y: ChunkCoordinate, _z: ChunkCoordinate, newBlock: Block) !void {
			const x = _x & chunkMask;
			const y = _y & chunkMask;
			const z = _z & chunkMask;
			self.mutex.lock();
			defer self.mutex.unlock();
			if(!self.generated) return;
			const oldBlock = self.chunk.load(.Monotonic).?.blocks[getIndex(x, y, z)];
			for(Neighbors.iterable) |neighbor| {
				var neighborMesh = self;
				var nx = x + Neighbors.relX[neighbor];
				var ny = y + Neighbors.relY[neighbor];
				var nz = z + Neighbors.relZ[neighbor];
				if(nx & chunkMask != nx or ny & chunkMask != ny or nz & chunkMask != nz) { // Outside this chunk.
					neighborMesh = renderer.RenderStructure.getNeighbor(self.pos, self.pos.voxelSize, neighbor) orelse continue;
					if(!neighborMesh.generated) continue;
					neighborMesh.mutex.lock();
				}
				defer if(neighborMesh != self) neighborMesh.mutex.unlock();
				nx &= chunkMask;
				ny &= chunkMask;
				nz &= chunkMask;
				const neighborBlock = neighborMesh.chunk.load(.Monotonic).?.blocks[getIndex(nx, ny, nz)];
				{
					{ // The face of the changed block
						const newVisibility = canBeSeenThroughOtherBlock(newBlock, neighborBlock, neighbor);
						const normal: u32 = neighbor;
						const position: u32 = @intCast(u32, nx) | @intCast(u32, ny)<<5 | @intCast(u32, nz)<<10 | normal<<24;
						const newTextureNormal = newBlock.typ | @as(u32, blocks.meshes.modelIndices(newBlock))<<16;
						const oldTextureNormal = oldBlock.typ | @as(u32, blocks.meshes.modelIndices(oldBlock))<<16;
						if(canBeSeenThroughOtherBlock(oldBlock, neighborBlock, neighbor) != newVisibility) {
							if(newVisibility) { // Adding the face
								if(neighborMesh == self) {
									try self.addFace(position, newTextureNormal, null);
								} else {
									try neighborMesh.addFace(position, newTextureNormal, neighbor);
								}
							} else { // Removing the face
								if(neighborMesh == self) {
									self.removeFace(position, oldTextureNormal, null);
								} else {
									neighborMesh.removeFace(position, oldTextureNormal, neighbor);
								}
							}
						} else if(newVisibility) { // Changing the face
							if(neighborMesh == self) {
								self.changeFace(position, oldTextureNormal, newTextureNormal, null);
							} else {
								neighborMesh.changeFace(position, oldTextureNormal, newTextureNormal, neighbor);
							}
						}
					}
					{ // The face of the neighbor block
						const newVisibility = canBeSeenThroughOtherBlock(neighborBlock, newBlock, neighbor ^ 1);
						const normal: u32 = neighbor ^ 1;
						const position: u32 = @intCast(u32, x) | @intCast(u32, y)<<5 | @intCast(u32, z)<<10 | normal<<24;
						const newTextureNormal = neighborBlock.typ | @as(u32, blocks.meshes.modelIndices(neighborBlock))<<16;
						const oldTextureNormal = neighborBlock.typ | @as(u32, blocks.meshes.modelIndices(neighborBlock))<<16;
						if(canBeSeenThroughOtherBlock(neighborBlock, oldBlock, neighbor ^ 1) != newVisibility) {
							if(newVisibility) { // Adding the face
								if(neighborMesh == self) {
									try self.addFace(position, newTextureNormal, null);
								} else {
									try self.addFace(position, newTextureNormal, neighbor);
								}
							} else { // Removing the face
								if(neighborMesh == self) {
									self.removeFace(position, oldTextureNormal, null);
								} else {
									self.removeFace(position, oldTextureNormal, neighbor);
								}
							}
						} else if(newVisibility) { // Changing the face
							if(neighborMesh == self) {
								self.changeFace(position, oldTextureNormal, newTextureNormal, null);
							} else {
								self.changeFace(position, oldTextureNormal, newTextureNormal, neighbor);
							}
						}
					}
				}
				if(neighborMesh != self) try neighborMesh.uploadData();
			}
			self.chunk.load(.Monotonic).?.blocks[getIndex(x, y, z)] = newBlock;
			try self.uploadData();
		}

		fn uploadData(self: *ChunkMesh) !void {
			self.vertexCount = @intCast(u31, 6*self.faces.items.len/2);
			try faceData.realloc(&self.bufferAllocation, @intCast(u31, 4*self.faces.items.len));
			faceData.bufferSubData(self.bufferAllocation.start, u32, self.faces.items);
		}

		pub fn uploadDataAndFinishNeighbors(self: *ChunkMesh) !void {
			std.debug.assert(!self.mutex.tryLock()); // The mutex should be locked when calling this function.
			const chunk = self.chunk.load(.Monotonic) orelse return; // In the mean-time the mesh was discarded and recreated and all the data was lost.
			self.faces.shrinkRetainingCapacity(self.coreCount);
			for(Neighbors.iterable) |neighbor| {
				self.neighborStart[neighbor] = @intCast(u31, self.faces.items.len);
				var nullNeighborMesh = renderer.RenderStructure.getNeighbor(self.pos, self.pos.voxelSize, neighbor);
				if(nullNeighborMesh) |neighborMesh| {
					std.debug.assert(neighborMesh != self);
					neighborMesh.mutex.lock();
					defer neighborMesh.mutex.unlock();
					if(neighborMesh.generated) {
						var additionalNeighborFaces = std.ArrayList(u32).init(main.threadAllocator);
						defer additionalNeighborFaces.deinit();
						var x3: u8 = if(neighbor & 1 == 0) @intCast(u8, chunkMask) else 0;
						var x1: u8 = 0;
						while(x1 < chunkSize): (x1 += 1) {
							var x2: u8 = 0;
							while(x2 < chunkSize): (x2 += 1) {
								var x: u8 = undefined;
								var y: u8 = undefined;
								var z: u8 = undefined;
								if(Neighbors.relX[neighbor] != 0) {
									x = x3;
									y = x1;
									z = x2;
								} else if(Neighbors.relY[neighbor] != 0) {
									x = x1;
									y = x3;
									z = x2;
								} else {
									x = x2;
									y = x1;
									z = x3;
								}
								var otherX = @intCast(u8, x+%Neighbors.relX[neighbor] & chunkMask);
								var otherY = @intCast(u8, y+%Neighbors.relY[neighbor] & chunkMask);
								var otherZ = @intCast(u8, z+%Neighbors.relZ[neighbor] & chunkMask);
								var block = (&chunk.blocks)[getIndex(x, y, z)]; // ← a temporary fix to a compiler performance bug. TODO: check if this was fixed.
								var otherBlock = (&neighborMesh.chunk.load(.Monotonic).?.blocks)[getIndex(otherX, otherY, otherZ)]; // ← a temporary fix to a compiler performance bug. TODO: check if this was fixed.
								if(canBeSeenThroughOtherBlock(block, otherBlock, neighbor)) {
									const normal: u32 = neighbor;
									const position: u32 = @as(u32, otherX) | @as(u32, otherY)<<5 | @as(u32, otherZ)<<10 | normal<<24;
									const textureNormal = block.typ | @as(u32, blocks.meshes.modelIndices(block))<<16;
									try additionalNeighborFaces.append(position);
									try additionalNeighborFaces.append(textureNormal);
								}
								if(canBeSeenThroughOtherBlock(otherBlock, block, neighbor ^ 1)) {
									const normal: u32 = neighbor ^ 1;
									const position: u32 = @as(u32, x) | @as(u32, y)<<5 | @as(u32, z)<<10 | normal<<24;
									const textureNormal = otherBlock.typ | @as(u32, blocks.meshes.modelIndices(otherBlock))<<16;
									try self.faces.append(position);
									try self.faces.append(textureNormal);
								}
							}
						}
						var rangeStart = neighborMesh.neighborStart[neighbor ^ 1];
						var rangeEnd = neighborMesh.neighborStart[(neighbor ^ 1)+1];
						try neighborMesh.faces.replaceRange(rangeStart, rangeEnd - rangeStart, additionalNeighborFaces.items);
						for(neighborMesh.neighborStart[1+(neighbor ^ 1)..]) |*neighborStart| {
							neighborStart.* = neighborStart.* - (rangeEnd - rangeStart) + @intCast(u31, additionalNeighborFaces.items.len);
						}
						try neighborMesh.uploadData();
						continue;
					}
				}
				// lod border:
				if(self.pos.voxelSize == 1 << settings.highestLOD) continue;
				var neighborMesh = renderer.RenderStructure.getNeighbor(self.pos, 2*self.pos.voxelSize, neighbor) orelse return error.LODMissing;
				neighborMesh.mutex.lock();
				defer neighborMesh.mutex.unlock();
				if(neighborMesh.generated) {
					const x3: u8 = if(neighbor & 1 == 0) @intCast(u8, chunkMask) else 0;
					const offsetX = @divExact(self.pos.wx, self.pos.voxelSize) & chunkSize;
					const offsetY = @divExact(self.pos.wy, self.pos.voxelSize) & chunkSize;
					const offsetZ = @divExact(self.pos.wz, self.pos.voxelSize) & chunkSize;
					var x1: u8 = 0;
					while(x1 < chunkSize): (x1 += 1) {
						var x2: u8 = 0;
						while(x2 < chunkSize): (x2 += 1) {
							var x: u8 = undefined;
							var y: u8 = undefined;
							var z: u8 = undefined;
							if(Neighbors.relX[neighbor] != 0) {
								x = x3;
								y = x1;
								z = x2;
							} else if(Neighbors.relY[neighbor] != 0) {
								x = x1;
								y = x3;
								z = x2;
							} else {
								x = x2;
								y = x1;
								z = x3;
							}
							var otherX = @intCast(u8, (x+%Neighbors.relX[neighbor]+%offsetX >> 1) & chunkMask);
							var otherY = @intCast(u8, (y+%Neighbors.relY[neighbor]+%offsetY >> 1) & chunkMask);
							var otherZ = @intCast(u8, (z+%Neighbors.relZ[neighbor]+%offsetZ >> 1) & chunkMask);
							var block = (&chunk.blocks)[getIndex(x, y, z)]; // ← a temporary fix to a compiler performance bug. TODO: check if this was fixed.
							var otherBlock = (&neighborMesh.chunk.load(.Monotonic).?.blocks)[getIndex(otherX, otherY, otherZ)]; // ← a temporary fix to a compiler performance bug. TODO: check if this was fixed.
							if(canBeSeenThroughOtherBlock(otherBlock, block, neighbor ^ 1)) {
								const normal: u32 = neighbor ^ 1;
								const position: u32 = @as(u32, x) | @as(u32, y)<<5 | @as(u32, z)<<10 | normal<<24;
								const textureNormal = otherBlock.typ | @as(u32, blocks.meshes.modelIndices(otherBlock))<<16;
								try self.faces.append(position);
								try self.faces.append(textureNormal);
							}
						}
					}
				} else {
					return error.LODMissing;
				}
			}
			self.neighborStart[6] = @intCast(u31, self.faces.items.len);
			try self.uploadData();
			self.generated = true;
		}

		pub fn render(self: *ChunkMesh, playerPosition: Vec3d) void {
			if(!self.generated) {
				return;
			}
			if(self.vertexCount == 0) return;
			c.glUniform3f(
				uniforms.modelPosition,
				@floatCast(f32, @intToFloat(f64, self.pos.wx) - playerPosition[0]),
				@floatCast(f32, @intToFloat(f64, self.pos.wy) - playerPosition[1]),
				@floatCast(f32, @intToFloat(f64, self.pos.wz) - playerPosition[2])
			);
			c.glUniform3i(uniforms.integerPosition, self.pos.wx, self.pos.wy, self.pos.wz);
			c.glUniform1i(uniforms.visibilityMask, self.visibilityMask);
			c.glUniform1i(uniforms.voxelSize, self.pos.voxelSize);
			c.glDrawElementsBaseVertex(c.GL_TRIANGLES, self.vertexCount, c.GL_UNSIGNED_INT, null, self.bufferAllocation.start/8*4);
		}
	};
};