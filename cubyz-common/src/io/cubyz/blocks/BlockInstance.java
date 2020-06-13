package io.cubyz.blocks;

import org.joml.Vector3i;

import io.cubyz.ClientOnly;
import io.cubyz.world.Surface;

public class BlockInstance {

	private Block block;
	private Object spatial;
	private Vector3i pos;
	private Surface surface;
	public boolean neighborUp, neighborDown, neighborEast, neighborWest, neighborNorth, neighborSouth;
	public byte blockData;
	
	public BlockInstance(Block block, byte data) {
		this.block = block;
		blockData = data;
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
	
	public Object getSpatial() {
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
