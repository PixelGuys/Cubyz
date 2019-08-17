package io.cubyz.modding;

import java.lang.annotation.Annotation;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

import io.cubyz.CubyzLogger;
import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.EventHandler;
import io.cubyz.api.Proxy;
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
	
	public static void init(Object mod) {
		commonRegister(mod);
		safeMethodInvoke(true, eventHandlerMethodSided(mod, "init", Side.SERVER), mod);
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
	
	public static void preInit(Object mod, Side side) {
		injectProxy(mod, side);
		Method m = eventHandlerMethodSided(mod, "preInit", Side.SERVER);
		if (m != null)
			safeMethodInvoke(true, m, mod);
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
	
	public static void commonRegister(Object mod) {
		Method block_method = eventHandlerMethod(mod, "block/register");
		Method item_method = eventHandlerMethod(mod, "item/register");
		Method entity_method = eventHandlerMethod(mod, "entity/register");
		
		// invoke
		if (block_method != null)
			safeMethodInvoke(true, block_method, mod, CubyzRegistries.BLOCK_REGISTRY);
		if (item_method != null)
			safeMethodInvoke(true, item_method, mod, CubyzRegistries.ITEM_REGISTRY);
		if (entity_method != null)
			safeMethodInvoke(true, entity_method, mod, CubyzRegistries.ENTITY_REGISTRY);
	}
	
}
