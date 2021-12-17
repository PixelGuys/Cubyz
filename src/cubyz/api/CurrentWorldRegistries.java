package cubyz.api;

import java.io.File;
import java.util.Random;

import cubyz.modding.base.AddonsMod;
import cubyz.world.ServerWorld;
import cubyz.world.blocks.CustomOre;
import cubyz.world.blocks.Ore;
import cubyz.world.entity.EntityType;
import cubyz.world.items.Item;
import cubyz.world.items.Recipe;
import cubyz.world.terrain.biomes.BiomeRegistry;

/**
 * Contains the world-specific registries.
 */

public class CurrentWorldRegistries {

	public final Registry<DataOrientedRegistry> blockRegistries = new Registry<DataOrientedRegistry>(CubyzRegistries.BLOCK_REGISTRIES);
	public final NoIDRegistry<Ore>              oreRegistry     = new NoIDRegistry<Ore>(CubyzRegistries.ORE_REGISTRY);
	public final Registry<Item>                 itemRegistry    = new Registry<Item>(CubyzRegistries.ITEM_REGISTRY);
	public final NoIDRegistry<Recipe>           recipeRegistry  = new NoIDRegistry<Recipe>(CubyzRegistries.RECIPE_REGISTRY);
	public final Registry<EntityType>           entityRegistry  = new Registry<EntityType>(CubyzRegistries.ENTITY_REGISTRY);
	public final BiomeRegistry                  biomeRegistry   = new BiomeRegistry(CubyzRegistries.BIOME_REGISTRY);

	/**
	 * Loads the world specific assets, such as procedural ores.
	 */
	public CurrentWorldRegistries(ServerWorld world) {
		String assetPath = "saves/" + world.getName() + "/assets/";
		File assets = new File(assetPath);
		if (!assets.exists()) {
			generateAssets(assets, world);
		}
		for(DataOrientedRegistry reg : blockRegistries.registered(new DataOrientedRegistry[0])) {
			reg.reset(CubyzRegistries.blocksBeforeWorld);
		}
		loadWorldAssets(assetPath);
	}

	public void loadWorldAssets(String assetPath) {
		AddonsMod.instance.preInit(assetPath);
		AddonsMod.instance.registerBlocks(blockRegistries, oreRegistry);
		AddonsMod.instance.registerItems(itemRegistry, assetPath);
		AddonsMod.instance.registerBiomes(biomeRegistry);
		AddonsMod.instance.init(itemRegistry, blockRegistries, recipeRegistry);
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
