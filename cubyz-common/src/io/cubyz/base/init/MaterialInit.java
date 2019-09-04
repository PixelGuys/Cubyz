package io.cubyz.base.init;

import java.util.ArrayList;

import io.cubyz.api.Registry;
import io.cubyz.items.tools.Material;
import io.cubyz.items.tools.modifiers.FallingApart;
import io.cubyz.items.tools.modifiers.Regrowth;

public class MaterialInit {
	
	public static final ArrayList<Material> MATERIALS = new ArrayList<>();
	public static Material wood;
	
	static {
		wood = new Material(-20, 50, 20, 0.01f/*being hit by a wood sword doesn't hurt*/, 1/*arbitrary at the moment*/);
		wood.setID("cubyz:wood");
		wood.addModifier(new Regrowth());
		wood.addModifier(new FallingApart(0.9f));
		wood.addItem(ItemInit.stick, 5000); // @zenith: how can I access other items without searching from here? // Set to 5000 to make a tool craftable.
		register(wood);
	}
	
	public static void register(Material mat) {
		MATERIALS.add(mat);
	}
	
	public static void registerAll(Registry<Material> reg) {
		reg.registerAll(MATERIALS);
	}
}
