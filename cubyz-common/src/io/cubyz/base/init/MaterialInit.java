package io.cubyz.base.init;

import java.util.ArrayList;

import io.cubyz.api.Registry;
import io.cubyz.items.tools.Material;
import io.cubyz.items.tools.modifiers.FallingApart;
import io.cubyz.items.tools.modifiers.Regrowth;

public class MaterialInit {
	
	public static final ArrayList<Material> MATERIALS = new ArrayList<>();
	public static Material dirt, wood, stone, iron, cactus, diamond; // Incomplete and WIP
	
	static {
		dirt = new Material(-50, 5, 0, 0.0f, 0.1f);
		dirt.setID("cubyz:dirt");
		dirt.addModifier(new FallingApart(0.1f));
		dirt.addItem(ItemInit.search("dirt"), 100);
		
		wood = new Material(-20, 50, 20, 0.01f/*being hit by a wood sword doesn't hurt*/, 1);
		wood.setMiningLevel(1);
		wood.setID("cubyz:wood");
		wood.addModifier(new Regrowth());
		wood.addModifier(new FallingApart(0.9f));
		wood.addItem(ItemInit.stick, 5000); // @zenith: how can I access other items without searching from here? // Set to 5000 to make a tool craftable.
		wood.addItem(ItemInit.search("oak_planks"), 100);
		wood.addItem(ItemInit.search("oak_log"), 150); // Working with oak logs in the table is inefficient.
		register(wood);
		
		stone = new Material(10, 30, 20, 0.1f, 1.5f);
		stone.setMiningLevel(2);
		stone.setID("cubyz:stone");
		// TODO: Modifiers
		stone.addItem(ItemInit.search("cobblestone"), 100);
		register(stone);
		
		cactus = new Material(-30, 75, 10, 0.2f, 0.7f);
		cactus.setID("cubyz:cactus");
		// TODO: Modifiers
		cactus.addItem(ItemInit.search("cactus"), 100);
		register(cactus);
	}
	
	public static void register(Material mat) {
		MATERIALS.add(mat);
	}
	
	public static void registerAll(Registry<Material> reg) {
		reg.registerAll(MATERIALS);
	}
}
