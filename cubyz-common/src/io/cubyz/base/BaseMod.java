package io.cubyz.base;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.EventHandler;
import io.cubyz.api.Mod;
import io.cubyz.api.NoIDRegistry;
import io.cubyz.api.Proxy;
import io.cubyz.api.Registry;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.command.ClearCommand;
import io.cubyz.command.CureCommand;
import io.cubyz.command.GiveCommand;
import io.cubyz.command.TimeCommand;
import io.cubyz.entity.EntityType;
import io.cubyz.entity.Pig;
import io.cubyz.entity.PlayerEntity;
import io.cubyz.items.Item;
import io.cubyz.items.Recipe;
import io.cubyz.items.tools.Material;
import io.cubyz.items.tools.modifiers.FallingApart;
import io.cubyz.items.tools.modifiers.Regrowth;
import io.cubyz.world.cubyzgenerators.biomes.Biome;
import io.cubyz.world.cubyzgenerators.biomes.BlockStructure;
import io.cubyz.world.cubyzgenerators.biomes.SimpleTreeModel;
import io.cubyz.world.cubyzgenerators.biomes.SimpleVegetation;
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
		registerMaterials(CubyzRegistries.TOOL_MATERIAL_REGISTRY);
		registerWorldGenerators(CubyzRegistries.STELLAR_TORUS_GENERATOR_REGISTRY);
		
		CubyzRegistries.COMMAND_REGISTRY.register(new GiveCommand());
		CubyzRegistries.COMMAND_REGISTRY.register(new ClearCommand());
		CubyzRegistries.COMMAND_REGISTRY.register(new CureCommand());
		CubyzRegistries.COMMAND_REGISTRY.register(new TimeCommand());
		
		// Init proxy
		proxy.init();
	}
	
	@EventHandler(type = "register:entity")
	public void registerEntities(Registry<EntityType> reg) {
		reg.register(new Pig());
		reg.register(new PlayerEntity());
	}
	
	public void registerWorldGenerators(Registry<SurfaceGenerator> reg) {
		reg.registerAll(new LifelandGenerator(), new FlatlandGenerator());
	}
	
	public void registerMaterials(Registry<Material> reg) {
		Item stick = CubyzRegistries.ITEM_REGISTRY.getByID("cubyz:stick");
		Material dirt = new Material(-50, 5, 0, 0.0f, 0.1f);
		dirt.setID("cubyz:dirt");
		dirt.addModifier(new FallingApart(0.1f));
		dirt.addItem(CubyzRegistries.ITEM_REGISTRY.getByID("cubyz:dirt"), 100);
		reg.register(dirt);
		
		Material wood = new Material(-20, 50, 20, 0.01f/*being hit by a wood sword doesn't hurt*/, 1);
		wood.setMiningLevel(1);
		wood.setID("cubyz:wood");
		wood.addModifier(new Regrowth());
		wood.addModifier(new FallingApart(0.9f));
		wood.addItem(stick, 50);
		wood.addItem(CubyzRegistries.ITEM_REGISTRY.getByID("cubyz:oak_planks"), 100);
		wood.addItem(CubyzRegistries.ITEM_REGISTRY.getByID("cubyz:oak_log"), 150); // Working with oak logs in the table is inefficient.
		reg.register(wood);
		
		Material stone = new Material(10, 30, 20, 0.1f, 1.5f);
		stone.setMiningLevel(2);
		stone.setID("cubyz:stone");
		// TODO: Modifiers
		stone.addItem(CubyzRegistries.ITEM_REGISTRY.getByID("cubyz:cobblestone"), 100);
		reg.register(stone);
		
		Material cactus = new Material(-30, 75, 10, 0.2f, 0.7f);
		cactus.setID("cubyz:cactus");
		// TODO: Modifiers
		cactus.addItem(CubyzRegistries.ITEM_REGISTRY.getByID("cubyz:cactus"), 100);
		reg.register(cactus);
	}
}
