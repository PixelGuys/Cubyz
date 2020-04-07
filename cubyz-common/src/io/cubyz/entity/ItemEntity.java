package io.cubyz.entity;

import org.joml.Vector3f;

import io.cubyz.api.Resource;
import io.cubyz.math.Vector3fi;

public class ItemEntity extends Entity {

	private Vector3f translation;
	
	public ItemEntity() {
		super(new EntityType(new Resource("cubyz:item_stack")) {
			@Override
			public Entity newEntity() {
				return new ItemEntity();
			}
			
		});
	}

}
