package io.cubyz.base.init;

import java.util.ArrayList;

import io.cubyz.api.Registry;
import io.cubyz.tools.FallingApart;
import io.cubyz.tools.Material;
import io.cubyz.tools.Regrowth;

public class MaterialInit {
	
	public static final ArrayList<Material> MATERIALS = new ArrayList<>();
	public static Material wood;
	
	static {
		wood = new Material(-20, 50, 20, 0.01f/*being hit by a wood sword doesn't hurt*/, 1/*arbitrary at the moment*/);
		wood.setID("cubyz:wood");
		wood.addModifier(new Regrowth());
		wood.addModifier(new FallingApart(0.9f));
		wood.addItem(ItemInit.stick, 50); // @zenith: how can I access other items without searching from here?
	}
	
	public static void register(Material mat) {
		MATERIALS.add(mat);
	}
	
	public static void registerAll(Registry<Material> reg) {
		reg.registerAll(MATERIALS);
	}
}
