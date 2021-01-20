package io.cubyz.blocks;

import org.joml.Vector3i;

import io.cubyz.entity.Player;
import io.cubyz.world.NormalChunk;
import io.cubyz.world.Surface;

/**
 * A block that will be used for rendering.
 */

public class BlockInstance {

	private Block block;
	public final int x, y, z;
	private Surface surface;
	private boolean[] neighbors;
	private byte blockData;
	private boolean lightUpdate;
	public final int[] light;
	public final NormalChunk source;
	public int renderIndex = 0;
	
	public BlockInstance(Block block, byte data, Vector3i position, Player player, NormalChunk source) {
		this.source = source;
		this.block = block;
		x = position.x;
		y = position.y;
		z = position.z;
		blockData = data;
		light = new int[8];
		neighbors = new boolean[6];
		scheduleLightUpdate();
	}
	
	public boolean[] getNeighbors() {
		return neighbors;
	}
	
	public void updateNeighbor(int i, boolean value, Player player) {
		if(neighbors[i] != value) {
			neighbors[i] = value;
		}
	}
	
	public Surface getStellarTorus() {
		return surface;
	}
	
	public void setStellarTorus(Surface world) {
		this.surface = world;
	}
	
	public int getID() {
		return block.ID;
	}
	
	public Vector3i getPosition() {
		return new Vector3i(x, y, z);
	}
	
	public int getX() {
		return x;
	}
	
	public int getY() {
		return y;
	}
	
	public int getZ() {
		return z;
	}
	
	public Block getBlock() {
		return block;
	}
	
	public void setBlock(Block b) {
		block = b;
	}
	
	public byte getData() {
		return blockData;
	}
	
	public void setData(byte data, Player player) {
		blockData = data;
	}
	
	public void scheduleLightUpdate() {
		lightUpdate = true;
	}
	
	public int[] updateLighting(int worldSizeX, int worldSizeZ, NormalChunk chunk) {
		if(lightUpdate) { // Update the internal light representation on demand.
			if(chunk != null) {
				chunk.getCornerLight(x & 15, y, z & 15, light);
				lightUpdate = false;
			}
		}
		return light;
	}

	float breakAnim = 0f;
	public void setBreakingAnimation(float f) { // 0 <= f < 1
		breakAnim = f;
	}
	
	public float getBreakingAnim() {
		return breakAnim;
	}
	
}
