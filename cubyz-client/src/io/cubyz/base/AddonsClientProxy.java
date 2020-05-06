package io.cubyz.base;

import java.io.File;

import io.cubyz.Utilities;
import io.cubyz.utils.ResourceManager;
import io.cubyz.utils.ResourcePack;

public class AddonsClientProxy extends AddonsCommonProxy {

	public void init(AddonsMod mod) {
		super.init(mod);
		ResourcePack pack = new ResourcePack();
		pack.name = "Add-Ons Resource Pack"; // used for path like: testaddon/models/thing.json
		pack.path = new File("addons");
		ResourceManager.packs.add(pack);
		for (File addon : mod.addons) {
			pack = new ResourcePack();
			pack.name = "Add-On: " + Utilities.capitalize(addon.getName()); // used for languages like: lang/en_US.lang
			pack.path = addon;
			ResourceManager.packs.add(pack);
		}
	}
	
}
