package cubyz.world.entity;

import cubyz.api.RegistryElement;
import cubyz.api.Resource;
import cubyz.world.World;

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
	
	public abstract Entity newEntity(World world);
	
	public boolean useDynamicEntityModel() {
		return false;
	}
	/**
	 * Is called when an entity dies. Used for item drops and removing the entity from the world.
	 * TODO: Death animation, particle effects.
	 */
	public void die(Entity ent) {
		ent.world.removeEntity(ent);
	}
	
}
