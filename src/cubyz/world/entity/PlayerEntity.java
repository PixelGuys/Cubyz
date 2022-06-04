
package cubyz.world.entity;

import cubyz.api.Resource;
import cubyz.world.World;

public class PlayerEntity extends EntityType {

	public PlayerEntity() {
		super(new Resource("cubyz:player"));
	}

	@Override
	public Entity newEntity(World world) {
		return new Player(world, "");
	}
	
	@Override
	public void die(Entity ent) {
		ent.health = ent.maxHealth;
		ent.hunger = ent.maxHunger;
		ent.setPosition(ent.world.spawn);
		ent.vx = ent.vy = ent.vz = 0;
		// TODO: Respawn screen
	}
}
