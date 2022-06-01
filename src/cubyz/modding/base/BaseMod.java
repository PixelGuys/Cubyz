package cubyz.modding.base;

import java.util.ArrayList;

import cubyz.api.CubyzRegistries;
import cubyz.api.CurrentWorldRegistries;
import cubyz.api.Mod;
import cubyz.api.Proxy;
import cubyz.api.Registry;
import cubyz.command.*;
import cubyz.rendering.rotation.*;
import cubyz.world.blocks.Blocks;
import cubyz.world.blocks.RotationMode;
import cubyz.world.entity.EntityType;
import cubyz.world.entity.Pig;
import cubyz.world.entity.PlayerEntity;
import cubyz.world.items.tools.Modifier;
import cubyz.world.items.tools.modifiers.FallingApart;
import cubyz.world.items.tools.modifiers.Regrowth;
import cubyz.world.terrain.biomes.*;
import cubyz.world.terrain.cavebiomegenerators.RandomBiomeDistribution;
import cubyz.world.terrain.cavegenerators.FractalCaveGenerator;
import cubyz.world.terrain.cavegenerators.NoiseCaveGenerator;
import cubyz.world.terrain.cavegenerators.SurfaceGenerator;
import cubyz.world.terrain.generators.*;
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
		CubyzRegistries.COMMAND_REGISTRY.register(new InviteCommand());
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

		CubyzRegistries.ROTATION_MODE_REGISTRY.register(new NoRotation());
		CubyzRegistries.ROTATION_MODE_REGISTRY.register(new TorchRotation());
		CubyzRegistries.ROTATION_MODE_REGISTRY.register(new LogRotation());
		CubyzRegistries.ROTATION_MODE_REGISTRY.register(new StackableRotation());
		CubyzRegistries.ROTATION_MODE_REGISTRY.register(new FenceRotation());
		CubyzRegistries.ROTATION_MODE_REGISTRY.register(new MultiTexture());

		CubyzRegistries.STRUCTURE_REGISTRY.register(new SimpleTreeModel());
		CubyzRegistries.STRUCTURE_REGISTRY.register(new SimpleVegetation());
		CubyzRegistries.STRUCTURE_REGISTRY.register(new GroundPatch());
		CubyzRegistries.STRUCTURE_REGISTRY.register(new Boulder());

		CubyzRegistries.GENERATORS.register(new TerrainGenerator());
		CubyzRegistries.GENERATORS.register(new OreGenerator());
		CubyzRegistries.GENERATORS.register(new StructureGenerator());
		CubyzRegistries.GENERATORS.register(new CrystalGenerator());

		CubyzRegistries.CAVE_GENERATORS.register(new SurfaceGenerator());
		CubyzRegistries.CAVE_GENERATORS.register(new FractalCaveGenerator());
		CubyzRegistries.CAVE_GENERATORS.register(new NoiseCaveGenerator());

		CubyzRegistries.CAVE_BIOME_GENERATORS.register(new RandomBiomeDistribution());

		CubyzRegistries.CLIMATE_GENERATOR_REGISTRY.register(new PolarCircles());
		CubyzRegistries.CLIMATE_GENERATOR_REGISTRY.register(new FlatLand());

		CubyzRegistries.MAP_GENERATOR_REGISTRY.register(new MapGenV1());
		
		CubyzRegistries.BLOCK_REGISTRIES.register(new Blocks());
		
		// Pre-Init proxy
		proxy.preInit();
	}
	
	@Override
	public void registerEntities(Registry<EntityType> reg) {
		// TODO: reg.register(new Pig());
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
			if (replacements.isEmpty()) {
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
			if (replacements.isEmpty()) {
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
