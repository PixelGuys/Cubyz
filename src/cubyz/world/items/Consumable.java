package cubyz.world.items;

import cubyz.api.Resource;
import cubyz.utils.json.JsonObject;
import cubyz.world.entity.Entity;

/**
 * Things the player can eat, drink, or otherwise use once.
 */

public class Consumable extends Item {
	float foodValue;
	// TODO: Effects.
	
	public Consumable(Resource id, JsonObject json) {
		super(id, json);
		foodValue = json.getFloat("food", 1);
	}
	
	@Override
	public boolean onUse(Entity user) {
		if ((user.hunger >= user.maxHunger - Math.min(user.maxHunger*0.1, 0.5) && foodValue > 0) || (user.hunger == 0 && foodValue < 0)) return false;
		user.hunger = Math.min(user.maxHunger, user.hunger+foodValue);
		return true;
	}
}
