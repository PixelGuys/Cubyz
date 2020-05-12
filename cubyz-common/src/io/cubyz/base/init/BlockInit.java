package io.cubyz.base.init;

import java.util.ArrayList;

import io.cubyz.api.Registry;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockGrass;
import io.cubyz.blocks.CoalOre;
import io.cubyz.blocks.DiamondOre;
import io.cubyz.blocks.EmeraldOre;
import io.cubyz.blocks.GoldOre;
import io.cubyz.blocks.IronOre;
import io.cubyz.blocks.OakLeaves;
import io.cubyz.blocks.RubyOre;
import io.cubyz.blocks.Water;
import io.cubyz.blocks.WorkBench;

import static io.cubyz.blocks.Block.BlockClass.*;

public class BlockInit {
	
	public static final ArrayList<Block> BLOCKS = new ArrayList<>();
	
	public static OakLeaves oakLeaves = new OakLeaves();
	public static Block oakLog = new Block("cubyz:oak_log", 8, WOOD);
	public static Block oakTop = new Block("cubyz:oak_top", 8, WOOD);
	public static Block oakPlanks = new Block("cubyz:oak_planks", 7, WOOD);
	public static BlockGrass grassVegetation = new BlockGrass();
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
		
		register(oakLeaves);
		register(oakLog);
		register(oakPlanks);
		register(oakTop);
		register(workbench);
		
		register(coal);
		register(diamond);
		register(emerald);
		register(gold);
		register(iron);
		register(ruby);
		
		register(water);
		
		register(grassVegetation);
		
		reg.registerAll(BLOCKS);
	}
	
}
