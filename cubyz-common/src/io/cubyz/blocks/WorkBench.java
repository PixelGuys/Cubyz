package io.cubyz.blocks;

import org.joml.Vector3i;

import io.cubyz.api.GameRegistry;
import io.cubyz.items.Inventory;
import io.cubyz.world.World;

public class WorkBench extends Block {
	
	class WorkBenchEntity extends BlockEntity {

		public Inventory inv;
		
		public WorkBenchEntity(BlockInstance bi) {
			super(bi);
			inv = new Inventory(10);
		}
		
	}
	
	public WorkBench() {
		super("cubyz:workbench", 7.5f, BlockClass.WOOD);
		texConverted = true; // texture already in runtime format
	}
	
	public boolean hasBlockEntity() {
		return true;
	}
	
	public BlockEntity createBlockEntity(BlockInstance bi) {
		return new WorkBenchEntity(bi);
	}
	
	public boolean onClick(World world, Vector3i pos) {
		BlockEntity ent = world.getBlockEntity(pos.x, pos.y, pos.z);
		if (ent == null)
			return false;
		GameRegistry.openGUI("cubyz:workbench", ((WorkBenchEntity) ent).inv);
		return true;
	}
	
}
