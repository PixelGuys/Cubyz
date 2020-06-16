package io.cubyz.api;

import io.cubyz.blocks.Block;
import io.cubyz.blocks.RotationMode;
import io.cubyz.command.CommandBase;
import io.cubyz.entity.EntityType;
import io.cubyz.items.Item;
import io.cubyz.items.Recipe;
import io.cubyz.items.tools.Material;
import io.cubyz.items.tools.Modifier;
import io.cubyz.world.cubyzgenerators.biomes.Biome;
import io.cubyz.world.generator.SurfaceGenerator;

public class CubyzRegistries {

	public static final Registry<Block>       BLOCK_REGISTRY         = new Registry<Block>();
	public static final Registry<Item>        ITEM_REGISTRY          = new Registry<Item>();
	public static final NoIDRegistry<Recipe>  RECIPE_REGISTRY    	 = new NoIDRegistry<Recipe>();
	public static final Registry<EntityType>  ENTITY_REGISTRY        = new Registry<EntityType>();
	public static final Registry<CommandBase> COMMAND_REGISTRY       = new Registry<CommandBase>();
	public static final Registry<Material>    TOOL_MATERIAL_REGISTRY = new Registry<Material>();
	public static final Registry<Modifier>    TOOL_MODIFIER_REGISTRY = new Registry<Modifier>();
	public static final Registry<Biome>       BIOME_REGISTRY         = new Registry<Biome>();
	public static final Registry<RotationMode>ROTATION_MODE_REGISTRY = new Registry<RotationMode>();
	
	// world generation
	public static final Registry<SurfaceGenerator> STELLAR_TORUS_GENERATOR_REGISTRY = new Registry<SurfaceGenerator>();
	
}
