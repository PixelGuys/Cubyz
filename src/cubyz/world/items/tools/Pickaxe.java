package cubyz.world.items.tools;

import cubyz.api.CurrentSurfaceRegistries;
import cubyz.utils.translate.ContextualTextKey;
import cubyz.world.blocks.Block;
import cubyz.world.blocks.Block.BlockClass;
import cubyz.world.items.Item;
import cubyz.world.items.ItemStack;

/**
 * Tool for mining stone.
 */

public class Pickaxe extends Tool {
	private static final int HEAD = 300, BINDING = 50, HANDLE = 50;
	private static final float baseSpeed = 5.0f, baseDamage = 1.0f;

	public Pickaxe(Material head, Material binding, Material handle) {
		super(head, binding, handle, calculateSpeed(head, binding, handle), calculateDmg(head, binding, handle));
		// The image is just an overlay of the part images:
		texturePath = 	 "assets/" + handle.id.getMod() + "/items/textures/parts/"+handle.getName()+"_handle.png#"
						+"assets/" + head.id.getMod() + "/items/textures/parts/"+head.getName()+"_pickaxe_head.png#"
						+"assets/" + binding.id.getMod() + "/items/textures/parts/"+binding.getName()+"_binding.png";
		setName(new ContextualTextKey("cubyz.grammar.tool_material", head.languageId, "cubyz.tools.names.pickaxe"));
	}
	
	private static float calculateSpeed(Material head, Material binding, Material handle) {
		return head.miningSpeed*baseSpeed;
	}
	
	private static float calculateDmg(Material head, Material binding, Material handle) {
		return head.damage + baseDamage;
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
		return new Pickaxe(he, bi, ha);
			
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
		return b.getBlockClass() == BlockClass.STONE;
	}
}
