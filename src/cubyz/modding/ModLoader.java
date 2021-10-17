package cubyz.modding;

import java.lang.annotation.Annotation;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.HashMap;

import cubyz.Logger;
import cubyz.api.CubyzRegistries;
import cubyz.api.CurrentWorldRegistries;
import cubyz.api.EventHandler;
import cubyz.api.LoadOrder;
import cubyz.api.Mod;
import cubyz.api.Order;
import cubyz.api.Proxy;
import cubyz.api.Registry;
import cubyz.api.Side;
import cubyz.api.SideOnly;

/**
 * Most methods should ALWAYS be found as if it were on Side.SERVER
 */
public class ModLoader {
	public static final ArrayList<Object> mods = new ArrayList<Object>();
	
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
	
	public static Method eventHandlerMethodSided(Object mod, String eventType, Side side) {
		Class<?> cl = mod.getClass();
		for (Method m : cl.getMethods()) {
			if (m.isAnnotationPresent(EventHandler.class)) {
				if (isCorrectSide(side, m)) {
					if (m.getAnnotation(EventHandler.class).type().equals(eventType)) {
						return m;
					}
				}
			}
		}
		return null;
	}
	
	public static Method eventHandlerMethod(Object mod, String eventType) {
		Class<?> cl = mod.getClass();
		for (Method m : cl.getMethods()) {
			if (m.isAnnotationPresent(EventHandler.class)) {
				if (m.getAnnotation(EventHandler.class).type().equals(eventType)) {
					return m;
				}
			}
		}
		return null;
	}
	
	public static void sortMods() {
		HashMap<String, Object> modIds = new HashMap<>();
		for (Object mod : mods) {
			Mod annot = mod.getClass().getAnnotation(Mod.class);
			modIds.put(annot.id(), mod);
		}
		for (int i = 0; i < mods.size(); i++) {
			Object mod = mods.get(i);
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
	
	public static void preInit(Object mod, Side side) {
		injectProxy(mod, side);
		Method m = eventHandlerMethodSided(mod, "preInit", Side.SERVER);
		if (m != null)
			safeMethodInvoke(true, m, mod);
	}
	
	public static void init(Object mod) {
		Method m = eventHandlerMethodSided(mod, "init", Side.SERVER);
		if (m != null)
			safeMethodInvoke(true, m, mod);
	}
	
	public static void registerEntries(Object mod, String type) {
		Method method = eventHandlerMethod(mod, "register:" + type);
		if (method != null) {
			Registry<?> reg = null;
			switch (type) {
			case "block":
				reg = CubyzRegistries.BLOCK_REGISTRY;
				break;
			case "item":
				reg = CubyzRegistries.ITEM_REGISTRY;
				break;
			case "entity":
				reg = CubyzRegistries.ENTITY_REGISTRY;
				break;
			case "biome":
				reg = CubyzRegistries.BIOME_REGISTRY;
				break;
			}
			safeMethodInvoke(true, method, mod, reg);
		}
	}
	
	public static void postInit(Object mod) {
		Method m = eventHandlerMethodSided(mod, "postInit", Side.SERVER);
		if (m != null)
			safeMethodInvoke(true, m, mod);
	}
	
	/**
	 * Calls mods after the world has been generated.
	 * @param mod
	 * @param reg registries of this world.
	 */
	public static void postWorldGen(CurrentWorldRegistries reg) {
		for(Object mod : mods) {
			Method m = eventHandlerMethodSided(mod, "postWorldGen", Side.SERVER);
			if (m != null)
				safeMethodInvoke(true, m, mod, reg);
		}
	}
	
	static void injectProxy(Object mod, Side side) {
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
