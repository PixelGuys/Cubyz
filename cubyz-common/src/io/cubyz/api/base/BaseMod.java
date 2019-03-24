package io.cubyz.api.base;

import io.cubyz.api.EventHandler;
import io.cubyz.api.Mod;
import io.cubyz.api.Registry;
import io.cubyz.blocks.Bedrock;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.CoalOre;
import io.cubyz.blocks.DiamondOre;
import io.cubyz.blocks.Dirt;
import io.cubyz.blocks.EmeraldOre;
import io.cubyz.blocks.GoldOre;
import io.cubyz.blocks.Grass;
import io.cubyz.blocks.IronOre;
import io.cubyz.blocks.OakLeaves;
import io.cubyz.blocks.OakLog;
import io.cubyz.blocks.RubyOre;
import io.cubyz.blocks.Sand;
import io.cubyz.blocks.SnowGrass;
import io.cubyz.blocks.Stone;
import io.cubyz.blocks.Water;

/**
 * Mod adding SpacyCubyd default content.
 * @author zenith391
 */
@Mod(id = "cubyz", name = "Cubyz")
public class BaseMod {
	
	// Normal:
	static Bedrock bedrock;
	static Grass grass;
	static Dirt dirt;
	static OakLeaves oakLeaves;
	static OakLog oakLog;
	static Sand sand;
	static SnowGrass snow;
	static Stone stone;
	
	// Ores:
	static CoalOre coal;
	static DiamondOre diamond;
	static EmeraldOre emerald;
	static GoldOre gold;
	static IronOre iron;
	static RubyOre ruby;
	
	// Fluid:
	static Water water;
	
	@EventHandler(type = "init")
	public void init() {
		System.out.println("Init!");
	}
	
	@EventHandler(type = "block/register")
	public void registerBlocks(Registry<Block> reg) {
		
		// Normal
		bedrock = new Bedrock();
		grass = new Grass();
		dirt = new Dirt();
		oakLeaves = new OakLeaves();
		oakLog = new OakLog();
		sand = new Sand();
		snow = new SnowGrass();
		stone = new Stone();
		
		// Ores
		coal = new CoalOre();
		diamond = new DiamondOre();
		emerald = new EmeraldOre();
		gold = new GoldOre();
		iron = new IronOre();
		ruby = new RubyOre();
		
		
		// Fluids
		water = new Water();
		
		// Register
		reg.registerAll(bedrock, grass, dirt, oakLeaves, oakLog, sand, snow, stone, coal, diamond, emerald, gold, iron, ruby, water);
	}
	
}
