package io.cubyz.base.init;

import java.util.ArrayList;

import io.cubyz.api.Registry;
import io.cubyz.blocks.Bedrock;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.Cactus;
import io.cubyz.blocks.CoalOre;
import io.cubyz.blocks.CobbleStone;
import io.cubyz.blocks.DiamondOre;
import io.cubyz.blocks.Dirt;
import io.cubyz.blocks.EmeraldOre;
import io.cubyz.blocks.GoldOre;
import io.cubyz.blocks.Grass;
import io.cubyz.blocks.Ice;
import io.cubyz.blocks.IronOre;
import io.cubyz.blocks.OakLeaves;
import io.cubyz.blocks.OakLog;
import io.cubyz.blocks.OakPlanks;
import io.cubyz.blocks.RubyOre;
import io.cubyz.blocks.Sand;
import io.cubyz.blocks.SnowGrass;
import io.cubyz.blocks.Stone;
import io.cubyz.blocks.Water;
import io.cubyz.blocks.WorkBench;

public class BlockInit {
	
	public static final ArrayList<Block> BLOCKS = new ArrayList<>();
	
	public static Bedrock bedrock = new Bedrock();
	public static Cactus cactus = new Cactus();
	public static CobbleStone cobblestone = new CobbleStone();
	public static Dirt dirt = new Dirt();
	public static Grass grass = new Grass();
	public static Ice ice = new Ice();
	public static OakLeaves oakLeaves = new OakLeaves();
	public static OakLog oakLog = new OakLog();
	public static OakPlanks oakPlanks = new OakPlanks();
	public static Sand sand = new Sand();
	public static SnowGrass snow = new SnowGrass();
	public static Stone stone = new Stone();
	public static WorkBench workbench = new WorkBench();
	
	public static CoalOre coal = new CoalOre();
	public static DiamondOre diamond = new DiamondOre();
	public static EmeraldOre emerald = new EmeraldOre();
	public static GoldOre gold = new GoldOre();
	public static IronOre iron = new IronOre();
	public static RubyOre ruby = new RubyOre();
	
	static Water water = new Water();
	
	public static void register(Block block) {
		if (block.getBlockDrop() != null && !ItemInit.ITEMS.contains(block.getBlockDrop()))
			ItemInit.ITEMS.add(block.getBlockDrop());
		BLOCKS.add(block);
	}

	public static void registerAll(Registry<Block> reg) {
		
		grass.setBlockDrop(dirt.getBlockDrop());
		snow.setBlockDrop(dirt.getBlockDrop());
		stone.setBlockDrop(cobblestone.getBlockDrop());
		
		register(bedrock);
		register(cactus);
		register(cobblestone);
		register(dirt);
		register(grass);
		register(ice);
		register(oakLeaves);
		register(oakLog);
		register(oakPlanks);
		register(sand);
		register(snow);
		register(stone);
		register(workbench);
		
		register(coal);
		register(diamond);
		register(emerald);
		register(gold);
		register(iron);
		register(ruby);
		
		register(water);
		
		reg.registerAll(BLOCKS);
	}
	
}
