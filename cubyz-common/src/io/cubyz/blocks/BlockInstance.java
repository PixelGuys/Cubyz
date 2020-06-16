package io.cubyz.blocks;

import org.joml.Vector3i;

import io.cubyz.Settings;
import io.cubyz.world.Surface;

public class BlockInstance {

	private Block block;
	private Object[] spatial;
	private Vector3i pos;
	private Surface surface;
	public boolean neighborUp, neighborDown, neighborEast, neighborWest, neighborNorth, neighborSouth;
	private byte blockData;
	public final int[] light;
	
	public BlockInstance(Block block, byte data) {
		this.block = block;
		blockData = data;
		if(Settings.easyLighting)
			light = new int[8];
		else
			light = null;
		if(block.mode != null) {
			spatial = block.mode.generateSpatials(this, blockData);
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
	
	public void setData(byte data) {
		blockData = data;
		spatial = block.mode.generateSpatials(this, blockData);
	}
	
	public void setPosition(Vector3i pos) {
		this.pos = pos;
	}
	
	public Object[] getSpatials() {
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
