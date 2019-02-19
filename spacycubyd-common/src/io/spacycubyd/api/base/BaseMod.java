package io.spacycubyd.api.base;

import io.spacycubyd.api.EventHandler;
import io.spacycubyd.api.Mod;
import io.spacycubyd.blocks.Dirt;
import io.spacycubyd.blocks.Grass;
import io.spacycubyd.blocks.Stone;
import io.spacycubyd.blocks.Water;
import io.spacycubyd.modding.BlockRegistry;

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
