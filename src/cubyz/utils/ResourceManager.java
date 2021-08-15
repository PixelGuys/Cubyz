package cubyz.utils;

import java.io.File;
import java.util.ArrayList;

import cubyz.api.Resource;

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
	
	/**
	 * Return the absolute <b>resource pack path</b>, which means it is not a path in the file system and must be looked up with {@link #lookup(String)} before any filesystem operation.
	 * @param ctx used to transform local into a resource pack path
	 * @param local the local path (resource id) that will be transformed into resource pack path
	 * @return resource pack path
	 */
	public static String contextToLocal(ResourceContext ctx, Resource local) {
		if (ctx == ResourceContext.MODEL_BLOCK) {
			return local.getMod() + "/models/block/" + local.getID() + ".json";
		} else if (ctx == ResourceContext.MODEL3D) {
			return local.getMod() + "/models/3d/" + local.getID();
		} else if (ctx == ResourceContext.TEXTURE) {
			return local.getMod() + "/textures/" + local.getID() + ".png";
		} else if (ctx == ResourceContext.MODEL_ENTITY) {
			return local.getMod() + "/models/entity/" + local.getID() + ".json";
		}
		return null;
	}
	
}
