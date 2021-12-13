package cubyz.world;

import java.util.Arrays;

public class ReducedChunkVisibilityData extends ChunkData {
	private static final int INITIAL_CAPACITY = 128;
	public int[] visibleBlocks = new int[INITIAL_CAPACITY];
	public byte[] x = new byte[INITIAL_CAPACITY], y = new byte[INITIAL_CAPACITY], z = new byte[INITIAL_CAPACITY];
	public byte[] neighbors = new byte[INITIAL_CAPACITY];
	public int size;
	public int capacity = INITIAL_CAPACITY;

	private void addBlock(byte x, byte y, byte z, byte neighbors, int block) {
		if (size == capacity)
			increaseCapacity();
		visibleBlocks[size] = block;
		this.x[size] = x;
		this.y[size] = y;
		this.z[size] = z;
		this.neighbors[size] = neighbors;
		size++;
	}

	private void increaseCapacity() {
		capacity *= 2;
		visibleBlocks = Arrays.copyOf(visibleBlocks, capacity);
		x = Arrays.copyOf(x, capacity);
		y = Arrays.copyOf(y, capacity);
		z = Arrays.copyOf(z, capacity);
		neighbors = Arrays.copyOf(neighbors, capacity);
	}

	private int getBlock(ReducedChunk[] chunks, int x, int y, int z) {
		x += (wx - chunks[0].wx)/voxelSize;
		y += (wy - chunks[0].wy)/voxelSize;
		z += (wz - chunks[0].wz)/voxelSize;
		ReducedChunk chunk = chunks[x/NormalChunk.chunkSize*4 + y/NormalChunk.chunkSize*2 + z/NormalChunk.chunkSize];
		x &= NormalChunk.chunkMask;
		y &= NormalChunk.chunkMask;
		z &= NormalChunk.chunkMask;
		return chunk.blocks[NormalChunk.getIndex(x, y, z)];
	}
	
	public ReducedChunkVisibilityData(ServerWorld world, int wx, int wy, int wz, int voxelSize) {
		super(wx, wy, wz, voxelSize);

		int chunkSize = voxelSize*NormalChunk.chunkSize;
		int chunkMask = chunkSize - 1;

		// Get or generate the 8 surrounding chunks:
		ReducedChunk[] chunks = new ReducedChunk[8];
		for(int x = 0; x <= 1; x++) {
			for(int y = 0; y <= 1; y++) {
				for(int z = 0; z <= 1; z++) {
					chunks[x*4 + y*2 + z] = world.getOrGenerateReducedChunk((wx & ~chunkMask) + x*chunkSize, (wy & ~chunkMask) + y*chunkSize, (wz & ~chunkMask) + z*chunkSize, voxelSize);
				}
			}
		}
		int halfMask = NormalChunk.chunkMask >> 1;
		// Go through all blocks of this chunk:
		for(byte x = 0; x < NormalChunk.chunkSize; x++) {
			for(byte y = 0; y < NormalChunk.chunkSize; y++) {
				for(byte z = 0; z < NormalChunk.chunkSize; z++) {
					int block = getBlock(chunks, x, y, z);
					if (block == 0) continue;
					// Check all neighbors:
					byte neighborVisibility = 0;
					for(byte i = 0; i < Neighbors.NEIGHBORS; i++) {
						int x2 = x + Neighbors.REL_X[i];
						int y2 = y + Neighbors.REL_Y[i];
						int z2 = z + Neighbors.REL_Z[i];
						boolean isVisible = false;
						int neighbor = getBlock(chunks, x2, y2, z2);
						isVisible = neighbor == 0;
						if (!isVisible) {
							// If the chunk is at a border, more neighbors need to be checked to prevent cracks at LOD changes:
							if ((x & halfMask) == ((x2 & halfMask) ^ halfMask) || (y & halfMask) == ((y2 & halfMask) ^ halfMask) || (z & halfMask) == ((z2 & halfMask) ^ halfMask)) {
								for(byte j = 0; j < Neighbors.NEIGHBORS; j++) {
									if (i == (j ^ 1)) continue; // Don't check the source block twice.
									int x3 = x2 + Neighbors.REL_X[j];
									int y3 = y2 + Neighbors.REL_Y[j];
									int z3 = z2 + Neighbors.REL_Z[j];
									neighbor = getBlock(chunks, x3, y3, z3);
									if (neighbor == 0) {
										isVisible = true;
										break;
									}
								}
							}
						}

						if (isVisible) {
							neighborVisibility |= Neighbors.BIT_MASK[i];
						}
					}
					if (neighborVisibility != 0) {
						addBlock(x, y, z, neighborVisibility, block);
					}
				}
			}
		}
	}
}
