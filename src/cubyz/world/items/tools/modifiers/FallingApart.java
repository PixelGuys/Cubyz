package cubyz.world.items.tools.modifiers;

import cubyz.world.items.tools.Modifier;
import cubyz.world.items.tools.Tool;

public class FallingApart extends Modifier {
	public static final float DECAY_RATE = 0.001f;
	
	public FallingApart() {
		super("cubyz", "falling_apart", "Falling Apart", "Every time you use this tool, small parts of it will fall off.\\nThat leads to a slow and steady decay of this tools stats.\\nYou can only replenish it by repairing it in the Workbench.", 0);
	}
	
	public FallingApart(int strength) {
		super("cubyz", "falling_apart", "Falling Apart", "Every time you use this tool, small parts of it will fall off.\\nThat leads to a slow and steady decay of this tools stats.\\nYou can only replenish it by repairing it in the Workbench.", strength);
	}

	@Override
	public void onUse(Tool tool) {
		/*tool.setSpeed(tool.getSpeed()*(1 - DECAY_RATE)*strength);
		tool.setMaxDurability((int) Math.round(tool.getMaxDurability()*(1 - DECAY_RATE)*strength)); // Yes, even durability is affected
		if (tool.getDurability() > tool.getMaxDurability()) {
			tool.setDurability(tool.getMaxDurability());
		}
		tool.setDamage(tool.getDamage()*(1 - DECAY_RATE)*strength);*/ // TODO: Implement modifiers into the new tool system.
	}

	@Override
	public void onTick(Tool tool) {}

	@Override
	public Modifier createInstance(int strength) {
		return new FallingApart(strength);
	}
}
