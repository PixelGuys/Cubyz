package io.cubyz.base;

import java.io.File;
import java.util.ArrayList;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.CurrentSurfaceRegistries;
import io.cubyz.api.EventHandler;
import io.cubyz.api.Mod;
import io.cubyz.api.NoIDRegistry;
import io.cubyz.api.Proxy;
import io.cubyz.api.Registry;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.RotationMode;
import io.cubyz.command.ClearCommand;
import io.cubyz.command.CureCommand;
import io.cubyz.command.GiveCommand;
import io.cubyz.command.TPCommand;
import io.cubyz.command.TimeCommand;
import io.cubyz.entity.EntityType;
import io.cubyz.entity.Pig;
import io.cubyz.entity.PlayerEntity;
import io.cubyz.items.Item;
import io.cubyz.items.Recipe;
import io.cubyz.items.tools.Material;
import io.cubyz.items.tools.Modifier;
import io.cubyz.items.tools.modifiers.FallingApart;
import io.cubyz.items.tools.modifiers.Regrowth;
import io.cubyz.world.cubyzgenerators.biomes.Biome;
import io.cubyz.world.cubyzgenerators.biomes.BlockStructure;
import io.cubyz.world.cubyzgenerators.biomes.SimpleTreeModel;
import io.cubyz.world.cubyzgenerators.biomes.SimpleVegetation;
import io.cubyz.world.generator.*;

/**
 * Mod adding Cubyz default content, which is not added by addon files.
 */
@Mod(id = "cubyz", name = "Cubyz")
@SuppressWarnings("unused")
public class BaseMod {
	
	// Client Proxy is defined in cubyz-client, a normal mod would define it in the same mod of course.
	// Proxies are injected at runtime.
	@Proxy(clientProxy = "io.cubyz.base.ClientProxy", serverProxy = "io.cubyz.base.CommonProxy")
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

	@EventHandler(type = "postSurfaceGen")
	public void postSurfaceGen(CurrentSurfaceRegistries registries) {
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
