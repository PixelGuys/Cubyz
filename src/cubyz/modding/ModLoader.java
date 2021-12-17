package cubyz.modding;

import java.lang.annotation.Annotation;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.HashMap;

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
public class ModLoader {
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
		if (!haveAnnot) {
			return true;
		}
		return false;
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
		case "block":
			mod.registerBlocks(CubyzRegistries.BLOCK_REGISTRIES);
			break;
		case "item":
			mod.registerItems(CubyzRegistries.ITEM_REGISTRY);
			break;
		case "entity":
			mod.registerEntities(CubyzRegistries.ENTITY_REGISTRY);
			break;
		case "biome":
			mod.registerBiomes(CubyzRegistries.BIOME_REGISTRY);
			break;
		}
	}
	
	/**
	 * Calls mods after the world has been generated.
	 * @param mod
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
					e.printStackTrace();
				}
				break;
			}
		}
	}
	
	static void safeMethodInvoke(boolean imp /* is it important (e.g. at init) */, Method m, Object o, Object... args) {
		try {
			m.invoke(o, args);
		} catch (IllegalAccessException | IllegalArgumentException | InvocationTargetException e) {
			if (e instanceof InvocationTargetException) {
				Logger.warning("Error while invoking mod method (" + m + "):");
				e.getCause().printStackTrace();
			} else {
				e.printStackTrace();
			}
			if (imp) {
				System.exit(1);
			}
		}
	}
	
}
