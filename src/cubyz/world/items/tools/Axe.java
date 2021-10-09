package cubyz.world.items.tools;

import cubyz.api.CurrentWorldRegistries;
import cubyz.utils.translate.ContextualTextKey;
import cubyz.world.blocks.Block;
import cubyz.world.blocks.Block.BlockClass;
import cubyz.world.items.Item;
import cubyz.world.items.ItemStack;

/**
 * A tool for cutting wood.
 */

public class Axe extends OldTool {
	private static final int HEAD = 300, BINDING = 50, HANDLE = 50;
	private static final float baseSpeed = 2.0f, baseDamage = 2.0f;

	public Axe(MaterialOld head, MaterialOld binding, MaterialOld handle) {
		super(head, binding, handle, calculateSpeed(head, binding, handle), calculateDmg(head, binding, handle));
		// The image is just an overlay of the part images:
		texturePath = 	 "assets/" + handle.id.getMod() + "/items/textures/parts/"+handle.getName()+"_handle.png#"
						+"assets/" + head.id.getMod() + "/items/textures/parts/"+head.getName()+"_axe_head.png#"
						+"assets/" + binding.id.getMod() + "/items/textures/parts/"+binding.getName()+"_binding.png";
		setName(new ContextualTextKey("cubyz.grammar.tool_material", head.languageId, "cubyz.tools.names.axe"));
	}
	
	private static float calculateSpeed(MaterialOld head, MaterialOld binding, MaterialOld handle) {
		return head.miningSpeed*baseSpeed;
	}
	
	private static float calculateDmg(MaterialOld head, MaterialOld binding, MaterialOld handle) {
		return head.damage + baseDamage;
	}
	
	public static Item canCraft(ItemStack head, ItemStack binding, ItemStack handle, CurrentWorldRegistries registries) {
		MaterialOld he = null, bi = null, ha = null;
		for(MaterialOld mat : registries.materialRegistry.registered(new MaterialOld[0])) {
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
		return new Axe(he, bi, ha);
			
	}
	
	public static int[] craftingAmount(ItemStack head, ItemStack binding, ItemStack handle, CurrentWorldRegistries registries) {
		int[] amount = new int[3];
		for(MaterialOld mat : registries.materialRegistry.registered(new MaterialOld[0])) {
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
		return b.getBlockClass() == BlockClass.WOOD;
	}
}
