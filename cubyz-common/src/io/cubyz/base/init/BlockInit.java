package io.cubyz.base.init;

import java.util.ArrayList;

import io.cubyz.api.Registry;
import io.cubyz.blocks.Bedrock;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.CoalOre;
import io.cubyz.blocks.DiamondOre;
import io.cubyz.blocks.EmeraldOre;
import io.cubyz.blocks.GoldOre;
import io.cubyz.blocks.Grass;
import io.cubyz.blocks.Ice;
import io.cubyz.blocks.IronOre;
import io.cubyz.blocks.OakLeaves;
import io.cubyz.blocks.RubyOre;
import io.cubyz.blocks.SnowGrass;
import io.cubyz.blocks.Water;
import io.cubyz.blocks.WorkBench;

public class BlockInit {
	
	public static final ArrayList<Block> BLOCKS = new ArrayList<>();
	
	public static Bedrock bedrock = new Bedrock();
	public static Block cactus = new Block("cubyz:cactus");
	public static Block cobblestone = new Block("cubyz:cobblestone");
	public static Block dirt = new Block("cubyz:dirt");
	public static Grass grass = new Grass();
	public static Ice ice = new Ice();
	public static OakLeaves oakLeaves = new OakLeaves();
	public static Block oakLog = new Block("cubyz:oak_log");
	public static Block oakPlanks = new Block("cubyz:oak_planks");
	public static Block sand = new Block("cubyz:sand");
	public static SnowGrass snow = new SnowGrass();
	public static Block stone = new Block("cubyz:stone");
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
