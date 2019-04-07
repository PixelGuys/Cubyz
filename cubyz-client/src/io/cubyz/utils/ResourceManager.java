package io.cubyz.utils;

import java.io.File;
import java.util.ArrayList;

import io.cubyz.api.Resource;

public class ResourceManager {

	public static ArrayList<ResourcePack> packs = new ArrayList<>();
	
	/**
	 * Look for file using resource pack directories and priorities.<br/>
	 * Returns null if not found
	 * @param path
	 */
	public static File lookup(String path) {
		int i = packs.size();
		while (i > 0) {
			ResourcePack rp = packs.get(i);
			File dir = rp.path;
			File f = new File(dir, path);
			if (f.exists()) {
				return f;
			}
			i--;
		}
		return null;
	}
	
	public static String contextToLocal(ResourceContext ctx, String local) {
		return contextToLocal(ctx, new Resource(local));
	}
	
	public static String contextToLocal(ResourceContext ctx, Resource local) {
		if (ctx == ResourceContext.MODEL) {
			return "assets/" + local.getMod() + "/models/" + local.getID() + ".json";
		} else if (ctx == ResourceContext.MODEL3D) {
			return "assets/" + local.getMod() + "/models/3d/" + local.getID() + ".json";
		} else if (ctx == ResourceContext.TEXTURE) {
			return "assets/" + local.getMod() + "/textures/" + local.getID() + ".png";
		}
		return null;
	}
	
}
