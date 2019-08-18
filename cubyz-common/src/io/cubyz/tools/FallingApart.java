package io.cubyz.tools;

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
		return "Every time you use this tool, small parts of it will fall off thus worsening the stats of this tool. You can only replenish it by repairing it in the Workbench, other healing tricks like regrowth won't help.";
	}

	@Override
	public void onUse(Tool tool) {
		tool.speed *= rate;
		tool.maxDurability = (int)Math.round(tool.maxDurability*rate); // Yes, even durability is affected
		if(tool.durability > tool.maxDurability) {
			tool.durability = tool.maxDurability;
		}
		tool.damage *= rate;
	}

	@Override
	public void onTick(Tool tool) {}

}
