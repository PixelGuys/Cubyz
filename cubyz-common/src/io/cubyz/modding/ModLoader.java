package io.cubyz.modding;

import java.lang.annotation.Annotation;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

import io.cubyz.CubzLogger;
import io.cubyz.api.EventHandler;
import io.cubyz.api.Registry;
import io.cubyz.api.Side;
import io.cubyz.api.SideOnly;
import io.cubyz.blocks.Block;
import io.cubyz.entity.EntityType;
import io.cubyz.items.Item;

// Most methods should ALWAYS be found as if it were on Side.SERVER
public class ModLoader {

	public static Registry<Block>      block_registry  = new Registry<Block>();
	public static Registry<Item>       item_registry   = new Registry<Item>();
	public static Registry<EntityType> entity_registry = new Registry<EntityType>();
	
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
					if (m.getAnnotation(EventHandler.class).type().equals("init")) {
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
				if (m.getAnnotation(EventHandler.class).type().equals("init")) {
					return m;
				}
			}
		}
		return null;
	}
	
	public static void init(Object mod) {
		commonRegister(mod);
		Class<?> cl = mod.getClass();
		safeMethodInvoke(true, eventHandlerMethodSided(mod, "init", Side.SERVER), mod);
	}
	
	static void safeMethodInvoke(boolean imp, Method m, Object o, Object... args) {
		try {
			m.invoke(o, args);
		} catch (IllegalAccessException | IllegalArgumentException | InvocationTargetException e) {
			if (e instanceof InvocationTargetException) {
				CubzLogger.i.warning("Error while invoking mod method (" + m + "):");
				e.getCause().printStackTrace();
			} else {
				e.printStackTrace();
			}
			System.err.flush();
			if (imp) {
				// fast exit
				//Cubz.instance.cleanup();
				System.exit(1); //NOTE: Normal > 1
			}
		}
	}
	
	public static void commonRegister(Object mod) {
		Class<?> cl = mod.getClass();
		for (Method m : cl.getMethods()) {
			if (m.isAnnotationPresent(EventHandler.class)) {
				if (isCorrectSide(Side.SERVER, m)) {
					if (m.getAnnotation(EventHandler.class).type().equals("block/register")) {
						safeMethodInvoke(true, m, mod, block_registry);
					}
					if (m.getAnnotation(EventHandler.class).type().equals("item/register")) {
						safeMethodInvoke(true, m, mod, item_registry);
					}
					if (m.getAnnotation(EventHandler.class).type().equals("entity/register")) {
						safeMethodInvoke(true, m, mod, entity_registry);
					}
				}
			}
		}
	}
	
}
