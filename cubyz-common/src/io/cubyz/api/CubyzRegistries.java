package io.cubyz.api;

import io.cubyz.blocks.Block;
import io.cubyz.command.CommandBase;
import io.cubyz.entity.EntityType;
import io.cubyz.items.Item;
import io.cubyz.items.Recipe;

public class CubyzRegistries {

	public static final Registry<Block>       BLOCK_REGISTRY   = new Registry<Block>();
	public static final Registry<Item>        ITEM_REGISTRY    = new Registry<Item>();
	public static final Registry<Recipe>      RECIPE_REGISTRY  = new Registry<Recipe>();
	public static final Registry<EntityType>  ENTITY_REGISTRY  = new Registry<EntityType>();
	public static final Registry<CommandBase> COMMAND_REGISTRY = new Registry<CommandBase>();
	
}
