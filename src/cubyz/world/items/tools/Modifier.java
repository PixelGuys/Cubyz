package cubyz.world.items.tools;

import cubyz.api.RegistryElement;
import cubyz.api.Resource;

/**
 * A modifier is a special property that a material can have.
 */

public abstract class Modifier implements RegistryElement {
	protected final Resource id;
	protected final String name;
	protected final String description;
	protected final int strength;
	
	public Modifier(String mod, String id, String name, String description, int strength) {
		this.id = new Resource(mod, id);
		this.name = name;
		this.description = description;
		this.strength = strength;
	}
	
	@Override
	public Resource getRegistryID() {
		return id;
	}
	
	public String getName() {
		return name;
	}
	
	public String getDescription() {
		return description;
	}
	
	public int getStrength() {
		return strength;
	}
	
	public abstract Modifier createInstance(int strength);
	public abstract void onUse(Tool tool); // For modifiers that do something when the tool is used for what it is supposed to.
	public abstract void onTick(Tool tool); // For modifiers that do something to the tool over time.
	//void onHit(Mob mob); // When hit a mob with it, no matter if the tool was build for that as main purpose. Will be included once we have mobs.
}