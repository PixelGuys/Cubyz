package io.cubyz.items.tools;

import io.cubyz.api.CurrentSurfaceRegistries;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.Block.BlockClass;
import io.cubyz.items.Item;
import io.cubyz.items.ItemStack;
import io.cubyz.translate.ContextualTextKey;

/**
 * Tool for digging stuff.
 */

public class Shovel extends Tool {
	private static final int HEAD = 100, BINDING = 50, HANDLE = 50;
	private static final float baseSpeed = 1.5f;

	public Shovel(Material head, Material binding, Material handle) {
		super(head, binding, handle, calculateSpeed(head, binding, handle), calculateDmg(head, binding, handle));
		// The image is just an overlay of the part images:
		texturePath = 	 "addons/" + handle.id.getMod() + "/items/textures/parts/"+handle.getName()+"_handle.png#"
				+"addons/" + head.id.getMod() + "/items/textures/parts/"+head.getName()+"_shovel_head.png#"
				+"addons/" + binding.id.getMod() + "/items/textures/parts/"+binding.getName()+"_binding.png";
		setName(new ContextualTextKey("cubyz.grammar.tool_material", head.languageId, "cubyz.tools.names.shovel"));
	}
	
	private static float calculateSpeed(Material head, Material binding, Material handle) {
		return head.miningSpeed*baseSpeed;
	}
	
	private static float calculateDmg(Material head, Material binding, Material handle) {
		return head.damage;
	}
	
	public static Item canCraft(ItemStack head, ItemStack binding, ItemStack handle, CurrentSurfaceRegistries registries) {
		Material he = null, bi = null, ha = null;
		for(Material mat : registries.materialRegistry.registered(new Material[0])) {
			if(mat.getItems().containsKey(head.getItem()) && head.getAmount()*mat.getItems().get(head.getItem()) >= HEAD) {
				he = mat;
			}
			if(mat.getItems().containsKey(binding.getItem()) && binding.getAmount()*mat.getItems().get(binding.getItem()) >= BINDING) {
				bi = mat;
			}
			if(mat.getItems().containsKey(handle.getItem()) && handle.getAmount()*mat.getItems().get(handle.getItem()) >= HANDLE) {
				ha = mat;
			}
		}
		if(he == null || bi == null || ha == null)
			return null;
		return new Shovel(he, bi, ha);
			
	}
	
	public static int[] craftingAmount(ItemStack head, ItemStack binding, ItemStack handle, CurrentSurfaceRegistries registries) {
		int[] amount = new int[3];
		for(Material mat : registries.materialRegistry.registered(new Material[0])) {
			if(mat.getItems().containsKey(head.getItem()) && head.getAmount()*mat.getItems().get(head.getItem()) >= HEAD) {
				amount[0] = (HEAD + mat.getItems().get(head.getItem()) - 1)/mat.getItems().get(head.getItem());
			}
			if(mat.getItems().containsKey(binding.getItem()) && binding.getAmount()*mat.getItems().get(binding.getItem()) >= BINDING) {
				amount[1] = (BINDING + mat.getItems().get(binding.getItem()) - 1)/mat.getItems().get(binding.getItem());
			}
			if(mat.getItems().containsKey(handle.getItem()) && handle.getAmount()*mat.getItems().get(handle.getItem()) >= HANDLE) {
				amount[2] = (HANDLE + mat.getItems().get(handle.getItem()) - 1)/mat.getItems().get(handle.getItem());
			}
		}
		return amount;
	}

	@Override
	public boolean canBreak(Block b) {
		return b.getBlockClass() == BlockClass.SAND;
	}
}
