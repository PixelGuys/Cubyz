package cubyz.world.items.tools.modifiers;

import cubyz.world.items.tools.Modifier;
import cubyz.world.items.tools.Tool;

public class Regrowth extends Modifier {
	
	private static final int TICKS_TO_HEAL = 200; // 200*100ms = 20s for 1 durability.
	private int ticks;
	
	public Regrowth() {
		super("cubyz", "regrowth", "Regrowth", "Slowly and magically regrows the tool.", 0);
	}
	
	private Regrowth(int strength) {
		super("cubyz", "regrowth", "Regrowth", "Slowly and magically regrows the tool.", strength);
	}

	@Override
	public void onUse(Tool tool) {
		return;
	}

	@Override
	public void onTick(Tool tool) {
		ticks += strength;
		if (ticks >= TICKS_TO_HEAL) { // TODO: should be nerfed, like only doing it when player have X experience, or food, or health
			ticks -= TICKS_TO_HEAL;
			tool.durability = tool.durability + 1;
			if (tool.durability > tool.maxDurability) {
				tool.durability = tool.maxDurability;
			}
		}
	}

	@Override
	public Modifier createInstance(int strength) {
		return new Regrowth(strength);
	}

}
