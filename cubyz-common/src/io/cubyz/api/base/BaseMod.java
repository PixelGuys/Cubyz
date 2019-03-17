package io.cubyz.api.base;

import io.cubyz.api.EventHandler;
import io.cubyz.api.Mod;
import io.cubyz.api.Registry;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.Dirt;
import io.cubyz.blocks.Grass;
import io.cubyz.blocks.Stone;
import io.cubyz.blocks.Water;

/**
 * Mod adding SpacyCubyd default content.
 * @author zenith391
 */
@Mod(id = "cubyz", name = "Cubyz")
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
	public void registerBlocks(Registry<Block> reg) {
		
		// Instances
		grass = new Grass();
		dirt = new Dirt();
		stone = new Stone();
		water = new Water();
		
		// Register
		reg.registerAll(grass, dirt, stone, water);
	}
	
}
