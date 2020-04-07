package io.cubyz.entity;

import io.cubyz.api.Resource;

public class Pig extends EntityType implements EntityAI {

	public Pig() {
		super(new Resource("cubyz:pig"));
	}

	@Override
	public Entity newEntity() {
		// TODO Auto-generated method stub
		Entity ent = new Entity(this, this);
		return ent;
	}

	@Override
	public void update(Entity ent) {
		ent.position.y += 0.01f;
	}

}
