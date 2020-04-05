package io.cubyz.base;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.EventHandler;
import io.cubyz.api.Mod;
import io.cubyz.api.Proxy;
import io.cubyz.api.Registry;
import io.cubyz.api.Resource;
import io.cubyz.base.init.BlockInit;
import io.cubyz.base.init.ItemInit;
import io.cubyz.base.init.MaterialInit;
import io.cubyz.blocks.Block;
import io.cubyz.command.ClearCommand;
import io.cubyz.command.GiveCommand;
import io.cubyz.entity.EntityType;
import io.cubyz.entity.PlayerEntity;
import io.cubyz.items.Item;
import io.cubyz.items.Recipe;
import io.cubyz.items.tools.Material;
import io.cubyz.world.cubyzgenerators.biomes.Biome;
import io.cubyz.world.generator.*;

/**
 * Mod adding Cubyz default content.
 */
@Mod(id = "cubyz", name = "Cubyz")
@SuppressWarnings("unused")
public class BaseMod {
	
	// Entities:
	static PlayerEntity player;
	
	// Recipes:
	static Recipe oakLogToPlanks;
	static Recipe oakPlanksToStick;
	static Recipe oakToWorkbench;
	
	// Client Proxy is defined in cubyz-client, a normal mod would define it in the same mod of course.
	// Proxies are injected at runtime.
	@Proxy(clientProxy = "io.cubyz.base.ClientProxy", serverProxy = "io.cubyz.base.CommonProxy")
	static CommonProxy proxy;
	
	@EventHandler(type = "init")
	public void init() {
		// Both commands and recipes don't have any attributed EventHandler
		// As they are independent to other (the correct order for others is block -> item (for item blocks and other items) -> entity)
		registerRecipes(CubyzRegistries.RECIPE_REGISTRY);
		registerMaterials(CubyzRegistries.TOOL_MATERIAL_REGISTRY);
		registerWorldGenerators(CubyzRegistries.WORLD_GENERATOR_REGISTRY);
		registerBiomes(CubyzRegistries.BIOME_REGISTRY);
		
		CubyzRegistries.COMMAND_REGISTRY.register(new GiveCommand());
		CubyzRegistries.COMMAND_REGISTRY.register(new ClearCommand());
		
		// Init proxy
		proxy.init();
	}
	
	@EventHandler(type = "entity/register")
	public void registerEntities(Registry<EntityType> reg) {
		player = new PlayerEntity();
		
		reg.register(player);
	}
	
	@EventHandler(type = "item/register")
	public void registerItems(Registry<Item> reg) {
		ItemInit.registerAll(reg);
	}
	
	@EventHandler(type = "block/register")
	public void registerBlocks(Registry<Block> reg) {
		BlockInit.registerAll(reg);
	}
	
	public void registerWorldGenerators(Registry<WorldGenerator> reg) {
		reg.registerAll(new LifelandGenerator(), new FlatlandGenerator());
	}
	
	public void registerBiomes(Registry<Biome> reg) {
		// Add some random biomes TODO: More biomes.
		// When creating a new biome there is one things to keep in mind: At their optimal height the biome's polynomial shut return that same height, otherwise terrain generation will get buggy.
		float pol[];
		
		// Beach
		pol = new float[] {0.0f, 1.5003947420951773f, -1.7562874281379752f, 1.255892686042798f};
		CubyzRegistries.BIOME_REGISTRY.register(new Biome(new Resource("cubyz:beach"), pol, 130.0f/360.0f, 102.0f/256.0f));
		
		// Flat lands
		pol = new float[] {0.35f, 0.3f};
		CubyzRegistries.BIOME_REGISTRY.register(new Biome(new Resource("cubyz:flat_lands"), pol, 120.0f/360.0f, 128.0f/256.0f));
		
		// Normal lands low
		pol = new float[] {0.0f, 1.136290302965442f, -0.44234572015099627f, 0.3060554171855542f};
		CubyzRegistries.BIOME_REGISTRY.register(new Biome(new Resource("cubyz:normal_lands_low"), pol, 110.0f/360.0f, 114.0f/256.0f));
		
		// Mountains
		pol = new float[] {0.0f, 5.310967705272164f, -21.14717562082649f, 33.47195695260881f, -16.854499037054477f};
		CubyzRegistries.BIOME_REGISTRY.register(new Biome(new Resource("cubyz:mountains"), pol, 115.0f/360.0f, 140.0f/256.0f));
		
		// Extreme mountains
		pol = new float[] {0.0f, 3.1151893301104367f, -13.738832774207244f, 25.171171602902316f, -13.766278158805507f};
		CubyzRegistries.BIOME_REGISTRY.register(new Biome(new Resource("cubyz:extreme_mountains"), pol, 115.0f/360.0f, 160.0f/256.0f));
	}
	
	public void registerMaterials(Registry<Material> reg) {
		MaterialInit.registerAll(reg);
	}
	
	public void registerRecipes(Registry<Recipe> reg) {
		Item[] recipe;
		
		recipe = new Item[] {BlockInit.oakLog.getBlockDrop()};
		oakLogToPlanks = new Recipe(recipe, 4, BlockInit.oakPlanks.getBlockDrop(), new Resource("cubyz", "logs_to_planks"));
		
		recipe = new Item[] {
				BlockInit.oakPlanks.getBlockDrop(),
				BlockInit.oakPlanks.getBlockDrop(),
		};
		oakPlanksToStick = new Recipe(1, 2, recipe, 4, ItemInit.stick, new Resource("cubyz", "planks_to_stick"));
		Item P = BlockInit.oakPlanks.getBlockDrop();
		Item L = BlockInit.oakLog.getBlockDrop();
		recipe = new Item[] { // Suggestion. // Shortened so it can atleast be craftable :) // Further simplified so it is craftable in our current inventory without farming 67 wood :D
				P, P,
				P, P,
		};
		oakToWorkbench = new Recipe(2, 2, recipe, 1, BlockInit.workbench.getBlockDrop(), new Resource("cubyz", "oak_to_workbench"));
		
		reg.registerAll(oakLogToPlanks, oakPlanksToStick, oakToWorkbench);
	}
}
