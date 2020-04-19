package io.cubyz.blocks;

import org.joml.Vector3i;

import io.cubyz.api.GameRegistry;
import io.cubyz.items.Inventory;
import io.cubyz.world.World;

public class WorkBench extends Block {
	public WorkBench() {
		super("cubyz:workbench", 7.5f, BlockClass.WOOD);
	}
	
	public boolean onClick(World world, Vector3i pos) {
		GameRegistry.openGUI("cubyz:workbench", new Inventory(10));
		return true;
	}
	
}
