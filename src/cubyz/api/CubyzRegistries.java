package cubyz.api;

import cubyz.command.CommandBase;
import cubyz.world.blocks.Ore;
import cubyz.world.blocks.RotationMode;
import cubyz.world.entity.EntityType;
import cubyz.world.items.Item;
import cubyz.world.items.tools.Modifier;
import cubyz.world.terrain.ClimateMapGenerator;
import cubyz.world.terrain.MapGenerator;
import cubyz.world.terrain.biomes.StructureModel;
import cubyz.world.terrain.cavebiomegenerators.CaveBiomeGenerator;
import cubyz.world.terrain.cavegenerators.CaveGenerator;
import cubyz.world.terrain.generators.Generator;

/**
 * A list of registries that are used on both server and client.
 */

public final class CubyzRegistries {
	private CubyzRegistries() {} // No instances allowed.

	public static final Registry<DataOrientedRegistry>   BLOCK_REGISTRIES           = new Registry<DataOrientedRegistry>();
	public static final NoIDRegistry<Ore>                ORE_REGISTRY               = new NoIDRegistry<Ore>();
	public static final Registry<Item>                   ITEM_REGISTRY              = new Registry<Item>();
	public static final Registry<EntityType>             ENTITY_REGISTRY            = new Registry<EntityType>();
	public static final Registry<CommandBase>            COMMAND_REGISTRY           = new Registry<CommandBase>();
	public static final Registry<Modifier>               TOOL_MODIFIER_REGISTRY     = new Registry<Modifier>();
	public static final Registry<RotationMode>           ROTATION_MODE_REGISTRY     = new Registry<RotationMode>();
	
	// world generation
	public static final Registry<StructureModel>         STRUCTURE_REGISTRY         = new Registry<>();
	public static final Registry<ClimateMapGenerator>    CLIMATE_GENERATOR_REGISTRY = new Registry<>();
	public static final Registry<MapGenerator>           MAP_GENERATOR_REGISTRY     = new Registry<>();
	public static final Registry<CaveGenerator>          CAVE_GENERATORS            = new Registry<>();
	public static final Registry<CaveBiomeGenerator>     CAVE_BIOME_GENERATORS      = new Registry<>();
	public static final Registry<Generator>              GENERATORS                 = new Registry<>();
	
}
