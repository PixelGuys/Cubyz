package cubyz.world.entity;

import java.util.Random;

import org.joml.Vector3f;

import cubyz.api.CubyzRegistries;
import cubyz.api.Resource;
import cubyz.world.World;
import cubyz.world.items.Item;
import cubyz.world.items.ItemStack;

/**
 * A source of meat.
 */

public class Pig extends EntityType {
	Item drop = CubyzRegistries.ITEM_REGISTRY.getByID("cubyz:raw_meat");
	public Pig() {
		super(new Resource("cubyz:pig"));
		super.model = CubyzRegistries.ENTITY_MODEL_REGISTRY.getByID("cuybz:quadruped").createInstance("body:12x20x10 \n leg:4x8 \n head:10x6x8 \n movement:stable", this);
	}

	@Override
	public Entity newEntity(World world) {
		Entity ent = new Entity(this, new PigAI(), world, 6, 10, 1);
		ent.height = 1;
		return ent;
	}
	
	
	@Override
	public void die(Entity ent) {
		// Drop 1-4 raw meat:
		ent.world.drop(new ItemStack(drop, 1+(int)(Math.random()*4)), ent.position, new Vector3f((float)Math.random(), (float)Math.random(), (float)Math.random()), 0.2f);
		super.die(ent);
	}
	
	static final Random directionRandom = new Random();
	
	private class PigAI implements EntityAI {
		// AI part:
		long directionTimer = 0;
		long nerfTimer = 0;
		@Override
		public void update(Entity ent) {
			if (directionTimer <= System.currentTimeMillis()) {
				directionTimer = System.currentTimeMillis() + directionRandom.nextInt(5000);
				ent.targetVX = directionRandom.nextFloat() * 0.2f - 0.1f;
				ent.targetVZ = directionRandom.nextFloat() * 0.2f - 0.1f;
				double xzAngle = Math.atan(ent.targetVZ/ent.targetVX);
				if (ent.targetVX > 0) xzAngle += Math.PI;
				ent.setRotation(new Vector3f(0, (float)xzAngle, 0));
			}
			
			if (ent.vx == 0 || ent.vz == 0) {
				// jump
				if (ent.isOnGround()) {
					ent.vy = 0.2f;
				}
				if (nerfTimer == 0) {
					nerfTimer = System.currentTimeMillis() + 2000;
				} else {
					if (System.currentTimeMillis() >= nerfTimer) {
						directionTimer = 0;
						nerfTimer = 0;
					}
				}
			}
		}
	}

}
