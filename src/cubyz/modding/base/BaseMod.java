package cubyz.modding.base;

import java.io.File;
import java.util.ArrayList;

import cubyz.api.CubyzRegistries;
import cubyz.api.CurrentWorldRegistries;
import cubyz.api.EventHandler;
import cubyz.api.Mod;
import cubyz.api.NoIDRegistry;
import cubyz.api.Proxy;
import cubyz.api.Registry;
import cubyz.api.Resource;
import cubyz.command.ClearCommand;
import cubyz.command.CureCommand;
import cubyz.command.GiveCommand;
import cubyz.command.TPCommand;
import cubyz.command.TimeCommand;
import cubyz.world.blocks.Block;
import cubyz.world.blocks.RotationMode;
import cubyz.world.cubyzgenerators.biomes.Biome;
import cubyz.world.cubyzgenerators.biomes.BlockStructure;
import cubyz.world.cubyzgenerators.biomes.SimpleTreeModel;
import cubyz.world.cubyzgenerators.biomes.SimpleVegetation;
import cubyz.world.entity.EntityType;
import cubyz.world.entity.Pig;
import cubyz.world.entity.PlayerEntity;
import cubyz.world.generator.*;
import cubyz.world.items.Item;
import cubyz.world.items.Recipe;
import cubyz.world.items.tools.Material;
import cubyz.world.items.tools.Modifier;
import cubyz.world.items.tools.modifiers.FallingApart;
import cubyz.world.items.tools.modifiers.Regrowth;

/**
 * Mod adding Cubyz default content, which is not added by addon files.
 */
@Mod(id = "cubyz", name = "Cubyz")
@SuppressWarnings("unused")
public class BaseMod {
	
	// Client Proxy is defined in cubyz-client, a normal mod would define it in the same mod of course.
	// Proxies are injected at runtime.
	@Proxy(clientProxy = "cubyz.modding.base.ClientProxy", serverProxy = "cubyz.modding.base.CommonProxy")
	static CommonProxy proxy;
	
	@EventHandler(type = "init")
	public void init() {
		// Both commands and recipes don't have any attributed EventHandler
		// As they are independent to other (the correct order for others is block -> item (for item blocks and other items) -> entity)
		registerWorldGenerators(CubyzRegistries.STELLAR_TORUS_GENERATOR_REGISTRY);
		
		CubyzRegistries.COMMAND_REGISTRY.register(new GiveCommand());
		CubyzRegistries.COMMAND_REGISTRY.register(new ClearCommand());
		CubyzRegistries.COMMAND_REGISTRY.register(new CureCommand());
		CubyzRegistries.COMMAND_REGISTRY.register(new TimeCommand());
		CubyzRegistries.COMMAND_REGISTRY.register(new TPCommand());
		
		// Init proxy
		proxy.init();
	}

	@EventHandler(type = "preInit")
	public void preInit() {
		registerModifiers(CubyzRegistries.TOOL_MODIFIER_REGISTRY);
		
		// Pre-Init proxy
		proxy.preInit();
	}
	
	@EventHandler(type = "register:entity")
	public void registerEntities(Registry<EntityType> reg) {
		reg.register(new Pig());
		reg.register(new PlayerEntity());
	}
	
	public void registerWorldGenerators(Registry<SurfaceGenerator> reg) {
		reg.registerAll(new LifelandGenerator(), new FlatlandGenerator());
	}
	
	public void registerModifiers(Registry<Modifier> reg) {
		reg.register(new FallingApart());
		reg.register(new Regrowth());
	}

	@EventHandler(type = "postWorldGen")
	public void postWorldGen(CurrentWorldRegistries registries) {
		// Get a list of replacement biomes for each biome:
		for(Biome biome : registries.biomeRegistry.registered(new Biome[0])) {
			ArrayList<Biome> replacements = new ArrayList<Biome>();
			// Check lower replacements:
			// Check if there are replacement biomes of the same type:
			registries.biomeRegistry.byTypeBiomes.get(biome.type).forEach(replacement -> {
				if(replacement.maxHeight > biome.minHeight && replacement.minHeight < biome.minHeight) {
					replacements.add(replacement);
				}
			});
			// If that doesn't work, check for the next smaller height region:
			if(replacements.size() == 0) {
				Biome.checkLowerTypesInRegistry(biome.type, replacement -> {
					if(replacement.maxHeight > biome.minHeight && replacement.minHeight < biome.minHeight) {
						replacements.add(replacement);
					}
				}, registries.biomeRegistry);
			}
			biome.lowerReplacements = replacements.toArray(biome.lowerReplacements);
			
			replacements.clear();
			// Check upper replacements:
			// Check if there are replacement biomes of the same type:
			registries.biomeRegistry.byTypeBiomes.get(biome.type).forEach(replacement -> {
				if(replacement.minHeight < biome.maxHeight && replacement.maxHeight > biome.maxHeight) {
					replacements.add(replacement);
				}
			});
			// If that doesn't work, check for the next smaller height region:
			if(replacements.size() == 0) {
				Biome.checkHigherTypesInRegistry(biome.type, replacement -> {
					if(replacement.minHeight < biome.maxHeight && replacement.maxHeight > biome.maxHeight) {
						replacements.add(replacement);
					}
				}, registries.biomeRegistry);
			}
			biome.upperReplacements = replacements.toArray(biome.upperReplacements);
		}
	}
}
