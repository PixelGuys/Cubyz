package io.cubyz.entity;

import java.util.Random;

import org.joml.Vector3f;

import io.cubyz.api.Resource;
import io.cubyz.world.Surface;

public class Pig extends EntityType {

	public Pig() {
		super(new Resource("cubyz:pig"));
	}

	@Override
	public Entity newEntity(Surface surface) {
		Entity ent = new Entity(this, surface, new PigAI());
		ent.height = 1;
		return ent;
	}
	
	
	public static class PigAI implements EntityAI {
		private static final Random directionRandom = new Random();
		long directionTimer = 0;
		long nerfTimer = 0;
		@Override
		public void update(Entity ent) {
			ent.vy -= ent.getStellarTorus().getGravity();
			
			if (directionTimer <= System.currentTimeMillis()) {
				directionTimer = System.currentTimeMillis() + directionRandom.nextInt(5000);
				ent.vx = directionRandom.nextFloat() * 0.2f - 0.1f;
				ent.vz = directionRandom.nextFloat() * 0.2f - 0.1f;
				double xzAngle = Math.atan(ent.vz/ent.vx);
				if(ent.vx < 0) xzAngle += Math.PI;
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
		}
	}

}
