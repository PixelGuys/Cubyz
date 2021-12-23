
package cubyz.world.entity;

import cubyz.api.Resource;
import cubyz.world.World;

public class PlayerEntity extends EntityType {

	public PlayerEntity() {
		super(new Resource("cubyz:player"));
	}

	@Override
	public Entity newEntity(World world) {
		return new Player(world);
	}
	
	@Override
	public void die(Entity ent) {
		// TODO: Respawning
	}
}
