package io.cubyz.world;

import java.util.ArrayList;

import org.joml.Vector3f;

import io.cubyz.blocks.Block;
import io.cubyz.math.CubyzMath;
import io.cubyz.save.BlockChange;

/**
 * A chunk with smaller resolution(2 blocks, 4 blocks, 8 blocks or 16 blocks). Used to work out the far-distance map of cubyz terrain.<br>
 * It is trimmed for low memory-usage and high-performance, because many of those are be needed.<br>
 * Instead of storing blocks it only stores 16 bit color values.<br>
 * For performance reasons, Cubyz uses a pretty simple downscaling algorithm: Only take every resolutionth voxel in each dimension.<br>
 */

public class ReducedChunk extends Chunk {
	/**The current surface the player is on.*/
	public static Surface surface;
	public ArrayList<BlockChange> changes;
	/**1 << resolutionShift = resolution*/
	public final int resolutionShift;
	/**How many blocks each voxel is wide.*/
	public final int resolution;
	/**If ((x & resoultionMask) == 0), a block can be considered to be visible.*/
	public final int resolutionMask;
	public final int size;
	public final int cx, cz;
	public final Block[] blocks;
	public boolean generated = false;
	public final int width;
	/** =log₂(width)*/
	public final int widthShift;
	
	public ReducedChunk(int cx, int cz, int resolutionShift, int widthShift, ArrayList<BlockChange> changes) {
		this.cx = cx;
		this.cz = cz;
		this.resolutionShift = resolutionShift;
		this.resolution = 1 << resolutionShift;
		this.resolutionMask = resolution - 1;
		width = 1 << widthShift;
		size = (World.WORLD_HEIGHT >>> resolutionShift)*(width >> resolutionShift)*(width >> resolutionShift);
		blocks = new Block[size];
		this.changes = changes;
		this.widthShift = widthShift;
	}
	
	public void applyBlockChanges() {
		/*for(BlockChange bc : changes) {
			
			int index = ((bc.x >>> resolution) << (4 - resolution)) | ((bc.y >>> resolution) << (8 - 2*resolution)) | (bc.z >>> resolution);
			Block b = bc.newType == -1 ? null : surface.getPlanetBlocks()[bc.newType];
			if (b != null && b.hasBlockEntity()) {
				Vector3i pos = new Vector3i(wx+bc.x, bc.y, wz+bc.z);
				blockEntities.add(b.createBlockEntity(surface, pos));
			}
			blocks[index] = b;
			blockData[index] = bc.newData;
		}*/ // TODO
	}
	
	public Vector3f getMin(float x0, float z0, int worldSizeX, int worldSizeZ) {
		return new Vector3f(CubyzMath.match(cx << 4, x0, worldSizeX), 0, CubyzMath.match(cz << 4, z0, worldSizeZ));
	}
	
	public Vector3f getMax(float x0, float z0, int worldSizeX, int worldSizeZ) {
		return new Vector3f(CubyzMath.match(cx << 4, x0, worldSizeX) + width, 256, CubyzMath.match(cz << 4, z0, worldSizeZ) + width);
	}
	
	@Override
	public int startIndex(int start) {
		return start+resolutionMask & ~resolutionMask;
	}
	
	@Override
	public void updateBlockIfAir(int x, int y, int z, Block newBlock) {
		x >>= resolutionShift;
		y >>= resolutionShift;
		z >>= resolutionShift;
		int index = (x << (widthShift - resolutionShift)) | (y << 2*(widthShift - resolutionShift)) | z;
		if(blocks[index] == null) {
			blocks[index] = newBlock;
		}
	}
	
	@Override
	public void updateBlock(int x, int y, int z, Block newBlock) {
		x >>= resolutionShift;
		y >>= resolutionShift;
		z >>= resolutionShift;
		int index = (x << (widthShift - resolutionShift)) | (y << 2*(widthShift - resolutionShift)) | z;
		blocks[index] = newBlock;
	}

	@Override
	public void updateBlock(int x, int y, int z, Block newBlock, byte data) {
		updateBlock(x, y, z, newBlock);
	}

	@Override
	public boolean liesInChunk(int x, int z) {
		return (x & resolutionMask) == 0 && (z & resolutionMask) == 0 && x >= 0 && x < width && z >= 0 && z < width;
	}

	@Override
	public boolean liesInChunk(int y) {
		return (y & resolutionMask) == 0 && y >= 0 && y < World.WORLD_HEIGHT;
	}

	@Override
	public int getVoxelSize() {
		return resolution;
	}

	@Override
	public int getWorldX() {
		return cx << 4;
	}

	@Override
	public int getWorldZ() {
		return cz << 4;
	}
	
	@Override
	public int getWidth() {
		return width;
	}
}
