package io.cubyz.entity;

import org.joml.Vector3f;

import io.cubyz.api.Resource;
import io.cubyz.math.Vector3fi;

public class ItemEntity extends Entity {

	private Vector3f translation;
	
	public ItemEntity() {
		super(new EntityType() {

			@Override
			public Resource getRegistryID() {
				return new Resource("cubyz:item_stack");
			}

			@Override
			public void setID(int ID) {}

			@Override
			public Entity newEntity() {
				return new ItemEntity();
			}
			
		});
	}
	
	public Vector3fi getRenderPosition() {
		Vector3fi render = renderPosition.clone();
		renderPosition.add(translation.x, translation.y, translation.z);
		return render;
	}

}
