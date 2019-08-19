package io.cubyz.items.tools;

// Modifier a certain material may have.
public interface Modifier {
	String getName();
	String getDescription();
	void onUse(Tool tool); // For modifiers that do something when the tool is used for what it is supposed to.
	void onTick(Tool tool); // For modifiers that do something to the tool over time.
	//void onHit(Mob mob); // When hit a mob with it, no matter if the tool was build for that as main purpose. Wil be included once we have mobs.
}
