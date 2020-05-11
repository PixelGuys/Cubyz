package io.cubyz.modding;

import java.lang.annotation.Annotation;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.List;

import io.cubyz.CubyzLogger;
import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.EventHandler;
import io.cubyz.api.LoadOrder;
import io.cubyz.api.Mod;
import io.cubyz.api.Order;
import io.cubyz.api.Proxy;
import io.cubyz.api.Registry;
import io.cubyz.api.Side;
import io.cubyz.api.SideOnly;

// Most methods should ALWAYS be found as if it were on Side.SERVER
public class ModLoader {
	
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
	
	public static void sortMods(List<Object> mods) {
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
				if (order.order() == Order.AFTER) {
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
					CubyzLogger.i.warning("Could not inject Proxy!");
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
				CubyzLogger.i.warning("Error while invoking mod method (" + m + "):");
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
