package cubyz.world.blocks;

import org.joml.Vector3i;

import cubyz.world.Neighbors;
import cubyz.world.NormalChunk;
import cubyz.world.World;

/**
 * A block that will be used for rendering.
 */

public class BlockInstance {

	private int block;
	/** world coordinates */
	public final int x, y, z;
	private final World world;
	private byte neighbors;
	public final int[] light;
	public final NormalChunk source;
	public float breakAnim = 0f;
	
	public BlockInstance(int block, Vector3i position, NormalChunk source, World world) {
		this.source = source;
		this.block = block;
		x = position.x;
		y = position.y;
		z = position.z;
		light = new int[27];
		this.world = world;
	}
	
	public byte getNeighbors() {
		return neighbors;
	}
	
	public void updateNeighbor(int i, boolean value) {
		byte mask = Neighbors.BIT_MASK[i];
		if(value) {
			neighbors |= mask;
		} else {
			neighbors &= ~mask;
		}
		source.setUpdated();
	}
	
	public Vector3i getPosition() {
		return new Vector3i(x, y, z);
	}
	
	public int getBlock() {
		return block;
	}
	
	public void setBlock(int b) {
		block = b;
	}
	
	public int[] updateLighting(int worldSizeX, int worldSizeZ, NormalChunk chunk) {
		if (chunk != null) {
			world.getLight(chunk, x, y, z, light);
		}
		return light;
	}
	
}
