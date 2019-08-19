package io.cubyz.items.tools.modifiers;

import io.cubyz.items.tools.Modifier;
import io.cubyz.items.tools.Tool;

public class Regrowth implements Modifier {
	
	private static final int TICKSTOHEAL = 200; // 200*100ms = 20s for 1 durability.
	private int ticks;
	
	@Override
	public String getName() {
		return "Regrowth";
	}

	@Override
	public String getDescription() {
		return "Slowly and magically regrows the tool";
	}

	@Override
	public void onUse(Tool tool) {
		return;
	}

	@Override
	public void onTick(Tool tool) {
		ticks++;
		if(ticks >= TICKSTOHEAL) { // should be nerfed, like only doing it when player have X experience, or food, or health
			ticks = 0;
			tool.setDurability(tool.getDurability() + 1);
			if (tool.getDurability() > tool.getMaxDurability()) {
				tool.setDurability(tool.getMaxDurability());
			}
		}
	}

}
