package cubyz.world.items.tools;

import cubyz.api.CurrentWorldRegistries;
import cubyz.utils.translate.ContextualTextKey;
import cubyz.world.blocks.Block;
import cubyz.world.items.Item;
import cubyz.world.items.ItemStack;

/**
 * Tool for fighting.
 */

public class Sword extends Tool {
	private static final int HEAD = 200, BINDING = 50, HANDLE = 50;
	private static final float baseSpeed = 1.0f, baseDamage = 4.0f;

	public Sword(Material head, Material binding, Material handle) {
		super(head, binding, handle, calculateSpeed(head, binding, handle), calculateDmg(head, binding, handle));
		// The image is just an overlay of the part images:
		texturePath = 	 "assets/" + handle.id.getMod() + "/items/textures/parts/sword/"+handle.getName()+"_handle.png#"
						+"assets/" + head.id.getMod() + "/items/textures/parts/sword/"+head.getName()+"_sword_head.png#"
						+"assets/" + binding.id.getMod() + "/items/textures/parts/sword/"+binding.getName()+"_binding.png";
		setName(new ContextualTextKey("cubyz.grammar.tool_material", head.languageId, "cubyz.tools.names.sword"));
	}
	
	private static float calculateSpeed(Material head, Material binding, Material handle) {
		return head.miningSpeed*baseSpeed;
	}
	
	private static float calculateDmg(Material head, Material binding, Material handle) {
		return head.damage + baseDamage;
	}
	
	public static Item canCraft(ItemStack head, ItemStack binding, ItemStack handle, CurrentWorldRegistries registries) {
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
		return new Sword(he, bi, ha);
			
	}
	
	public static int[] craftingAmount(ItemStack head, ItemStack binding, ItemStack handle, CurrentWorldRegistries registries) {
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
		return false; // Swords are not made to break blocks (for now).
	}
}
