package io.cubyz.api;

import io.cubyz.blocks.Block;
import io.cubyz.entity.EntityType;
import io.cubyz.items.Item;
import io.cubyz.items.Recipe;
import io.cubyz.items.tools.Material;
import io.cubyz.world.cubyzgenerators.biomes.BiomeRegistry;
import io.cubyz.world.generator.SurfaceGenerator;

/**
 * Contains the torus-specific registries.
 */

public class CurrentSurfaceRegistries {

	public final Registry<Block>       blockRegistry         = new Registry<Block>(CubyzRegistries.BLOCK_REGISTRY);
	public final Registry<Item>        itemRegistry          = new Registry<Item>(CubyzRegistries.ITEM_REGISTRY);
	public final NoIDRegistry<Recipe>  recipeRegistry        = new NoIDRegistry<Recipe>(CubyzRegistries.RECIPE_REGISTRY);
	public final Registry<EntityType>  entityRegistry        = new Registry<EntityType>(CubyzRegistries.ENTITY_REGISTRY);
	public final Registry<Material>    materialRegistry		 = new Registry<Material>(CubyzRegistries.TOOL_MATERIAL_REGISTRY);
	public final BiomeRegistry         biomeRegistry         = new BiomeRegistry(CubyzRegistries.BIOME_REGISTRY);
	
	// world generation
	public final Registry<SurfaceGenerator> worldGeneratorRegistry = new Registry<SurfaceGenerator>(CubyzRegistries.STELLAR_TORUS_GENERATOR_REGISTRY);
}
