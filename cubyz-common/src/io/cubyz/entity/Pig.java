package io.cubyz.entity;

import java.util.Random;

import org.joml.Vector3f;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Resource;
import io.cubyz.items.Item;
import io.cubyz.items.ItemStack;
import io.cubyz.world.Surface;

public class Pig extends EntityType {
	Item drop = CubyzRegistries.ITEM_REGISTRY.getByID("cubyz:raw_meat");
	public Pig() {
		super(new Resource("cubyz:pig"));
		super.model = CubyzRegistries.ENTITY_MODEL_REGISTRY.getByID("cuybz:quadruped").createInstance("body:12x20x10 \n leg:4x8 \n head:10x6x8 \n movement:stable", this);
	}

	@Override
	public Entity newEntity(Surface surface) {
		Entity ent = new Entity(this, surface, 6, 10);
		ent.height = 1;
		return ent;
	}
	
	// AI part:
	private static final Random directionRandom = new Random();
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
		model.update(ent);
	}
	
	@Override
	public void die(Entity ent) {
		// Drop 1-4 raw meat:
		ent.surface.drop(new ItemStack(drop, 1+(int)(Math.random()*4)), ent.position);
		super.die(ent);
	}

}
