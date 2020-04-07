package io.cubyz.entity;

import java.util.Random;

import org.joml.Vector3f;

import io.cubyz.api.Resource;
import io.cubyz.ndt.NDTContainer;

public class Pig extends EntityType implements EntityAI {

	public Pig() {
		super(new Resource("cubyz:pig"));
	}

	@Override
	public Entity newEntity() {
		Entity ent = new Entity(this, this);
		ent.height = 1;
		return ent;
	}
	
	private Random directionRandom = new Random();
	
	@Override
	public void update(Entity ent) {
		ent.vy -= 0.015F;
		NDTContainer ndt = ent.getAINDT();
		if (!ndt.hasKey("directionTimer")) {
			ndt.setLong("directionTimer", 0);
			ndt.setLong("nerfTimer", 0);
		}
		
		if (ndt.getLong("directionTimer") <= System.currentTimeMillis()) {
			ndt.setLong("directionTimer", System.currentTimeMillis() + directionRandom.nextInt(5000));
			ent.vx = directionRandom.nextFloat() * 0.2f - 0.1f;
			ent.vz = directionRandom.nextFloat() * 0.2f - 0.1f;
			ent.setRotation(new Vector3f(0, (float) Math.sin(ent.vx)*360, (float) Math.cos(ent.vz)*360));
		}
		
		if (ent._getX(ent.vx) != ent.vx || ent._getZ(ent.vz) != ent.vz) {
			// jump
			if (ent.isOnGround()) {
				ent.vy = 0.2f;
			}
			if (ndt.getLong("nerfTimer") == 0) {
				ndt.setLong("nerfTimer", System.currentTimeMillis() + 2000);
			} else {
				if (System.currentTimeMillis() >= ndt.getLong("nerfTimer")) {
					ndt.setLong("directionTimer", 0);
					ndt.setLong("nerfTimer", 0);
				}
			}
		}
	}

}
