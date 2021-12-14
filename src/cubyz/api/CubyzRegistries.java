package cubyz.api;

import cubyz.command.CommandBase;
import cubyz.world.blocks.Ore;
import cubyz.world.blocks.RotationMode;
import cubyz.world.entity.EntityModel;
import cubyz.world.entity.EntityType;
import cubyz.world.handler.RemoveBlockHandler;
import cubyz.world.handler.PlaceBlockHandler;
import cubyz.world.items.Item;
import cubyz.world.items.Recipe;
import cubyz.world.items.tools.Modifier;
import cubyz.world.terrain.biomes.BiomeRegistry;
import cubyz.world.terrain.biomes.StructureModel;
import cubyz.world.terrain.worldgenerators.SurfaceGenerator;

/**
 * A list of registries that are used on both server and client.
 */

public class CubyzRegistries {

	public static final Registry<RegistryElement>   BLOCK_REGISTRIES        = new Registry<RegistryElement>();
	public static final NoIDRegistry<Ore>                ORE_REGISTRY            = new NoIDRegistry<Ore>();
	public static final Registry<Item>                   ITEM_REGISTRY           = new Registry<Item>();
	public static final NoIDRegistry<Recipe>             RECIPE_REGISTRY         = new NoIDRegistry<Recipe>();
	public static final Registry<EntityType>             ENTITY_REGISTRY         = new Registry<EntityType>();
	public static final Registry<CommandBase>            COMMAND_REGISTRY        = new Registry<CommandBase>();
	public static final Registry<Modifier>               TOOL_MODIFIER_REGISTRY  = new Registry<Modifier>();
	public static final BiomeRegistry                    BIOME_REGISTRY          = new BiomeRegistry();
	public static final Registry<StructureModel>         STRUCTURE_REGISTRY      = new Registry<StructureModel>();
	public static final Registry<RotationMode>           ROTATION_MODE_REGISTRY  = new Registry<RotationMode>();
	public static final Registry<EntityModel>            ENTITY_MODEL_REGISTRY   = new Registry<EntityModel>();

	// block handlers
	public static final NoIDRegistry<RemoveBlockHandler> REMOVE_HANDLER_REGISTRY = new NoIDRegistry<RemoveBlockHandler>();
	public static final NoIDRegistry<PlaceBlockHandler>  PLACE_HANDLER_REGISTRY  = new NoIDRegistry<PlaceBlockHandler>();
	
	// world generation
	public static final Registry<SurfaceGenerator>       STELLAR_TORUS_GENERATOR_REGISTRY = new Registry<SurfaceGenerator>();

	/**
	 * How many blocks were loaded before the world specific blocks.
	 */
	public static int blocksBeforeWorld = 0;
	
}
