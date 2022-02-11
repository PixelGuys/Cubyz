package cubyz.world;


import org.joml.Vector3f;

import cubyz.world.blocks.Blocks;

/**
 * A chunk with smaller resolution(2 blocks, 4 blocks, 8 blocks or 16 blocks). Used to work out the far-distance map of cubyz terrain.<br>
 * It is trimmed for low memory-usage and high-performance, because many of those are be needed.<br>
 * Instead of storing blocks it only stores 16 bit color values.<br>
 * For performance reasons, Cubyz uses a pretty simple downscaling algorithm: Only take every resolutionth voxel in each dimension.<br>
 */

public class ReducedChunk extends Chunk {
	/**1 << voxelSizeShift = voxelSize*/
	public final int voxelSizeShift;
	/**If ((x & voxelSizeMask) == 0), a block can be considered to be visible.*/
	public final int voxelSizeMask;
	/** =log₂(width)*/
	public final int widthShift;
	
	public ReducedChunk(World world, int wx, int wy, int wz, int resolutionShift) {
		super(world, wx, wy, wz, 1 << resolutionShift);
		this.voxelSizeShift = resolutionShift;
		this.voxelSizeMask = voxelSize - 1;
		widthShift = Chunk.chunkShift + resolutionShift;
	}
	
	public Vector3f getMin() {
		return new Vector3f(wx, wy, wz);
	}
	
	public Vector3f getMax() {
		return new Vector3f(wx + width, (wy) + width, wz + width);
	}
	
	@Override
	public int startIndex(int start) {
		return start+voxelSizeMask & ~voxelSizeMask; // Rounds up to the nearest valid voxel coordinate.
	}
	
	@Override
	public void updateBlockIfDegradable(int x, int y, int z, int newBlock) {
		x >>= voxelSizeShift;
		y >>= voxelSizeShift;
		z >>= voxelSizeShift;
		int index = getIndex(x, y, z);
		if (blocks[index] == 0 || Blocks.degradable(blocks[index])) {
			blocks[index] = newBlock;
		}
	}
	
	@Override
	public void updateBlock(int x, int y, int z, int newBlock) {
		x >>= voxelSizeShift;
		y >>= voxelSizeShift;
		z >>= voxelSizeShift;
		int index = getIndex(x, y, z);
		blocks[index] = newBlock;
	}
	
	@Override
	public void updateBlockInGeneration(int x, int y, int z, int newBlock) {
		x >>= voxelSizeShift;
		y >>= voxelSizeShift;
		z >>= voxelSizeShift;
		int index = getIndex(x, y, z);
		blocks[index] = newBlock;
	}

	public void updateFromLowerResolution(Chunk chunk) {
		int xOffset = chunk.wx != wx ? chunkSize/2 : 0; // Offsets of the lower resolution chunk in this chunk.
		int yOffset = chunk.wy != wy ? chunkSize/2 : 0;
		int zOffset = chunk.wz != wz ? chunkSize/2 : 0;
		
		for(int x = 0; x < chunkSize/2; x++) {
			for(int y = 0; y < chunkSize/2; y++) {
				for(int z = 0; z < chunkSize/2; z++) {
					// Count the neighbors for each subblock. An transparent block counts 5. A chunk border(unknown block) only counts 1.
					int[] neighborCount = new int[8];
					int[] blocks = new int[8];
					int maxCount = 0;
					for(int dx = 0; dx <= 1; dx++) {
						for(int dy = 0; dy <= 1; dy++) {
							for(int dz = 0; dz <= 1; dz++) {
								int index = getIndex(x*2 + dx, y*2 + dy, z*2 + dz);
								int i = dx*4 + dz*2 + dy;
								blocks[i] = chunk.blocks[index];
								if(blocks[i] == 0) continue; // I don't care about air blocks.
								
								int count = 0;
								for(int n = 0; n < Neighbors.NEIGHBORS; n++) {
									int nx = x*2 + dx + Neighbors.REL_X[n];
									int ny = y*2 + dy + Neighbors.REL_Y[n];
									int nz = z*2 + dz + Neighbors.REL_Z[n];
									if((nx & chunkMask) == nx && (ny & chunkMask) == ny && (nz & chunkMask) == nz) { // If it's inside the chunk.
										int neighborIndex = getIndex(nx, ny, nz);
										if(Blocks.transparent(chunk.blocks[neighborIndex])) {
											count += 5;
										}
									} else {
										count += 1;
									}
								}
								maxCount = Math.max(maxCount, count);
								neighborCount[i] = count;
							}
						}
					}
					// Uses a specific permutation here that keeps high resolution patterns in lower resolution.
					int permutationStart = (x & 1)*4 + (z & 1)*2 + (y & 1);
					int block = 0;
					for(int i = 0; i < 8; i++) {
						int appliedPermutation = permutationStart ^ i;
						if(neighborCount[appliedPermutation] >= maxCount - 1) { // Avoid pattern breaks at chunk borders.
							block = blocks[appliedPermutation];
						}
					}
					// Update the block:
					int thisIndex = getIndex(x + xOffset, y + yOffset, z + zOffset);
					this.blocks[thisIndex] = block;
				}
			}
		}
		
		// Create updated meshes and send to client:
		for(int x = 0; x <= 2*xOffset; x += chunkSize) {
			for(int y = 0; y <= 2*yOffset; y += chunkSize) {
				for(int z = 0; z <= 2*zOffset; z += chunkSize) {
					int wx = this.wx + x*voxelSize - Chunk.chunkSize;
					int wy = this.wy + y*voxelSize - Chunk.chunkSize;
					int wz = this.wz + z*voxelSize - Chunk.chunkSize;
					if(voxelSize == 32) {
						wx -= chunkSize*voxelSize/2;
						wy -= chunkSize*voxelSize/2;
						wz -= chunkSize*voxelSize/2;
					}
					world.queueChunk(new ChunkData(wx, wy, wz, voxelSize));
				}
			}
		}
		
		setChanged();
	}

	@Override
	public int getBlock(int x, int y, int z) {
		x >>= voxelSizeShift;
		y >>= voxelSizeShift;
		z >>= voxelSizeShift;
		int index = getIndex(x, y, z);
		return blocks[index];
	}
}

