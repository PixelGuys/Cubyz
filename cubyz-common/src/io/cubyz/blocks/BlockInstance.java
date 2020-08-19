package io.cubyz.blocks;

import org.joml.Vector3i;

import io.cubyz.Settings;
import io.cubyz.entity.Player;
import io.cubyz.world.Chunk;
import io.cubyz.world.Surface;

public class BlockInstance {

	private Block block;
	private Object[] spatial;
	public final int x, y, z;
	private Surface surface;
	private boolean[] neighbors;
	private byte blockData;
	private boolean spatialUpdate;
	private boolean lightUpdate;
	public final int[] light;
	
	public BlockInstance(Block block, byte data, Vector3i position, Player player, int worldSize) {
		this.block = block;
		x = position.x;
		y = position.y;
		z = position.z;
		blockData = data;
		if(Settings.easyLighting)
			light = new int[8];
		else
			light = null;
		neighbors = new boolean[6];
		spatialUpdate = true;
		scheduleLightUpdate();
	}
	
	public boolean[] getNeighbors() {
		return neighbors;
	}
	
	public void updateNeighbor(int i, boolean value, Player player, int worldSize) {
		if(neighbors[i] != value) {
			neighbors[i] = value;
			if(block.mode.dependsOnNeightbors()) {
				spatialUpdate = true;
			}
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
	
	public void setData(byte data, Player player, int worldSize) {
		blockData = data;
		spatialUpdate = true;
	}
	
	public void scheduleLightUpdate() {
		lightUpdate = true;
	}
	
	public Object[] getSpatials(Player player, int worldSize, Chunk chunk) {
		if(spatialUpdate) { // Generate the Spatials on demand.
			spatial = block.mode.generateSpatials(this, blockData, player, worldSize);
			spatialUpdate = false;
		}
		if(Settings.easyLighting && lightUpdate) { // Update the internal light representation on demand.
			if(chunk != null) {
				chunk.getCornerLight(x & 15, y, z & 15, light);
				lightUpdate = false;
			}
		}
		return spatial;
	}

	float breakAnim = 0f;
	public void setBreakingAnimation(float f) { // 0 <= f < 1
		breakAnim = f;
	}
	
	public float getBreakingAnim() {
		return breakAnim;
	}
	
}
