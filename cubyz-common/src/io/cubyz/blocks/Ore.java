package io.cubyz.blocks;

import java.util.Properties;

import io.cubyz.api.Resource;

public class Ore extends Block {

	public final float size; // average size of a vein in blocks.
	public final float veins; // average veins per chunk.
	public final int maxHeight;

	public Ore(Resource id, Properties props, int maxHeight, float veins, float size) {
		super(id, props, "STONE");
		this.maxHeight = maxHeight;
		this.veins = veins;
		this.size = size;
	}
	public Ore(int maxHeight, float veins, float size) {
		this.maxHeight = maxHeight;
		this.veins = veins;
		this.size = size;
	}
}