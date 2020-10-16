package io.cubyz.blocks;

import java.util.Properties;

import io.cubyz.api.Resource;

/**
 * Ores can be found underground in veins.<br>
 * TODO: Add support for non-stone ores.
 */

public class Ore extends Block {
	/**average size of a vein in blocks*/
	public final float size;
	/**average veins per chunk*/
	public final float veins;
	/**maximum height this ore can be generated*/
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