package io.cubyz.api.base;

import io.cubyz.api.EventHandler;
import io.cubyz.api.Mod;
import io.cubyz.blocks.Dirt;
import io.cubyz.blocks.Grass;
import io.cubyz.blocks.Stone;
import io.cubyz.blocks.Water;
import io.cubyz.modding.BlockRegistry;

/**
 * Mod adding SpacyCubyd default content.
 * @author zenith391
 */
@Mod(id = "spacycubyd", name = "SpacyCubyd")
public class BaseMod {

	static Grass grass;
	static Dirt dirt;
	static Stone stone;
	static Water water;
	
	@EventHandler(type = "init")
	public void init() {
		System.out.println("Init!");
	}
	
	@EventHandler(type = "blocks/register")
	public void registerBlocks(BlockRegistry reg) {
		
		// Instances
		grass = new Grass();
		dirt = new Dirt();
		stone = new Stone();
		water = new Water();
		
		// Register
		reg.registerAll(grass, dirt, stone, water);
	}
	
}
