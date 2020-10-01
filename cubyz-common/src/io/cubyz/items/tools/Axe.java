package io.cubyz.items.tools;

import io.cubyz.api.CurrentSurfaceRegistries;
import io.cubyz.api.RegistryElement;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.Block.BlockClass;
import io.cubyz.items.Item;
import io.cubyz.items.ItemStack;
import io.cubyz.translate.ContextualTextKey;
import io.cubyz.translate.TextKey;

public class Axe extends Tool {
	private static final int HEAD = 300, BINDING = 50, HANDLE = 50;
	private static final float baseSpeed = 2.0f, baseDamage = 2.0f;

	public Axe(Material head, Material binding, Material handle) {
		super(head, binding, handle, calculateSpeed(head, binding, handle), calculateDmg(head, binding, handle));
		// The image is just an overlay of the part images:
		texturePath = 	 "addons/" + handle.id.getMod() + "/items/textures/parts/"+handle.getName()+"_handle.png#"
						+"addons/" + head.id.getMod() + "/items/textures/parts/"+head.getName()+"_axe_head.png#"
						+"addons/" + binding.id.getMod() + "/items/textures/parts/"+binding.getName()+"_binding.png";
		setName(new ContextualTextKey("cubyz.grammar.tool_material", head.languageId, "cubyz.tools.names.axe"));
	}
	
	private static float calculateSpeed(Material head, Material binding, Material handle) {
		return head.miningSpeed*baseSpeed;
	}
	
	private static float calculateDmg(Material head, Material binding, Material handle) {
		return head.damage + baseDamage;
	}
	
	public static Item canCraft(ItemStack head, ItemStack binding, ItemStack handle, CurrentSurfaceRegistries registries) {
		Material he = null, bi = null, ha = null;
		for(RegistryElement reg : registries.materialRegistry.registered()) {
			Material ma = (Material)reg;
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
	
	public static int[] craftingAmount(ItemStack head, ItemStack binding, ItemStack handle, CurrentSurfaceRegistries registries) {
		int[] amount = new int[3];
		for(RegistryElement reg : registries.materialRegistry.registered()) {
			Material ma = (Material)reg;
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
		return b.getBlockClass() == BlockClass.WOOD;
	}
}
