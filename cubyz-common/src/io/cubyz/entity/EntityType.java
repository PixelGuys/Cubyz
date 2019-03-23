package io.cubyz.entity;

import io.cubyz.api.IRegistryElement;

public abstract class EntityType implements IRegistryElement {
	
	public abstract Entity newEntity();
	
}
