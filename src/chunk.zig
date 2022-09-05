const std = @import("std");
const Allocator = std.mem.Allocator;

const blocks = @import("blocks.zig");
const Block = blocks.Block;
const game = @import("game.zig");
const graphics = @import("graphics.zig");
const c = graphics.c;
const Shader = graphics.Shader;
const SSBO = graphics.SSBO;
const Vec3f = @import("vec.zig").Vec3f;
const Vec3d = @import("vec.zig").Vec3d;
const Mat4f = @import("vec.zig").Mat4f;

pub const ChunkCoordinate = u32;
pub const chunkShift: u5 = 5;
pub const chunkShift2: u5 = chunkShift*2;
pub const chunkSize: ChunkCoordinate = 1 << chunkShift;
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
	pub const relX = [_]u32 {0, 0, 1, -1, 0, 0};
	/// Index to relative position
	pub const relY = [_]u32 {1, -1, 0, 0, 0, 0};
	/// Index to relative position
	pub const relZ = [_]u32 {0, 0, 0, 0, 1, -1};
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

pub const ChunkPosition = struct {
	wx: ChunkCoordinate,
	wy: ChunkCoordinate,
	wz: ChunkCoordinate,
	voxelSize: ChunkCoordinate,
	
//	TODO(mabye?):
//	public int hashCode() {
//		int shift = Math.min(Integer.numberOfTrailingZeros(wx), Math.min(Integer.numberOfTrailingZeros(wy), Integer.numberOfTrailingZeros(wz)));
//		return (((wx >> shift) * 31 + (wy >> shift)) * 31 + (wz >> shift)) * 31 + voxelSize;
//	}
//	TODO:
//	public float getPriority(Player source) {
//		int halfWidth = voxelSize * Chunk.chunkSize / 2;
//		return -(float) source.getPosition().distance(wx + halfWidth, wy + halfWidth, wz + halfWidth) / voxelSize;
//	}
//	public double getMinDistanceSquared(double px, double py, double pz) {
//		int halfWidth = voxelSize * Chunk.chunkSize / 2;
//		double dx = Math.abs(wx + halfWidth - px);
//		double dy = Math.abs(wy + halfWidth - py);
//		double dz = Math.abs(wz + halfWidth - pz);
//		dx = Math.max(0, dx - halfWidth);
//		dy = Math.max(0, dy - halfWidth);
//		dz = Math.max(0, dz - halfWidth);
//		return dx*dx + dy*dy + dz*dz;
//	}
};

pub const Chunk = struct {
	pos: ChunkPosition,
	blocks: [chunkSize*chunkSize*chunkSize]Block = undefined,

	wasChanged: bool = false,
	/// When a chunk is cleaned, it won't be saved by the ChunkManager anymore, so following changes need to be saved directly.
	wasCleaned: bool = false,
	generated: bool = false,

	width: ChunkCoordinate,
	voxelSizeShift: u5,
	voxelSizeMask: ChunkCoordinate,
	widthShift: u5,
	mutex: std.Thread.Mutex,

	pub fn init(wx: ChunkCoordinate, wy: ChunkCoordinate, wz: ChunkCoordinate, voxelSize: ChunkCoordinate) Chunk {
		std.debug.assert((voxelSize - 1 & voxelSize) == 0, "the voxel size must be a power of 2.");
		std.debug.assert(wx % voxelSize == 0 and wy % voxelSize == 0 and wz % voxelSize == 0);
		return Chunk {
			.pos = ChunkPosition {
				.wx = wx, .wy = wy, .wz = wz, .voxelSize = voxelSize
			},
			.width = voxelSize*chunkSize,
			.voxelSizeShift = @intCast(u5, std.math.log2_int(u32, voxelSize)),
			.voxelSizeMask = voxelSize - 1,
			.widthShift = .voxelSizeShift + chunkShift,
			.mutex = std.Thread.Mutex{},
		};
	}

	pub fn setChanged(self: *const Chunk) void {
		self.wasChanged = true;
		{
			self.mutex.lock();
			if(self.wasCleaned) {
				self.save();
			}
			self.mutex.unlock();
		}
	}

	pub fn clean(self: *const Chunk) void {
		{
			self.mutex.lock();
			self.wasCleaned = true;
			self.save();
			self.mutex.unlock();
		}
	}

	pub fn unclean(self: *const Chunk) void {
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
	pub fn updateBlockIfDegradable(self: *const Chunk, x: ChunkCoordinate, y: ChunkCoordinate, z: ChunkCoordinate, newBlock: Block) void {
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
	pub fn updateBlock(self: *const Chunk, x: ChunkCoordinate, y: ChunkCoordinate, z: ChunkCoordinate, newBlock: Block) void {
		x >>= self.voxelSizeShift;
		y >>= self.voxelSizeShift;
		z >>= self.voxelSizeShift;
		var index = getIndex(x, y, z);
		self.blocks[index] = newBlock;
	}

	///  Updates a block if it is inside this chunk. Should be used in generation to prevent accidently storing these as changes.
	/// Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	pub fn updateBlockInGeneration(self: *const Chunk, x: ChunkCoordinate, y: ChunkCoordinate, z: ChunkCoordinate, newBlock: Block) void {
		x >>= self.voxelSizeShift;
		y >>= self.voxelSizeShift;
		z >>= self.voxelSizeShift;
		var index = getIndex(x, y, z);
		self.blocks[index] = newBlock;
	}

	/// Gets a block if it is inside this chunk.
	/// Does not do any bound checks. They are expected to be done with the `liesInChunk` function.
	pub fn getBlock(self: *const Chunk, x: ChunkCoordinate, y: ChunkCoordinate, z: ChunkCoordinate) Block {
		x >>= self.voxelSizeShift;
		y >>= self.voxelSizeShift;
		z >>= self.voxelSizeShift;
		var index = getIndex(x, y, z);
		return self.blocks[index];
	}

	pub fn updateFromLowerResolution(self: *const Chunk, other: *const Chunk) void {
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
								maxCount = @maximum(maxCount, count);
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
		
		setChanged();
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
};






//	TODO: Check if/how they are needed:
//	
//	public Vector3d getMin() {
//		return new Vector3d(wx, wy, wz);
//	}
//	
//	public Vector3d getMax() {
//		return new Vector3d(wx + width, wy + width, wz + width);
//	}
//	
//	@Override
//	public byte[] saveToByteArray() {
//		byte[] data = new byte[4*blocks.length];
//		for(int i = 0; i < blocks.length; i++) {
//			Bits.putInt(data, i*4, blocks[i]);
//		}
//		return data;
//	}
//	
//	@Override
//	public boolean loadFromByteArray(byte[] data, int outputLength) {
//		if(outputLength != 4*blocks.length) {
//			Logger.error("Chunk is corrupted(invalid data length "+outputLength+") : " + this);
//			return false;
//		}
//		for(int i = 0; i < blocks.length; i++) {
//			blocks[i] = Bits.getInt(data, i*4);
//		}
//		generated = true;
//		return true;
//	}

pub const VisibleBlock = struct {
	block: Block,
	x: u8,
	y: u8,
	z: u8,
	neighbors: u8,
};
pub const ChunkVisibilityData = struct {
	pos: ChunkPosition,
	visibles: std.ArrayList(VisibleBlock),
	voxelSizeShift: u5,

	/// Finds a block in the surrounding 8 chunks using relative corrdinates.
	fn getBlock(self: ChunkVisibilityData, chunks: *const [8]Chunk, x: ChunkCoordinate, y: ChunkCoordinate, z: ChunkCoordinate) Block {
		var relX = x + (self.pos.wx - chunks[0].pos.wx) >> self.voxelSizeShift;
		var relY = y + (self.pos.wy - chunks[0].pos.wy) >> self.voxelSizeShift;
		var relZ = z + (self.pos.wz - chunks[0].pos.wz) >> self.voxelSizeShift;
		var chunk = &chunks[(x >> chunkShift)*4 + (y >> chunkShift)*2 + (z >> chunkShift)];
		relX &= chunkMask;
		relY &= chunkMask;
		relZ &= chunkMask;
		return chunk.blocks[getIndex(x, y, z)];
	}

	pub fn init(allocator: Allocator, pos: ChunkPosition) !ChunkVisibilityData {
		var self = ChunkVisibilityData {
			.pos = pos,
			.visibles = std.ArrayList(VisibleBlock).init(allocator),
			.voxelSizeShift = std.math.log2_int(pos.voxelSize),
		};

		const width = pos.voxelSize*chunkSize;
		const widthMask = width - 1;

		// Get or generate the 8 surrounding chunks:
		var chunks: [8]Chunk = undefined;
		var x: u8 = 0;
		while(x <= 1): (x += 1) {
			var y: u8 = 0;
			while(y <= 1): (y += 1) {
				var z: u8 = 0;
				while(z <= 1): (z += 1) {
					chunks[x*4 + y*2 + z] = Chunk.init((pos.wx & ~widthMask) + x*width, (pos.wy & ~widthMask) + y*width, (pos.wz & ~widthMask) + z*width, pos.voxelSize);
					// TODO: world.chunkManager.getOrGenerateReducedChunk((wx & ~widthMask) + x*width, (wy & ~widthMask) + y*width, (wz & ~widthMask) + z*width, voxelSize);
				}
			}
		}

		const halfMask = chunkMask >> 1;
		x = 0;
		while(x < chunkSize): (x += 1) {
			var y: u8 = 0;
			while(y < chunkSize): (y += 1) {
				var z: u8 = 0;
				while(z < chunkSize): (z += 1) {
					const block = self.getBlock(chunks, x, y, z);
					if(block.typ == 0) continue;
					// Check all neighbors:
					var neighborVisibility: u8 = 0;
					for(Neighbors.iterable) |i| {
						const x2 = x + Neighbors.relX[i];
						const y2 = y + Neighbors.relY[i];
						const z2 = z + Neighbors.relZ[i];
						const neighborBlock = self.getBlock(chunks, x2, y2, z2);
						var isVisible = neighborBlock.typ == 0;
						if(!isVisible) {
							// If the chunk is at a border, more neighbors need to be checked to prevent cracks at LOD changes:
							// TODO: Find a better way to do this. This method doesn't always work and adds a lot of additional triangles.
							if(x & halfMask == (x2 & halfMask) ^ halfMask or y & halfMask == (y2 & halfMask) ^ halfMask or z & halfMask == (z2 & halfMask) ^ halfMask) {
								for(Neighbors.iterable) |j| {
									const x3 = x2 + Neighbors.relX[j];
									const y3 = y2 + Neighbors.relY[j];
									const z3 = z2 + Neighbors.relZ[j];
									if(self.getBlock(chunks, x3, y3, z3) == 0) {
										isVisible = true;
										break;
									}
								}
							}
						}

						if(isVisible) {
							neighborVisibility |= Neighbors.bitMask[i];
						}
					}
					if(neighborVisibility != 0) {
						try self.visibles.append(VisibleBlock{
							.block = block,
							.x = x,
							.y = y,
							.z = z,
							.neighbors = neighborVisibility,
						});
					}
				}
			}
		}
		return self;
	}

// TODO: Check how this constructor is actually needed.
//	public ReducedChunkVisibilityData(int wx, int wy, int wz, int voxelSize, byte[] x, byte[] y, byte[] z, byte[] neighbors, int[] visibleBlocks) {
//		super(wx, wy, wz, voxelSize);
//		voxelSizeShift = 31 - Integer.numberOfLeadingZeros(voxelSize); // log2
//		assert x.length == y.length && y.length == z.length && z.length == neighbors.length && neighbors.length == visibleBlocks.length : "Size of input parameters doesn't match.";
//		this.x = x;
//		this.y = y;
//		this.z = z;
//		this.neighbors = neighbors;
//		this.visibleBlocks = visibleBlocks;
//		capacity = size = x.length;
//	}
//}
};

pub const meshing = struct {
	var shader: Shader = undefined;
	pub var uniforms: struct {
		projectionMatrix: c_int,
		viewMatrix: c_int,
		modelPosition: c_int,
		ambientLight: c_int,
		directionalLight: c_int,
		fog_activ: c_int,
		fog_color: c_int,
		fog_density: c_int,
		lowerBounds: c_int,
		upperBounds: c_int,
		texture_sampler: c_int,
		emissionSampler: c_int,
		waterFog_activ: c_int,
		waterFog_color: c_int,
		waterFog_density: c_int,
		time: c_int,
	} = undefined;
	var vao: c_uint = undefined;
	var vbo: c_uint = undefined;
	var faces: std.ArrayList(u32) = undefined;

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
	}

	pub fn deinit() void {
		shader.delete();
		c.glDeleteVertexArrays(1, &vao);
		c.glDeleteBuffers(1, &vbo);
		faces.deinit();
	}

	pub fn bindShaderAndUniforms(projMatrix: Mat4f, ambient: Vec3f, directional: Vec3f, time: u32) void {
		shader.bind();

		c.glUniform1i(uniforms.fog_activ, if(game.fog.active) 1 else 0);
		c.glUniform3fv(uniforms.fog_color, 1, @ptrCast([*c]f32, &game.fog.color));
		c.glUniform1f(uniforms.fog_density, game.fog.density);

		c.glUniformMatrix4fv(uniforms.projectionMatrix, 1, c.GL_FALSE, @ptrCast([*c]f32, &projMatrix));

		c.glUniform1i(uniforms.texture_sampler, 0);
		c.glUniform1i(uniforms.emissionSampler, 1);

		c.glUniformMatrix4fv(uniforms.viewMatrix, 1, c.GL_FALSE, @ptrCast([*c]f32, &game.camera.viewMatrix));

		c.glUniform3f(uniforms.ambientLight, ambient.x, ambient.y, ambient.z);
		c.glUniform3f(uniforms.directionalLight, directional.x, directional.y, directional.z);

		c.glUniform1i(uniforms.time, @bitCast(i32, time));

		c.glBindVertexArray(vao);
	}
	
	pub fn bindShaderForReplacement() void {
		shader.bind();
		c.glBindVertexArray(vao);
	}

	pub const ChunkMesh = struct {
		pos: ChunkPosition,
		size: ChunkCoordinate,
		replacement: ?*ChunkMesh,
		faceData: SSBO,
		vertexCount: u32,
		generated: bool = false,

		pub fn init(pos: ChunkPosition, replacement: ?*ChunkMesh) ChunkMesh {
			return ChunkMesh{
				.pos = pos,
				.size = chunkSize*pos.voxelSize,
				.replacement = replacement,
				.faceData = SSBO.init(),
			};
		}

		pub fn deinit(self: ChunkMesh) void {
			self.faceData.deinit();
		}

		pub fn regenerateMesh(self: *ChunkMesh, visDat: ChunkVisibilityData) void {
			self.generated = true;

			faces.clearRetainingCapacity();
			faces.add(visDat.voxelSizeShift);

			for(visDat.visibles.items) |visible| {
				const block = visible.block;
				const x = visible.x;
				const y = visible.y;
				const z = visible.z;
				if(visible.neighbors & Neighbors.bitMask[Neighbors.dirNegX] != 0) {
					const normal: u32 = 0;
					const position: u32 = x | y << 6 | z << 12;
					const textureNormal = blocks.meshes.textureIndices(block)[Neighbors.dirNegX] | (normal << 24);
					try faces.append(position);
					try faces.append(textureNormal);
				}
				if(visible.neighbors & Neighbors.bitMask[Neighbors.dirPosX] != 0) {
					const normal: u32 = 1;
					const position: u32 = x+1 | y << 6 | z << 12;
					const textureNormal = blocks.meshes.textureIndices(block)[Neighbors.dirPosX] | (normal << 24);
					try faces.append(position);
					try faces.append(textureNormal);
				}
				if(visible.neighbors & Neighbors.bitMask[Neighbors.dirDown] != 0) {
					const normal: u32 = 4;
					const position: u32 = x | y << 6 | z << 12;
					const textureNormal = blocks.meshes.textureIndices(block)[Neighbors.dirDown] | (normal << 24);
					try faces.append(position);
					try faces.append(textureNormal);
				}
				if(visible.neighbors & Neighbors.bitMask[Neighbors.dirUp] != 0) {
					const normal: u32 = 5;
					const position: u32 = x | (y+1) << 6 | z << 12;
					const textureNormal = blocks.meshes.textureIndices(block)[Neighbors.dirUp] | (normal << 24);
					try faces.append(position);
					try faces.append(textureNormal);
				}
				if(visible.neighbors & Neighbors.bitMask[Neighbors.dirNegZ] != 0) {
					const normal: u32 = 2;
					const position: u32 = x | y << 6 | z << 12;
					const textureNormal = blocks.meshes.textureIndices(block)[Neighbors.dirNegZ] | (normal << 24);
					try faces.append(position);
					try faces.append(textureNormal);
				}
				if(visible.neighbors & Neighbors.bitMask[Neighbors.dirPosZ] != 0) {
					const normal: u32 = 3;
					const position: u32 = x | y << 6 | (z + 1) << 12;
					const textureNormal = blocks.meshes.textureIndices(block)[Neighbors.dirPosZ] | (normal << 24);
					try faces.append(position);
					try faces.append(textureNormal);
				}
			}

			self.vertexCount = 6*(faces.size-1)/2;
			self.faceData.bufferData(u32, faces.items);
		}

		pub fn render(self: *ChunkMesh, playerPosition: Vec3d) void {
			if(!self.generated) {
				if(self.replacement == null) return;
				c.glUniform3f(
					uniforms.lowerBounds,
					@floatCast(f32, self.pos.wx - playerPosition.x - 0.001),
					@floatCast(f32, self.pos.wy - playerPosition.y - 0.001),
					@floatCast(f32, self.pos.wz - playerPosition.z - 0.001)
				);
				c.glUniform3f(
					uniforms.upperBounds,
					@floatCast(f32, self.pos.wx + self.size - playerPosition.x + 0.001),
					@floatCast(f32, self.pos.wy + self.size - playerPosition.y + 0.001),
					@floatCast(f32, self.pos.wz + self.size - playerPosition.z + 0.001)
				);

				self.replacement.?.render(playerPosition);

				c.glUniform3f(uniforms.lowerBounds, -std.math.inf_f32, -std.math.inf_f32, -std.math.inf_f32);
				c.glUniform3f(uniforms.upperBounds, std.math.inf_f32, std.math.inf_f32, std.math.inf_f32);
				return;
			}
			c.glUniform3f(
				uniforms.modelPosition,
				@floatCast(f32, self.pos.wx - playerPosition.x),
				@floatCast(f32, self.pos.wy - playerPosition.y),
				@floatCast(f32, self.pos.wz - playerPosition.z)
			);
			self.faceData.bind(3);
			c.glDrawElements(c.GL_TRIANGLES, self.vertexCount, c.GL_UNSIGNED_INT, null);
		}
	};
};