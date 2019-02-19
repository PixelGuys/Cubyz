package io.spacycubyd.modding;

import java.lang.annotation.Annotation;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

import io.spacycubyd.CubzLogger;
import io.spacycubyd.api.EventHandler;
import io.spacycubyd.api.Side;
import io.spacycubyd.api.SideOnly;

public class ModLoader {

	public static BlockRegistry block_registry = new BlockRegistry();
	
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
	
	public static void registerBlocks(Object mod, BlockRegistry reg) {
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
