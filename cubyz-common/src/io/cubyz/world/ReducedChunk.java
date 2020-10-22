package io.cubyz.world;

import java.util.ArrayList;

import org.joml.Vector3f;

import io.cubyz.math.CubyzMath;
import io.cubyz.save.BlockChange;

/**
 * A chunk with smaller resolution(2 blocks, 4 blocks, 8 blocks or 16 blocks). Used to work out the far-distance map of cubyz terrain.<br>
 * It is trimmed for low memory-usage and high-performance, because many of those are be needed.<br>
 * Instead of storing blocks it only stores 16 bit color values.<br>
 * For performance reasons, Cubyz uses a pretty simple downscaling algorithm: Only take every resolutionth voxel in each dimension.<br>
 */

public class ReducedChunk {
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
	public final short[] blocks;
	public boolean generated = false;
	public final int width;
	/** =log₂(width)*/
	public final int widthShift;
	/**
	 * Used for rendering only.
	 * Do not change!
	 */
	public Object mesh = null;
	public ReducedChunk(int cx, int cz, int resolutionShift, int widthShift, ArrayList<BlockChange> changes) {
		this.cx = cx;
		this.cz = cz;
		this.resolutionShift = resolutionShift;
		this.resolution = 1 << resolutionShift;
		this.resolutionMask = resolution - 1;
		width = 1 << widthShift;
		size = (World.WORLD_HEIGHT >>> resolutionShift)*(width >> resolutionShift)*(width >> resolutionShift);
		blocks = new short[size];
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
	
	public Vector3f getMin(float x0, float z0, int worldSize) {
		return new Vector3f(CubyzMath.match(cx << 4, x0, worldSize), 0, CubyzMath.match(cz << 4, z0, worldSize));
	}
	
	public Vector3f getMax(float x0, float z0, int worldSize) {
		return new Vector3f(CubyzMath.match(cx << 4, x0, worldSize) + width, 256, CubyzMath.match(cz << 4, z0, worldSize) + width);
	}
	
	/**
	 * This is useful to convert for loops to work for reduced resolution:<br>
	 * Instead of using<br>
	 * for(int i = start; i < end; i++)<br>
	 * for(int i = chunk.startIndex(start); i < end; i += chunk.resolution)<br>
	 * should be used to only activate those voxels that are used in Cubyz's downscaling technique.
	 * @param index The normal starting index(for normal generation).
	 * @return the next higher index that is inside the grid of this chunk.
	 */
	public int startIndex(int start) {
		return start+resolutionMask & ~resolutionMask;
	}
	
	/**
	 * Updates a block if current value is 0 (air) and if it is inside this chunk.
	 * @param x relative x without considering resolution.
	 * @param y relative y without considering resolution.
	 * @param z relative z without considering resolution.
	 * @param newColor
	 */
	public void updateBlockIfAir(int x, int y, int z, short newColor) {
		if(x < 0 || x >= width || z < 0 || z >= width) return;
		x >>= resolutionShift;
		y >>= resolutionShift;
		z >>= resolutionShift;
		int index = (x << (widthShift - resolutionShift)) | (y << 2*(widthShift - resolutionShift)) | z;
		if(blocks[index] == (short)0) {
			blocks[index] = newColor;
		}
	}
	
	/**
	 * Updates a block if it is inside this chunk.
	 * @param x relative x without considering resolution.
	 * @param y relative y without considering resolution.
	 * @param z relative z without considering resolution.
	 * @param newColor
	 */
	public void updateBlock(int x, int y, int z, short newColor) {
		if(x < 0 || x >= width || z < 0 || z >= width) return;
		x >>= resolutionShift;
		y >>= resolutionShift;
		z >>= resolutionShift;
		int index = (x << (widthShift - resolutionShift)) | (y << 2*(widthShift - resolutionShift)) | z;
		blocks[index] = newColor;
	}
}
