package io.cubyz.entity;

import io.cubyz.api.Resource;

public class ItemEntity extends Entity {
	public ItemEntity() {
		super(new EntityType(new Resource("cubyz:item_stack")) {
			@Override
			public Entity newEntity() {
				return new ItemEntity();
			}
			
		});
	}

}
