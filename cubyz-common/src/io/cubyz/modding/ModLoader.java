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
import io.cubyz.items.Item;

public class ModLoader {

	public static Registry<Block> block_registry = new Registry<Block>();
	public static Registry<Item>  item_registry =  new Registry<Item>();
	
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
	
	public static void init(Object mod) {
		registerBlocks(mod, block_registry);
		Class<?> cl = mod.getClass();
		for (Method m : cl.getMethods()) {
			if (m.isAnnotationPresent(EventHandler.class)) {
				if (isCorrectSide(Side.CLIENT, m)) {
					if (m.getAnnotation(EventHandler.class).type().equals("init")) {
						safeMethodInvoke(true, m, mod);
					}
				}
			}
		}
	}
	
	static void safeMethodInvoke(boolean imp, Method m, Object o, Object... args) {
		try {
			m.invoke(o, args);
		} catch (IllegalAccessException | IllegalArgumentException | InvocationTargetException e) {
			if (e instanceof InvocationTargetException) {
				CubzLogger.i.warning("Error while invoking method (" + m + "):");
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
	
	public static void registerBlocks(Object mod, Registry<Block> reg) {
		Class<?> cl = mod.getClass();
		for (Method m : cl.getMethods()) {
			if (m.isAnnotationPresent(EventHandler.class)) {
				if (isCorrectSide(Side.CLIENT, m)) {
					if (m.getAnnotation(EventHandler.class).type().equals("blocks/register")) {
						safeMethodInvoke(true, m, mod, reg);
					}
				}
			}
		}
	}
	
}
