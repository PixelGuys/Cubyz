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
		for (int i = packs.size()-1; i >= 0; i--) {
			ResourcePack rp = packs.get(i);
			File dir = rp.path;
			File f = new File(dir, path);
			if (f.exists()) {
				return f;
			}
		}
		return null;
	}
	
	/**
	 * Look for path using resource pack directories and priorities.<br/>
	 * Returns null if not found
	 * @param path
	 */
	public static String lookupPath(String path) {
		File f = lookup(path);
		if (f == null) {
			return null;
		} else {
			return f.getPath();
		}
	}
	
	public static File[] listFiles(String path) {
		ArrayList<File> files = new ArrayList<>();
		for (int i = packs.size()-1; i >= 0; i--) {
			ResourcePack rp = packs.get(i);
			File dir = rp.path;
			File f = new File(dir, path);
			if (f.exists() && f.isDirectory()) {
				File[] list = f.listFiles();
				for (File file : list) {
					files.add(file);
				}
			}
		}
		return files.toArray(new File[files.size()]);
	}
	
	public static String contextToLocal(ResourceContext ctx, String local) {
		return contextToLocal(ctx, new Resource(local));
	}
	
	public static String contextToLocal(ResourceContext ctx, Resource local) {
		if (ctx == ResourceContext.MODEL_BLOCK) {
			return "assets/" + local.getMod() + "/models/block/" + local.getID() + ".json";
		} else if (ctx == ResourceContext.MODEL3D) {
			return "assets/" + local.getMod() + "/models/3d/" + local.getID() + ".json";
		} else if (ctx == ResourceContext.TEXTURE) {
			return "assets/" + local.getMod() + "/textures/" + local.getID() + ".png";
		}
		return null;
	}
	
}
