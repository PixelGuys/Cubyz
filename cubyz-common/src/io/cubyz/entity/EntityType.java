package io.cubyz.entity;

import io.cubyz.api.RegistryElement;
import io.cubyz.api.Resource;
import io.cubyz.world.Surface;

public abstract class EntityType implements RegistryElement {
	
	Resource id;
	public EntityModel model;
	
	public EntityType(Resource id) {
		this.id = id;
	}

	@Override
	public Resource getRegistryID() {
		return id;
	}
	
	public abstract Entity newEntity(Surface surface);
	
	public boolean useDynamicEntityModel() {
		return false;
	}
	/**
	 * Is called when an entity dies. Used for item drops and removing the entity from the world.
	 * TODO: Death animation, particle effects.
	 */
	public void die(Entity ent) {
		ent.surface.removeEntity(ent);
	}
	
	/**
	 * Used for entity AI if it has any.
	 * @param ent
	 */
	public void update(Entity ent) {}
	
}
