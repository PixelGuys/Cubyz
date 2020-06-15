package io.cubyz.entity;

import io.cubyz.api.Resource;
import io.cubyz.items.ItemStack;
import io.cubyz.world.Surface;

public class ItemEntity extends Entity {
	public ItemStack items;
	public ItemEntity(Surface surface, ItemStack items) {
		super(new EntityType(new Resource("cubyz:item_stack")) {
			@Override
			public Entity newEntity(Surface surface) {
				return null;
			}
			
		}, surface);
		this.items = items;
		super.height = super.width = super.depth = 0.1f;
	}

}
