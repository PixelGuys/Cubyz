package io.cubyz.ui.mods;

import org.lwjgl.glfw.GLFW;

import io.cubyz.api.EventHandler;
import io.cubyz.api.Mod;
import io.cubyz.client.Cubyz;

/**
 * Mod adding Cubyz default GUIs.
 */
@Mod(id = "cubyzGUI", name = "CubyzGUI")
public class BaseModGUI {
	@EventHandler(type = "init")
	public void init() {
		Cubyz.addModGUI(new InventoryGUI(), GLFW.GLFW_KEY_I);
		System.out.println("Init2!");
	}
}
