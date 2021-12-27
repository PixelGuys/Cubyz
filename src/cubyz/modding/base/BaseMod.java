package cubyz.modding.base;

import java.util.ArrayList;

import cubyz.api.CubyzRegistries;
import cubyz.api.CurrentWorldRegistries;
import cubyz.api.Mod;
import cubyz.api.Proxy;
import cubyz.api.Registry;
import cubyz.command.ClearCommand;
import cubyz.command.CureCommand;
import cubyz.command.GameTimeCycleCommand;
import cubyz.command.GiveCommand;
import cubyz.command.TPCommand;
import cubyz.command.TimeCommand;
import cubyz.world.blocks.Blocks;
import cubyz.world.entity.EntityType;
import cubyz.world.entity.Pig;
import cubyz.world.entity.PlayerEntity;
import cubyz.world.items.tools.Modifier;
import cubyz.world.items.tools.modifiers.FallingApart;
import cubyz.world.items.tools.modifiers.Regrowth;
import cubyz.world.terrain.biomes.Biome;
import cubyz.world.terrain.biomes.GroundPatch;
import cubyz.world.terrain.biomes.SimpleTreeModel;
import cubyz.world.terrain.biomes.SimpleVegetation;
import cubyz.world.terrain.generators.CrystalCavernGenerator;
import cubyz.world.terrain.generators.FractalCaveGenerator;
import cubyz.world.terrain.generators.OreGenerator;
import cubyz.world.terrain.generators.StructureGenerator;
import cubyz.world.terrain.generators.TerrainGenerator;
import cubyz.world.terrain.worldgenerators.FlatLand;
import cubyz.world.terrain.worldgenerators.MapGenV1;
import cubyz.world.terrain.worldgenerators.PolarCircles;

/**
 * Mod adding Cubyz default content, which is not added by addon files.
 */
public class BaseMod implements Mod {

	@Override
	public String id() {
		return "cubyz";
	}

	@Override
	public String name() {
		return "Cubyz";
	}
	
	// Client Proxy is defined in cubyz-client, a normal mod would define it in the same mod of course.
	// Proxies are injected at runtime.
	@Proxy(clientProxy = "cubyz.modding.base.ClientProxy", serverProxy = "cubyz.modding.base.CommonProxy")
	static CommonProxy proxy;
	
	@Override
	public void init() {
		// Both commands and recipes don't have any attributed EventHandler
		// As they are independent to other (the correct order for others is block -> item (for item blocks and other items) -> entity)
		CubyzRegistries.COMMAND_REGISTRY.register(new GameTimeCycleCommand());
		CubyzRegistries.COMMAND_REGISTRY.register(new GiveCommand());
		CubyzRegistries.COMMAND_REGISTRY.register(new ClearCommand());
		CubyzRegistries.COMMAND_REGISTRY.register(new CureCommand());
		CubyzRegistries.COMMAND_REGISTRY.register(new TimeCommand());
		CubyzRegistries.COMMAND_REGISTRY.register(new TPCommand());
		
		// Init proxy
		proxy.init();
	}

	@Override
	public void preInit() {
		registerModifiers(CubyzRegistries.TOOL_MODIFIER_REGISTRY);

		CubyzRegistries.STRUCTURE_REGISTRY.register(new SimpleTreeModel());
		CubyzRegistries.STRUCTURE_REGISTRY.register(new SimpleVegetation());
		CubyzRegistries.STRUCTURE_REGISTRY.register(new GroundPatch());

		CubyzRegistries.GENERATORS.register(new TerrainGenerator());
		CubyzRegistries.GENERATORS.register(new OreGenerator());
		CubyzRegistries.GENERATORS.register(new FractalCaveGenerator());
		CubyzRegistries.GENERATORS.register(new CrystalCavernGenerator());
		CubyzRegistries.GENERATORS.register(new StructureGenerator());

		CubyzRegistries.CLIMATE_GENERATOR_REGISTRY.register(new PolarCircles());
		CubyzRegistries.CLIMATE_GENERATOR_REGISTRY.register(new FlatLand());

		CubyzRegistries.MAP_GENERATOR_REGISTRY.register(new MapGenV1());
		
		CubyzRegistries.BLOCK_REGISTRIES.register(new Blocks());
		
		// Pre-Init proxy
		proxy.preInit();
	}
	
	@Override
	public void registerEntities(Registry<EntityType> reg) {
		reg.register(new Pig());
		reg.register(new PlayerEntity());
	}
	
	public void registerModifiers(Registry<Modifier> reg) {
		reg.register(new FallingApart());
		reg.register(new Regrowth());
	}

	@Override
	public void postWorldGen(CurrentWorldRegistries registries) {
		// Get a list of replacement biomes for each biome:
		for(Biome biome : registries.biomeRegistry.registered(new Biome[0])) {
			ArrayList<Biome> replacements = new ArrayList<Biome>();
			// Check lower replacements:
			// Check if there are replacement biomes of the same type:
			registries.biomeRegistry.byTypeBiomes.get(biome.type).forEach(replacement -> {
				if (replacement.maxHeight > biome.minHeight && replacement.minHeight < biome.minHeight) {
					replacements.add(replacement);
				}
			});
			// If that doesn't work, check for the next smaller height region:
			if (replacements.size() == 0) {
				Biome.checkLowerTypesInRegistry(biome.type, replacement -> {
					if (replacement.maxHeight > biome.minHeight && replacement.minHeight < biome.minHeight) {
						replacements.add(replacement);
					}
				}, registries.biomeRegistry);
			}
			biome.lowerReplacements = replacements.toArray(biome.lowerReplacements);
			
			replacements.clear();
			// Check upper replacements:
			// Check if there are replacement biomes of the same type:
			registries.biomeRegistry.byTypeBiomes.get(biome.type).forEach(replacement -> {
				if (replacement.minHeight < biome.maxHeight && replacement.maxHeight > biome.maxHeight) {
					replacements.add(replacement);
				}
			});
			// If that doesn't work, check for the next smaller height region:
			if (replacements.size() == 0) {
				Biome.checkHigherTypesInRegistry(biome.type, replacement -> {
					if (replacement.minHeight < biome.maxHeight && replacement.maxHeight > biome.maxHeight) {
						replacements.add(replacement);
					}
				}, registries.biomeRegistry);
			}
			biome.upperReplacements = replacements.toArray(biome.upperReplacements);
		}
	}
}
