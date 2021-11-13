package cubyz.world.blocks;

import org.joml.Vector3i;

import cubyz.world.NormalChunk;
import cubyz.world.ServerWorld;

/**
 * A block that will be used for rendering.
 */

public class BlockInstance {

	private int block;
	public final int x, y, z;
	private ServerWorld world;
	private boolean[] neighbors;
	public final int[] light;
	public final NormalChunk source;
	public int renderIndex = 0;
	
	public BlockInstance(int block, Vector3i position, NormalChunk source) {
		this.source = source;
		this.block = block;
		x = position.x;
		y = position.y;
		z = position.z;
		light = new int[27];
		neighbors = new boolean[6];
	}
	
	public boolean[] getNeighbors() {
		return neighbors;
	}
	
	public void updateNeighbor(int i, boolean value) {
		if(neighbors[i] != value) {
			neighbors[i] = value;
		}
		source.setUpdated();
	}
	
	public ServerWorld getWorld() {
		return world;
	}
	
	public void setWorld(ServerWorld world) {
		this.world = world;
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
	
	public int getBlock() {
		return block;
	}
	
	public void setBlock(int b) {
		block = b;
	}
	
	public int[] updateLighting(int worldSizeX, int worldSizeZ, NormalChunk chunk) {
		if(chunk != null) {
			world.getLight(chunk, x, y, z, light);
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
