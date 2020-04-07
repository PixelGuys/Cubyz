package io.cubyz.entity;

import io.cubyz.api.IRegistryElement;
import io.cubyz.api.Resource;

public abstract class EntityType implements IRegistryElement {
	Resource id;
	public EntityType(Resource id) {
		this.id = id;
	}

	@Override
	public Resource getRegistryID() {
		return id;
	}

	@Override
	public void setID(int ID) {}
	
	public abstract Entity newEntity();
	
}
