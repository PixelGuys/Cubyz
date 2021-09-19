package cubyz.world.blocks;

import java.util.Properties;

import cubyz.api.Resource;

/**
 * Ores can be found underground in veins.<br>
 * TODO: Add support for non-stone ores.
 */

public class Ore extends Block {
	/**average size of a vein in blocks*/
	public final float size;
	/**average density of a vein*/
	public final float density;
	/**average veins per chunk*/
	public final float veins;
	/**maximum height this ore can be generated*/
	public final int maxHeight;

	public Ore(Resource id, Properties props, int maxHeight, float veins, float size, float density) {
		super(id, props, "STONE");
		this.maxHeight = maxHeight;
		this.veins = veins;
		this.size = size;
		this.density = Math.max(0.05f, Math.min(density, 1));
	}
	public Ore(int maxHeight, float veins, float size, float density) {
		this.maxHeight = maxHeight;
		this.veins = veins;
		this.size = size;
		this.density = Math.max(0.05f, Math.min(density, 1));
	}
}