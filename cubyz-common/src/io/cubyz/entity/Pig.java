package io.cubyz.entity;

import java.util.Random;

import org.joml.Vector3f;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Resource;
import io.cubyz.world.Surface;

public class Pig extends EntityType {
	public Pig() {
		super(new Resource("cubyz:pig"));
		super.model = CubyzRegistries.ENTITY_MODEL_REGISTRY.getByID("cuybz:quadruped").createInstance("body:12x20x10 \n leg:4x8 \n head:10x6x8 \n movement:stable", this);
	}

	@Override
	public Entity newEntity(Surface surface) {
		Entity ent = new Entity(this, surface, new PigAI());
		ent.health = ent.maxHealth = 6;
		ent.height = 1;
		return ent;
	}
	

	private static final Random directionRandom = new Random();
	public class PigAI implements EntityAI {
		long directionTimer = 0;
		long nerfTimer = 0;
		@Override
		public void update(Entity ent) {
			ent.vy -= ent.getStellarTorus().getGravity();
			
			if (directionTimer <= System.currentTimeMillis()) {
				directionTimer = System.currentTimeMillis() + directionRandom.nextInt(5000);
				ent.targetVX = directionRandom.nextFloat() * 0.2f - 0.1f;
				ent.targetVZ = directionRandom.nextFloat() * 0.2f - 0.1f;
				double xzAngle = Math.atan(ent.targetVZ/ent.targetVX);
				if(ent.targetVX > 0) xzAngle += Math.PI;
				ent.setRotation(new Vector3f(0, (float)xzAngle, 0));
			}
			
			if (ent._getX(ent.vx) != ent.vx || ent._getZ(ent.vz) != ent.vz) {
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
			model.update(ent);
		}
	}

}
