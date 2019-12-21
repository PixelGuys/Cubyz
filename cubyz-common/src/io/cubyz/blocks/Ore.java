package io.cubyz.blocks;

public class Ore extends Block {

	protected float maxSize;
	protected float spawns; // average spawns per chunk. Will seem to be less if the length gets close to 0.
	protected float maxLength;
	protected int height;
	
	public Ore() {
		bc = BlockClass.STONE;
	}
	
	public float getMaxSize() {
		return maxSize;
	}

	public float getSpawns() {
		return spawns;
	}

	public float getMaxLength() {
		return maxLength;
	}

	public int getHeight() {
		return height;
	}
	
}