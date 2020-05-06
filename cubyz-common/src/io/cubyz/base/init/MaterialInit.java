package io.cubyz.base.init;

import java.util.ArrayList;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Registry;
import io.cubyz.items.Item;
import io.cubyz.items.tools.CustomMaterial;
import io.cubyz.items.tools.Material;
import io.cubyz.items.tools.modifiers.FallingApart;
import io.cubyz.items.tools.modifiers.Regrowth;

public class MaterialInit {

	public static final ArrayList<Material> MATERIALS = new ArrayList<>();
	public static final ArrayList<CustomMaterial> CUSTOM_MATERIALS = new ArrayList<>();
	public static Material dirt, wood, stone, iron, cactus, diamond; // Incomplete and WIP
	
	static {
		Item stick = CubyzRegistries.ITEM_REGISTRY.getByID("cubyz:stick");
		dirt = new Material(-50, 5, 0, 0.0f, 0.1f);
		dirt.setID("cubyz:dirt");
		dirt.addModifier(new FallingApart(0.1f));
		dirt.addItem(CubyzRegistries.ITEM_REGISTRY.getByID("cubyz:dirt"), 100);
		
		wood = new Material(-20, 50, 20, 0.01f/*being hit by a wood sword doesn't hurt*/, 1);
		wood.setMiningLevel(1);
		wood.setID("cubyz:wood");
		wood.addModifier(new Regrowth());
		wood.addModifier(new FallingApart(0.9f));
		wood.addItem(stick, 50);
		wood.addItem(CubyzRegistries.ITEM_REGISTRY.getByID("cubyz:oak_planks"), 100);
		wood.addItem(CubyzRegistries.ITEM_REGISTRY.getByID("cubyz:oak_log"), 150); // Working with oak logs in the table is inefficient.
		register(wood);
		
		stone = new Material(10, 30, 20, 0.1f, 1.5f);
		stone.setMiningLevel(2);
		stone.setID("cubyz:stone");
		// TODO: Modifiers
		stone.addItem(CubyzRegistries.ITEM_REGISTRY.getByID("cubyz:cobblestone"), 100);
		register(stone);
		
		cactus = new Material(-30, 75, 10, 0.2f, 0.7f);
		cactus.setID("cubyz:cactus");
		// TODO: Modifiers
		cactus.addItem(CubyzRegistries.ITEM_REGISTRY.getByID("cubyz:cactus"), 100);
		register(cactus);
	}
	
	public static void register(Material mat) {
		MATERIALS.add(mat);
	}
	
	public static void registerCustom(CustomMaterial mat) {
		register(mat);
		CUSTOM_MATERIALS.add(mat); // Keep track of the custom materials to prevent spamming the whole list with custom materials upon rejoin.
	}
	
	public static void resetCustom() {
		for(Material mat : CUSTOM_MATERIALS) {
			MATERIALS.remove(mat);
		}
		CUSTOM_MATERIALS.clear();
	}
	
	public static void registerAll(Registry<Material> reg) {
		reg.registerAll(MATERIALS);
	}
	
	public static Material search(String id) {
		for(Material mat : MATERIALS) {
			if(mat.getRegistryID().toString().equals(id))
				return mat;
		}
		return null;
	}
}
