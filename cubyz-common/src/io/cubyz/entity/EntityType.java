package io.cubyz.entity;

import io.cubyz.api.RegistryElement;
import io.cubyz.api.Resource;

public abstract class EntityType implements RegistryElement {
	
	Resource id;
	public EntityType(Resource id) {
		this.id = id;
	}

	@Override
	public Resource getRegistryID() {
		return id;
	}
	
	public abstract Entity newEntity();
	
}
