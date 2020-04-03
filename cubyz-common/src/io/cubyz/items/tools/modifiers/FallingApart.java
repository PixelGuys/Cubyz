package io.cubyz.items.tools.modifiers;

import io.cubyz.items.tools.Modifier;
import io.cubyz.items.tools.Tool;

public class FallingApart implements Modifier {
	
	float rate;
	
	public FallingApart(float rate) {
		this.rate = rate;
	}
	@Override
	public String getName() {
		return "Falling Apart";
	}

	@Override
	public String getDescription() {
		return "Every time you use this tool, small parts of it will fall off.\nThat leads to a slow and steady decay of this tools stats.\nYou can only replenish it by repairing it in the Workbench.";
	}

	@Override
	public void onUse(Tool tool) {
		tool.setSpeed(tool.getSpeed() * rate);
		tool.setMaxDurability((int) Math.round(tool.getMaxDurability()*rate)); // Yes, even durability is affected
		if(tool.getDurability() > tool.getMaxDurability()) {
			tool.setDurability(tool.getMaxDurability());
		}
		tool.setDamage(rate);
	}

	@Override
	public void onTick(Tool tool) {}

}
