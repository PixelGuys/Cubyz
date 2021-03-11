package io.cubyz.world;


import org.joml.Vector3f;

import io.cubyz.blocks.Block;
import io.cubyz.client.Cubyz;
import io.cubyz.math.CubyzMath;
import io.cubyz.world.generator.SurfaceGenerator;

/**
 * A chunk with smaller resolution(2 blocks, 4 blocks, 8 blocks or 16 blocks). Used to work out the far-distance map of cubyz terrain.<br>
 * It is trimmed for low memory-usage and high-performance, because many of those are be needed.<br>
 * Instead of storing blocks it only stores 16 bit color values.<br>
 * For performance reasons, Cubyz uses a pretty simple downscaling algorithm: Only take every resolutionth voxel in each dimension.<br>
 */

public class ReducedChunk extends Chunk {
	/**1 << resolutionShift = resolution*/
	public final int resolutionShift;
	/**How many blocks each voxel is wide.*/
	public final int resolution;
	/**If ((x & resoultionMask) == 0), a block can be considered to be visible.*/
	public final int resolutionMask;
	public final int size;
	public final int wx, wy, wz;
	public final Block[] blocks;
	public boolean generated = false;
	public final int width;
	/** =log₂(width)*/
	public final int widthShift;
	
	public ReducedChunk(int wx, int wy, int wz, int resolutionShift, int widthShift) {
		this.wx = wx;
		this.wy = wy;
		this.wz = wz;
		this.resolutionShift = resolutionShift;
		this.resolution = 1 << resolutionShift;
		this.resolutionMask = resolution - 1;
		width = 1 << widthShift;
		size = (width >>> resolutionShift)*(width >> resolutionShift)*(width >> resolutionShift);
		blocks = new Block[size];
		this.widthShift = widthShift;
	}
	
	public void applyBlockChanges() {
		// TODO
	}
	
	public Vector3f getMin(float x0, float z0, int worldSizeX, int worldSizeZ) {
		return new Vector3f(CubyzMath.match(wx, x0, worldSizeX), wy, CubyzMath.match(wz, z0, worldSizeZ));
	}
	
	public Vector3f getMax(float x0, float z0, int worldSizeX, int worldSizeZ) {
		return new Vector3f(CubyzMath.match(wx, x0, worldSizeX) + width, (wy) + width, CubyzMath.match(wz, z0, worldSizeZ) + width);
	}
	
	@Override
	public int startIndex(int start) {
		return start+resolutionMask & ~resolutionMask;
	}
	
	@Override
	public void updateBlockIfDegradable(int x, int y, int z, Block newBlock) {
		x >>= resolutionShift;
		y >>= resolutionShift;
		z >>= resolutionShift;
		int index = (x << (widthShift - resolutionShift)) | (y << 2*(widthShift - resolutionShift)) | z;
		if(blocks[index] == null || blocks[index].isDegradable()) {
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
	
	public void generateFrom(SurfaceGenerator gen) {
		gen.generate(this, Cubyz.surface);
		applyBlockChanges();
		generated = true;
	}

	@Override
	public boolean liesInChunk(int x, int y, int z) {
		return (x & resolutionMask) == 0
				&& (y & resolutionMask) == 0
				&& (z & resolutionMask) == 0
				&& x >= 0
				&& x < width
				&& y >= 0
				&& y < width
				&& z >= 0
				&& z < width;
	}

	@Override
	public int getVoxelSize() {
		return resolution;
	}

	@Override
	public int getWorldX() {
		return wx;
	}

	@Override
	public int getWorldY() {
		return wy;
	}

	@Override
	public int getWorldZ() {
		return wz;
	}
	
	@Override
	public int getWidth() {
		return width;
	}

	@Override
	public Block getBlock(int x, int y, int z) {
		x >>= resolutionShift;
		y >>= resolutionShift;
		z >>= resolutionShift;
		int index = (x << (widthShift - resolutionShift)) | (y << 2*(widthShift - resolutionShift)) | z;
		return blocks[index];
	}
}

