package io.cubyz.tools;

public class Regrowth implements Modifier {
	private static final int TICKSTOHEAL = 200; // 200*100ms = 20s for 1 durability.
	private int ticks;
	@Override
	public String getName() {
		return "Regrowth";
	}

	@Override
	public String getDescription() {
		return "Slowly heals regrows the tools durability.";
	}

	@Override
	public void onUse(Tool tool) {
		return;
	}

	@Override
	public void onTick(Tool tool) {
		ticks++;
		if(ticks >= TICKSTOHEAL) {
			ticks = 0;
			tool.durability++;
			if(tool.durability > tool.maxDurability) {
				tool.durability = tool.maxDurability;
			}
		}
	}

}
