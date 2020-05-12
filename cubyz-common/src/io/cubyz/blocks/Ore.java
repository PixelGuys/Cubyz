package io.cubyz.blocks;

public class Ore extends Block {

	public float maxSize;
	public float spawns; // average spawns per chunk. Will seem to be less if the length gets close to 0.
	public float maxLength;
	public int height;
	
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