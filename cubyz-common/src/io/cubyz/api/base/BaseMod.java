package io.cubyz.api.base;

import java.util.ArrayList;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.EventHandler;
import io.cubyz.api.Mod;
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
import io.cubyz.command.GiveCommand;
import io.cubyz.entity.EntityType;
import io.cubyz.entity.PlayerEntity;
import io.cubyz.items.Item;
import io.cubyz.items.Recipe;

/**
 * Mod adding Cubyz default content.
 */
@Mod(id = "cubyz", name = "Cubyz")
public class BaseMod {
	
	// Entities:
	static PlayerEntity player;
	
	// Blocks:
	static Bedrock bedrock;
	static Cactus cactus;
	static CobbleStone cobblestone;
	static Dirt dirt;
	static Grass grass;
	static Ice ice;
	static OakLeaves oakLeaves;
	static OakLog oakLog;
	static OakPlanks oakPlanks;
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
	
	// Block Drops:
	static Item Icactus;
	static Item Icoal;
	static Item Icobblestone;
	static Item Idiamond;
	static Item Idirt;
	static Item Iemerald;
	static Item Igold;
	static Item Iiron;
	static Item IoakLog;
	static Item IoakPlanks;
	static Item Iruby;
	static Item Isand;
	
	// Craftables:
	static Item Istick;
	
	// Recipes:
	static Recipe oakLogToPlanks;
	static Recipe oakPlanksToStick;
	
	@EventHandler(type = "init")
	public void init() {
		System.out.println("Init!");
		CubyzRegistries.COMMAND_REGISTRY.register(new GiveCommand());
	}
	
	@EventHandler(type = "entity/register")
	public void registerEntities(Registry<EntityType> reg) {
		player = new PlayerEntity();
		
		reg.register(player);
	}
	
	@EventHandler(type = "item/register")
	public void registerItems(Registry<Item> reg) {
		Icactus = cactus.getBlockDrop();
		Icoal = coal.getBlockDrop();
		Icobblestone = cobblestone.getBlockDrop();
		Idiamond = diamond.getBlockDrop();
		Idirt = dirt.getBlockDrop();
		Iemerald = emerald.getBlockDrop();
		Igold = gold.getBlockDrop();
		Iiron = iron.getBlockDrop();
		IoakLog = oakLog.getBlockDrop();
		IoakPlanks = oakPlanks.getBlockDrop();
		Iruby = ruby.getBlockDrop();
		Isand = sand.getBlockDrop();
		
		Istick = new Item();
		Istick.setID("cubyz_items:stick");
		Istick.setTexture("materials/stick.png");
		reg.registerAll(Icactus, Icoal, Icobblestone, Idiamond, Idirt, Iemerald, Igold, Iiron, IoakLog, IoakPlanks, Iruby, Isand, Istick);
	}
	
	@EventHandler(type = "block/register")
	public void registerBlocks(Registry<Block> reg) {
		
		// Normal
		bedrock = new Bedrock();
		cactus = new Cactus();
		cobblestone = new CobbleStone();
		dirt = new Dirt();
		grass = new Grass();
		ice = new Ice();
		oakLeaves = new OakLeaves();
		oakLog = new OakLog();
		oakPlanks = new OakPlanks();
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
		
		// Make some special block drops that cannot be done within the constructor due to uncertainty
		grass.setBlockDrop(dirt.getBlockDrop());
		snow.setBlockDrop(dirt.getBlockDrop());
		stone.setBlockDrop(cobblestone.getBlockDrop());
		
		// Register
		reg.registerAll(bedrock, cactus, cobblestone, dirt, grass, ice, oakLeaves, oakLog, oakPlanks, sand, snow, stone, coal, diamond, emerald, gold, iron, ruby, water);
	}
	
	@SuppressWarnings("rawtypes")
	@EventHandler(type = "recipe/register")
	public void registerRecipes (Registry reg) {
		Item[] recipe;
		
		recipe = new Item[] {IoakLog};
		oakLogToPlanks = new Recipe(recipe, IoakPlanks);
		
		recipe = new Item[] {
				IoakPlanks,
				IoakPlanks,
		};
		oakPlanksToStick = new Recipe(1, 2, recipe, Istick);
		
		//reg.registerAll(oakLogToPlanks, oakPlanksToStick); TODO!
	}
}
