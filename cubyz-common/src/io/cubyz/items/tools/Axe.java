package io.cubyz.items.tools;

import io.cubyz.base.init.MaterialInit;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.Block.BlockClass;
import io.cubyz.items.Item;
import io.cubyz.items.ItemStack;

public class Axe extends Tool {
	private static final int HEAD = 300, BINDING = 50, HANDLE = 50;
	private static final float baseSpeed = 2.0f, baseDamage = 2.0f;

	public Axe(Material head, Material binding, Material handle) {
		super(head, binding, handle, calculateSpeed(head, binding, handle), calculateDmg(head, binding, handle));
		// The image is just an overlay of the part images:
		texturePath = 	 "assets/cubyz/textures/items/parts/"+handle.getName()+"_handle.png#"
						+"assets/cubyz/textures/items/parts/"+head.getName()+"_axe_head.png#"
						+"assets/cubyz/textures/items/parts/"+binding.getName()+"_binding.png";
	}
	
	private static float calculateSpeed(Material head, Material binding, Material handle) {
		return head.miningSpeed * baseSpeed;
	}
	
	private static float calculateDmg(Material head, Material binding, Material handle) {
		return head.damage + baseDamage;
	}
	
	public static Item canCraft(ItemStack head, ItemStack binding, ItemStack handle) {
		Material he = null, bi = null, ha = null;
		if(head.getItem() != null)
		for(Material ma : MaterialInit.MATERIALS) {
			if(ma.getItems().containsKey(head.getItem()) && head.getAmount()*ma.getItems().get(head.getItem()) >= HEAD) {
				he = ma;
			}
			if(ma.getItems().containsKey(binding.getItem()) && binding.getAmount()*ma.getItems().get(binding.getItem()) >= BINDING) {
				bi = ma;
			}
			if(ma.getItems().containsKey(handle.getItem()) && handle.getAmount()*ma.getItems().get(handle.getItem()) >= HANDLE) {
				ha = ma;
			}
		}
		if(he == null || bi == null || ha == null)
			return null;
		return new Axe(he, bi, ha);
			
	}

	@Override
	public boolean canBreak(Block b) {
		return b.getBlockClass() == BlockClass.WOOD;
	}
}
