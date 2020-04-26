package io.cubyz.blocks;

import org.joml.Vector3i;

import io.cubyz.ClientOnly;
import io.cubyz.world.Chunk;
import io.cubyz.world.Surface;
import io.cubyz.world.World;

public class BlockInstance {

	private Block block;
	private IBlockSpatial spatial;
	private Vector3i pos;
	private Surface surface;
	public boolean neighborUp, neighborDown, neighborEast, neighborWest, neighborNorth, neighborSouth;
	
	public Surface getStellarTorus() {
		return surface;
	}
	
	public void setStellarTorus(Surface world) {
		this.surface = world;
	}
	
	public BlockInstance(Block block) {
		this.block = block;
	}
	
	public int getID() {
		return block.ID;
	}
	
	public Vector3i getPosition() {
		return pos;
	}
	
	public int getX() {
		return pos.x;
	}
	
	public int getY() {
		return pos.y;
	}
	
	public int getZ() {
		return pos.z;
	}
	
	public Block getBlock() {
		return block;
	}
	
	public void setBlock(Block b) {
		block = b;
	}
	
	public void setPosition(Vector3i pos) {
		this.pos = pos;
	}
	
	public IBlockSpatial getSpatial() {
		if (spatial == null) {
			spatial = ClientOnly.createBlockSpatial.apply(this);
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
