package io.cubyz.items;

import io.cubyz.entity.Entity;

/**
 * Things the player can eat, drink, or otherwise use once.
 */

public class Consumable extends Item {
	float foodValue;
	// TODO: Effects.
	
	public Consumable(float food) {
		foodValue = food;
	}
	
	@Override
	public boolean onUse(Entity user) {
		if((user.hunger == user.maxHunger && foodValue > 0) || (user.hunger == 0 && foodValue < 0)) return false;
		user.hunger = Math.min(user.maxHunger, user.hunger+foodValue);
		return true;
	}
}
