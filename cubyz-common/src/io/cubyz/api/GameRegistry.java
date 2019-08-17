package io.cubyz.api;

import io.cubyz.ClientOnly;

/**
 * Everything not fitting in Registry class
 */
public class GameRegistry {
	
	public static void registerGUI(String name, Object gui) {
		if (ClientOnly.registerGui != null) {
			ClientOnly.registerGui.accept(name, gui);
		}
	}
	
	public static void openGUI(String name) {
		if (ClientOnly.openGui != null) {
			ClientOnly.openGui.accept(name);
		}
	}
	
}
