package io.cubyz.api;

import io.cubyz.blocks.Block;
import io.cubyz.entity.EntityType;
import io.cubyz.items.Item;

public class CubzRegistries {

	public static final Registry<Block>      BLOCK_REGISTRY  = new Registry<Block>();
	public static final Registry<Item>       ITEM_REGISTRY   = new Registry<Item>();
	public static final Registry<EntityType> ENTITY_REGISTRY = new Registry<EntityType>();
	
}
