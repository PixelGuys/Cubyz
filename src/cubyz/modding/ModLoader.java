package cubyz.modding;

import java.io.File;
import java.io.IOException;
import java.lang.annotation.Annotation;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;

import cubyz.Constants;
import cubyz.modding.base.AddonsMod;
import cubyz.modding.base.BaseMod;
import cubyz.utils.Logger;
import cubyz.api.CubyzRegistries;
import cubyz.api.CurrentWorldRegistries;
import cubyz.api.LoadOrder;
import cubyz.api.Mod;
import cubyz.api.Order;
import cubyz.api.Proxy;
import cubyz.api.Side;
import cubyz.api.SideOnly;

/**
 * Most methods should ALWAYS be found as if it were on Side.SERVER
 */
public final class ModLoader {
	private ModLoader() {} // No instances allowed.

	public static final ArrayList<Mod> mods = new ArrayList<Mod>();
	
	public static boolean isCorrectSide(Side currentSide, Method method) {
		boolean haveAnnot = false;
		for (Annotation annot : method.getAnnotations()) {
			if (annot.annotationType().equals(SideOnly.class)) {
				SideOnly anno = (SideOnly) annot;
				haveAnnot = true;
				if (anno.side() == currentSide) {
					return true;
				}
			}
		}
		return !haveAnnot;
	}
	
	public static void sortMods() {
		HashMap<String, Mod> modIds = new HashMap<>();
		for (Mod mod : mods) {
			modIds.put(mod.id(), mod);
		}
		for (int i = 0; i < mods.size(); i++) {
			Mod mod = mods.get(i);
			Class<?> cl = mod.getClass();
			LoadOrder[] orders = cl.getAnnotationsByType(LoadOrder.class);
			for (LoadOrder order : orders) {
				if (order.order() == Order.AFTER && i < mods.indexOf(modIds.get(order.id()))) {
					mods.remove(i);
					mods.add(mods.indexOf(modIds.get(order.id()))+1, mod);
				}
			}
		}
	}
	
	public static void preInit(Mod mod, Side side) {
		injectProxy(mod, side);
		mod.preInit();
	}
	
	public static void registerEntries(Mod mod, String type) {
		switch (type) {
		case "item":
			mod.registerItems(CubyzRegistries.ITEM_REGISTRY);
			break;
		case "entity":
			mod.registerEntities(CubyzRegistries.ENTITY_REGISTRY);
			break;
		}
	}
	
	/**
	 * Calls mods after the world has been generated.
	 * @param reg registries of this world.
	 */
	public static void postWorldGen(CurrentWorldRegistries reg) {
		for(Mod mod : mods) {
			mod.postWorldGen(reg);
		}
	}
	
	static void injectProxy(Mod mod, Side side) {
		Class<?> cl = mod.getClass();
		for (Field field : cl.getDeclaredFields()) {
			field.setAccessible(true);
			if (field.isAnnotationPresent(Proxy.class)) {
				Proxy a = field.getAnnotation(Proxy.class);
				try {
					if (side == Side.CLIENT) {
						field.set(mod, Class.forName(a.clientProxy()).getConstructor().newInstance());
					} else {
						field.set(mod, Class.forName(a.serverProxy()).getConstructor().newInstance());
					}
				} catch (IllegalArgumentException | IllegalAccessException | InstantiationException
						| InvocationTargetException | NoSuchMethodException | SecurityException
						| ClassNotFoundException e) {
					Logger.warning("Could not inject Proxy!");
					Logger.warning(e);
				}
				break;
			}
		}
	}
	
	static void safeMethodInvoke(boolean isImportant /* → exits on error */, Method m, Object o, Object... args) {
		try {
			m.invoke(o, args);
		} catch(InvocationTargetException e) {
			Logger.warning("Error while invoking mod method (" + m + "):");
			Logger.warning(e.getCause());
			if (isImportant) {
				System.exit(1);
			}
		} catch (IllegalAccessException | IllegalArgumentException e) {
			Logger.error(e);
			if (isImportant) {
				System.exit(1);
			}
		}
	}

	static void loadModClasses(String pathToJar, ArrayList<Class<?>> modClasses) {
		try {
			JarFile jarFile = new JarFile(pathToJar);
			Enumeration<JarEntry> e = jarFile.entries();

			URL[] urls = { new URL("jar:file:" + pathToJar+"!/") };
			URLClassLoader cl = URLClassLoader.newInstance(urls);

			while (e.hasMoreElements()) {
				JarEntry je = e.nextElement();
				if (je.isDirectory() || !je.getName().endsWith(".class") || je.getName().contains("module-info")){
					continue;
				}
				// -6 because of .class
				String className = je.getName().substring(0, je.getName().length()-6);
				className = className.replace('/', '.');
				Class<?> c = cl.loadClass(className);
				if (c.isAssignableFrom(Mod.class)) modClasses.add(c);

			}
			jarFile.close();
		} catch(IOException | ClassNotFoundException e) {
			Logger.error(e);
		}
	}

	public static void load(Side side) {
		// Load Mods (via reflection)
		ArrayList<File> modSearchPath = new ArrayList<>();
		modSearchPath.add(new File("mods"));
		modSearchPath.add(new File("mods/" + Constants.GAME_VERSION));
		ArrayList<String> modPaths = new ArrayList<>();

		for (File sp : modSearchPath) {
			if (!sp.exists()) {
				sp.mkdirs();
			}
			for (File mod : sp.listFiles()) {
				if (mod.isFile()) {
					modPaths.add(mod.getAbsolutePath());
					Logger.info("- Add " + mod.getName());
				}
			}
		}

		Logger.info("Seeking mods..");
		long start = System.currentTimeMillis();
		// Load all mods:
		ArrayList<Class<?>> allClasses = new ArrayList<>();
		for(String path : modPaths) {
			loadModClasses(path, allClasses);
		}
		long end = System.currentTimeMillis();
		Logger.info("Took " + (end - start) + "ms for reflection");
		if (!allClasses.contains(BaseMod.class)) {
			allClasses.add(BaseMod.class);
			allClasses.add(AddonsMod.class);
			Logger.info("Manually adding BaseMod (probably on distributed JAR)");
		}
		for (Class<?> cl : allClasses) {
			Logger.info("Mod class present: " + cl.getName());
			try {
				ModLoader.mods.add((Mod)cl.getConstructor().newInstance());
			} catch (Exception e) {
				Logger.error("Error while loading mod:");
				Logger.error(e);
			}
		}
		Logger.info("Mod list complete");
		ModLoader.sortMods();

		for (int i = 0; i < ModLoader.mods.size(); i++) {
			Mod mod = ModLoader.mods.get(i);
			Logger.info("Pre-initiating " + mod);
			ModLoader.preInit(mod, side);
		}

		// Between pre-init and init code

		AddonsMod.instance.readBlocks();
		AddonsMod.instance.readBiomes();
		for (int i = 0; i < ModLoader.mods.size(); i++) {
			Mod mod = ModLoader.mods.get(i);
			ModLoader.registerEntries(mod, "item");
		}
		for (int i = 0; i < ModLoader.mods.size(); i++) {
			Mod mod = ModLoader.mods.get(i);
			ModLoader.registerEntries(mod, "entity");
		}

		for (int i = 0; i < ModLoader.mods.size(); i++) {
			Mod mod = ModLoader.mods.get(i);
			Logger.info("Initiating " + mod);
			mod.init();
		}

		for (int i = 0; i < ModLoader.mods.size(); i++) {
			Mod mod = ModLoader.mods.get(i);
			Logger.info("Post-initiating " + mod);
			mod.postInit();
		}
	}
	
}
