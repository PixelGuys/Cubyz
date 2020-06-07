package io.cubyz.items.tools.modifiers;

import io.cubyz.items.tools.Modifier;
import io.cubyz.items.tools.Tool;

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
		if(ticks >= TICKS_TO_HEAL) { // should be nerfed, like only doing it when player have X experience, or food, or health
			ticks -= TICKS_TO_HEAL;
			tool.setDurability(tool.getDurability() + 1);
			if (tool.getDurability() > tool.getMaxDurability()) {
				tool.setDurability(tool.getMaxDurability());
			}
		}
	}

	@Override
	public Modifier createInstance(int strength) {
		return new Regrowth(strength);
	}

}
