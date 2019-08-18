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
import io.cubyz.command.GiveCommand;
import io.cubyz.entity.EntityType;
import io.cubyz.entity.PlayerEntity;
import io.cubyz.items.Item;
import io.cubyz.items.Recipe;
import io.cubyz.tools.Material;

/**
 * Mod adding Cubyz default content.
 */
@Mod(id = "cubyz", name = "Cubyz")
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
		CubyzRegistries.COMMAND_REGISTRY.register(new GiveCommand());
		
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
	
	@EventHandler(type = "material/register")
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
