package cubyz.api;

import java.io.File;
import java.util.Random;

import cubyz.modding.base.AddonsMod;
import cubyz.world.ServerWorld;
import cubyz.world.blocks.Block;
import cubyz.world.blocks.CustomOre;
import cubyz.world.blocks.Ore;
import cubyz.world.entity.EntityType;
import cubyz.world.items.Item;
import cubyz.world.items.Recipe;
import cubyz.world.terrain.biomes.BiomeRegistry;
import cubyz.world.terrain.worldgenerators.SurfaceGenerator;

/**
 * Contains the world-specific registries.
 */

public class CurrentWorldRegistries {

	public final Registry<Block>       blockRegistry         = new Registry<Block>(CubyzRegistries.BLOCK_REGISTRY);
	public final NoIDRegistry<Ore>     oreRegistry           = new NoIDRegistry<Ore>(CubyzRegistries.ORE_REGISTRY);
	public final Registry<Item>        itemRegistry          = new Registry<Item>(CubyzRegistries.ITEM_REGISTRY);
	public final NoIDRegistry<Recipe>  recipeRegistry        = new NoIDRegistry<Recipe>(CubyzRegistries.RECIPE_REGISTRY);
	public final Registry<EntityType>  entityRegistry        = new Registry<EntityType>(CubyzRegistries.ENTITY_REGISTRY);
	public final BiomeRegistry         biomeRegistry         = new BiomeRegistry(CubyzRegistries.BIOME_REGISTRY);
	
	// world generation
	public final Registry<SurfaceGenerator> worldGeneratorRegistry = new Registry<SurfaceGenerator>(CubyzRegistries.STELLAR_TORUS_GENERATOR_REGISTRY);

	/**
	 * Loads the world specific assets, such as procedural ores.
	 */
	public CurrentWorldRegistries(ServerWorld world) {
		File assets = new File("saves/" + world.getName() + "/assets");
		if(!assets.exists()) {
			generateAssets(assets, world);
		}
		loadWorldAssets(assets);
	}

	public void loadWorldAssets(File assets) {
		AddonsMod.instance.preInit(assets);
		System.out.println(assets);
		AddonsMod.instance.registerBlocks(blockRegistry, oreRegistry);
		AddonsMod.instance.registerItems(itemRegistry, assets.getAbsolutePath()+"/");
		AddonsMod.instance.registerBiomes(biomeRegistry);
		AddonsMod.instance.init(itemRegistry, blockRegistry, recipeRegistry);
	}

	public void generateAssets(File assets, ServerWorld world) {
		assets = new File(assets, "cubyz");
		assets.mkdirs();
		new File(assets, "blocks/textures").mkdirs();
		new File(assets, "items/textures").mkdirs();
		Random rand = new Random(world.getSeed());
		int randomAmount = 9 + rand.nextInt(3); // TODO
		int i = 0;
		for(i = 0; i < randomAmount; i++) {
			CustomOre.random(rand, assets, "cubyz");
		}
	}
}
