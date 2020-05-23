package io.cubyz.items.tools;

import io.cubyz.base.init.MaterialInit;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.Block.BlockClass;
import io.cubyz.items.Item;
import io.cubyz.items.ItemStack;
import io.cubyz.translate.TextKey;

public class Pickaxe extends Tool {
	private static final int HEAD = 300, BINDING = 50, HANDLE = 50;
	private static final float baseSpeed = 5.0f, baseDamage = 1.0f;

	public Pickaxe(Material head, Material binding, Material handle) {
		super(head, binding, handle, calculateSpeed(head, binding, handle), calculateDmg(head, binding, handle));
		// The image is just an overlay of the part images:
		texturePath = 	 "addons/" + handle.id.getMod() + "/items/textures/parts/"+handle.getName()+"_handle.png#"
						+"addons/" + head.id.getMod() + "/items/textures/parts/"+head.getName()+"_pickaxe_axe_head.png#"
						+"addons/" + binding.id.getMod() + "/items/textures/parts/"+binding.getName()+"_binding.png";
		setName(new TextKey(head.getRegistryID().getID()+" Pickaxe"));
	}
	
	private static float calculateSpeed(Material head, Material binding, Material handle) {
		return head.miningSpeed*baseSpeed;
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
		return new Pickaxe(he, bi, ha);
			
	}
	
	public static int[] craftingAmount(ItemStack head, ItemStack binding, ItemStack handle) {
		int[] amount = new int[3];
		if(head.getItem() != null)
		for(Material ma : MaterialInit.MATERIALS) {
			if(ma.getItems().containsKey(head.getItem()) && head.getAmount()*ma.getItems().get(head.getItem()) >= HEAD) {
				amount[0] = (HEAD + ma.getItems().get(head.getItem()) - 1)/ma.getItems().get(head.getItem());
			}
			if(ma.getItems().containsKey(binding.getItem()) && binding.getAmount()*ma.getItems().get(binding.getItem()) >= BINDING) {
				amount[1] = (BINDING + ma.getItems().get(binding.getItem()) - 1)/ma.getItems().get(binding.getItem());
			}
			if(ma.getItems().containsKey(handle.getItem()) && handle.getAmount()*ma.getItems().get(handle.getItem()) >= HANDLE) {
				amount[2] = (HANDLE + ma.getItems().get(handle.getItem()) - 1)/ma.getItems().get(handle.getItem());
			}
		}
		return amount;
	}

	@Override
	public boolean canBreak(Block b) {
		return b.getBlockClass() == BlockClass.STONE;
	}
}
