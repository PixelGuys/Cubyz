package io.cubyz.entity;

import io.cubyz.api.Resource;
import io.cubyz.world.Surface;

public class ItemEntity extends Entity {
	public ItemEntity(Surface surface) {
		super(new EntityType(new Resource("cubyz:item_stack")) {
			@Override
			public Entity newEntity(Surface surface) {
				return new ItemEntity(surface);
			}
			
		}, surface);
	}

}
