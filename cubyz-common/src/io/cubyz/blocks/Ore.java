package io.cubyz.blocks;

public class Ore extends Block {

	public final float size; // average size of a vein in blocks.
	public final float veins; // average veins per chunk.
	public final int maxHeight;
	
	public Ore(int maxHeight, float veins, float size) {
		this.maxHeight = maxHeight;
		this.veins = veins;
		this.size = size;
		bc = BlockClass.STONE;
	}
}